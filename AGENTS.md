# Repository Guidelines

## Project Structure & Module Organization

This repository currently contains the product requirements for KarunStream in `LAN Sharing App PRD.md`. The planned application has two main modules:

- `server/`: Python LAN daemon/API, WebSocket orchestration, mDNS discovery, file-transfer endpoints, and Docker assets.
- `client/`: Flutter app for mobile, desktop, and web clients.
- `tests/`: Automated tests, grouped by module when implementation begins (for example, `tests/server/` and `client/test/`).
- `docs/`: Design notes, API contracts, screenshots, and follow-up specifications.

Keep generated files, local downloads, transfer fixtures, and secrets out of the repository.

## Build, Test, and Development Commands

No build system is committed yet. When adding tooling, document commands in the relevant module README and keep root commands predictable. Recommended examples:

- `docker compose up --build`: build and run the Python LAN server locally.
- `pytest`: run Python server tests.
- `flutter pub get`: install Flutter client dependencies.
- `flutter test`: run Flutter unit and widget tests.
- `flutter run -d <device>`: launch the client on a selected device.

Prefer scripts or Make targets only when they wrap repeatable workflows used by contributors.

## Coding Style & Naming Conventions

For Python, use 4-space indentation, type hints for public functions, `snake_case` for modules/functions, and `PascalCase` for classes. Prefer asynchronous FastAPI/`asyncio` patterns for network code. For Flutter/Dart, follow `dart format`, use `lower_snake_case.dart` filenames, `camelCase` members, and `PascalCase` widgets/classes. Keep protocol event names explicit and stable, such as `CHAT_MESSAGE` and `FILE_OFFER`.

## Testing Guidelines

Add tests with every behavioral change once code exists. Server tests should cover API contracts, WebSocket events, mDNS/discovery behavior where practical, file hash verification, filename sanitization, and resume/error handling. Flutter tests should cover state management, protocol serialization, and core UI flows. Name Python tests `test_*.py`; name Dart tests `*_test.dart`.

## Advanced Development & Integration Guidelines

### Python 3.13 Async SQLite & Windows Compatibility
* Compiling the `greenlet` dependency from source fails on Windows under Python 3.13. Always pin `greenlet==3.5.3` (or use a compatible precompiled wheel version) when setting up asynchronous SQLite engines with SQLAlchemy.

### Dynamic SQLAlchemy Session Factories in Services
* Services instantiated at import-time (e.g., `db_service = DatabaseService()`) must resolve `session_factory` dynamically via a `@property` rather than caching it once during `__init__`. This allows test engines to override the global database URL dynamically (e.g., to run tests in a clean `sqlite+aiosqlite:///:memory:` database).

### Test Isolation & Async Fixtures
* When writing Python test suites that use `fastapi.testclient.TestClient` inside synchronous test functions, do not use `async def` fixtures. Instead, use synchronous fixtures and run async database resets/initializations synchronously using `asyncio.run(reset_engine_for_testing(...))`. This prevents the TestClient event loop from raising `CancelledError` during WebSocket lifecycle execution.

### Client-Server Model Alignment
* Always verify that property keys of serialized attachments or file offers (e.g., `'file_offers'` vs `'attachments'`) are identically named and mapped across the WebSocket event routing logic and the HTTP REST history endpoints. This prevents media/attachments from disappearing from lists when reloading or reopening threads.

### Client Session Persistence
* Save client peer identity (`peerId`) and the last connected server URI in `SharedPreferences` to ensure they persist across app restarts, reloads, or web browser refreshes. Schedule a background microtask connection to auto-restore sessions seamlessly on startup.

## Commit & Pull Request Guidelines

There is no established Git history yet, so use concise Conventional Commit-style messages, such as `feat: add websocket peer registry` or `fix: sanitize upload filenames`. Pull requests should include a short summary, testing performed, linked issue or requirement, and screenshots/GIFs for UI changes. Call out network, security, or Docker configuration changes clearly.

## Security & Configuration Tips

KarunStream is local-first: do not add cloud relays, telemetry, or external account dependencies without explicit approval. Never commit certificates, private keys, `.env` files, or captured user transfers. Validate filenames, bind server services intentionally, and document any ports required for LAN discovery or file transfer.

## Business & Brand Guidelines

KarunStream is an internet-independent, cross-platform LAN application for real-time chat and high-speed file transfers. Keep product decisions aligned with an offline-first, zero-configuration experience for secure, high-bandwidth data exchange across iOS, Android, Windows, macOS, desktop, mobile, and web clients without cloud server reliance.

Core brand values are privacy-first, zero-configuration, cross-platform compatibility, and offline-first operation. Visual and product work should feel modern, clean, seamless, and efficient. Use a technical, precise, professional, utility-focused tone in copy, documentation, UI text, and marketing content.

When creating brand or UI assets, prefer the brand colors `#253858`, `#42526E`, `#FF8B00`, and `#FFFFFF`, and the fonts Kanit and Vazirmatn where practical. Existing campaign creative assets live under `business-assets/`; keep references to generated campaign files synchronized with `business.json`.

Campaign themes emphasize avoiding cloud uploads, internet-free transfer speed, cross-OS compatibility, local data privacy, no-signal operation, field-tested privacy, offline coordination, and peak-season reliability.
