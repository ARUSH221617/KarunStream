from __future__ import annotations

from enum import StrEnum
from time import time
from typing import Any, Literal
from uuid import uuid4

from pydantic import BaseModel, Field


class EventType(StrEnum):
    PEER_JOIN = "PEER_JOIN"
    PEER_LEAVE = "PEER_LEAVE"
    PEER_LIST = "PEER_LIST"
    CHAT_MESSAGE = "CHAT_MESSAGE"
    CHAT_EDIT = "CHAT_EDIT"
    CHAT_DELETE = "CHAT_DELETE"
    FILE_OFFER = "FILE_OFFER"
    FILE_ACCEPT = "FILE_ACCEPT"
    FILE_DECLINE = "FILE_DECLINE"
    FILE_DELETED = "FILE_DELETED"
    HEARTBEAT = "HEARTBEAT"
    ERROR = "ERROR"
    FOLDER_SHARE = "FOLDER_SHARE"
    FOLDER_UNSHARE = "FOLDER_UNSHARE"
    SHARE_FILE_REQUEST = "SHARE_FILE_REQUEST"
    SHARE_FILE_READY = "SHARE_FILE_READY"
    SHARE_FILE_ERROR = "SHARE_FILE_ERROR"


class ErrorCode(StrEnum):
    OUT_OF_SPACE = "OUT_OF_SPACE"
    OFFSET_MISMATCH = "OFFSET_MISMATCH"
    FILE_MODIFIED = "FILE_MODIFIED"
    AUTH_EXPIRED = "AUTH_EXPIRED"
    TRANSFER_NOT_FOUND = "TRANSFER_NOT_FOUND"
    INVALID_CHECKSUM = "INVALID_CHECKSUM"
    PERMISSION_DENIED = "PERMISSION_DENIED"
    VALIDATION_FAILED = "VALIDATION_FAILED"


class ErrorEventPayload(BaseModel):
    event_type: Literal["ERROR"] = "ERROR"
    error_code: ErrorCode
    message: str = Field(min_length=1)
    transfer_id: str | None = None
    details: dict[str, Any] | None = None
    timestamp: float = Field(default_factory=time)


class PeerRegistration(BaseModel):
    peer_id: str = Field(default_factory=lambda: str(uuid4()))
    nickname: str = "Anonymous"
    platform: str = "unknown"
    avatar_index: int | None = None
    auth_token: str | None = None


class PeerHandshake(BaseModel):
    v: str = "1.0"
    peer_id: str = Field(default_factory=lambda: str(uuid4()), min_length=1)
    nickname: str = Field(default="Anonymous", min_length=1)
    platform: Literal["android", "ios", "windows", "macos", "linux", "web", "unknown"] = "unknown"
    capabilities: list[str] = Field(
        default_factory=lambda: ["resume", "chunk_manifest", "folders", "tus_upload"]
    )
    tls_fingerprint: str | None = Field(default=None, pattern=r"^[a-fA-F0-9]{64}$")
    auth_token: str | None = None


class SystemStatus(BaseModel):
    status: str = "healthy"
    server_id: str
    version: str
    active_peers: int = 0
    capabilities: list[str] = Field(
        default_factory=lambda: ["resume", "chunk_manifest", "folders", "tus_upload"]
    )


class PairingPayload(BaseModel):
    pairing_url: str
    host_ip: str
    port: int = Field(ge=1, le=65535)
    auth_token: str | None = None
    tls_fingerprint: str | None = None
    wifi_qr: str | None = None
    server_name: str


class TransferInitPayload(BaseModel):
    transfer_id: str = Field(
        default_factory=lambda: str(uuid4()),
        pattern=r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
    )
    sender_id: str = Field(min_length=1)
    recipient_id: str = Field(min_length=1)
    file_name: str = Field(min_length=1)
    total_bytes: int = Field(ge=0)
    chunk_size: int = Field(default=1048576, ge=65536)
    sha256_prefix: str | None = Field(default=None, pattern=r"^([a-fA-F0-9]{64})?$")
    metadata: dict[str, Any] = Field(default_factory=dict)


class TransferInitResponse(BaseModel):
    transfer_id: str
    upload_url: str
    upload_offset: int = 0
    chunk_size: int = 1048576


class ChunkHashRecord(BaseModel):
    chunk_index: int = Field(ge=0)
    byte_offset: int = Field(ge=0)
    byte_length: int = Field(ge=0)
    sha256: str = Field(pattern=r"^[a-fA-F0-9]{64}$")


class TransferManifestPayload(BaseModel):
    transfer_id: str = Field(
        default_factory=lambda: str(uuid4()),
        pattern=r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
    )
    chunk_size: int = Field(ge=65536)
    total_chunks: int = Field(ge=1)
    chunks: list[ChunkHashRecord] = Field(default_factory=list)


class Peer(BaseModel):
    peer_id: str
    nickname: str
    platform: str
    ip: str
    avatar_index: int | None = None
    connected_at: float = Field(default_factory=time)
    last_seen: float = Field(default_factory=time)


class ChatPayload(BaseModel):
    msg_id: str = Field(default_factory=lambda: str(uuid4()))
    sender_id: str
    receiver_id: str = "global"
    body: str
    message_type: Literal["text", "system", "link"] = "text"
    is_edited: bool = False
    timestamp: float = Field(default_factory=time)
    file_offers: list[FileOfferPayload] = Field(default_factory=list)


class FileOfferPayload(BaseModel):
    transfer_id: str = Field(default_factory=lambda: str(uuid4()))
    sender_id: str
    receiver_id: str | None = None
    file_name: str
    file_size: int = Field(ge=0)
    sha256: str = Field(min_length=64, max_length=64)
    chunk_size: int | None = None
    download_url: str | None = None
    timestamp: float = Field(default_factory=time)


class FileTransferRecord(BaseModel):
    transfer_id: str = Field(default_factory=lambda: str(uuid4()))
    sender_id: str
    recipient_id: str
    file_name: str
    bytes: int = Field(ge=0)
    sha256: str = Field(min_length=64, max_length=64)
    stored_path: str
    download_url: str
    created_at: float = Field(default_factory=time)
    duration_seconds: float


class WebSocketEvent(BaseModel):
    event_type: EventType
    payload: dict[str, Any] = Field(default_factory=dict)


class SharedFolderFile(BaseModel):
    relative_path: str
    file_name: str
    file_size: int = Field(ge=0)


class SharedFolderRecord(BaseModel):
    share_id: str
    peer_id: str
    peer_nickname: str
    name: str
    files: list[SharedFolderFile] = Field(default_factory=list)


class ConversationCreate(BaseModel):
    title: str | None = None
    conversation_type: Literal["private", "group", "channel"]
    description: str | None = None
    initial_members: list[str] = Field(default_factory=list)


class ConversationResponse(BaseModel):
    conversation_id: str
    conversation_type: str
    title: str | None
    description: str | None
    created_by: str | None
    created_at: float
    updated_at: float
    is_archived: bool
    members: list[str] = Field(default_factory=list)


class MessageAttachmentResponse(BaseModel):
    attachment_id: str
    file_name: str
    file_size: int
    sha256: str
    download_url: str | None
    created_at: float


class MessageResponse(BaseModel):
    msg_id: str
    conversation_id: str
    sender_id: str
    body: str
    message_type: str
    timestamp: float
    is_edited: bool
    is_deleted: bool
    reply_to_msg_id: str | None = None
    message_hash: str
    attachments: list[MessageAttachmentResponse] = Field(default_factory=list)


class ConversationMemberAdd(BaseModel):
    peer_id: str
    role: Literal["owner", "admin", "member"] = "member"


