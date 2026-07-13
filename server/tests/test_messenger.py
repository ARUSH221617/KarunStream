import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.services.sockets import registry
from app.services.db_service import db_service
from app.db.engine import reset_engine_for_testing
from app.db.tables import ConversationType, MemberRole


@pytest.fixture(autouse=True)
async def setup_test_db():
    # Use a separate test SQLite DB in memory or file
    await reset_engine_for_testing("sqlite+aiosqlite:///:memory:")
    registry._peers.clear()
    registry._connections.clear()
    yield


def test_create_and_manage_conversations() -> None:
    with TestClient(app) as client:
        # Create users/peers
        with client.websocket_connect("/ws/orchestrator") as ws1:
            ws1.send_json({"peer_id": "alice", "nickname": "Alice", "platform": "Windows"})
            ws1.receive_json()  # PEER_LIST

            with client.websocket_connect("/ws/orchestrator") as ws2:
                ws2.send_json({"peer_id": "bob", "nickname": "Bob", "platform": "Android"})
                ws2.receive_json()  # PEER_LIST
                ws1.receive_json()  # PEER_JOIN (Bob joined)

                # 1. Create a group conversation via REST API
                conv_payload = {
                    "title": "Developers Group",
                    "conversation_type": "group",
                    "description": "Group for dev talk",
                    "initial_members": ["alice", "bob"]
                }
                create_resp = client.post(
                    "/api/v1/conversations",
                    json=conv_payload,
                    headers={"X-Peer-ID": "alice"}
                )
                assert create_resp.status_code == 201
                conv_data = create_resp.json()
                assert conv_data["title"] == "Developers Group"
                assert conv_data["conversation_type"] == "group"
                assert "alice" in conv_data["members"]
                assert "bob" in conv_data["members"]

                conv_id = conv_data["conversation_id"]

                # 2. List Bob's conversations
                list_resp = client.get("/api/v1/conversations", headers={"X-Peer-ID": "bob"})
                assert list_resp.status_code == 200
                bob_convs = list_resp.json()["conversations"]
                assert len(bob_convs) == 1
                assert bob_convs[0]["conversation_id"] == conv_id

                # 3. Add a new member to the conversation
                # Let's first register Charlie
                with client.websocket_connect("/ws/orchestrator") as ws3:
                    ws3.send_json({"peer_id": "charlie", "nickname": "Charlie", "platform": "Linux"})
                    ws3.receive_json()  # PEER_LIST
                    ws1.receive_json()  # PEER_JOIN (Charlie joined)
                    ws2.receive_json()  # PEER_JOIN (Charlie joined)

                    add_member_resp = client.post(
                        f"/api/v1/conversations/{conv_id}/members",
                        json={"peer_id": "charlie", "role": "member"}
                    )
                    assert add_member_resp.status_code == 201
                    assert add_member_resp.json()["peer_id"] == "charlie"

                    # 4. Bob sends message to group via WebSocket
                    msg_id = "msg-123"
                    chat_msg = {
                        "msg_id": msg_id,
                        "sender_id": "bob",
                        "receiver_id": conv_id,  # sending to group conversation
                        "body": "Hello Developers!",
                        "message_type": "text"
                    }
                    ws2.send_json({"event_type": "CHAT_MESSAGE", "payload": chat_msg})

                    # Alice receives it
                    recv_alice = ws1.receive_json()
                    assert recv_alice["event_type"] == "CHAT_MESSAGE"
                    assert recv_alice["payload"]["body"] == "Hello Developers!"
                    assert recv_alice["payload"]["sender_id"] == "bob"
                    assert "message_hash" in recv_alice["payload"]
                    alice_hash = recv_alice["payload"]["message_hash"]

                    # Charlie receives it
                    recv_charlie = ws3.receive_json()
                    assert recv_charlie["event_type"] == "CHAT_MESSAGE"
                    assert recv_charlie["payload"]["body"] == "Hello Developers!"
                    assert recv_charlie["payload"]["message_hash"] == alice_hash

                    # 5. Fetch message history & verify integrity hashes
                    history_resp = client.get(f"/api/v1/conversations/{conv_id}/messages")
                    assert history_resp.status_code == 200
                    messages = history_resp.json()["messages"]
                    assert len(messages) == 1
                    assert messages[0]["body"] == "Hello Developers!"
                    assert messages[0]["message_hash"] == alice_hash
                    # No corrupted messages detected
                    assert len(history_resp.json()["corrupted_msg_ids"]) == 0


def test_private_conversation_and_upload_paths(tmp_path) -> None:
    from app.core.config import get_settings
    settings = get_settings()
    original_upload_dir = settings.upload_dir
    settings.upload_dir = tmp_path

    try:
        with TestClient(app) as client:
            with client.websocket_connect("/ws/orchestrator") as ws1:
                ws1.send_json({"peer_id": "alice", "nickname": "Alice", "platform": "Windows"})
                ws1.receive_json()

                with client.websocket_connect("/ws/orchestrator") as ws2:
                    ws2.send_json({"peer_id": "bob", "nickname": "Bob", "platform": "macOS"})
                    ws2.receive_json()
                    ws1.receive_json()

                    # 1. Send direct message (will automatically create private DM conversation)
                    chat_msg = {
                        "msg_id": "dm-1",
                        "sender_id": "alice",
                        "receiver_id": "bob",
                        "body": "Hey Bob, private chat!",
                        "message_type": "text"
                    }
                    ws1.send_json({"event_type": "CHAT_MESSAGE", "payload": chat_msg})

                    recv_bob = ws2.receive_json()
                    assert recv_bob["event_type"] == "CHAT_MESSAGE"
                    assert recv_bob["payload"]["body"] == "Hey Bob, private chat!"
                    assert "message_hash" in recv_bob["payload"]

                    # 2. Upload file & verify that path is saved in the database
                    upload_resp = client.post(
                        "/api/v1/files/upload",
                        headers={"X-Sender-ID": "alice", "X-Recipient-ID": "bob"},
                        files={"file": ("confidential.pdf", b"highly secret bytes", "application/pdf")},
                    )
                    assert upload_resp.status_code == 201
                    upload_data = upload_resp.json()
                    transfer_id = upload_data["transfer_id"]
                    stored_path = upload_data["stored_path"]

                    # List files - should load from database
                    list_resp = client.get("/api/v1/files", params={"peer_id": "bob"})
                    assert list_resp.status_code == 200
                    files = list_resp.json()["files"]
                    assert len(files) == 1
                    assert files[0]["transfer_id"] == transfer_id
                    assert files[0]["stored_path"] == stored_path
                    assert "confidential.pdf" in files[0]["file_name"]

                    # Delete file
                    delete_resp = client.delete(
                        f"/api/v1/files/{transfer_id}",
                        headers={"X-Peer-ID": "alice"},
                    )
                    assert delete_resp.status_code == 204

                    # After deletion, it should be marked as deleted in DB and not listed
                    list_resp_after = client.get("/api/v1/files", params={"peer_id": "bob"})
                    assert len(list_resp_after.json()["files"]) == 0
    finally:
        settings.upload_dir = original_upload_dir
