from __future__ import annotations

import json
from pathlib import Path
from uuid import uuid4

import jsonschema
from jsonschema import Draft202012Validator
from fastapi.testclient import TestClient
import pytest

from app.main import app
from app.models import (
    ChatPayload,
    ChunkHashRecord,
    ErrorCode,
    ErrorEventPayload,
    FileOfferPayload,
    PairingPayload,
    PeerHandshake,
    SystemStatus,
    TransferInitPayload,
    TransferManifestPayload,
)

SCHEMAS_V1_DIR = Path(__file__).resolve().parents[2] / "shared" / "schemas" / "v1"


def load_schema(name: str) -> dict:
    schema_file = SCHEMAS_V1_DIR / name
    assert schema_file.is_file(), f"Schema file not found: {schema_file}"
    return json.loads(schema_file.read_text(encoding="utf-8"))


def test_schemas_conform_to_draft_202012() -> None:
    schema_files = list(SCHEMAS_V1_DIR.glob("*.json"))
    assert len(schema_files) >= 6, f"Expected at least 6 schemas in v1, found {len(schema_files)}"

    for schema_file in schema_files:
        schema = json.loads(schema_file.read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)


def test_transfer_init_contract_and_model() -> None:
    schema = load_schema("transfer_init.json")
    validator = Draft202012Validator(schema)

    # 1. Pydantic model generation and validation
    model = TransferInitPayload(
        sender_id="peer-alice",
        recipient_id="peer-bob",
        file_name="video.mp4",
        total_bytes=10485760,
        chunk_size=1048576,
        sha256_prefix="a" * 64,
        metadata={"mtime": 1700000000.0, "mime_type": "video/mp4"},
    )
    payload = model.model_dump(mode="json")
    validator.validate(payload)

    # 2. Minimal valid payload
    minimal_payload = {
        "transfer_id": str(uuid4()),
        "sender_id": "sender-1",
        "recipient_id": "recipient-1",
        "file_name": "data.bin",
        "total_bytes": 0,
    }
    validator.validate(minimal_payload)

    # 3. Payload with empty / null sha256_prefix
    payload_empty_hash = {
        **minimal_payload,
        "sha256_prefix": "",
    }
    validator.validate(payload_empty_hash)

    payload_null_hash = {
        **minimal_payload,
        "sha256_prefix": None,
    }
    validator.validate(payload_null_hash)

    # 4. Reject missing required field
    with pytest.raises(jsonschema.ValidationError):
        bad_payload = dict(minimal_payload)
        del bad_payload["file_name"]
        validator.validate(bad_payload)

    # 5. Reject negative total_bytes
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({**minimal_payload, "total_bytes": -1})

    # 6. Reject chunk_size below minimum (65536)
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({**minimal_payload, "chunk_size": 1024})

    # 7. Reject invalid sha256_prefix pattern
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({**minimal_payload, "sha256_prefix": "not-a-valid-hex-hash"})

    # 8. Reject invalid transfer_id (not UUID)
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({**minimal_payload, "transfer_id": "12345-not-uuid"})

    # 9. Reject additional unknown properties
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({**minimal_payload, "extra_unexpected_field": True})


def test_transfer_manifest_contract_and_model() -> None:
    schema = load_schema("transfer_manifest.json")
    validator = Draft202012Validator(schema)

    # 1. Pydantic model generation and validation
    chunk_1 = ChunkHashRecord(
        chunk_index=0,
        byte_offset=0,
        byte_length=1048576,
        sha256="b" * 64,
    )
    chunk_2 = ChunkHashRecord(
        chunk_index=1,
        byte_offset=1048576,
        byte_length=524288,
        sha256="c" * 64,
    )
    manifest_model = TransferManifestPayload(
        chunk_size=1048576,
        total_chunks=2,
        chunks=[chunk_1, chunk_2],
    )
    payload = manifest_model.model_dump(mode="json")
    validator.validate(payload)

    # 2. Reject missing chunks array
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "transfer_id": str(uuid4()),
            "chunk_size": 1048576,
            "total_chunks": 1,
        })

    # 3. Reject chunk_size < 65536
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "transfer_id": str(uuid4()),
            "chunk_size": 32768,
            "total_chunks": 1,
            "chunks": [{"chunk_index": 0, "byte_offset": 0, "byte_length": 32768, "sha256": "0" * 64}],
        })

    # 4. Reject total_chunks < 1
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "transfer_id": str(uuid4()),
            "chunk_size": 1048576,
            "total_chunks": 0,
            "chunks": [],
        })

    # 5. Reject invalid chunk sha256
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "transfer_id": str(uuid4()),
            "chunk_size": 1048576,
            "total_chunks": 1,
            "chunks": [{"chunk_index": 0, "byte_offset": 0, "byte_length": 1024, "sha256": "bad-sha"}],
        })

    # 6. Reject negative chunk_index or byte_offset
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "transfer_id": str(uuid4()),
            "chunk_size": 1048576,
            "total_chunks": 1,
            "chunks": [{"chunk_index": -1, "byte_offset": 0, "byte_length": 1024, "sha256": "0" * 64}],
        })

    # 7. Reject extra property
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "transfer_id": str(uuid4()),
            "chunk_size": 1048576,
            "total_chunks": 1,
            "chunks": [],
            "unknown_field": "disallowed",
        })


def test_peer_handshake_contract_and_model() -> None:
    schema = load_schema("peer_handshake.json")
    validator = Draft202012Validator(schema)

    # 1. Pydantic model generation and validation
    handshake = PeerHandshake(
        v="1.0",
        peer_id="peer-12345",
        nickname="Charlie",
        platform="windows",
        capabilities=["resume", "chunk_manifest", "folders", "tus_upload"],
        tls_fingerprint="d" * 64,
        auth_token="jwt-token-sample",
    )
    payload = handshake.model_dump(mode="json")
    validator.validate(payload)

    # 2. Handshake with default / none optional fields
    handshake_default = PeerHandshake()
    validator.validate(handshake_default.model_dump(mode="json"))

    # 3. Reject invalid platform
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "v": "1.0",
            "peer_id": "p-1",
            "nickname": "Test",
            "platform": "symbian",
            "capabilities": ["resume"],
        })

    # 4. Reject invalid tls_fingerprint
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "v": "1.0",
            "peer_id": "p-1",
            "nickname": "Test",
            "platform": "linux",
            "capabilities": ["resume"],
            "tls_fingerprint": "too-short",
        })

    # 5. Reject missing required v
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "peer_id": "p-1",
            "nickname": "Test",
            "platform": "linux",
            "capabilities": ["resume"],
        })

    # 6. Reject extra property
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "v": "1.0",
            "peer_id": "p-1",
            "nickname": "Test",
            "platform": "linux",
            "capabilities": ["resume"],
            "extra_field": "not-allowed",
        })


def test_error_event_contract_and_model() -> None:
    schema = load_schema("error_event.json")
    validator = Draft202012Validator(schema)

    # 1. Pydantic model for every ErrorCode enum
    for error_code in ErrorCode:
        model = ErrorEventPayload(
            error_code=error_code,
            message=f"Error occurred: {error_code.value}",
            transfer_id=str(uuid4()),
            details={"reason": "test-suite", "code": error_code.value},
        )
        validator.validate(model.model_dump(mode="json"))

    # 2. Reject unknown error_code
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "event_type": "ERROR",
            "error_code": "UNKNOWN_ERROR_CODE",
            "message": "Something went wrong",
            "timestamp": 123456789.0,
        })

    # 3. Reject wrong event_type
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "event_type": "WARNING",
            "error_code": "OUT_OF_SPACE",
            "message": "Out of disk space",
            "timestamp": 123456789.0,
        })

    # 4. Reject missing message
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "event_type": "ERROR",
            "error_code": "OUT_OF_SPACE",
            "timestamp": 123456789.0,
        })

    # 5. Reject extra property
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "event_type": "ERROR",
            "error_code": "OUT_OF_SPACE",
            "message": "Out of space",
            "timestamp": 123456789.0,
            "extra_key": 42,
        })


def test_chat_message_contract_and_model() -> None:
    schema = load_schema("chat_message.json")
    validator = Draft202012Validator(schema)

    model = ChatPayload(
        sender_id="peer-1",
        receiver_id="peer-2",
        body="Hello world",
        message_type="text",
    )
    validator.validate(model.model_dump(mode="json"))

    # Reject missing sender_id
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "msg_id": "msg-1",
            "receiver_id": "peer-2",
            "body": "Hello",
            "timestamp": 123456.0,
        })

    # Reject extra property
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "msg_id": "msg-1",
            "sender_id": "peer-1",
            "receiver_id": "peer-2",
            "body": "Hello",
            "timestamp": 123456.0,
            "unexpected": "reject-me",
        })


def test_file_offer_contract_and_model() -> None:
    schema = load_schema("file_offer.json")
    validator = Draft202012Validator(schema)

    model = FileOfferPayload(
        sender_id="peer-1",
        file_name="archive.zip",
        file_size=2048,
        sha256="e" * 64,
        download_url="/api/v1/files/download",
    )
    validator.validate(model.model_dump(mode="json"))

    # Reject invalid sha256
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "transfer_id": "t-1",
            "sender_id": "peer-1",
            "file_name": "archive.zip",
            "file_size": 2048,
            "sha256": "invalid-hex",
        })

    # Reject negative file_size
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({
            "transfer_id": "t-1",
            "sender_id": "peer-1",
            "file_name": "archive.zip",
            "file_size": -5,
            "sha256": "e" * 64,
        })


def test_system_status_endpoint_and_model_contract() -> None:
    schema = load_schema("system_status.json")
    validator = Draft202012Validator(schema)

    # 1. Pydantic model validation
    model = SystemStatus(
        server_id="test-server",
        version="0.1.0",
        active_peers=1,
    )
    validator.validate(model.model_dump(mode="json"))

    # 2. HTTP GET endpoint contract validation
    with TestClient(app) as client:
        response = client.get("/api/v1/system/status")

    assert response.status_code == 200
    data = response.json()

    # Validate against JSON schema
    validator.validate(data)

    # Verify capabilities explicitly
    expected_capabilities = ["resume", "chunk_manifest", "folders", "tus_upload"]
    assert "capabilities" in data
    assert isinstance(data["capabilities"], list)
    for cap in expected_capabilities:
        assert cap in data["capabilities"]


def test_pairing_payload_contract_and_model() -> None:
    schema = load_schema("pairing_payload.json")
    validator = Draft202012Validator(schema)

    # 1. Pydantic model validation
    model = PairingPayload(
        pairing_url="karunstream://pair?v=1&ip=192.168.1.10&port=8080",
        host_ip="192.168.1.10",
        port=8080,
        auth_token="secure-token-123",
        tls_fingerprint="a" * 64,
        wifi_qr="WIFI:S:TestNet;T:WPA;P:password;H:false;;",
        server_name="KarunStream LAN",
    )
    validator.validate(model.model_dump(mode="json"))

    # 2. Minimal payload
    minimal = {
        "pairing_url": "karunstream://pair?v=1&ip=10.0.0.1&port=9000",
        "host_ip": "10.0.0.1",
        "port": 9000,
        "server_name": "Minimal Server",
    }
    validator.validate(minimal)

    # 3. Payload with null optional fields
    with_nulls = {
        **minimal,
        "auth_token": None,
        "tls_fingerprint": None,
        "wifi_qr": None,
    }
    validator.validate(with_nulls)

    # 4. Reject missing required field
    for req_field in ["pairing_url", "host_ip", "port", "server_name"]:
        bad = dict(minimal)
        del bad[req_field]
        with pytest.raises(jsonschema.ValidationError):
            validator.validate(bad)

    # 5. Reject invalid port
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({**minimal, "port": 0})
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({**minimal, "port": 70000})

    # 6. Reject invalid pairing_url
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({**minimal, "pairing_url": "http://pair?ip=10.0.0.1"})

    # 7. Reject extra property
    with pytest.raises(jsonschema.ValidationError):
        validator.validate({**minimal, "extra_unexpected": "disallowed"})

    # 8. HTTP GET endpoint contract validation
    with TestClient(app) as client:
        response = client.get("/api/v1/system/pair-payload")

    assert response.status_code == 200
    data = response.json()
    validator.validate(data)
    assert data["pairing_url"].startswith("karunstream://pair")
    assert isinstance(data["port"], int)
    assert isinstance(data["host_ip"], str)
