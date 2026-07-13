"""SQLAlchemy engine, session factory, and Base for KarunStream.

SQLite is the default store – lightweight, zero-config, and perfect for a
LAN-only server that must work without cloud dependencies.
"""

from __future__ import annotations

from pathlib import Path
from typing import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

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


def get_engine():
    global _engine
    if _engine is None:
        _engine = create_async_engine(
            _build_db_url(),
            echo=False,
            future=True,
            connect_args={"check_same_thread": False},
        )
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
    _engine = create_async_engine(
        db_url,
        echo=False,
        future=True,
        connect_args={"check_same_thread": False},
    )
    _session_factory = async_sessionmaker(
        bind=_engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )
    async with _engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
