# KarunStream Server

Python LAN daemon/API for KarunStream, built from the PRD as a Docker-ready FastAPI service.

## Features

- HTTP status and peer roster endpoints under `/api/v1`.
- WebSocket orchestration at `/ws/orchestrator` for peer registration, heartbeat, chat, and file-offer events.
- Chunked multipart upload endpoint at `/api/v1/files/upload` with SHA-256 calculation, filename sanitization, transfer metadata, and download links.
- mDNS advertisement for `_karunstream._tcp.local.` when host networking allows multicast.
- Rolling local logs and configurable upload/log directories.

## Run With Docker Compose

From the repository root:

```bash
docker compose up --build
```

The API listens on `http://localhost:8080`. Docker Compose maps TCP `8080` and UDP `5353`; Linux hosts can use host networking for best mDNS behavior:

```bash
docker build -t karunstream-server ./server
docker run --rm --network host karunstream-server
```

On Docker Desktop for Windows/macOS, multicast discovery can be limited by the VM network. Use manual pairing with the host IP and port `8080` if mDNS is not visible.

## Local Development

```bash
cd server
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
pytest
```

## Configuration

All settings use the `KARUNSTREAM_` prefix:

- `KARUNSTREAM_PORT`: API/WebSocket port, default `8080`.
- `KARUNSTREAM_UPLOAD_DIR`: directory for uploaded files.
- `KARUNSTREAM_LOG_DIR`: directory for rolling logs.
- `KARUNSTREAM_ENABLE_MDNS`: enable/disable mDNS advertisement.
- `KARUNSTREAM_ENABLE_TLS`: run Uvicorn with local cert/key files from `KARUNSTREAM_TLS_DIR`.
- `KARUNSTREAM_MAX_UPLOAD_BYTES`: upload size limit.

## WebSocket Registration

The first message sent after connecting registers the peer:

```json
{
  "peer_id": "u1",
  "nickname": "Sarah",
  "platform": "iOS",
  "avatar_index": 1
}
```

## File Sharing API

Upload a file with peer headers:

```bash
curl -F "file=@./demo.zip" \
  -H "X-Sender-ID: peer-a" \
  -H "X-Recipient-ID: peer-b" \
  http://localhost:8080/api/v1/files/upload
```

The response includes `transfer_id`, `sha256`, `bytes`, and `download_url`. Peers can list available transfers with `GET /api/v1/files?peer_id=peer-b`, inspect one transfer with `GET /api/v1/files/{transfer_id}`, and download bytes with `GET /api/v1/files/{transfer_id}/download`. Uploaders can delete their own server copy with `DELETE /api/v1/files/{transfer_id}` and the `X-Peer-ID` header.

Subsequent messages use the shared event wrapper:

```json
{
  "event_type": "CHAT_MESSAGE",
  "payload": {
    "sender_id": "u1",
    "receiver_id": "global",
    "body": "Ready to test this stream?"
  }
}
```
