import asyncio
import hashlib
import logging
import os
from pathlib import Path
import shutil
from time import time
from uuid import uuid4

from fastapi import APIRouter, File, Header, HTTPException, Query, Request, Response, UploadFile, status
from fastapi.responses import FileResponse, StreamingResponse

from app.core.config import get_settings
from app.core.pairing import format_pairing_url, format_wifi_qr
from app.core.security import safe_upload_path
from app.models import (
    ConversationCreate,
    ConversationMemberAdd,
    ConversationResponse,
    EventType,
    FileOfferPayload,
    FileTransferRecord,
    MessageAttachmentResponse,
    MessageResponse,
    PairingPayload,
    SystemStatus,
    TransferInitPayload,
    TransferManifestPayload,
)
from app.db.tables import TransferStatus
from app.services.files import file_registry
from app.services.sockets import registry
from app.services.shares import share_registry
from app.services.db_service import db_service
from app.services.discovery import _get_lan_ip

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1")


@router.get("/system/status", response_model=SystemStatus)
async def system_status() -> SystemStatus:
    settings = get_settings()
    return SystemStatus(
        status="healthy",
        server_id=settings.server_id,
        version=settings.version,
        active_peers=registry.active_count,
    )


@router.get("/system/pair-payload", response_model=PairingPayload)
async def get_pair_payload() -> PairingPayload:
    settings = get_settings()
    host_ip = settings.advertised_ip or _get_lan_ip()
    pairing_url = format_pairing_url(
        ip=host_ip,
        port=settings.port,
        token=settings.auth_token,
        tls_fingerprint=settings.tls_fingerprint,
        server_name=settings.server_name,
    )
    wifi_qr: str | None = None
    if settings.hotspot_ssid:
        wifi_qr = format_wifi_qr(
            ssid=settings.hotspot_ssid,
            password=settings.hotspot_password,
            auth_type=settings.hotspot_auth_type,
        )

    return PairingPayload(
        pairing_url=pairing_url,
        host_ip=host_ip,
        port=settings.port,
        auth_token=settings.auth_token,
        tls_fingerprint=settings.tls_fingerprint,
        wifi_qr=wifi_qr,
        server_name=settings.server_name,
    )


@router.get("/peers")
async def peers() -> dict:
    return {"peers": [peer.model_dump(mode="json") for peer in registry.list_peers()]}


@router.get("/shares")
async def list_shares() -> dict:
    return {"shares": [share.model_dump(mode="json") for share in share_registry.list_shares()]}


# ---------------------------------------------------------------------------
# High-Speed Resumable Transfer Endpoints
# ---------------------------------------------------------------------------

@router.post("/transfers", status_code=status.HTTP_201_CREATED)
async def init_transfer(payload: TransferInitPayload) -> dict:
    """Initialize a resumable transfer, check disk space, allocate part file, and return upload metadata."""
    settings = get_settings()
    settings.upload_dir.mkdir(parents=True, exist_ok=True)

    free_bytes = shutil.disk_usage(settings.upload_dir).free
    if free_bytes < payload.total_bytes:
        raise HTTPException(
            status_code=status.HTTP_507_INSUFFICIENT_STORAGE,
            detail="Insufficient storage",
        )

    transfer = await db_service.create_transfer(payload)

    part_file = settings.upload_dir / f"{payload.transfer_id}.part"
    part_file.touch(exist_ok=True)

    return {
        "transfer_id": transfer.transfer_id,
        "upload_url": f"/api/v1/transfers/{transfer.transfer_id}/upload",
        "upload_offset": 0,
        "chunk_size": transfer.chunk_size,
    }


@router.head("/transfers/{transfer_id}/upload")
async def get_upload_offset(transfer_id: str) -> Response:
    """Return the authoritative upload offset and metadata for resuming an upload."""
    settings = get_settings()
    transfer = await db_service.get_transfer(transfer_id)
    if transfer is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transfer not found",
        )

    part_file = settings.upload_dir / f"{transfer_id}.part"
    offset = transfer.committed_bytes
    if transfer.status == TransferStatus.COMPLETED:
        offset = transfer.total_bytes
    elif part_file.exists():
        part_size = part_file.stat().st_size
        offset = min(transfer.committed_bytes, part_size)

    return Response(
        status_code=status.HTTP_200_OK,
        headers={
            "Upload-Offset": str(offset),
            "Upload-Length": str(transfer.total_bytes),
            "Tus-Resumable": "1.0.0",
            "Cache-Control": "no-store",
        },
    )


@router.patch("/transfers/{transfer_id}/upload")
async def upload_transfer_chunk(transfer_id: str, request: Request) -> Response:
    """Stream an upload chunk, update progress, hash blocks, and complete transfer when all bytes arrive."""
    settings = get_settings()
    offset_header = request.headers.get("Upload-Offset")
    if offset_header is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing Upload-Offset header",
        )
    try:
        upload_offset = int(offset_header)
        if upload_offset < 0:
            raise ValueError()
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid Upload-Offset header",
        )

    transfer = await db_service.get_transfer(transfer_id)
    if transfer is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transfer not found",
        )

    if transfer.status == TransferStatus.COMPLETED:
        return Response(
            status_code=status.HTTP_204_NO_CONTENT,
            headers={
                "Upload-Offset": str(transfer.total_bytes),
                "Tus-Resumable": "1.0.0",
            },
        )

    if upload_offset != transfer.committed_bytes:
        return Response(
            status_code=status.HTTP_409_CONFLICT,
            headers={
                "Upload-Offset": str(transfer.committed_bytes),
                "Tus-Resumable": "1.0.0",
            },
            content="Upload-Offset conflict",
            media_type="text/plain",
        )

    part_file = settings.upload_dir / f"{transfer_id}.part"
    loop = asyncio.get_running_loop()

    def _prepare_part_file() -> None:
        if not part_file.exists():
            part_file.touch()
        with part_file.open("r+b") as pf:
            pf.seek(0, os.SEEK_END)
            end_pos = pf.tell()
            if end_pos > upload_offset:
                pf.truncate(upload_offset)

    await loop.run_in_executor(None, _prepare_part_file)

    current_offset = upload_offset
    f = await loop.run_in_executor(None, part_file.open, "r+b")
    await loop.run_in_executor(None, f.seek, upload_offset)

    try:
        async for chunk in request.stream():
            if not chunk:
                continue
            chunk_len = len(chunk)
            free_space = shutil.disk_usage(settings.upload_dir).free
            if free_space < chunk_len:
                raise HTTPException(
                    status_code=status.HTTP_507_INSUFFICIENT_STORAGE,
                    detail="Insufficient storage",
                )
            if current_offset + chunk_len > transfer.total_bytes:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Upload exceeds total bytes",
                )
            await loop.run_in_executor(None, f.write, chunk)
            current_offset += chunk_len

        def _sync_file() -> None:
            f.flush()
            os.fsync(f.fileno())

        await loop.run_in_executor(None, _sync_file)
    finally:
        await loop.run_in_executor(None, f.close)

    # Compute and save chunk hashes
    chunk_size = transfer.chunk_size
    total_bytes = transfer.total_bytes

    def _hash_block(start: int, length: int) -> str:
        h = hashlib.sha256()
        with part_file.open("rb") as pf:
            pf.seek(start)
            remaining = length
            while remaining > 0:
                buf = pf.read(min(remaining, 65536))
                if not buf:
                    break
                h.update(buf)
                remaining -= len(buf)
        return h.hexdigest()

    if total_bytes == 0:
        block_hash = hashlib.sha256(b"").hexdigest()
        await db_service.record_chunk(transfer_id, 0, 0, 0, block_hash)
    else:
        num_chunks = (total_bytes + chunk_size - 1) // chunk_size
        for idx in range(num_chunks):
            start = idx * chunk_size
            end = min(total_bytes, (idx + 1) * chunk_size)
            length = end - start
            if end <= current_offset:
                block_hash = await loop.run_in_executor(None, _hash_block, start, length)
                await db_service.record_chunk(transfer_id, idx, start, length, block_hash)

    await db_service.update_transfer_progress(
        transfer_id=transfer_id,
        committed_bytes=current_offset,
        status=TransferStatus.ACTIVE if current_offset < total_bytes else TransferStatus.COMPLETED,
    )

    if current_offset >= total_bytes:
        def _compute_full_sha256() -> str:
            h = hashlib.sha256()
            with part_file.open("rb") as pf:
                while buf := pf.read(65536):
                    h.update(buf)
            return h.hexdigest()

        file_sha256 = await loop.run_in_executor(None, _compute_full_sha256)

        destination = _unique_destination(
            safe_upload_path(settings.upload_dir, transfer.file_name or "upload.bin")
        )
        await loop.run_in_executor(None, part_file.replace, destination)

        download_url = f"/api/v1/files/{transfer_id}/download"
        await db_service.complete_transfer(
            transfer_id=transfer_id,
            sha256=file_sha256,
            stored_path=str(destination),
            download_url=download_url,
        )

        duration = round(time() - transfer.created_at, 3)
        await db_service.save_file_record(
            transfer_id=transfer_id,
            sender_id=transfer.sender_id,
            recipient_id=transfer.recipient_id,
            file_name=destination.name,
            file_bytes=total_bytes,
            sha256=file_sha256,
            stored_path=str(destination),
            download_url=download_url,
            duration_seconds=duration,
        )

        record = FileTransferRecord(
            transfer_id=transfer_id,
            sender_id=transfer.sender_id,
            recipient_id=transfer.recipient_id,
            file_name=destination.name,
            bytes=total_bytes,
            sha256=file_sha256,
            stored_path=str(destination),
            download_url=download_url,
            duration_seconds=duration,
        )
        file_registry.add(record)

        # Broadcast FILE_OFFER over WebSocket
        file_offer = FileOfferPayload(
            transfer_id=transfer_id,
            sender_id=transfer.sender_id,
            receiver_id=transfer.recipient_id,
            file_name=destination.name,
            file_size=total_bytes,
            sha256=file_sha256,
            chunk_size=transfer.chunk_size,
            download_url=download_url,
        )
        if transfer.recipient_id == "global" or not transfer.recipient_id:
            await registry.broadcast(EventType.FILE_OFFER, file_offer.model_dump(mode="json"))
        else:
            delivered = await registry.send(
                transfer.recipient_id,
                EventType.FILE_OFFER,
                file_offer.model_dump(mode="json"),
            )
            if not delivered:
                logger.debug("Recipient %s not connected for file offer", transfer.recipient_id)

        return Response(
            status_code=status.HTTP_204_NO_CONTENT,
            headers={
                "Upload-Offset": str(total_bytes),
                "Tus-Resumable": "1.0.0",
            },
        )

    return Response(
        status_code=status.HTTP_204_NO_CONTENT,
        headers={
            "Upload-Offset": str(current_offset),
            "Tus-Resumable": "1.0.0",
        },
    )


@router.get("/transfers/{transfer_id}/manifest", response_model=TransferManifestPayload)
async def get_transfer_manifest(transfer_id: str) -> TransferManifestPayload:
    """Return the verified chunk hashes and manifest for a transfer."""
    manifest = await db_service.get_transfer_manifest(transfer_id)
    if manifest is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Transfer not found",
        )
    return manifest



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

    loop = asyncio.get_running_loop()

    async def _drain_upload() -> None:
        nonlocal total_bytes
        # Stream the upload to disk in a worker thread so hashing and file
        # I/O never block the event loop; reads stay async on Starlette's
        # spooled temp file.  The hash is computed incrementally while
        # streaming instead of buffering the whole body in memory.
        output = await loop.run_in_executor(None, destination.open, "wb")
        try:
            while chunk := await file.read(settings.chunk_size):
                total_bytes += len(chunk)
                if total_bytes > settings.max_upload_bytes:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail="Upload too large",
                    )
                sha256.update(chunk)
                await loop.run_in_executor(None, output.write, chunk)
            await loop.run_in_executor(None, output.flush)
        finally:
            await loop.run_in_executor(None, output.close)

    try:
        await _drain_upload()
    except HTTPException:
        destination.unlink(missing_ok=True)
        raise
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
async def download_file(transfer_id: str, request: Request) -> Response:
    record = await _get_existing_record(transfer_id)
    path = Path(record.stored_path)
    stat = path.stat()
    file_size = stat.st_size
    mtime = int(stat.st_mtime)
    etag = f'W/"{file_size}-{mtime}-{record.sha256[:16]}"'

    base_headers = {
        "Accept-Ranges": "bytes",
        "ETag": etag,
        "X-Transfer-ID": record.transfer_id,
        "X-Content-SHA256": record.sha256,
    }

    range_header = request.headers.get("Range")
    if_range = request.headers.get("If-Range")

    serve_range = False
    start = 0
    end = file_size - 1

    if range_header and range_header.startswith("bytes="):
        # If-Range check: if provided and doesn't match ETag, ignore Range header and serve full file (HTTP 200)
        if not if_range or if_range == etag:
            serve_range = True
            range_val = range_header.removeprefix("bytes=").strip()
            if "-" in range_val:
                s_part, _, e_part = range_val.partition("-")
                try:
                    if s_part and e_part:
                        start = int(s_part)
                        end = int(e_part)
                    elif s_part and not e_part:
                        start = int(s_part)
                        end = file_size - 1
                    elif not s_part and e_part:
                        suffix_len = int(e_part)
                        start = max(0, file_size - suffix_len)
                        end = file_size - 1
                    else:
                        serve_range = False
                except ValueError:
                    serve_range = False
            else:
                serve_range = False

    if serve_range:
        if file_size == 0 or start < 0 or start >= file_size or end >= file_size or start > end:
            return Response(
                status_code=status.HTTP_416_REQUESTED_RANGE_NOT_SATISFIABLE,
                headers={"Content-Range": f"bytes */{file_size}"},
                content="Range Not Satisfiable",
                media_type="text/plain",
            )

        content_length = end - start + 1

        def _iter_slice():
            with path.open("rb") as f:
                f.seek(start)
                remaining = content_length
                while remaining > 0:
                    buf = f.read(min(remaining, 65536))
                    if not buf:
                        break
                    remaining -= len(buf)
                    yield buf

        headers = {
            **base_headers,
            "Content-Range": f"bytes {start}-{end}/{file_size}",
            "Content-Length": str(content_length),
            "Content-Type": "application/octet-stream",
        }
        return StreamingResponse(
            _iter_slice(),
            status_code=status.HTTP_206_PARTIAL_CONTENT,
            headers=headers,
        )

    # Full file response (HTTP 200)
    def _iter_full():
        with path.open("rb") as f:
            while buf := f.read(65536):
                yield buf

    headers = {
        **base_headers,
        "Content-Length": str(file_size),
        "Content-Type": "application/octet-stream",
        "Content-Disposition": f'attachment; filename="{record.file_name}"',
    }
    return StreamingResponse(
        _iter_full(),
        status_code=status.HTTP_200_OK,
        headers=headers,
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
        # Members were eager-loaded via selectinload – no per-conversation query.
        result.append({
            "conversation_id": conv.conversation_id,
            "conversation_type": conv.conversation_type,
            "title": conv.title,
            "description": conv.description,
            "created_by": conv.created_by,
            "created_at": conv.created_at,
            "updated_at": conv.updated_at,
            "is_archived": conv.is_archived,
            "members": [m.user_peer_id for m in conv.members],
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
                "file_offers": [
                    {
                        "transfer_id": a.file_record_id or a.attachment_id,
                        "sender_id": m.sender_id,
                        "receiver_id": m.conversation_id,
                        "file_name": a.file_name,
                        "file_size": a.file_size,
                        "sha256": a.sha256,
                        "download_url": a.download_url,
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
        # Fallback to database file records
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
            file_registry.add(record)

    if record is None:
        # Fallback to database transfers table
        tr = await db_service.get_transfer(transfer_id)
        if tr is not None and tr.stored_path:
            record = FileTransferRecord(
                transfer_id=tr.transfer_id,
                sender_id=tr.sender_id,
                recipient_id=tr.recipient_id,
                file_name=tr.file_name,
                bytes=tr.total_bytes,
                sha256=tr.sha256 or "",
                stored_path=tr.stored_path,
                download_url=tr.download_url or f"/api/v1/files/{transfer_id}/download",
                created_at=tr.created_at,
                duration_seconds=round(tr.updated_at - tr.created_at, 3),
            )
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
