from fastapi.testclient import TestClient

from app.main import app


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
