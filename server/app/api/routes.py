import hashlib
from pathlib import Path
from time import time
from uuid import uuid4

from fastapi import APIRouter, File, Header, HTTPException, Query, UploadFile, status
from fastapi.responses import FileResponse

from app.core.config import get_settings
from app.core.security import safe_upload_path
from app.models import FileTransferRecord
from app.services.files import file_registry
from app.services.sockets import registry

router = APIRouter(prefix="/api/v1")


@router.get("/system/status")
async def system_status() -> dict:
    settings = get_settings()
    return {
        "status": "healthy",
        "server_id": settings.server_id,
        "version": settings.version,
        "active_peers": registry.active_count,
    }


@router.get("/peers")
async def peers() -> dict:
    return {"peers": [peer.model_dump(mode="json") for peer in registry.list_peers()]}


@router.post("/files/upload", status_code=status.HTTP_201_CREATED)
async def upload_file(
    file: UploadFile = File(...),
    x_sender_id: str = Header(...),
    x_recipient_id: str = Header(...),
) -> dict:
    settings = get_settings()
    destination = _unique_destination(safe_upload_path(settings.upload_dir, file.filename or "upload.bin"))
    sha256 = hashlib.sha256()
    total_bytes = 0
    started_at = time()
    transfer_id = str(uuid4())

    try:
        with destination.open("wb") as output:
            while chunk := await file.read(settings.chunk_size):
                total_bytes += len(chunk)
                if total_bytes > settings.max_upload_bytes:
                    destination.unlink(missing_ok=True)
                    raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="Upload too large")
                sha256.update(chunk)
                output.write(chunk)
    finally:
        await file.close()

    record = FileTransferRecord(
        transfer_id=transfer_id,
        sender_id=x_sender_id,
        recipient_id=x_recipient_id,
        file_name=destination.name,
        bytes=total_bytes,
        sha256=sha256.hexdigest(),
        stored_path=str(destination),
        download_url=f"/api/v1/files/{transfer_id}/download",
        duration_seconds=round(time() - started_at, 3),
    )
    file_registry.add(record)
    return record.model_dump(mode="json")


@router.get("/files")
async def list_files(peer_id: str | None = Query(default=None)) -> dict:
    file_registry.remove_missing()
    return {
        "files": [
            record.model_dump(mode="json")
            for record in file_registry.list_for_peer(peer_id)
        ],
    }


@router.get("/files/{transfer_id}")
async def file_metadata(transfer_id: str) -> dict:
    record = _get_existing_record(transfer_id)
    return record.model_dump(mode="json")


@router.get("/files/{transfer_id}/download")
async def download_file(transfer_id: str) -> FileResponse:
    record = _get_existing_record(transfer_id)
    return FileResponse(
        record.stored_path,
        media_type="application/octet-stream",
        filename=record.file_name,
        headers={
            "X-Transfer-ID": record.transfer_id,
            "X-Content-SHA256": record.sha256,
        },
    )


@router.delete("/files/{transfer_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_file(
    transfer_id: str,
    x_peer_id: str = Header(...),
) -> None:
    record = _get_existing_record(transfer_id)
    if record.sender_id != x_peer_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the uploading peer can delete this file",
        )

    Path(record.stored_path).unlink(missing_ok=True)
    file_registry.remove(transfer_id)


def _get_existing_record(transfer_id: str) -> FileTransferRecord:
    record = file_registry.get(transfer_id)
    if record is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="File transfer not found")
    if not Path(record.stored_path).is_file():
        raise HTTPException(status_code=status.HTTP_410_GONE, detail="Stored file is no longer available")
    return record


def _unique_destination(destination: Path) -> Path:
    if not destination.exists():
        return destination
    stem = destination.stem
    suffix = destination.suffix
    for index in range(1, 10_000):
        candidate = destination.with_name(f"{stem}-{index}{suffix}")
        if not candidate.exists():
            return candidate
    raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Could not allocate unique filename")
