import asyncio
import logging
from time import time

from fastapi import WebSocket
from pydantic import ValidationError

from app.models import ChatPayload, EventType, FileOfferPayload, Peer, PeerRegistration, WebSocketEvent, SharedFolderRecord
from app.services.shares import share_registry
from app.services.db_service import db_service

logger = logging.getLogger(__name__)


class PeerRegistry:
    def __init__(self) -> None:
        self._peers: dict[str, Peer] = {}
        self._connections: dict[str, WebSocket] = {}

    @property
    def active_count(self) -> int:
        return len(self._connections)

    def list_peers(self) -> list[Peer]:
        return list(self._peers.values())

    async def register(self, websocket: WebSocket, registration: PeerRegistration) -> Peer:
        client_host = websocket.client.host if websocket.client else "unknown"
        peer = Peer(
            peer_id=registration.peer_id,
            nickname=registration.nickname,
            platform=registration.platform,
            avatar_index=registration.avatar_index,
            ip=client_host,
        )
        self._peers[peer.peer_id] = peer
        self._connections[peer.peer_id] = websocket

        # Persist user in SQLite
        await db_service.upsert_user(
            peer_id=peer.peer_id,
            nickname=peer.nickname,
            platform=peer.platform,
            avatar_index=peer.avatar_index,
            last_ip=client_host,
        )

        await self.broadcast(EventType.PEER_JOIN, peer.model_dump(), exclude_peer_id=peer.peer_id)
        await self.send(peer.peer_id, EventType.PEER_LIST, {"peers": [item.model_dump() for item in self.list_peers()]})
        logger.info("Peer registered: %s (%s)", peer.peer_id, peer.nickname)
        return peer

    async def unregister(self, peer_id: str | None) -> None:
        if peer_id is None:
            return
        peer = self._peers.pop(peer_id, None)
        self._connections.pop(peer_id, None)
        if peer:
            await self.broadcast(EventType.PEER_LEAVE, {"peer_id": peer_id})
            removed_share_ids = share_registry.remove_by_peer(peer_id)
            for share_id in removed_share_ids:
                await self.broadcast(EventType.FOLDER_UNSHARE, {"share_id": share_id})
            logger.info("Peer unregistered: %s", peer_id)
            # Deactivate user in database
            await db_service.deactivate_user(peer_id)

    async def send(self, peer_id: str, event_type: EventType, payload: dict) -> bool:
        websocket = self._connections.get(peer_id)
        if websocket is None:
            return False
        await websocket.send_json(WebSocketEvent(event_type=event_type, payload=payload).model_dump(mode="json"))
        return True

    async def broadcast(
        self,
        event_type: EventType,
        payload: dict,
        exclude_peer_id: str | None = None,
    ) -> None:
        # Serialize once, fan out concurrently – slow or stalled clients no
        # longer delay delivery to the rest of the peers.
        message = WebSocketEvent(event_type=event_type, payload=payload).model_dump(mode="json")
        targets = [
            (peer_id, websocket)
            for peer_id, websocket in list(self._connections.items())
            if peer_id != exclude_peer_id
        ]
        if not targets:
            return
        results = await asyncio.gather(
            *(websocket.send_json(message) for _, websocket in targets),
            return_exceptions=True,
        )
        for (peer_id, _), result in zip(targets, results):
            if isinstance(result, RuntimeError):
                await self.unregister(peer_id)

    async def send_many(self, peer_ids: list[str], event_type: EventType, payload: dict) -> None:
        """Send the same event to multiple peers concurrently."""
        message = WebSocketEvent(event_type=event_type, payload=payload).model_dump(mode="json")
        websockets = [(pid, self._connections.get(pid)) for pid in peer_ids]
        results = await asyncio.gather(
            *(ws.send_json(message) for pid, ws in websockets if ws is not None),
            return_exceptions=True,
        )
        sent = iter(results)
        for peer_id, ws in websockets:
            if ws is None:
                continue
            result = next(sent)
            if isinstance(result, RuntimeError):
                await self.unregister(peer_id)

    def mark_seen(self, peer_id: str) -> None:
        peer = self._peers.get(peer_id)
        if peer:
            peer.last_seen = time()

    async def route_event(self, sender_id: str, event: WebSocketEvent) -> None:
        self.mark_seen(sender_id)
        if event.event_type == EventType.HEARTBEAT:
            await self.send(sender_id, EventType.HEARTBEAT, {"timestamp": time()})
            return

        if event.event_type == EventType.CHAT_MESSAGE:
            payload = ChatPayload(**event.payload)
            # Make sure sender exists in DB
            sender_peer = self._peers.get(sender_id)
            if sender_peer:
                await db_service.upsert_user(
                    peer_id=sender_peer.peer_id,
                    nickname=sender_peer.nickname,
                    platform=sender_peer.platform,
                    avatar_index=sender_peer.avatar_index,
                )

            # Resolve conversation
            if payload.receiver_id == "global":
                conv_id = "global"
                conv = await db_service.get_conversation(conv_id)
                if not conv:
                    # Create special global channel
                    from app.db.tables import ConversationType
                    conv = await db_service.create_group_or_channel(
                        title="Global Chat",
                        conversation_type=ConversationType.CHANNEL,
                        creator_id=sender_id,
                    )
                    # Force conv ID to be 'global' in DB
                    async with db_service.session_factory() as session:
                        async with session.begin():
                            from sqlalchemy import update
                            from app.db.tables import ConversationRow
                            stmt = update(ConversationRow).where(ConversationRow.id == conv.id).values(conversation_id="global")
                            await session.execute(stmt)
                    conv_id = "global"
            else:
                # Check if receiver_id is an existing conversation (e.g. group or channel)
                conv = await db_service.get_conversation(payload.receiver_id)
                if conv:
                    conv_id = conv.conversation_id
                else:
                    # Upsert receiver to ensure foreign key constraint passes
                    receiver_peer = self._peers.get(payload.receiver_id)
                    if receiver_peer:
                        await db_service.upsert_user(
                            peer_id=receiver_peer.peer_id,
                            nickname=receiver_peer.nickname,
                            platform=receiver_peer.platform,
                            avatar_index=receiver_peer.avatar_index,
                        )
                    else:
                        # If receiver is not currently online/connected, we still create user in DB if they don't exist
                        await db_service.upsert_user(
                            peer_id=payload.receiver_id,
                            nickname="Anonymous",
                            platform="unknown",
                        )
                    # Get or create private DM
                    conv = await db_service.get_or_create_private_conversation(sender_id, payload.receiver_id)
                    conv_id = conv.conversation_id

            # Save message attachments if any
            attachments = []
            for offer in payload.file_offers:
                # Look up file path in DB by transfer_id
                stored_path = None
                download_url = None
                db_rec = await db_service.get_file_record(offer.transfer_id)
                if db_rec:
                    stored_path = db_rec.stored_path
                    download_url = db_rec.download_url
                attachments.append({
                    "file_record_id": offer.transfer_id,
                    "file_name": offer.file_name,
                    "file_size": offer.file_size,
                    "sha256": offer.sha256,
                    "stored_path": stored_path,
                    "download_url": download_url or offer.download_url,
                })

            # Save message & compute integrity hash
            saved_msg = await db_service.save_message(
                msg_id=payload.msg_id,
                sender_id=payload.sender_id,
                conversation_id=conv_id,
                body=payload.body,
                message_type=payload.message_type,
                timestamp=payload.timestamp,
                attachments=attachments,
            )

            # Update payload/outgoing message with hash & conversation info
            outgoing = payload.model_dump(mode="json")
            outgoing["message_hash"] = saved_msg.message_hash
            outgoing["conversation_id"] = conv_id

            # Route/Deliver message
            if payload.receiver_id == "global":
                await self.broadcast(event.event_type, outgoing)
            elif conv and conv.conversation_type in {"group", "channel"}:
                # Fan out to group/channel members concurrently
                members = await db_service.get_conversation_members(conv_id)
                await self.send_many(
                    [m.peer_id for m in members if m.peer_id != sender_id],
                    event.event_type,
                    outgoing,
                )
            else:
                delivered = await self.send(payload.receiver_id, event.event_type, outgoing)
                if not delivered:
                    await self.send(sender_id, EventType.ERROR, {"message": "Recipient is not connected"})
            return

        if event.event_type == EventType.CHAT_EDIT:
            payload = ChatPayload(**event.payload)
            edited_msg = await db_service.edit_message(
                msg_id=payload.msg_id,
                sender_id=payload.sender_id,
                new_body=payload.body,
            )
            if edited_msg:
                outgoing = payload.model_dump(mode="json")
                outgoing["message_hash"] = edited_msg.message_hash
                outgoing["conversation_id"] = edited_msg.conversation_id
                if payload.receiver_id == "global":
                    await self.broadcast(event.event_type, outgoing)
                else:
                    # If edited message was a group/channel conversation
                    conv = await db_service.get_conversation(edited_msg.conversation_id)
                    if conv and conv.conversation_type in {"group", "channel"}:
                        members = await db_service.get_conversation_members(edited_msg.conversation_id)
                        await self.send_many(
                            [m.peer_id for m in members if m.peer_id != sender_id],
                            event.event_type,
                            outgoing,
                        )
                    else:
                        await self.send(payload.receiver_id, event.event_type, outgoing)
            return

        if event.event_type == EventType.CHAT_DELETE:
            msg_id = event.payload.get("msg_id")
            if isinstance(msg_id, str):
                await db_service.delete_message(msg_id, sender_id)
                await self.broadcast(EventType.CHAT_DELETE, event.payload)
            return

        if event.event_type == EventType.FILE_OFFER:
            payload = FileOfferPayload(**event.payload)
            outgoing = payload.model_dump(mode="json")
            if payload.receiver_id:
                delivered = await self.send(payload.receiver_id, EventType.FILE_OFFER, outgoing)
                if not delivered:
                    await self.send(sender_id, EventType.ERROR, {"message": "Recipient is not connected"})
            else:
                await self.broadcast(EventType.FILE_OFFER, outgoing, exclude_peer_id=sender_id)
            return

        if event.event_type in {EventType.FILE_ACCEPT, EventType.FILE_DECLINE}:
            receiver_id = event.payload.get("receiver_id") or event.payload.get("sender_id")
            if isinstance(receiver_id, str):
                await self.send(receiver_id, event.event_type, event.payload)
            return

        if event.event_type == EventType.FOLDER_SHARE:
            try:
                record = SharedFolderRecord(**event.payload)
                share_registry.add(record)
                await self.broadcast(EventType.FOLDER_SHARE, record.model_dump(mode="json"), exclude_peer_id=sender_id)
            except ValidationError as exc:
                await self.send(sender_id, EventType.ERROR, {"message": "Invalid folder share payload", "details": exc.errors()})
            return

        if event.event_type == EventType.FOLDER_UNSHARE:
            share_id = event.payload.get("share_id")
            if isinstance(share_id, str):
                share_registry.remove(share_id)
                await self.broadcast(EventType.FOLDER_UNSHARE, {"share_id": share_id}, exclude_peer_id=sender_id)
            return

        if event.event_type in {EventType.SHARE_FILE_REQUEST, EventType.SHARE_FILE_READY, EventType.SHARE_FILE_ERROR}:
            recipient_id = event.payload.get("recipient_id") or event.payload.get("receiver_id")
            if isinstance(recipient_id, str):
                event.payload["sender_id"] = sender_id
                delivered = await self.send(recipient_id, event.event_type, event.payload)
                if not delivered:
                    await self.send(sender_id, EventType.ERROR, {"message": "Recipient is not connected"})
            return

        await self.send(sender_id, EventType.ERROR, {"message": f"Unsupported event type: {event.event_type}"})


registry = PeerRegistry()


async def receive_orchestrator_messages(websocket: WebSocket, peer: Peer) -> None:
    while True:
        try:
            raw_event = await websocket.receive_json()
            event = WebSocketEvent(**raw_event)
            await registry.route_event(peer.peer_id, event)
        except ValidationError as exc:
            await registry.send(peer.peer_id, EventType.ERROR, {"message": "Invalid event payload", "details": exc.errors()})
