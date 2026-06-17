import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.services.sockets import registry

@pytest.fixture(autouse=True)
def clean_registry():
    registry._peers.clear()
    registry._connections.clear()

def test_websocket_registers_and_echoes_heartbeat() -> None:
    with TestClient(app) as client:
        with client.websocket_connect("/ws/orchestrator") as websocket:
            websocket.send_json({"peer_id": "peer-1", "nickname": "Alex", "platform": "Linux"})
            roster = websocket.receive_json()
            assert roster["event_type"] == "PEER_LIST"
            assert roster["payload"]["peers"][0]["peer_id"] == "peer-1"

            websocket.send_json({"event_type": "HEARTBEAT", "payload": {}})
            heartbeat = websocket.receive_json()

    assert heartbeat["event_type"] == "HEARTBEAT"
    assert "timestamp" in heartbeat["payload"]

def test_websocket_chat_routing() -> None:
    with TestClient(app) as client:
        with client.websocket_connect("/ws/orchestrator") as ws1:
            ws1.send_json({"peer_id": "peer-1", "nickname": "Alex", "platform": "Linux"})
            roster1 = ws1.receive_json()
            assert roster1["event_type"] == "PEER_LIST"

            with client.websocket_connect("/ws/orchestrator") as ws2:
                ws2.send_json({"peer_id": "peer-2", "nickname": "Bob", "platform": "macOS"})
                roster2 = ws2.receive_json()
                assert roster2["event_type"] == "PEER_LIST"

                # Peer 1 receives PEER_JOIN
                join_event = ws1.receive_json()
                assert join_event["event_type"] == "PEER_JOIN"
                assert join_event["payload"]["peer_id"] == "peer-2"

                # Direct Chat message from Peer 1 to Peer 2
                chat_payload = {
                    "sender_id": "peer-1",
                    "receiver_id": "peer-2",
                    "body": "Hello Bob!",
                    "message_type": "text"
                }
                ws1.send_json({"event_type": "CHAT_MESSAGE", "payload": chat_payload})
                
                # Peer 2 receives it
                recv_msg = ws2.receive_json()
                assert recv_msg["event_type"] == "CHAT_MESSAGE"
                assert recv_msg["payload"]["body"] == "Hello Bob!"
                assert recv_msg["payload"]["sender_id"] == "peer-1"

                # Global Chat message from Peer 2
                global_payload = {
                    "sender_id": "peer-2",
                    "receiver_id": "global",
                    "body": "Hello world",
                    "message_type": "text"
                }
                ws2.send_json({"event_type": "CHAT_MESSAGE", "payload": global_payload})

                # Both receive it
                recv_global1 = ws1.receive_json()
                assert recv_global1["event_type"] == "CHAT_MESSAGE"
                assert recv_global1["payload"]["body"] == "Hello world"

                recv_global2 = ws2.receive_json()
                assert recv_global2["event_type"] == "CHAT_MESSAGE"
                assert recv_global2["payload"]["body"] == "Hello world"

                # Chat Edit
                edit_payload = {
                    "msg_id": recv_global2["payload"]["msg_id"],
                    "sender_id": "peer-2",
                    "receiver_id": "global",
                    "body": "Hello world (edited)",
                    "message_type": "text",
                    "is_edited": True
                }
                ws2.send_json({"event_type": "CHAT_EDIT", "payload": edit_payload})

                recv_edit1 = ws1.receive_json()
                assert recv_edit1["event_type"] == "CHAT_EDIT"
                assert recv_edit1["payload"]["is_edited"] is True
                assert recv_edit1["payload"]["body"] == "Hello world (edited)"

                recv_edit2 = ws2.receive_json()
                assert recv_edit2["event_type"] == "CHAT_EDIT"
                assert recv_edit2["payload"]["body"] == "Hello world (edited)"

                # Chat Delete
                delete_payload = {"msg_id": recv_global2["payload"]["msg_id"]}
                ws2.send_json({"event_type": "CHAT_DELETE", "payload": delete_payload})

                recv_del1 = ws1.receive_json()
                assert recv_del1["event_type"] == "CHAT_DELETE"
                assert recv_del1["payload"]["msg_id"] == delete_payload["msg_id"]

                recv_del2 = ws2.receive_json()
                assert recv_del2["event_type"] == "CHAT_DELETE"

def test_websocket_file_offer_routing() -> None:
    with TestClient(app) as client:
        with client.websocket_connect("/ws/orchestrator") as ws1:
            ws1.send_json({"peer_id": "peer-1", "nickname": "Alex", "platform": "Linux"})
            ws1.receive_json() # PEER_LIST

            with client.websocket_connect("/ws/orchestrator") as ws2:
                ws2.send_json({"peer_id": "peer-2", "nickname": "Bob", "platform": "macOS"})
                ws2.receive_json() # PEER_LIST
                ws1.receive_json() # PEER_JOIN

                # Direct File Offer from Peer 1 to Peer 2
                offer_payload = {
                    "sender_id": "peer-1",
                    "receiver_id": "peer-2",
                    "file_name": "test.txt",
                    "file_size": 1024,
                    "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" # 64 chars
                }
                ws1.send_json({"event_type": "FILE_OFFER", "payload": offer_payload})

                recv_offer = ws2.receive_json()
                assert recv_offer["event_type"] == "FILE_OFFER"
                assert recv_offer["payload"]["file_name"] == "test.txt"

                # Peer 2 accepts file offer
                accept_payload = {
                    "transfer_id": recv_offer["payload"]["transfer_id"],
                    "sender_id": "peer-2",
                    "receiver_id": "peer-1",
                    "status": "accepted"
                }
                ws2.send_json({"event_type": "FILE_ACCEPT", "payload": accept_payload})

                recv_accept = ws1.receive_json()
                assert recv_accept["event_type"] == "FILE_ACCEPT"
                assert recv_accept["payload"]["transfer_id"] == accept_payload["transfer_id"]

                # Broadcast File Offer from Peer 1 (receiver_id is None or empty)
                broadcast_offer = {
                    "sender_id": "peer-1",
                    "file_name": "broadcast.txt",
                    "file_size": 512,
                    "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
                }
                ws1.send_json({"event_type": "FILE_OFFER", "payload": broadcast_offer})

                recv_broadcast_offer = ws2.receive_json()
                assert recv_broadcast_offer["event_type"] == "FILE_OFFER"
                assert recv_broadcast_offer["payload"]["file_name"] == "broadcast.txt"

def test_websocket_error_handling() -> None:
    with TestClient(app) as client:
        with client.websocket_connect("/ws/orchestrator") as ws1:
            ws1.send_json({"peer_id": "peer-1", "nickname": "Alex", "platform": "Linux"})
            ws1.receive_json() # PEER_LIST

            # Route to an offline peer
            chat_payload = {
                "sender_id": "peer-1",
                "receiver_id": "offline-peer",
                "body": "Hello?",
                "message_type": "text"
            }
            ws1.send_json({"event_type": "CHAT_MESSAGE", "payload": chat_payload})

            error_msg = ws1.receive_json()
            assert error_msg["event_type"] == "ERROR"
            assert "Recipient is not connected" in error_msg["payload"]["message"]

            # Invalid Event Type (validation error on WebSocketEvent.event_type)
            ws1.send_json({"event_type": "UNKNOWN_ACTION", "payload": {}})
            error_msg = ws1.receive_json()
            assert error_msg["event_type"] == "ERROR"
            assert "Invalid event payload" in error_msg["payload"]["message"]

            # Invalid Payload / Pydantic validation error (e.g. missing required field sender_id on ChatPayload)
            ws1.send_json({"event_type": "CHAT_MESSAGE", "payload": {"body": "no sender"}})
            error_msg = ws1.receive_json()
            assert error_msg["event_type"] == "ERROR"
            assert "Invalid event payload" in error_msg["payload"]["message"]

            # Unsupported event type (but valid EventType enum value)
            ws1.send_json({"event_type": "PEER_JOIN", "payload": {}})
            error_msg = ws1.receive_json()
            assert error_msg["event_type"] == "ERROR"
            assert "Unsupported event type" in error_msg["payload"]["message"]
