import hashlib
from pathlib import Path
from time import time
from uuid import uuid4

from fastapi import APIRouter, File, Header, HTTPException, Query, UploadFile, status
from fastapi.responses import FileResponse

from app.core.config import get_settings
from app.core.security import safe_upload_path
from app.models import (
    FileTransferRecord,
    ConversationCreate,
    ConversationResponse,
    MessageResponse,
    MessageAttachmentResponse,
    ConversationMemberAdd,
)
from app.services.files import file_registry
from app.services.sockets import registry
from app.services.shares import share_registry
from app.services.db_service import db_service

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


@router.get("/shares")
async def list_shares() -> dict:
    return {"shares": [share.model_dump(mode="json") for share in share_registry.list_shares()]}


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

    download_url = f"/api/v1/files/{transfer_id}/download"
    duration = round(time() - started_at, 3)
    sha256_hex = sha256.hexdigest()

    # Persist in DB
    await db_service.save_file_record(
        transfer_id=transfer_id,
        sender_id=x_sender_id,
        recipient_id=x_recipient_id,
        file_name=destination.name,
        file_bytes=total_bytes,
        sha256=sha256_hex,
        stored_path=str(destination),
        download_url=download_url,
        duration_seconds=duration,
    )

    record = FileTransferRecord(
        transfer_id=transfer_id,
        sender_id=x_sender_id,
        recipient_id=x_recipient_id,
        file_name=destination.name,
        bytes=total_bytes,
        sha256=sha256_hex,
        stored_path=str(destination),
        download_url=download_url,
        duration_seconds=duration,
    )
    file_registry.add(record)
    return record.model_dump(mode="json")


@router.get("/files")
async def list_files(peer_id: str | None = Query(default=None)) -> dict:
    file_registry.remove_missing()
    # List files from DB
    records = await db_service.list_files_for_peer(peer_id)
    return {
        "files": [
            {
                "transfer_id": r.transfer_id,
                "sender_id": r.sender_id,
                "recipient_id": r.recipient_id,
                "file_name": r.file_name,
                "bytes": r.file_bytes,
                "sha256": r.sha256,
                "stored_path": r.stored_path,
                "download_url": r.download_url,
                "created_at": r.created_at,
                "duration_seconds": r.duration_seconds,
            }
            for r in records
        ]
    }


@router.get("/files/{transfer_id}")
async def file_metadata(transfer_id: str) -> dict:
    record = await _get_existing_record(transfer_id)
    return record.model_dump(mode="json")


@router.get("/files/{transfer_id}/download")
async def download_file(transfer_id: str) -> FileResponse:
    record = await _get_existing_record(transfer_id)
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
    record = await _get_existing_record(transfer_id)
    if record.sender_id != x_peer_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the uploading peer can delete this file",
        )

    Path(record.stored_path).unlink(missing_ok=True)
    file_registry.remove(transfer_id)
    await db_service.delete_file_record(transfer_id)
    await registry.broadcast("FILE_DELETED", {"transfer_id": transfer_id})


# ---------------------------------------------------------------------------
# Conversations & Messaging Endpoints
# ---------------------------------------------------------------------------

@router.post("/conversations", response_model=ConversationResponse, status_code=status.HTTP_201_CREATED)
async def create_conversation(
    payload: ConversationCreate,
    x_peer_id: str = Header(...),
) -> dict:
    """Create a new group or channel conversation."""
    if payload.conversation_type == "private":
        if not payload.initial_members or len(payload.initial_members) != 1:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Private conversations must specify exactly one initial member (the peer ID).",
            )
        conv = await db_service.get_or_create_private_conversation(x_peer_id, payload.initial_members[0])
    else:
        if not payload.title:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Title is required for group or channel conversations.",
            )
        conv = await db_service.create_group_or_channel(
            title=payload.title,
            conversation_type=payload.conversation_type,
            creator_id=x_peer_id,
            description=payload.description,
        )
        for member_id in payload.initial_members:
            if member_id != x_peer_id:
                await db_service.add_member(conv.conversation_id, member_id)

    members = await db_service.get_conversation_members(conv.conversation_id)
    return {
        "conversation_id": conv.conversation_id,
        "conversation_type": conv.conversation_type,
        "title": conv.title,
        "description": conv.description,
        "created_by": conv.created_by,
        "created_at": conv.created_at,
        "updated_at": conv.updated_at,
        "is_archived": conv.is_archived,
        "members": [m.peer_id for m in members],
    }


@router.get("/conversations")
async def list_conversations(x_peer_id: str = Header(...)) -> dict:
    """List all conversations for the calling peer."""
    conversations = await db_service.get_user_conversations(x_peer_id)
    result = []
    for conv in conversations:
        members = await db_service.get_conversation_members(conv.conversation_id)
        result.append({
            "conversation_id": conv.conversation_id,
            "conversation_type": conv.conversation_type,
            "title": conv.title,
            "description": conv.description,
            "created_by": conv.created_by,
            "created_at": conv.created_at,
            "updated_at": conv.updated_at,
            "is_archived": conv.is_archived,
            "members": [m.peer_id for m in members],
        })
    return {"conversations": result}


@router.get("/conversations/{conversation_id}/messages")
async def get_conversation_messages(
    conversation_id: str,
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> dict:
    """Retrieve message history for a conversation. Verifies message integrity hashes."""
    messages, corrupted_ids = await db_service.get_messages(
        conversation_id=conversation_id,
        limit=limit,
        offset=offset,
        verify_integrity=True,
    )
    return {
        "messages": [
            {
                "msg_id": m.msg_id,
                "conversation_id": m.conversation_id,
                "sender_id": m.sender_id,
                "body": m.body,
                "message_type": m.message_type,
                "timestamp": m.timestamp,
                "is_edited": m.is_edited,
                "is_deleted": m.is_deleted,
                "reply_to_msg_id": m.reply_to_msg_id,
                "message_hash": m.message_hash,
                "attachments": [
                    {
                        "attachment_id": a.attachment_id,
                        "file_name": a.file_name,
                        "file_size": a.file_size,
                        "sha256": a.sha256,
                        "download_url": a.download_url,
                        "created_at": a.created_at,
                    }
                    for a in m.attachments
                ],
            }
            for m in messages
        ],
        "corrupted_msg_ids": corrupted_ids,
    }


@router.post("/conversations/{conversation_id}/members", status_code=status.HTTP_201_CREATED)
async def add_conversation_member(
    conversation_id: str,
    payload: ConversationMemberAdd,
) -> dict:
    """Add a member to a conversation."""
    member = await db_service.add_member(
        conversation_id=conversation_id,
        peer_id=payload.peer_id,
        role=payload.role,
    )
    if not member:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation or User not found",
        )
    return {
        "conversation_id": conversation_id,
        "peer_id": payload.peer_id,
        "role": payload.role,
    }


@router.delete("/conversations/{conversation_id}/members/{peer_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_conversation_member(
    conversation_id: str,
    peer_id: str,
) -> None:
    """Remove a member from a conversation (or leave)."""
    success = await db_service.remove_member(conversation_id, peer_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation member not found",
        )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _get_existing_record(transfer_id: str) -> FileTransferRecord:
    record = file_registry.get(transfer_id)
    if record is None:
        # Fallback to database
        db_rec = await db_service.get_file_record(transfer_id)
        if db_rec is not None:
            record = FileTransferRecord(
                transfer_id=db_rec.transfer_id,
                sender_id=db_rec.sender_id,
                recipient_id=db_rec.recipient_id,
                file_name=db_rec.file_name,
                bytes=db_rec.file_bytes,
                sha256=db_rec.sha256,
                stored_path=db_rec.stored_path,
                download_url=db_rec.download_url,
                created_at=db_rec.created_at,
                duration_seconds=db_rec.duration_seconds,
            )
            # Add to registry to save future DB hits
            file_registry.add(record)

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
