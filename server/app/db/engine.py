"""SQLAlchemy engine, session factory, and Base for KarunStream.

SQLite is the default store – lightweight, zero-config, and perfect for a
LAN-only server that must work without cloud dependencies.
"""

from __future__ import annotations

from pathlib import Path
from typing import AsyncGenerator

from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import AsyncAdaptedQueuePool

from app.core.config import get_settings


class Base(DeclarativeBase):
    """Shared declarative base for all ORM models."""


_engine = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


def _build_db_url() -> str:
    settings = get_settings()
    db_path: Path = settings.db_path
    db_path.parent.mkdir(parents=True, exist_ok=True)
    return f"sqlite+aiosqlite:///{db_path}"


def _is_memory_db(engine) -> bool:
    """True for SQLite in-memory URLs (including shared-cache variants)."""
    database = engine.url.database or ""
    return not database or database == ":memory:"


def _attach_sqlite_pragmas(engine) -> None:
    """Tune SQLite connections for throughput.

    - WAL journaling lets readers and the writer operate concurrently and
      avoids the fsync-per-commit cost of the default rollback journal.
    - NORMAL synchronous is safe under WAL (only a checkpoint syncs fully).
    - A larger page cache speeds up repeated reads of hot tables.
    In-memory databases do not support WAL; those keep their defaults.
    """
    use_wal = not _is_memory_db(engine.sync_engine)

    @event.listens_for(engine.sync_engine, "connect")
    def _set_sqlite_pragma(dbapi_connection, _connection_record) -> None:  # pragma: no cover
        cursor = dbapi_connection.cursor()
        try:
            if use_wal:
                cursor.execute("PRAGMA journal_mode=WAL")
                cursor.execute("PRAGMA synchronous=NORMAL")
            cursor.execute("PRAGMA temp_store=MEMORY")
            cursor.execute("PRAGMA cache_size=-8000")  # ~8 MiB page cache
        finally:
            cursor.close()


def _create_engine(db_url: str):
    """Create an async engine tuned for SQLite workloads.

    The aiosqlite dialect uses a QueuePool (one pooled connection per
    concurrent writer) instead of the default NullPool so connections are
    reused across requests.
    """
    kwargs = {}
    if ":memory:" not in (db_url or ""):
        kwargs = {"pool_size": 5, "max_overflow": 10}
    engine = create_async_engine(
        db_url,
        echo=False,
        future=True,
        poolclass=None if ":memory:" in (db_url or "") else AsyncAdaptedQueuePool,
        pool_pre_ping=True,
        connect_args={"check_same_thread": False},
        **kwargs,
    )
    _attach_sqlite_pragmas(engine)
    return engine


def get_engine():
    global _engine
    if _engine is None:
        _engine = _create_engine(_build_db_url())
    return _engine


def get_session_factory() -> async_sessionmaker[AsyncSession]:
    global _session_factory
    if _session_factory is None:
        _session_factory = async_sessionmaker(
            bind=get_engine(),
            class_=AsyncSession,
            expire_on_commit=False,
        )
    return _session_factory


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI dependency – yields a per-request async session."""
    factory = get_session_factory()
    async with factory() as session:
        yield session


async def init_db() -> None:
    """Create all tables if they don't exist yet.  Called once at startup."""
    engine = get_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def close_db() -> None:
    """Dispose of the engine pool.  Called once at shutdown."""
    global _engine, _session_factory
    if _engine is not None:
        await _engine.dispose()
        _engine = None
        _session_factory = None


async def reset_engine_for_testing(db_url: str) -> None:
    """Replace the global engine with one pointed at a test-only DB."""
    global _engine, _session_factory
    if _engine is not None:
        await _engine.dispose()
    _engine = _create_engine(db_url)
    _session_factory = async_sessionmaker(
        bind=_engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )
    async with _engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
