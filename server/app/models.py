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


class PeerRegistration(BaseModel):
    peer_id: str = Field(default_factory=lambda: str(uuid4()))
    nickname: str = "Anonymous"
    platform: str = "unknown"
    avatar_index: int | None = None


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

