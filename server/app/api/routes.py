import hashlib
from pathlib import Path
from time import time
from uuid import uuid4

from fastapi import APIRouter, File, Header, HTTPException, UploadFile, status

from app.core.config import get_settings
from app.core.security import safe_upload_path
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

    return {
        "transfer_id": str(uuid4()),
        "sender_id": x_sender_id,
        "recipient_id": x_recipient_id,
        "file_name": destination.name,
        "bytes": total_bytes,
        "sha256": sha256.hexdigest(),
        "stored_path": str(destination),
        "duration_seconds": round(time() - started_at, 3),
    }


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
