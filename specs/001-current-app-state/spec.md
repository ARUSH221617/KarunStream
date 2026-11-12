# Feature Specification: KarunStream Current State (Core LAN Chat, Messenger & High-Speed File Streaming)

**Feature Branch**: `001-current-app-state`

**Created**: 2026-11-12

**Status**: Baseline Specification

**Input**: User description: "init github spec and write spec for current state of app"

---

## 1. Executive Summary & Architecture Context

KarunStream is an offline-first, internet-independent, cross-platform local area network (LAN) communication and high-speed data exchange suite. It provides zero-configuration discovery, encrypted local messaging, group/channel collaboration, real-time folder synchronization, and high-throughput file transfers across Windows, macOS, Linux, Android, iOS, and Web without relying on any external cloud server, third-party authentication provider, or public internet connectivity.

The system is partitioned into three coordinated modules:
1. **Server Daemon (`server/`)**: An asynchronous Python service built on FastAPI, Uvicorn, SQLAlchemy 2.0 (async SQLite with `aiosqlite`), and `zeroconf`. It acts as an mDNS announcer, WebSocket event orchestrator, and high-speed chunked file streamer.
2. **Client Application (`client/`)**: A cross-platform Flutter application utilizing Riverpod 3 for state management, Dio for chunked streaming, `web_socket_channel` for signaling, `multicast_dns` alongside parallel subnet scanning for zero-config discovery, and native desktop system tray integration.
3. **Shared Schemas (`shared/schemas/`)**: JSON Schema definitions guaranteeing binary-exact protocol compliance between client and daemon.

---

## 2. User Scenarios & Testing *(mandatory)*

### User Story 1 - Zero-Config LAN Peer & Server Auto-Discovery (Priority: P1)

As a user on a local network (home Wi-Fi, office Ethernet, or mobile hotspot without internet), I want KarunStream to automatically discover nearby active nodes without requiring me to look up or type IP addresses, so that I can immediately start collaborating with zero friction.

**Why this priority**: Zero-configuration discovery is the core foundation of KarunStream. Without discovery, users cannot connect, chat, or transfer files.

**Independent Test**:
Launch the Python server on machine A and the Flutter client on machine B on the same Wi-Fi subnet. The client must discover and list the server in under 4 seconds via mDNS or automatic subnet sweep and auto-connect to the orchestrator WebSocket.

**Acceptance Scenarios**:
1. **Given** a Python server daemon running with mDNS service `_karunstream._tcp` on port 8080, **When** the Flutter client launches on the same subnet, **Then** the client detects the server via `MDnsClient`, fetches `/api/v1/system/status`, and establishes a WebSocket connection to `/ws/orchestrator`.
2. **Given** a network where mDNS multicast packets are blocked by the Wi-Fi router, **When** discovery begins, **Then** the client automatically falls back to an asynchronous parallel subnet scan (chunked probing of `/24` address blocks), identifies the server at `http://<target_ip>:8080`, and connects.
3. **Given** no active server exists on the network, **When** discovery completes without candidates, **Then** the client presents the user with an intuitive connection screen with manual IP/port input and retry capabilities.

---

### User Story 2 - Real-Time Subnet Messenger & Persistent Conversations (Priority: P1)

As a connected peer, I want to participate in 1-on-1 direct chats, multi-user groups, and broadcast channels, sending text, formatted links, and attachments that are persisted in a local database and verified for tamper integrity.

**Why this priority**: Instant communication and coordination are primary functions of the app. Conversations must be persistent and tamper-evident across sessions.

**Independent Test**:
Create a group conversation with multiple peers, send text messages, edit an existing message, and verify that all connected members receive real-time updates via WebSockets and can query full history via REST with verified SHA-256 integrity hashes.

**Acceptance Scenarios**:
1. **Given** two registered peers on the server, **When** Peer A sends a direct message to Peer B, **Then** the server persists the message in SQLite, calculates a deterministic SHA-256 message hash (`compute_message_hash`), relays the `CHAT_MESSAGE` event over WebSocket to Peer B, and returns delivery confirmation.
2. **Given** an existing message authored by Peer A, **When** Peer A edits the text via the Flutter UI, **Then** the client sends a `CHAT_EDIT` event, the server updates `is_edited=True`, recomputes the integrity hash, and broadcasts the modification to all conversation participants.
3. **Given** an existing message, **When** the sender deletes it, **Then** the client emits `CHAT_DELETE`, and the server marks the message as `is_deleted=True` while suppressing its body in subsequent queries.
4. **Given** a conversation history request to `/api/v1/conversations/{id}/messages`, **When** the server reads messages, **Then** it validates each message's body, timestamp, and sender against its stored SHA-256 hash, identifying any corrupted or externally modified records.

---

### User Story 3 - High-Speed Chunked File Transfers with End-to-End Verification (Priority: P1)

As a user with large files (videos, documents, disk images, codebases), I want to send files directly over the local network at maximum physical interface speed, monitor real-time progress and average transfer rates, and cancel in-flight transfers if needed, with guaranteed cryptographic bit integrity.

**Why this priority**: High-speed, internet-free file transfer is KarunStream's signature capability. It must outperform cloud uploads and ensure zero file corruption.

**Independent Test**:
Upload a 200MB test file from the Flutter client to the server daemon, verify streaming chunk consumption in the server without memory spike, verify SHA-256 matching, initiate a download from a second client, observe live transfer speed and progress, and verify the saved file matches the original hash.

**Acceptance Scenarios**:
1. **Given** a file selected via the client file picker, **When** the user clicks send, **Then** the client streams the file via multipart HTTP `POST /api/v1/files/upload` with headers `X-Sender-ID` and `X-Recipient-ID`.
2. **Given** an incoming upload stream on the server, **When** bytes arrive, **Then** the server streams chunks (64 KB - 1 MB) directly to disk using a threadpool worker executor, updates SHA-256 incrementally, saves metadata to `FileRecord`, and registers the transfer in `file_registry`.
3. **Given** an active download from `/api/v1/files/{transfer_id}/download`, **When** the downloading user presses "Cancel", **Then** the client cancels the Dio `CancelToken`, deletes the partial local file, and resets transfer state cleanly.
4. **Given** a file upload completed by Peer A, **When** Peer A deletes the file via `DELETE /api/v1/files/{transfer_id}`, **Then** the server verifies `record.sender_id == x_peer_id`, removes the file from disk, deletes the database record, and broadcasts `FILE_DELETED` to all peers.

---

### User Story 4 - Live Folder Sharing & File Synchronization (Priority: P2)

As a desktop or mobile user, I want to expose a specific directory on my machine as a shared workspace folder so that other peers on the LAN can browse its file tree and fetch files on-demand.

**Why this priority**: Enables frictionless team folder sharing without configuring OS-level network sharing protocols (SMB, NFS, or FTP).

**Independent Test**:
Select a local directory in the client to share. Verify a `FOLDER_SHARE` event is broadcast with the relative paths and sizes of all files. Add a new file to the folder, verify the local file watcher detects the change and automatically emits an updated file list, and verify a remote peer can request and receive a file via `SHARE_FILE_REQUEST`.

**Acceptance Scenarios**:
1. **Given** a local directory selected by Peer A, **When** Peer A confirms sharing, **Then** the client indexes the directory recursively, assigns a `share_id`, and emits `FOLDER_SHARE` over the WebSocket.
2. **Given** an actively shared folder, **When** the user adds, deletes, or modifies a file inside the folder, **Then** the local directory watcher triggers a debounced re-scan and emits an updated `FOLDER_SHARE` payload.
3. **Given** Peer B browsing Peer A's shared folder, **When** Peer B clicks to download a file, **Then** Peer B sends `SHARE_FILE_REQUEST`, Peer A's client uploads the requested file to the daemon, emits `SHARE_FILE_READY` with the resulting `transfer_id`, and Peer B downloads the file via HTTP.

---

### User Story 5 - Session Persistence & Native Desktop Integration (Priority: P2)

As a user running KarunStream on a desktop or mobile device, I want my peer identity, nickname, and server connection settings to be remembered across app restarts, and I want the desktop app to minimize to the system tray and run seamlessly in the background.

**Why this priority**: Prevents user annoyance from re-entering nicknames and re-discovering servers on every app restart.

**Independent Test**:
Set custom nickname and connect to a server. Close and reopen the app. Verify that `SharedPreferences` restores the peer ID, nickname, and server URI, and initiates a microtask auto-reconnect. Verify minimizing to tray on Windows hides the taskbar icon while keeping transfers active.

**Acceptance Scenarios**:
1. **Given** an established session, **When** the app is terminated and relaunched, **Then** `LanWorkspaceController` loads `peerId`, `nickname`, and `lastConnectedServerUri` from `SharedPreferences`, auto-initiates connection, and registers with the orchestrator.
2. **Given** the app running on Windows with `minimizeToTray=true`, **When** the user clicks the window close or minimize button, **Then** `windows_tray_helper` hides the main window to the system notification area and displays a tray menu with "Show KarunStream" and "Exit".

---

## 3. Edge Cases & Handling

1. **Duplicate Upload Filenames**:
   - *Condition*: Two peers or the same peer uploads files with identical names (e.g., `document.pdf`).
   - *Behavior*: The server utilizes `_unique_destination` to generate sequential non-colliding disk filenames (`document-1.pdf`, `document-2.pdf`) while preserving original metadata in headers.
2. **Directory Traversal / Malicious Paths**:
   - *Condition*: An upload filename contains sequences like `../../etc/passwd` or absolute path syntax.
   - *Behavior*: `safe_upload_path` sanitizes incoming filenames via `Path(filename).name`, strictly prohibiting directory escape.
3. **Network Switch / Multi-Adapter Binding**:
   - *Condition*: A host has multiple active network interfaces (e.g. Ethernet `192.168.1.50` and Wi-Fi `10.0.0.12`).
   - *Behavior*: The Python server binds to `0.0.0.0` to listen on all interfaces. The client mDNS and subnet scanner aggregate interfaces, probing all non-loopback IPv4 subnets concurrently.
4. **WebSocket Sudden Disconnect & Ghost Peers**:
   - *Condition*: A peer's Wi-Fi drops or the process terminates without clean TCP shutdown.
   - *Behavior*: Periodic heartbeat pings detect stale sockets; the server unregisters ghost peers and broadcasts `PEER_LEAVE` to keep rosters synchronized.
5. **Database Engine Test Isolation**:
   - *Condition*: Running pytest suites against SQLite database engines under Python 3.13 on Windows.
   - *Behavior*: Services resolve `session_factory` dynamically via `@property`. Tests inject in-memory `sqlite+aiosqlite:///:memory:` engines synchronously using `asyncio.run()` to prevent event loop cancellation during Starlette lifespan shutdowns.
6. **Download Interruption / Incomplete Transfers**:
   - *Condition*: Client aborts an in-progress file download or loses socket connection.
   - *Behavior*: The client intercepts cancellation via Dio `CancelToken`, removes partial `.part` or target files from disk, and resets state without corrupting downloads.

---

## 4. Requirements *(mandatory)*

### Functional Requirements

#### Discovery & Network Orchestration
- **FR-001**: Server MUST broadcast mDNS service announcements using service type `_karunstream._tcp.local` on its active HTTP port (default 8080).
- **FR-002**: Server MUST expose `GET /api/v1/system/status` returning server health, server UUID, version, and active peer count.
- **FR-003**: Server MUST provide a persistent WebSocket endpoint at `/ws/orchestrator` for real-time peer signaling, heartbeat monitoring, and event relaying.
- **FR-004**: Client MUST automatically probe both mDNS service records and active local IPv4 subnet ranges (`192.168.x.x`, `10.x.x.x`, `172.16-31.x.x`, and loopbacks) to locate listening servers.

#### Peer Registry & Presence
- **FR-005**: Clients connecting to `/ws/orchestrator` MUST send a `PeerRegistration` payload containing `peer_id`, `nickname`, `platform`, and optional `avatar_index`.
- **FR-006**: Server MUST maintain an in-memory `PeerRegistry` mapping active WebSocket channels to peer identities and broadcast `PEER_JOIN`, `PEER_LEAVE`, and `PEER_LIST` events.
- **FR-007**: Server MUST persist peer identities in the `users` SQLite table to maintain cross-session profile consistency.

#### Messaging & Collaboration
- **FR-008**: Server MUST support three conversation types: `private` (1-on-1), `group` (multi-peer with title/description), and `channel` (broadcast).
- **FR-009**: Server MUST expose REST endpoints:
  - `POST /api/v1/conversations`: Create private/group/channel.
  - `GET /api/v1/conversations`: List conversations for the calling peer (`X-Peer-ID`).
  - `GET /api/v1/conversations/{id}/messages`: Fetch paginated message history.
  - `POST /api/v1/conversations/{id}/members`: Add participant.
  - `DELETE /api/v1/conversations/{id}/members/{peer_id}`: Remove participant / leave.
- **FR-010**: Every persisted message MUST include a cryptographic SHA-256 hash computed deterministically from `msg_id`, `sender_id`, `conversation_id`, `body`, and `timestamp`.
- **FR-011**: The messages endpoint MUST verify integrity hashes during history retrieval and flag any modified/corrupted message IDs in `corrupted_msg_ids`.
- **FR-012**: Clients MUST support real-time message editing (`CHAT_EDIT`) and deletion (`CHAT_DELETE`) with instant broadcast to all members.

#### File Streaming & Verification
- **FR-013**: Server MUST provide `POST /api/v1/files/upload` accepting multipart file payloads streamed directly to disk in chunks via worker threads.
- **FR-014**: Server MUST compute SHA-256 hashes incrementally during streaming without buffering entire files in RAM.
- **FR-015**: Server MUST reject uploads exceeding configured maximum size limits (`max_upload_bytes`) with HTTP 413.
- **FR-016**: Server MUST provide `GET /api/v1/files/{transfer_id}/download` streaming files with `X-Transfer-ID` and `X-Content-SHA256` headers.
- **FR-017**: Server MUST provide `DELETE /api/v1/files/{transfer_id}` restricting deletion to the original uploading sender (`X-Peer-ID`).
- **FR-018**: Client MUST calculate local SHA-256 hashes on downloaded files and notify users of any integrity mismatch.
- **FR-019**: Client MUST track real-time transfer telemetry, including percent progress, current transfer speed (e.g., `MB/s`), and running average speed.

#### Live Folder Sharing
- **FR-020**: Client MUST allow users to select local file directories to share with the LAN.
- **FR-021**: Client MUST broadcast folder structure metadata via `FOLDER_SHARE` and announce removal via `FOLDER_UNSHARE`.
- **FR-022**: Client MUST run a filesystem watcher over shared folders, automatically debouncing and broadcasting updates when contents change.
- **FR-023**: Remote peers MUST be able to request shared folder files via `SHARE_FILE_REQUEST`, prompting the sharing client to upload the file to the daemon and return `SHARE_FILE_READY`.

#### Client Persistence & System Integration
- **FR-024**: Client MUST persist peer ID, nickname, and last-connected server URI in `SharedPreferences`.
- **FR-025**: Client MUST attempt automatic reconnection to the last-known server on application startup.
- **FR-026**: Desktop clients (Windows) MUST support minimize-to-system-tray and background execution.

---

## 5. Key Entities & Data Schema

### User / Peer
- `peer_id` (String UUID): Natural client identifier.
- `nickname` (String): Display name.
- `platform` (String): OS identifier (`android`, `ios`, `windows`, `macos`, `linux`, `web`).
- `avatar_index` (Integer, optional): Preset avatar index.
- `ip` (String): Host IP address.
- `connected_at` / `last_seen` (Float timestamp).

### Conversation
- `conversation_id` (String UUID): Unique container identifier.
- `conversation_type` (Enum): `private`, `group`, or `channel`.
- `title` (String, optional for private).
- `description` (String, optional).
- `created_by` (String peer ID).
- `is_archived` (Boolean).
- `members` (List of `ConversationMember` with role `owner`, `admin`, `member`).

### Message
- `msg_id` (String UUID): Unique message identifier.
- `conversation_id` (String UUID): Parent conversation.
- `sender_id` (String peer ID): Authoring peer.
- `body` (Text): Content of message.
- `message_type` (Enum): `text`, `system`, `link`, `file`.
- `is_edited` (Boolean) & `is_deleted` (Boolean).
- `reply_to_msg_id` (String UUID, optional).
- `message_hash` (String SHA-256): Deterministic integrity signature.
- `attachments` (List of `MessageAttachment`).

### FileTransferRecord / FileOffer
- `transfer_id` (String UUID): Transfer session identifier.
- `sender_id` (String peer ID) & `recipient_id` (String peer ID or conversation ID).
- `file_name` (String): Cleaned file name.
- `bytes` / `file_size` (Integer >= 0).
- `sha256` (String 64-char hex): Checksum.
- `stored_path` (String): Daemon local filesystem location.
- `download_url` (String): Relative download route.

### SharedFolder
- `share_id` (String UUID): Unique folder share identifier.
- `peer_id` (String peer ID) & `peer_nickname` (String).
- `name` (String): Folder name.
- `files` (List of `SharedFolderFile` containing `relative_path`, `file_name`, `file_size`).

---

## 6. Measurable Success Criteria *(mandatory)*

- **SC-001 (Discovery Speed)**: Automatic discovery of an active LAN daemon across identical subnet occurs within $\le 4.0$ seconds without manual IP entry.
- **SC-002 (Transfer Throughput)**: Large file streaming achieves $\ge 80\%$ of physical interface network bandwidth (saturating 100 Mbps / 1 Gbps LAN without memory bloat on sender, daemon, or recipient).
- **SC-003 (Cryptographic Integrity)**: 100% of completed transfers and stored messages pass automated SHA-256 verification with zero bit errors.
- **SC-004 (Offline Operation)**: All core capabilities (discovery, chat, file transfers, folder sync) function with 0 bytes transmitted over the public internet.
- **SC-005 (Graceful Cancellation)**: In-flight download cancellation stops network consumption immediately and leaves no orphaned, incomplete files on the recipient device.
- **SC-006 (Session Recovery)**: Client application restarts automatically re-establish connection and workspace context in $\le 1.5$ seconds using persisted session state.

---

## 7. Assumptions & Boundaries

### In-Scope Boundaries
- Pure local area network communication (Wi-Fi, Ethernet, Hotspot, Ad-hoc).
- Single-daemon or multi-daemon local mesh coordination.
- Transient and locally persisted SQLite data storage.

### Out-of-Scope Boundaries
- Public internet routing, cloud sync, and remote relays (STUN, TURN, ICE).
- User identity accounts, phone numbers, or passwords.
- Real-time video/voice WebRTC streaming (reserved for future milestones).
