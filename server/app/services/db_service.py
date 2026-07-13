"""Database services for handling users, conversations, messages, and files in KarunStream."""

from __future__ import annotations

import logging
import time
from typing import Any, Sequence
from sqlalchemy import select, and_, or_, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.db.engine import get_session_factory
from app.db.tables import (
    UserRow,
    ConversationRow,
    ConversationMemberRow,
    MessageRow,
    MessageAttachmentRow,
    FileRecordRow,
    ConversationType,
    MemberRole,
    MessageType,
    compute_message_hash,
)

logger = logging.getLogger(__name__)


class DatabaseService:
    """Service to handle persistence layer using SQLAlchemy async sessions."""

    @property
    def session_factory(self):
        return get_session_factory()

    async def upsert_user(
        self,
        peer_id: str,
        nickname: str,
        platform: str,
        avatar_index: int | None = None,
        last_ip: str | None = None,
    ) -> UserRow:
        """Create a user or update their metadata and last_seen time."""
        async with self.session_factory() as session:
            async with session.begin():
                stmt = select(UserRow).where(UserRow.peer_id == peer_id)
                res = await session.execute(stmt)
                user = res.scalar_one_or_none()

                if user is None:
                    user = UserRow(
                        peer_id=peer_id,
                        nickname=nickname,
                        platform=platform,
                        avatar_index=avatar_index,
                        last_ip=last_ip,
                    )
                    session.add(user)
                    logger.debug("Database: Registered new user %s (%s)", peer_id, nickname)
                else:
                    user.nickname = nickname
                    user.platform = platform
                    user.avatar_index = avatar_index
                    if last_ip:
                        user.last_ip = last_ip
                    user.last_seen = time.time()
                    user.is_active = True
                    logger.debug("Database: Updated user %s (%s)", peer_id, nickname)
                
                await session.flush()
                # Refresh user to load its attributes safely
                await session.refresh(user)
                return user

    async def get_user(self, peer_id: str) -> UserRow | None:
        """Fetch user by peer_id."""
        async with self.session_factory() as session:
            stmt = select(UserRow).where(UserRow.peer_id == peer_id)
            res = await session.execute(stmt)
            return res.scalar_one_or_none()

    async def deactivate_user(self, peer_id: str) -> None:
        """Mark user as inactive when they disconnect."""
        async with self.session_factory() as session:
            async with session.begin():
                stmt = update(UserRow).where(UserRow.peer_id == peer_id).values(is_active=False)
                await session.execute(stmt)

    async def get_or_create_private_conversation(self, peer_a: str, peer_b: str) -> ConversationRow:
        """Get or create a private DM conversation between two peers.

        The private_key is calculated by sorting the peer IDs to ensure uniqueness.
        """
        sorted_peers = sorted([peer_a, peer_b])
        private_key = f"{sorted_peers[0]}:{sorted_peers[1]}"

        async with self.session_factory() as session:
            async with session.begin():
                # 1. Search for existing conversation by private_key
                stmt = select(ConversationRow).where(ConversationRow.private_key == private_key)
                res = await session.execute(stmt)
                conv = res.scalar_one_or_none()

                if conv is not None:
                    return conv

                # 2. Doesn't exist, create it
                conv = ConversationRow(
                    conversation_type=ConversationType.PRIVATE,
                    private_key=private_key,
                    title=None,
                )
                session.add(conv)
                await session.flush()

                # 3. Add both members
                member_a = ConversationMemberRow(
                    conversation_id=conv.conversation_id,
                    user_peer_id=peer_a,
                    role=MemberRole.MEMBER,
                )
                member_b = ConversationMemberRow(
                    conversation_id=conv.conversation_id,
                    user_peer_id=peer_b,
                    role=MemberRole.MEMBER,
                )
                session.add_all([member_a, member_b])
                await session.flush()
                await session.refresh(conv)
                return conv

    async def create_group_or_channel(
        self,
        title: str,
        conversation_type: ConversationType,
        creator_id: str,
        description: str | None = None,
    ) -> ConversationRow:
        """Create a new group or channel and add the creator as owner."""
        async with self.session_factory() as session:
            async with session.begin():
                conv = ConversationRow(
                    conversation_type=conversation_type,
                    title=title,
                    description=description,
                    created_by=creator_id,
                )
                session.add(conv)
                await session.flush()

                # Add owner member
                member = ConversationMemberRow(
                    conversation_id=conv.conversation_id,
                    user_peer_id=creator_id,
                    role=MemberRole.OWNER,
                )
                session.add(member)
                await session.flush()
                await session.refresh(conv)
                return conv

    async def add_member(
        self,
        conversation_id: str,
        peer_id: str,
        role: MemberRole = MemberRole.MEMBER,
    ) -> ConversationMemberRow | None:
        """Add a peer to an existing group or channel conversation."""
        async with self.session_factory() as session:
            async with session.begin():
                # Verify conversation exists
                conv_stmt = select(ConversationRow).where(ConversationRow.conversation_id == conversation_id)
                conv_res = await session.execute(conv_stmt)
                conv = conv_res.scalar_one_or_none()
                if not conv:
                    return None

                # Verify user exists
                user_stmt = select(UserRow).where(UserRow.peer_id == peer_id)
                user_res = await session.execute(user_stmt)
                if not user_res.scalar_one_or_none():
                    return None

                # Check if already a member
                member_stmt = select(ConversationMemberRow).where(
                    and_(
                        ConversationMemberRow.conversation_id == conversation_id,
                        ConversationMemberRow.user_peer_id == peer_id,
                    )
                )
                member_res = await session.execute(member_stmt)
                member = member_res.scalar_one_or_none()

                if member is None:
                    member = ConversationMemberRow(
                        conversation_id=conversation_id,
                        user_peer_id=peer_id,
                        role=role,
                    )
                    session.add(member)
                    await session.flush()
                else:
                    # Update role if needed
                    member.role = role
                
                await session.refresh(member)
                return member

    async def remove_member(self, conversation_id: str, peer_id: str) -> bool:
        """Remove a member from a conversation."""
        async with self.session_factory() as session:
            async with session.begin():
                stmt = select(ConversationMemberRow).where(
                    and_(
                        ConversationMemberRow.conversation_id == conversation_id,
                        ConversationMemberRow.user_peer_id == peer_id,
                    )
                )
                res = await session.execute(stmt)
                member = res.scalar_one_or_none()
                if member:
                    await session.delete(member)
                    return True
                return False

    async def get_conversation_members(self, conversation_id: str) -> list[UserRow]:
        """Get all users who are members of a conversation."""
        async with self.session_factory() as session:
            stmt = (
                select(UserRow)
                .join(ConversationMemberRow, UserRow.peer_id == ConversationMemberRow.user_peer_id)
                .where(ConversationMemberRow.conversation_id == conversation_id)
            )
            res = await session.execute(stmt)
            return list(res.scalars().all())

    async def get_user_conversations(self, peer_id: str) -> list[ConversationRow]:
        """List all conversations (DMs, groups, channels) that a peer belongs to."""
        async with self.session_factory() as session:
            stmt = (
                select(ConversationRow)
                .join(ConversationMemberRow, ConversationRow.conversation_id == ConversationMemberRow.conversation_id)
                .where(ConversationMemberRow.user_peer_id == peer_id)
                .options(selectinload(ConversationRow.members))
                .order_by(ConversationRow.updated_at.desc())
            )
            res = await session.execute(stmt)
            return list(res.scalars().all())

    async def get_conversation(self, conversation_id: str) -> ConversationRow | None:
        """Get a single conversation metadata."""
        async with self.session_factory() as session:
            stmt = select(ConversationRow).where(ConversationRow.conversation_id == conversation_id)
            res = await session.execute(stmt)
            return res.scalar_one_or_none()

    async def save_message(
        self,
        msg_id: str,
        sender_id: str,
        conversation_id: str,
        body: str,
        message_type: str = MessageType.TEXT,
        reply_to_msg_id: str | None = None,
        timestamp: float | None = None,
        attachments: list[dict[str, Any]] | None = None,
    ) -> MessageRow:
        """Save a new chat message, compute its integrity hash, and persist attachments."""
        ts = timestamp or time.time()
        msg_hash = compute_message_hash(
            msg_id=msg_id,
            sender_id=sender_id,
            conversation_id=conversation_id,
            body=body,
            timestamp=ts,
        )

        async with self.session_factory() as session:
            async with session.begin():
                # Make sure conversation update time is refreshed
                conv_update_stmt = (
                    update(ConversationRow)
                    .where(ConversationRow.conversation_id == conversation_id)
                    .values(updated_at=ts)
                )
                await session.execute(conv_update_stmt)

                msg = MessageRow(
                    msg_id=msg_id,
                    conversation_id=conversation_id,
                    sender_id=sender_id,
                    body=body,
                    message_type=message_type,
                    timestamp=ts,
                    reply_to_msg_id=reply_to_msg_id,
                    message_hash=msg_hash,
                )
                session.add(msg)
                await session.flush()

                if attachments:
                    for att_data in attachments:
                        att = MessageAttachmentRow(
                            msg_id=msg_id,
                            file_record_id=att_data.get("file_record_id"),
                            file_name=att_data["file_name"],
                            file_size=att_data["file_size"],
                            sha256=att_data["sha256"],
                            stored_path=att_data.get("stored_path"),
                            download_url=att_data.get("download_url"),
                        )
                        session.add(att)
                    await session.flush()

                await session.refresh(msg)
                # Load attachments
                stmt = select(MessageRow).where(MessageRow.msg_id == msg_id).options(selectinload(MessageRow.attachments))
                res = await session.execute(stmt)
                return res.scalar_one()

    async def get_messages(
        self,
        conversation_id: str,
        limit: int = 50,
        offset: int = 0,
        verify_integrity: bool = True,
    ) -> tuple[list[MessageRow], list[str]]:
        """Fetch messages for a conversation, optionally verifying their integrity.

        Returns a tuple of (messages, list_of_corrupted_msg_ids).
        """
        async with self.session_factory() as session:
            stmt = (
                select(MessageRow)
                .where(MessageRow.conversation_id == conversation_id)
                .options(selectinload(MessageRow.attachments))
                .order_by(MessageRow.timestamp.desc())
                .limit(limit)
                .offset(offset)
            )
            res = await session.execute(stmt)
            messages = list(res.scalars().all())
            # We want them in chronological order
            messages.reverse()

            corrupted = []
            if verify_integrity:
                for m in messages:
                    expected = compute_message_hash(
                        msg_id=m.msg_id,
                        sender_id=m.sender_id,
                        conversation_id=m.conversation_id,
                        body=m.body,
                        timestamp=m.timestamp,
                    )
                    if m.message_hash != expected:
                        logger.error(
                            "Database integrity check FAILED for message %s. Hash mismatch: %s != %s",
                            m.msg_id,
                            m.message_hash,
                            expected,
                        )
                        corrupted.append(m.msg_id)

            return messages, corrupted

    async def delete_message(self, msg_id: str, requester_id: str) -> bool:
        """Soft delete a message if requester is the sender."""
        async with self.session_factory() as session:
            async with session.begin():
                stmt = select(MessageRow).where(MessageRow.msg_id == msg_id)
                res = await session.execute(stmt)
                msg = res.scalar_one_or_none()
                if msg and msg.sender_id == requester_id:
                    msg.is_deleted = True
                    msg.body = "[This message was deleted]"
                    msg.message_hash = compute_message_hash(
                        msg_id=msg.msg_id,
                        sender_id=msg.sender_id,
                        conversation_id=msg.conversation_id,
                        body=msg.body,
                        timestamp=msg.timestamp,
                    )
                    await session.flush()
                    return True
                return False

    async def edit_message(self, msg_id: str, sender_id: str, new_body: str) -> MessageRow | None:
        """Edit an existing message and update its integrity hash."""
        async with self.session_factory() as session:
            async with session.begin():
                stmt = select(MessageRow).where(MessageRow.msg_id == msg_id).options(selectinload(MessageRow.attachments))
                res = await session.execute(stmt)
                msg = res.scalar_one_or_none()
                if msg and msg.sender_id == sender_id and not msg.is_deleted:
                    msg.body = new_body
                    msg.is_edited = True
                    msg.message_hash = compute_message_hash(
                        msg_id=msg.msg_id,
                        sender_id=msg.sender_id,
                        conversation_id=msg.conversation_id,
                        body=new_body,
                        timestamp=msg.timestamp,
                    )
                    await session.flush()
                    await session.refresh(msg)
                    return msg
                return None

    # -----------------------------------------------------------------------
    # File Records
    # -----------------------------------------------------------------------

    async def save_file_record(
        self,
        transfer_id: str,
        sender_id: str,
        recipient_id: str,
        file_name: str,
        file_bytes: int,
        sha256: str,
        stored_path: str,
        download_url: str,
        duration_seconds: float = 0.0,
    ) -> FileRecordRow:
        """Create and save a persistent record of an uploaded file."""
        async with self.session_factory() as session:
            async with session.begin():
                record = FileRecordRow(
                    transfer_id=transfer_id,
                    sender_id=sender_id,
                    recipient_id=recipient_id,
                    file_name=file_name,
                    file_bytes=file_bytes,
                    sha256=sha256,
                    stored_path=stored_path,
                    download_url=download_url,
                    duration_seconds=duration_seconds,
                )
                session.add(record)
                await session.flush()
                await session.refresh(record)
                return record

    async def get_file_record(self, transfer_id: str) -> FileRecordRow | None:
        """Retrieve a file record by transfer_id."""
        async with self.session_factory() as session:
            stmt = select(FileRecordRow).where(
                and_(
                    FileRecordRow.transfer_id == transfer_id,
                    FileRecordRow.is_deleted == False,
                )
            )
            res = await session.execute(stmt)
            return res.scalar_one_or_none()

    async def list_files_for_peer(self, peer_id: str | None = None) -> list[FileRecordRow]:
        """List active file records. If peer_id provided, filter by sender/recipient."""
        async with self.session_factory() as session:
            if peer_id is None:
                stmt = select(FileRecordRow).where(FileRecordRow.is_deleted == False).order_by(FileRecordRow.created_at.desc())
            else:
                stmt = (
                    select(FileRecordRow)
                    .where(
                        and_(
                            FileRecordRow.is_deleted == False,
                            or_(
                                FileRecordRow.sender_id == peer_id,
                                FileRecordRow.recipient_id == peer_id,
                                FileRecordRow.recipient_id == "global",
                            ),
                        )
                    )
                    .order_by(FileRecordRow.created_at.desc())
                )
            res = await session.execute(stmt)
            return list(res.scalars().all())

    async def delete_file_record(self, transfer_id: str) -> bool:
        """Mark a file record as deleted."""
        async with self.session_factory() as session:
            async with session.begin():
                stmt = select(FileRecordRow).where(FileRecordRow.transfer_id == transfer_id)
                res = await session.execute(stmt)
                record = res.scalar_one_or_none()
                if record:
                    record.is_deleted = True
                    await session.flush()
                    return True
                return False


db_service = DatabaseService()
