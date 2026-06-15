# KarunStream Client

Flutter client for KarunStream LAN chat and file sharing.

## Run

```bash
flutter pub get
flutter run -d <device>
```

Start the Python LAN server first:

```bash
docker compose up --build
```

The current client entrypoint opens a local-first KarunStream lobby, attempts LAN server discovery, and supports manual pairing with a URL such as `http://127.0.0.1:8080` or `http://<server-lan-ip>:8080`.

## Implemented Starter Scope

- Brand-themed Material 3 shell using KarunStream colors.
- Manual/automatic server connection panel.
- WebSocket registration, heartbeat, peer roster, and lobby chat.
- Shared protocol models for peers, chat messages, file offers, and server status.
- Android/iOS local-network permissions for cleartext LAN development and Bonjour discovery.
