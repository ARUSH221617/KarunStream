import hashlib
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app
from app.services.files import file_registry


def test_full_resumable_upload(tmp_path: Path) -> None:
    """Test full resumable upload workflow:
    POST init -> HEAD offset 0 -> PATCH first 500 bytes -> HEAD offset 500
    -> PATCH remaining 500 bytes -> verify COMPLETED, final file exists, SHA-256 matches.
    """
    settings = get_settings()
    original_upload_dir = settings.upload_dir
    settings.upload_dir = tmp_path
    file_registry.clear()

    total_size = 1000
    payload_data = b"A" * 500 + b"B" * 500
    expected_sha256 = hashlib.sha256(payload_data).hexdigest()
    transfer_id = str(uuid4())

    try:
        with TestClient(app) as client:
            # 1. POST /api/v1/transfers (init)
            init_resp = client.post(
                "/api/v1/transfers",
                json={
                    "transfer_id": transfer_id,
                    "sender_id": "alice",
                    "recipient_id": "bob",
                    "file_name": "resumable_test.bin",
                    "total_bytes": total_size,
                    "chunk_size": 1048576,
                },
            )
            assert init_resp.status_code == 201
            init_json = init_resp.json()
            assert init_json["transfer_id"] == transfer_id
            assert init_json["upload_url"] == f"/api/v1/transfers/{transfer_id}/upload"
            assert init_json["upload_offset"] == 0

            # 2. HEAD /api/v1/transfers/{transfer_id}/upload (verify offset 0)
            head_resp1 = client.head(f"/api/v1/transfers/{transfer_id}/upload")
            assert head_resp1.status_code == 200
            assert head_resp1.headers["upload-offset"] == "0"
            assert head_resp1.headers["upload-length"] == str(total_size)
            assert head_resp1.headers["tus-resumable"] == "1.0.0"

            # 3. PATCH first 500 bytes at offset 0
            patch_resp1 = client.patch(
                f"/api/v1/transfers/{transfer_id}/upload",
                headers={"Upload-Offset": "0", "Content-Type": "application/offset+octet-stream"},
                content=payload_data[:500],
            )
            assert patch_resp1.status_code == 204
            assert patch_resp1.headers["upload-offset"] == "500"

            # 4. HEAD offset verification (should now be 500)
            head_resp2 = client.head(f"/api/v1/transfers/{transfer_id}/upload")
            assert head_resp2.status_code == 200
            assert head_resp2.headers["upload-offset"] == "500"

            # 5. PATCH remaining 500 bytes at offset 500
            patch_resp2 = client.patch(
                f"/api/v1/transfers/{transfer_id}/upload",
                headers={"Upload-Offset": "500", "Content-Type": "application/offset+octet-stream"},
                content=payload_data[500:],
            )
            assert patch_resp2.status_code == 204
            assert patch_resp2.headers["upload-offset"] == "1000"

            # 6. HEAD should now report 1000
            head_resp3 = client.head(f"/api/v1/transfers/{transfer_id}/upload")
            assert head_resp3.status_code == 200
            assert head_resp3.headers["upload-offset"] == "1000"

            # 7. Check file metadata via GET /api/v1/files/{transfer_id}
            meta_resp = client.get(f"/api/v1/files/{transfer_id}")
            assert meta_resp.status_code == 200
            meta = meta_resp.json()
            assert meta["bytes"] == total_size
            assert meta["sha256"] == expected_sha256
            final_file = Path(meta["stored_path"])
            assert final_file.exists()
            assert final_file.read_bytes() == payload_data
    finally:
        settings.upload_dir = original_upload_dir


def test_upload_offset_conflict(tmp_path: Path) -> None:
    """Test upload conflict: PATCH with wrong offset returns HTTP 409 with authoritative offset."""
    settings = get_settings()
    original_upload_dir = settings.upload_dir
    settings.upload_dir = tmp_path
    transfer_id = str(uuid4())

    try:
        with TestClient(app) as client:
            init_resp = client.post(
                "/api/v1/transfers",
                json={
                    "transfer_id": transfer_id,
                    "sender_id": "alice",
                    "recipient_id": "bob",
                    "file_name": "conflict_test.bin",
                    "total_bytes": 1000,
                },
            )
            assert init_resp.status_code == 201

            # PATCH with wrong offset (e.g. offset 100 instead of 0)
            conflict_resp = client.patch(
                f"/api/v1/transfers/{transfer_id}/upload",
                headers={"Upload-Offset": "100"},
                content=b"some bytes",
            )
            assert conflict_resp.status_code == 409
            assert conflict_resp.headers["upload-offset"] == "0"
            assert "conflict" in conflict_resp.text.lower()
    finally:
        settings.upload_dir = original_upload_dir


def test_disk_space_preflight_insufficient_storage(tmp_path: Path) -> None:
    """Test disk space pre-flight: mock disk_usage free bytes < requested bytes -> returns HTTP 507."""
    settings = get_settings()
    original_upload_dir = settings.upload_dir
    settings.upload_dir = tmp_path
    transfer_id = str(uuid4())

    try:
        with TestClient(app) as client:
            class MockDiskUsage:
                total = 1000000
                used = 999900
                free = 100  # Only 100 bytes free

            with patch("shutil.disk_usage", return_value=MockDiskUsage()):
                resp = client.post(
                    "/api/v1/transfers",
                    json={
                        "transfer_id": transfer_id,
                        "sender_id": "alice",
                        "recipient_id": "bob",
                        "file_name": "huge_file.bin",
                        "total_bytes": 50000,  # 50,000 > 100 bytes free
                    },
                )
                assert resp.status_code == 507
                assert "Insufficient storage" in resp.json()["detail"]
    finally:
        settings.upload_dir = original_upload_dir


def test_resumable_download_ranges(tmp_path: Path) -> None:
    """Test resumable download with Range and If-Range headers."""
    settings = get_settings()
    original_upload_dir = settings.upload_dir
    settings.upload_dir = tmp_path
    file_registry.clear()

    total_size = 1000
    # Create deterministic content: byte i has value (i % 256)
    content_bytes = bytes([i % 256 for i in range(total_size)])
    transfer_id = str(uuid4())

    try:
        with TestClient(app) as client:
            # Upload file completely
            init_resp = client.post(
                "/api/v1/transfers",
                json={
                    "transfer_id": transfer_id,
                    "sender_id": "alice",
                    "recipient_id": "bob",
                    "file_name": "range_test.bin",
                    "total_bytes": total_size,
                },
            )
            assert init_resp.status_code == 201

            patch_resp = client.patch(
                f"/api/v1/transfers/{transfer_id}/upload",
                headers={"Upload-Offset": "0"},
                content=content_bytes,
            )
            assert patch_resp.status_code == 204

            # 1. GET with Range: bytes=0-99 -> returns 206 Partial Content, exactly 100 bytes
            r1 = client.get(
                f"/api/v1/files/{transfer_id}/download",
                headers={"Range": "bytes=0-99"},
            )
            assert r1.status_code == 206
            assert len(r1.content) == 100
            assert r1.content == content_bytes[0:100]
            assert r1.headers["content-range"] == "bytes 0-99/1000"
            assert r1.headers["content-length"] == "100"
            assert r1.headers["accept-ranges"] == "bytes"
            assert "etag" in r1.headers

            etag = r1.headers["etag"]

            # 2. GET with Range: bytes=100- -> returns 206 from byte 100 to end
            r2 = client.get(
                f"/api/v1/files/{transfer_id}/download",
                headers={"Range": "bytes=100-"},
            )
            assert r2.status_code == 206
            assert len(r2.content) == 900
            assert r2.content == content_bytes[100:]
            assert r2.headers["content-range"] == "bytes 100-999/1000"
            assert r2.headers["content-length"] == "900"

            # 3. GET with matching If-Range -> returns 206
            r3 = client.get(
                f"/api/v1/files/{transfer_id}/download",
                headers={"Range": "bytes=0-49", "If-Range": etag},
            )
            assert r3.status_code == 206
            assert len(r3.content) == 50
            assert r3.content == content_bytes[0:50]
            assert r3.headers["content-range"] == "bytes 0-49/1000"

            # 4. GET with non-matching If-Range -> returns 200 with full content
            r4 = client.get(
                f"/api/v1/files/{transfer_id}/download",
                headers={"Range": "bytes=0-49", "If-Range": 'W/"invalid-etag"'},
            )
            assert r4.status_code == 200
            assert len(r4.content) == 1000
            assert r4.content == content_bytes
            assert "content-range" not in r4.headers

            # 5. GET with out of bounds Range -> returns 416
            r5 = client.get(
                f"/api/v1/files/{transfer_id}/download",
                headers={"Range": "bytes=2000-3000"},
            )
            assert r5.status_code == 416
            assert r5.headers["content-range"] == "bytes */1000"
    finally:
        settings.upload_dir = original_upload_dir


def test_manifest_endpoint(tmp_path: Path) -> None:
    """Test manifest endpoint returns verified chunk hashes matching TransferManifestPayload."""
    settings = get_settings()
    original_upload_dir = settings.upload_dir
    settings.upload_dir = tmp_path
    file_registry.clear()

    # Create a 200 KiB file with 64 KiB chunks -> 4 chunks (64K, 64K, 64K, 8K)
    chunk_size = 65536
    total_size = 200000
    file_data = b"X" * total_size
    transfer_id = str(uuid4())

    try:
        with TestClient(app) as client:
            init_resp = client.post(
                "/api/v1/transfers",
                json={
                    "transfer_id": transfer_id,
                    "sender_id": "alice",
                    "recipient_id": "bob",
                    "file_name": "manifest_test.bin",
                    "total_bytes": total_size,
                    "chunk_size": chunk_size,
                },
            )
            assert init_resp.status_code == 201

            # Upload in 2 halves: first 131072 bytes (exactly 2 chunks), then remaining
            patch1 = client.patch(
                f"/api/v1/transfers/{transfer_id}/upload",
                headers={"Upload-Offset": "0"},
                content=file_data[:131072],
            )
            assert patch1.status_code == 204

            # Check intermediate manifest
            mid_manifest_resp = client.get(f"/api/v1/transfers/{transfer_id}/manifest")
            assert mid_manifest_resp.status_code == 200
            mid_manifest = mid_manifest_resp.json()
            assert mid_manifest["transfer_id"] == transfer_id
            assert mid_manifest["chunk_size"] == chunk_size
            assert len(mid_manifest["chunks"]) == 2
            assert mid_manifest["chunks"][0]["chunk_index"] == 0
            assert mid_manifest["chunks"][0]["byte_offset"] == 0
            assert mid_manifest["chunks"][0]["byte_length"] == chunk_size
            assert mid_manifest["chunks"][0]["sha256"] == hashlib.sha256(file_data[:chunk_size]).hexdigest()

            # Upload remaining bytes
            patch2 = client.patch(
                f"/api/v1/transfers/{transfer_id}/upload",
                headers={"Upload-Offset": "131072"},
                content=file_data[131072:],
            )
            assert patch2.status_code == 204

            # Final manifest
            final_manifest_resp = client.get(f"/api/v1/transfers/{transfer_id}/manifest")
            assert final_manifest_resp.status_code == 200
            final_manifest = final_manifest_resp.json()
            assert final_manifest["transfer_id"] == transfer_id
            assert len(final_manifest["chunks"]) == 4

            # Verify every chunk
            for i, chunk in enumerate(final_manifest["chunks"]):
                start = i * chunk_size
                end = min(total_size, (i + 1) * chunk_size)
                assert chunk["chunk_index"] == i
                assert chunk["byte_offset"] == start
                assert chunk["byte_length"] == end - start
                assert chunk["sha256"] == hashlib.sha256(file_data[start:end]).hexdigest()
    finally:
        settings.upload_dir = original_upload_dir


def test_missing_and_invalid_transfer_handling() -> None:
    """Test error handling for missing transfers and invalid headers."""
    with TestClient(app) as client:
        fake_id = str(uuid4())

        # HEAD on non-existent transfer -> 404
        head_resp = client.head(f"/api/v1/transfers/{fake_id}/upload")
        assert head_resp.status_code == 404

        # PATCH on non-existent transfer -> 404
        patch_resp = client.patch(
            f"/api/v1/transfers/{fake_id}/upload",
            headers={"Upload-Offset": "0"},
            content=b"test",
        )
        assert patch_resp.status_code == 404

        # PATCH with missing Upload-Offset header -> 400
        bad_patch = client.patch(f"/api/v1/transfers/{fake_id}/upload", content=b"test")
        assert bad_patch.status_code == 400

        # Manifest on non-existent transfer -> 404
        manifest_resp = client.get(f"/api/v1/transfers/{fake_id}/manifest")
        assert manifest_resp.status_code == 404


def test_zero_byte_transfer(tmp_path: Path) -> None:
    """Test zero-byte file transfer completes and computes empty sha256."""
    settings = get_settings()
    original_upload_dir = settings.upload_dir
    settings.upload_dir = tmp_path
    transfer_id = str(uuid4())

    try:
        with TestClient(app) as client:
            init_resp = client.post(
                "/api/v1/transfers",
                json={
                    "transfer_id": transfer_id,
                    "sender_id": "alice",
                    "recipient_id": "bob",
                    "file_name": "empty.txt",
                    "total_bytes": 0,
                },
            )
            assert init_resp.status_code == 201

            patch_resp = client.patch(
                f"/api/v1/transfers/{transfer_id}/upload",
                headers={"Upload-Offset": "0"},
                content=b"",
            )
            assert patch_resp.status_code == 204
            assert patch_resp.headers["upload-offset"] == "0"

            meta = client.get(f"/api/v1/files/{transfer_id}").json()
            assert meta["bytes"] == 0
            assert meta["sha256"] == hashlib.sha256(b"").hexdigest()

            # Manifest should also have 1 chunk of length 0
            manifest = client.get(f"/api/v1/transfers/{transfer_id}/manifest").json()
            assert manifest["total_chunks"] >= 1
            assert manifest["chunks"][0]["byte_length"] == 0
    finally:
        settings.upload_dir = original_upload_dir


def test_resumable_upload_broadcasts_file_offer(tmp_path: Path) -> None:
    """Test completing a transfer sends FILE_OFFER event to the recipient peer over WebSocket."""
    settings = get_settings()
    original_upload_dir = settings.upload_dir
    settings.upload_dir = tmp_path
    transfer_id = str(uuid4())

    try:
        with TestClient(app) as client:
            with client.websocket_connect("/ws/orchestrator") as ws_bob:
                ws_bob.send_json({"peer_id": "bob", "nickname": "Bob", "platform": "windows"})
                roster = ws_bob.receive_json()
                assert roster["event_type"] == "PEER_LIST"

                init_resp = client.post(
                    "/api/v1/transfers",
                    json={
                        "transfer_id": transfer_id,
                        "sender_id": "alice",
                        "recipient_id": "bob",
                        "file_name": "photo.jpg",
                        "total_bytes": 100,
                    },
                )
                assert init_resp.status_code == 201

                patch_resp = client.patch(
                    f"/api/v1/transfers/{transfer_id}/upload",
                    headers={"Upload-Offset": "0"},
                    content=b"P" * 100,
                )
                assert patch_resp.status_code == 204

                # Bob should receive FILE_OFFER event
                event = ws_bob.receive_json()
                assert event["event_type"] == "FILE_OFFER"
                assert event["payload"]["transfer_id"] == transfer_id
                assert event["payload"]["file_name"] == "photo.jpg"
                assert event["payload"]["file_size"] == 100
    finally:
        settings.upload_dir = original_upload_dir

