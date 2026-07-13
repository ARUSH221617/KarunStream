"""SQLAlchemy ORM tables for KarunStream's messenger-style chat system.

Entities
--------
- **User** – a registered peer identity persisted across sessions.
- **Conversation** – an abstract container (private, group, or channel).
- **ConversationMember** – many-to-many linking users to conversations, with role.
- **Message** – a single chat message inside a conversation, with integrity hash.
- **MessageAttachment** – file references attached to messages (stored-path in DB).
- **FileRecord** – persisted version of uploaded files with their server-side path.
"""

from __future__ import annotations

import hashlib
from enum import StrEnum
from time import time
from typing import Optional
from uuid import uuid4

from sqlalchemy import (
    BigInteger,
    Boolean,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.engine import Base


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

class ConversationType(StrEnum):
    PRIVATE = "private"
    GROUP = "group"
    CHANNEL = "channel"


class MemberRole(StrEnum):
    OWNER = "owner"
    ADMIN = "admin"
    MEMBER = "member"


class MessageType(StrEnum):
    TEXT = "text"
    SYSTEM = "system"
    LINK = "link"
    FILE = "file"


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

def _uuid() -> str:
    return str(uuid4())


def _now() -> float:
    return time()


def compute_message_hash(
    msg_id: str,
    sender_id: str,
    conversation_id: str,
    body: str,
    timestamp: float,
) -> str:
    """Deterministic SHA-256 hash for message integrity verification."""
    raw = f"{msg_id}:{sender_id}:{conversation_id}:{body}:{timestamp}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
# ORM Models
# ---------------------------------------------------------------------------

class UserRow(Base):
    """Persisted peer identity.  peer_id is the natural key from the client."""

    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    peer_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    nickname: Mapped[str] = mapped_column(String(128), nullable=False, default="Anonymous")
    platform: Mapped[str] = mapped_column(String(32), nullable=False, default="unknown")
    avatar_index: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    last_ip: Mapped[Optional[str]] = mapped_column(String(45), nullable=True)
    created_at: Mapped[float] = mapped_column(Float, nullable=False, default=_now)
    last_seen: Mapped[float] = mapped_column(Float, nullable=False, default=_now)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    # Relationships
    memberships: Mapped[list["ConversationMemberRow"]] = relationship(
        back_populates="user", cascade="all, delete-orphan"
    )
    messages: Mapped[list["MessageRow"]] = relationship(
        back_populates="sender", cascade="all, delete-orphan"
    )


class ConversationRow(Base):
    """A conversation container – private DM, group chat, or broadcast channel."""

    __tablename__ = "conversations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    conversation_id: Mapped[str] = mapped_column(
        String(64), unique=True, nullable=False, index=True, default=_uuid
    )
    conversation_type: Mapped[str] = mapped_column(
        String(16), nullable=False, default=ConversationType.PRIVATE
    )
    title: Mapped[Optional[str]] = mapped_column(String(256), nullable=True)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    avatar_url: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)
    created_by: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    created_at: Mapped[float] = mapped_column(Float, nullable=False, default=_now)
    updated_at: Mapped[float] = mapped_column(Float, nullable=False, default=_now)
    is_archived: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    # For private chats – store sorted peer_id pair for uniqueness
    private_key: Mapped[Optional[str]] = mapped_column(
        String(130), nullable=True, unique=True
    )

    # Relationships
    members: Mapped[list["ConversationMemberRow"]] = relationship(
        back_populates="conversation", cascade="all, delete-orphan"
    )
    messages: Mapped[list["MessageRow"]] = relationship(
        back_populates="conversation", cascade="all, delete-orphan"
    )


class ConversationMemberRow(Base):
    """Membership junction: user ←→ conversation with role and mute state."""

    __tablename__ = "conversation_members"
    __table_args__ = (
        UniqueConstraint("conversation_id", "user_peer_id", name="uq_conv_user"),
        Index("ix_conv_members_user", "user_peer_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    conversation_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("conversations.conversation_id", ondelete="CASCADE"), nullable=False
    )
    user_peer_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.peer_id", ondelete="CASCADE"), nullable=False
    )
    role: Mapped[str] = mapped_column(String(16), nullable=False, default=MemberRole.MEMBER)
    joined_at: Mapped[float] = mapped_column(Float, nullable=False, default=_now)
    is_muted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    last_read_at: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Relationships
    conversation: Mapped["ConversationRow"] = relationship(back_populates="members")
    user: Mapped["UserRow"] = relationship(back_populates="memberships")


class MessageRow(Base):
    """A single message stored with an integrity hash for tamper detection."""

    __tablename__ = "messages"
    __table_args__ = (
        Index("ix_messages_conv_ts", "conversation_id", "timestamp"),
        Index("ix_messages_sender", "sender_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    msg_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True, default=_uuid)
    conversation_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("conversations.conversation_id", ondelete="CASCADE"), nullable=False
    )
    sender_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.peer_id", ondelete="CASCADE"), nullable=False
    )
    body: Mapped[str] = mapped_column(Text, nullable=False, default="")
    message_type: Mapped[str] = mapped_column(String(16), nullable=False, default=MessageType.TEXT)
    timestamp: Mapped[float] = mapped_column(Float, nullable=False, default=_now)
    is_edited: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    is_deleted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    reply_to_msg_id: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    message_hash: Mapped[str] = mapped_column(String(64), nullable=False, default="")

    # Relationships
    conversation: Mapped["ConversationRow"] = relationship(back_populates="messages")
    sender: Mapped["UserRow"] = relationship(back_populates="messages")
    attachments: Mapped[list["MessageAttachmentRow"]] = relationship(
        back_populates="message", cascade="all, delete-orphan"
    )


class MessageAttachmentRow(Base):
    """Links a message to one or more uploaded files stored on the server."""

    __tablename__ = "message_attachments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    attachment_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, default=_uuid)
    msg_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("messages.msg_id", ondelete="CASCADE"), nullable=False
    )
    file_record_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("file_records.transfer_id", ondelete="SET NULL"), nullable=True
    )
    file_name: Mapped[str] = mapped_column(String(512), nullable=False)
    file_size: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False, default="")
    stored_path: Mapped[Optional[str]] = mapped_column(String(1024), nullable=True)
    download_url: Mapped[Optional[str]] = mapped_column(String(512), nullable=True)
    created_at: Mapped[float] = mapped_column(Float, nullable=False, default=_now)

    # Relationships
    message: Mapped["MessageRow"] = relationship(back_populates="attachments")


class FileRecordRow(Base):
    """Persistent record of every file uploaded to the server."""

    __tablename__ = "file_records"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    transfer_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True, default=_uuid)
    sender_id: Mapped[str] = mapped_column(String(64), nullable=False)
    recipient_id: Mapped[str] = mapped_column(String(64), nullable=False, default="global")
    file_name: Mapped[str] = mapped_column(String(512), nullable=False)
    file_bytes: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False, default="")
    stored_path: Mapped[str] = mapped_column(String(1024), nullable=False)
    download_url: Mapped[str] = mapped_column(String(512), nullable=False, default="")
    created_at: Mapped[float] = mapped_column(Float, nullable=False, default=_now)
    duration_seconds: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    is_deleted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
