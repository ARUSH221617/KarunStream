import asyncio
from pathlib import Path
import pytest

from app.core.config import get_settings
from app.db.engine import reset_engine_for_testing, close_db
from app.services.sockets import registry
from app.services.files import file_registry
from app.services.shares import share_registry


@pytest.fixture(autouse=True)
def test_environment(tmp_path: Path):
    """Global test fixture: isolate DB, storage, and networking across every test."""
    settings = get_settings()
    settings.enable_mdns = False
    original_upload_dir = settings.upload_dir
    test_upload_dir = tmp_path / "uploads"
    test_upload_dir.mkdir(parents=True, exist_ok=True)
    settings.upload_dir = test_upload_dir

    # Initialize a clean in-memory SQLite database using StaticPool
    asyncio.run(reset_engine_for_testing("sqlite+aiosqlite:///:memory:"))

    # Clean in-memory registries
    registry._peers.clear()
    registry._connections.clear()
    file_registry.clear()
    share_registry._shares.clear()

    yield

    # Clean teardown of database engine
    asyncio.run(close_db())
    settings.upload_dir = original_upload_dir
