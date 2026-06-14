# KarunStream Design Document

This document outlines the technical architecture, communication protocols, and visual design system for **KarunStream**, as derived from the Product Requirement Document (PRD) and Business Identity specifications.

---

## 1. System Architecture

KarunStream follows a **Client-Server** model designed specifically for local network environments. 

### 1.1 High-Level Component Diagram
```text
┌──────────────────────────────────────────────────────────┐
│                      Local Wi-Fi / LAN                   │
│                                                          │
│   ┌───────────────┐     UDP / mDNS Discovery    ┌───────────────┐
│   │ Flutter Client│ <─────────────────────────> │ Docker Server │
│   │ (KarunStream) │      WebSocket (Chat)       │   (Python)    │
│   └───────┬───────┘ <─────────────────────────> └───────┬───────┘
│           │                                             │
│           │            Direct TCP Socket / HTTP         │
│           └─────────────────────────────────────────────┘
└──────────────────────────────────────────────────────────┘
```

### 1.2 Module Breakdown
- **Backend (Python/FastAPI):** Acts as the "Orchestrator." Handles peer registration, mDNS broadcasting, WebSocket relay for chat, and metadata management for file transfers.
- **Frontend (Flutter):** Multi-platform GUI. Handles user interactions, local file system access, WebSocket client state, and high-speed binary streaming.
- **Shared (JSON Schemas):** Strictly defined contracts for network payloads to ensure interoperability between the Python and Dart implementations.

---

## 2. Backend Design (The Orchestrator)

### 2.1 Core Technologies
- **Framework:** FastAPI (Asynchronous Python).
- **Network Engine:** `asyncio` for raw socket handling.
- **Discovery:** `zeroconf` for mDNS broadcasting and service discovery.
- **Containerization:** Alpine-based Docker image for minimal footprint (< 50MB RAM idle).

### 2.2 Peer Discovery (mDNS)
- **Service Type:** `_karunstream._tcp`
- **Payload:** Advertises the server's Hostname, IP, and Port.
- **Multi-Interface:** Binds to `0.0.0.0` to listen on all active NICs (Wi-Fi, Ethernet).

### 2.3 API Strategy
- **REST (HTTP):** Used for system status and heavy multipart file uploads (for smaller/medium files).
- **WebSockets (WS):** Persistent channel for heartbeats, chat messages, and file transfer signaling.

---

## 3. Frontend Design (The Client)

### 3.1 Tech Stack
- **Framework:** Flutter (Material 3).
- **State Management:** `ChangeNotifier` with `ListenableBuilder` (built-in Flutter solutions).
- **Navigation:** `go_router` for deep-link capability and web compatibility.
- **Storage:** SQLite (via `sqflite`) or simple JSON for local transient history.

### 3.2 File Transfer Logic
- **Chunked Transfer:** Binary data is split into 1MB - 4MB chunks to prevent memory overflow on mobile devices.
- **SHA-256 Verification:** Computed locally on both ends to ensure 100% data integrity.
- **Resume Capability:** Byte-offset tracking to allow transfers to resume after network drops.

---

## 4. Communication Protocols

### 4.1 WebSocket Event Schema
All signaling follows a unified JSON structure:
```json
{
  "event_type": "STRING",
  "payload": { ... }
}
```
**Common Events:**
- `CHAT_MESSAGE`: Global or peer-to-peer text.
- `FILE_OFFER`: Initial handshake for file transfers (Name, Size, Hash).
- `FILE_ACCEPT / FILE_DECLINE`: Peer response to file offers.
- `PEER_JOIN / PEER_LEAVE`: Membership updates.

### 4.2 File Streaming
- **Small Files:** Transferred via `POST /api/v1/files/upload`.
- **Large Files:** Direct TCP streams (sender to recipient) or fast-relay through the Python server's memory buffer.

---

## 5. Security Architecture

1. **Local TLS:** Self-signed certificates generated at runtime by the Python server. Clients perform "Local Trust" for certificates within the subnet.
2. **Path Sanitization:** Backend strictly strips `../` and absolute paths to prevent Directory Traversal attacks.
3. **Zero-Cloud Policy:** The application logic contains no code for WAN routing, STUN/TURN, or external telemetry.
4. **Sandboxing:** Flutter clients use `Document` (iOS/macOS) or `Scoped Storage` (Android) to respect OS-level security.

---

## 6. Visual Design System

Consistent with the `business.json` identity, the UI focuses on a "Utility-Focused Professional" aesthetic.

### 6.1 Brand Colors
- **Primary (Accent):** `#FF8B00` (Amber/Orange) - Used for action buttons, progress bars, and "Online" indicators.
- **Dark Neutral:** `#253858` (Navy Blue) - Primary background for dark mode and header surfaces.
- **Mid Neutral:** `#42526E` (Steel Grey) - Secondary text, borders, and inactive states.
- **Light:** `#FFFFFF` (White) - Primary background for light mode.

### 6.2 Typography
- **Headlines:** `Kanit` (Bold/Medium) - For a modern, technical feel.
- **Body/UI:** `Vazirmatn` - For high legibility across platforms, especially for multilingual support.

### 6.3 UI Principles
- **Modern & Clean:** Minimalist cards with multi-layered drop shadows for depth.
- **Efficient:** Real-time speed charts and clear "Time Remaining" (ETA) calculations during transfers.
- **Touch-Friendly:** Large tap targets (48dp+) for mobile clients.

---

## 7. Data Models

### 7.1 Peer Model
```json
{
  "peer_id": "UUID",
  "nickname": "String",
  "platform": "iOS | Android | Windows | macOS | Linux | Web",
  "ip_address": "String",
  "avatar_index": "Int"
}
```

### 7.2 File Transfer State
```json
{
  "transfer_id": "UUID",
  "status": "Pending | Active | Paused | Completed | Failed",
  "progress_bytes": "Long",
  "total_bytes": "Long",
  "current_speed": "String (e.g., 45MB/s)"
}
```
