from pathlib import Path

from fastapi.testclient import TestClient

from app.api import routes
from app.core.config import get_settings
from app.main import app


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


def test_unique_destination_avoids_overwrite(tmp_path: Path) -> None:
    destination = tmp_path / "demo.txt"
    destination.write_text("existing", encoding="utf-8")

    unique = routes._unique_destination(destination)

    assert unique == tmp_path / "demo-1.txt"
