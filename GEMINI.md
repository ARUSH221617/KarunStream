# KarunStream: LAN Chat & High-Speed File Sharing

KarunStream is an internet-independent, cross-platform local area network (LAN) application designed for real-time chat and high-speed file transfers. It provides an offline-first, zero-configuration solution for secure, high-bandwidth data exchange across iOS, Android, Windows, macOS, and Linux without relying on cloud servers.

## Project Overview

- **Purpose:** Fast, private, and offline-first file sharing and chat over LAN.
- **Core Technology Stack:**
  - **Backend:** Python (FastAPI, WebSockets, mDNS/UDP discovery) - containerized with Docker.
  - **Frontend:** Flutter (Mobile, Desktop, Web).
  - **Protocol:** Custom JSON-based messaging over WebSockets for signaling and chat; TCP/HTTP for file streams.
- **Architecture:** Monorepo containing separate modules for backend, frontend, and shared schemas.

## Intended Project Structure

```text
karunstream/                    # Monorepo Root
├── backend/                    # Python Server Component
│   ├── app/                    # FastAPI application logic
│   ├── Dockerfile              # Production Docker setup
│   └── requirements.txt        # Python dependencies
├── frontend/                   # Flutter Client Component
│   ├── lib/                    # Flutter source code
│   └── pubspec.yaml            # Flutter dependencies
├── shared/                     # Centralized Contract Definitions
│   └── schemas/                # JSON schemas for WebSocket messaging
├── docker-compose.yml          # Orchestrates local backend development
├── LAN Sharing App PRD.md      # Product Requirement Document
└── AGENTS.md                   # Repository Guidelines and Conventions
```

## Building and Running (Planned)

### Backend (Python)
- **Docker:** `docker-compose up --build` (recommended for Linux/Headless).
- **Manual:** `pip install -r backend/requirements.txt` and run `python backend/app/main.py`.

### Frontend (Flutter)
- **Install Dependencies:** `cd frontend && flutter pub get`.
- **Run App:** `flutter run -d <device_id>`.

## Development Conventions

### Coding Standards
- **Python:**
  - Follow PEP 8 (4-space indentation).
  - Use type hints for all public functions.
  - Naming: `snake_case` for modules/functions, `PascalCase` for classes.
  - Prefer asynchronous patterns (`asyncio`, FastAPI).
- **Flutter/Dart:**
  - Strictly adhere to `dart format`.
  - Naming: `lower_snake_case.dart` for files, `camelCase` for members, `PascalCase` for classes/widgets.

### Network & Security
- **Privacy First:** No cloud relays, external trackers, or telemetry. All data stays within the local subnet.
- **Discovery:** Automatic peer discovery via mDNS (`_karunstream._tcp`).
- **Validation:** Always sanitize incoming filenames and verify file integrity using SHA-256 hashes.

### Testing Guidelines
- **Python:** Use `pytest`. Tests located in `backend/tests/`.
- **Dart:** Use `flutter test`. Tests located in `frontend/test/`.
- **Requirements:** Add tests for every behavioral change. Cover API contracts, WebSocket events, and file transfer edge cases (e.g., resumes, low disk space).

## Key Files
- `LAN Sharing App PRD.md`: Comprehensive product requirements and technical scope.
- `AGENTS.md`: Detailed repository guidelines, module organization, and coding styles.
- `business.json`: Brand identity, colors, typography, and creative campaign metadata.
- `business-assets/`: Branding and marketing creative resources.
