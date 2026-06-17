import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.services.shares import share_registry
from app.services.sockets import registry


@pytest.fixture(autouse=True)
def clean_registries():
    registry._peers.clear()
    registry._connections.clear()
    share_registry._shares.clear()


def test_folder_sharing_flow() -> None:
    with TestClient(app) as client:
        # 1. Connect Peer A (Host) and Peer B (Requester)
        with client.websocket_connect("/ws/orchestrator") as ws_a:
            ws_a.send_json({"peer_id": "peer-a", "nickname": "Alice", "platform": "Windows"})
            roster_a = ws_a.receive_json()
            assert roster_a["event_type"] == "PEER_LIST"

            with client.websocket_connect("/ws/orchestrator") as ws_b:
                ws_b.send_json({"peer_id": "peer-b", "nickname": "Bob", "platform": "macOS"})
                roster_b = ws_b.receive_json()
                assert roster_b["event_type"] == "PEER_LIST"

                # Peer A receives PEER_JOIN for Peer B
                join_b = ws_a.receive_json()
                assert join_b["event_type"] == "PEER_JOIN"

                # 2. Peer A shares folder
                folder_payload = {
                    "share_id": "share-1",
                    "peer_id": "peer-a",
                    "peer_nickname": "Alice",
                    "name": "MyDocuments",
                    "files": [
                        {"relative_path": "report.pdf", "file_name": "report.pdf", "file_size": 1024},
                        {"relative_path": "images/pic.png", "file_name": "pic.png", "file_size": 2048}
                    ]
                }
                ws_a.send_json({"event_type": "FOLDER_SHARE", "payload": folder_payload})

                # Peer B receives FOLDER_SHARE broadcast
                share_event = ws_b.receive_json()
                assert share_event["event_type"] == "FOLDER_SHARE"
                assert share_event["payload"]["share_id"] == "share-1"
                assert len(share_event["payload"]["files"]) == 2

                # 3. Check HTTP GET /shares lists the folder
                response = client.get("/api/v1/shares")
                assert response.status_code == 200
                shares_list = response.json()["shares"]
                assert len(shares_list) == 1
                assert shares_list[0]["share_id"] == "share-1"

                # 4. Peer B requests download of report.pdf
                req_payload = {
                    "request_id": "req-1",
                    "share_id": "share-1",
                    "relative_path": "report.pdf",
                    "recipient_id": "peer-a"
                }
                ws_b.send_json({"event_type": "SHARE_FILE_REQUEST", "payload": req_payload})

                # Peer A receives SHARE_FILE_REQUEST routed from Peer B
                req_event = ws_a.receive_json()
                assert req_event["event_type"] == "SHARE_FILE_REQUEST"
                assert req_event["payload"]["request_id"] == "req-1"
                assert req_event["payload"]["sender_id"] == "peer-b"

                # 5. Peer A responds with SHARE_FILE_READY
                ready_payload = {
                    "request_id": "req-1",
                    "transfer_id": "transfer-xyz",
                    "relative_path": "report.pdf",
                    "recipient_id": "peer-b"
                }
                ws_a.send_json({"event_type": "SHARE_FILE_READY", "payload": ready_payload})

                # Peer B receives SHARE_FILE_READY routed from Peer A
                ready_event = ws_b.receive_json()
                assert ready_event["event_type"] == "SHARE_FILE_READY"
                assert ready_event["payload"]["request_id"] == "req-1"
                assert ready_event["payload"]["transfer_id"] == "transfer-xyz"
                assert ready_event["payload"]["sender_id"] == "peer-a"

            # 6. Peer B disconnects (exited the with-block).
            # Now let's close Peer A to trigger automatic cleanup.
            # Peer A unregisters -> triggers folder cleanup.
            
        # Check HTTP GET /shares after Peer A disconnects
        response = client.get("/api/v1/shares")
        assert response.status_code == 200
        assert len(response.json()["shares"]) == 0
