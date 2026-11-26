from __future__ import annotations

from collections.abc import AsyncGenerator
from typing import Any

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.config import get_settings

_engine: AsyncEngine | None = None
_session_factory: async_sessionmaker[AsyncSession] | None = None


class OfflineStubResult:
    """Minimal query result returned by `OfflineStubSession` when offline."""

    def scalar_one_or_none(self) -> None:
        return None

    def scalars(self) -> OfflineStubResult:
        return self

    def all(self) -> list[Any]:
        return []


class OfflineStubSession:
    """Zero-lock stub session for offline execution without a live DB container."""

    is_stub: bool = True

    async def execute(self, *_args: Any, **_kwargs: Any) -> OfflineStubResult:
        return OfflineStubResult()

    async def scalar(self, *_args: Any, **_kwargs: Any) -> None:
        return None

    def add(self, _instance: Any) -> None:
        return None

    def add_all(self, _instances: Any) -> None:
        return None

    async def flush(self) -> None:
        return None

    async def delete(self, _instance: Any) -> None:
        return None

    async def commit(self) -> None:
        return None

    async def rollback(self) -> None:
        return None

    async def refresh(self, _instance: Any) -> None:
        return None

    async def close(self) -> None:
        return None


def get_engine(database_url: str | None = None) -> AsyncEngine:
    """Lazily construct the async SQLAlchemy engine without connecting on import."""
    global _engine
    if _engine is None or database_url is not None:
        url = database_url or get_settings().database_url
        engine = create_async_engine(url, echo=False, pool_pre_ping=True)
        if database_url is not None:
            return engine
        _engine = engine
    return _engine


def get_session_factory(
    engine: AsyncEngine | None = None,
) -> async_sessionmaker[AsyncSession]:
    """Lazily construct the async sessionmaker."""
    global _session_factory
    if engine is not None:
        return async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    if _session_factory is None:
        _session_factory = async_sessionmaker(
            get_engine(),
            expire_on_commit=False,
            class_=AsyncSession,
        )
    return _session_factory


async def get_db() -> AsyncGenerator[AsyncSession | OfflineStubSession]:
    """FastAPI dependency yielding an async DB session or offline stub session."""
    settings = get_settings()
    if settings.offline_stub_db:
        yield OfflineStubSession()
        return

    factory = get_session_factory()
    async with factory() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise


async def check_db_health() -> dict[str, str]:
    """Check database readiness safely without raising unhandled exceptions."""
    settings = get_settings()
    if settings.offline_stub_db:
        return {"status": "stub", "mode": "offline"}
    try:
        engine = get_engine()
        async with engine.connect() as conn:
            await conn.execute(sa.text("SELECT 1"))
        return {"status": "ok"}
    except Exception as exc:
        return {"status": "unavailable", "detail": type(exc).__name__}


def reset_db_state() -> None:
    """Reset cached engine/sessionmaker (useful in tests)."""
    global _engine, _session_factory
    _engine = None
    _session_factory = None
