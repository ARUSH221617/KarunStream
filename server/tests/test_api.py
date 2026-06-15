from pathlib import Path

from fastapi.testclient import TestClient

from app.api import routes
from app.core.config import get_settings
from app.main import app
from app.services.files import file_registry


def test_status_endpoint_reports_healthy() -> None:
    with TestClient(app) as client:
        response = client.get("/api/v1/system/status")

    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_peers_endpoint_defaults_to_empty_list() -> None:
    with TestClient(app) as client:
        response = client.get("/api/v1/peers")

    assert response.status_code == 200
    assert response.json() == {"peers": []}


def test_upload_sanitizes_filename_and_hashes_bytes(tmp_path: Path) -> None:
    settings = get_settings()
    original_upload_dir = settings.upload_dir
    settings.upload_dir = tmp_path
    file_registry.clear()

    try:
        with TestClient(app) as client:
            response = client.post(
                "/api/v1/files/upload",
                headers={"X-Sender-ID": "sender", "X-Recipient-ID": "recipient"},
                files={"file": ("../../unsafe.txt", b"karunstream", "text/plain")},
            )
    finally:
        settings.upload_dir = original_upload_dir

    body = response.json()
    assert response.status_code == 201
    assert body["file_name"] == "unsafe.txt"
    assert body["bytes"] == 11
    assert body["sha256"] == "90f6b9c9d0918f156228aad23c89809efaeea1caddfef68464cfab4f7dd9b419"
    assert Path(body["stored_path"]).parent == tmp_path
    assert body["download_url"] == f"/api/v1/files/{body['transfer_id']}/download"


def test_uploaded_file_can_be_listed_and_downloaded(tmp_path: Path) -> None:
    settings = get_settings()
    original_upload_dir = settings.upload_dir
    settings.upload_dir = tmp_path
    file_registry.clear()

    try:
        with TestClient(app) as client:
            upload_response = client.post(
                "/api/v1/files/upload",
                headers={"X-Sender-ID": "sender", "X-Recipient-ID": "recipient"},
                files={"file": ("report.pdf", b"local bytes", "application/pdf")},
            )
            transfer_id = upload_response.json()["transfer_id"]
            list_response = client.get("/api/v1/files", params={"peer_id": "recipient"})
            metadata_response = client.get(f"/api/v1/files/{transfer_id}")
            download_response = client.get(f"/api/v1/files/{transfer_id}/download")
    finally:
        settings.upload_dir = original_upload_dir

    assert list_response.status_code == 200
    assert list_response.json()["files"][0]["transfer_id"] == transfer_id
    assert metadata_response.status_code == 200
    assert metadata_response.json()["file_name"] == "report.pdf"
    assert download_response.status_code == 200
    assert download_response.content == b"local bytes"
    assert download_response.headers["x-content-sha256"] == upload_response.json()["sha256"]


def test_only_uploader_can_delete_uploaded_file(tmp_path: Path) -> None:
    settings = get_settings()
    original_upload_dir = settings.upload_dir
    settings.upload_dir = tmp_path
    file_registry.clear()

    try:
        with TestClient(app) as client:
            upload_response = client.post(
                "/api/v1/files/upload",
                headers={"X-Sender-ID": "sender", "X-Recipient-ID": "recipient"},
                files={"file": ("delete-me.txt", b"temporary", "text/plain")},
            )
            body = upload_response.json()
            transfer_id = body["transfer_id"]
            stored_path = Path(body["stored_path"])

            forbidden_response = client.delete(
                f"/api/v1/files/{transfer_id}",
                headers={"X-Peer-ID": "recipient"},
            )
            delete_response = client.delete(
                f"/api/v1/files/{transfer_id}",
                headers={"X-Peer-ID": "sender"},
            )
            metadata_response = client.get(f"/api/v1/files/{transfer_id}")
    finally:
        settings.upload_dir = original_upload_dir

    assert forbidden_response.status_code == 403
    assert delete_response.status_code == 204
    assert metadata_response.status_code == 404
    assert not stored_path.exists()


def test_unique_destination_avoids_overwrite(tmp_path: Path) -> None:
    destination = tmp_path / "demo.txt"
    destination.write_text("existing", encoding="utf-8")

    unique = routes._unique_destination(destination)

    assert unique == tmp_path / "demo-1.txt"
