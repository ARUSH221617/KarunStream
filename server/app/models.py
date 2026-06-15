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
    FILE_OFFER = "FILE_OFFER"
    FILE_ACCEPT = "FILE_ACCEPT"
    FILE_DECLINE = "FILE_DECLINE"
    HEARTBEAT = "HEARTBEAT"
    ERROR = "ERROR"


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
    timestamp: float = Field(default_factory=time)


class FileOfferPayload(BaseModel):
    transfer_id: str = Field(default_factory=lambda: str(uuid4()))
    sender_id: str
    receiver_id: str | None = None
    file_name: str
    file_size: int = Field(ge=0)
    sha256: str = Field(min_length=64, max_length=64)
    chunk_size: int | None = None
    timestamp: float = Field(default_factory=time)


class WebSocketEvent(BaseModel):
    event_type: EventType
    payload: dict[str, Any] = Field(default_factory=dict)
