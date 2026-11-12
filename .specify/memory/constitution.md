# KarunStream Constitution

## Core Principles

### I. Offline-First & Zero-Cloud Dependency (NON-NEGOTIABLE)
KarunStream is strictly local-first and internet-independent. Under no circumstances may features introduce cloud relays, external telemetry, STUN/TURN/ICE infrastructure, third-party authentication services, or external database identity management. All peer-to-peer messaging, signaling, and file streaming must operate fully within the local subnet (LAN/WLAN). If a host loses external internet connectivity, KarunStream must remain 100% operational.

### II. Zero-Configuration Discovery
Users must never be required to type IP addresses, configure port forwarding, or manage Samba/NFS shares to communicate. Discovery must happen seamlessly over Multicast DNS (`_karunstream._tcp`) complemented by intelligent parallel subnet scanning across active network interfaces (e.g., Wi-Fi, Ethernet, virtual adapters). A manual fallback must be available solely as an emergency diagnostic option.

### III. Maximum Throughput & Bit-Exact File Integrity
File transfers must utilize the maximum physical throughput of the local network interface without buffering entire files in system RAM. File streaming must use asynchronous chunking (1 MB to 4 MB chunks) with non-blocking disk I/O. Every file transferred must be verified end-to-end using SHA-256 cryptographic hashes. If a hash mismatch occurs or a transfer is aborted, partial files must be handled cleanly without leaving orphaned corrupted data.

### IV. Cross-Platform Parity
KarunStream client must maintain consistent capabilities and cohesive UX across Android, iOS, Windows, macOS, Linux, and Web clients. The backend must run either as a lightweight Dockerized daemon or bare-metal process. Native OS integrations (such as Windows system tray, Android scoped storage, and desktop file drag-and-drop) must be leveraged gracefully without compromising cross-platform uniformity.

### V. Shared Protocol Contracts
All WebSocket signaling and messaging payloads must conform to versioned, strict JSON schemas maintained in `shared/schemas/`. Backend models (Pydantic / SQLAlchemy) and frontend models (Dart Freezed / Riverpod) must remain strictly synchronized in property naming, validation constraints, and serialization rules.

---

## Technical Constraints & Standards

### 1. Technology Stack
- **Backend**: Python 3.12+ / 3.13, FastAPI (asynchronous), Uvicorn, SQLAlchemy 2.0 (async ORM via `aiosqlite`), Zeroconf for mDNS.
  - *Windows Compatibility*: Pin `greenlet==3.5.3` (or precompiled binary wheel) to prevent compilation failures on Windows under Python 3.13.
  - *Dynamic Database Engine*: Database service instances must resolve `session_factory` dynamically through properties rather than caching an initial engine at module import time, ensuring test suites can inject in-memory SQLite instances.
- **Frontend**: Flutter 3.x (Dart 3.x), Material 3 design system, Riverpod 3 (state management), Dio (HTTP/streaming), `web_socket_channel` (signaling), SQLite (`sqflite` / `sqflite_common_ffi`).
- **Brand & Styling**: Primary palette `#253858`, `#42526E`, `#FF8B00`, `#FFFFFF`. Kanit / Vazirmatn typography.

### 2. Security Standards
- **Path Sanitization**: All incoming file names and upload paths must be strictly sanitized. Absolute paths, `..` directory traversal sequences, null bytes, and non-printable control characters must be rejected or stripped before disk writes.
- **Local Network Safety**: The daemon must bind intentionally to configurable host/ports and gracefully handle network transitions.
- **Message Integrity**: Persisted messages must include deterministic SHA-256 message hashes to verify message tamper resistance across client-server persistence.

### 3. Testing Gates
- **Backend Quality**: 100% of API endpoints, WebSocket event flows, mDNS announcements, and file hash verifications must be covered by automated `pytest` test suites.
- **Test Isolation**: In test suites utilizing `fastapi.testclient.TestClient`, synchronous test runners must run database resets and setup synchronously (using `asyncio.run`) to avoid event loop cancellation warnings.
- **Frontend Quality**: State controllers, data serialization, and models must be verified using `flutter test`.

---

## Governance

1. **Constitution Authority**: This constitution represents the foundational architectural law of the KarunStream codebase. Any specification, plan, task, or implementation that violates these principles (especially cloud relays or external dependencies) is invalid.
2. **Amendment Process**: Amendments require documented rationale, architectural review, and explicit approval before updating `.specify/memory/constitution.md`.
3. **Traceability**: All new features must proceed through the Spec Kit workflow: `speckit-specify` → `speckit-plan` → `speckit-tasks` → `speckit-implement` → `speckit-converge`.

**Version**: 1.0.0 | **Ratified**: 2026-11-12 | **Last Amended**: 2026-11-12
