from __future__ import annotations

from collections.abc import AsyncGenerator

import pytest
import pytest_asyncio
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import Settings
from app.db.base import Base
from app.db.seeds import seed_reference_data
from app.db.session import OfflineStubSession, get_db
from app.main import create_app


@pytest.fixture
def offline_settings() -> Settings:
    """Settings configured strictly for offline execution."""
    return Settings(
        app_env="test",
        debug=False,
        database_url="sqlite+aiosqlite:///:memory:",
        offline_stub_db=True,
        gemini_api_key="",
        jwt_secret_key="test-secret-key-for-offline-unit-tests-only-32chars",
    )


@pytest.fixture
def stub_app(offline_settings: Settings) -> FastAPI:
    """FastAPI app wired with zero-lock `OfflineStubSession`."""
    application = create_app(offline_settings)

    async def _override_stub_db() -> AsyncGenerator[OfflineStubSession]:
        yield OfflineStubSession()

    application.dependency_overrides[get_db] = _override_stub_db
    return application


@pytest.fixture
def stub_client(stub_app: FastAPI) -> TestClient:
    """Synchronous TestClient against the zero-lock offline stub app."""
    with TestClient(stub_app) as client:
        yield client


@pytest_asyncio.fixture
async def sqlite_session_factory() -> AsyncGenerator[async_sessionmaker[AsyncSession]]:
    """In-memory SQLite async engine with all ORM tables & 25-province seeds."""
    engine = create_async_engine("sqlite+aiosqlite:///:memory:", echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with factory() as seed_session:
        await seed_reference_data(seed_session)

    try:
        yield factory
    finally:
        await engine.dispose()


@pytest.fixture
def sqlite_app(
    offline_settings: Settings,
    sqlite_session_factory: async_sessionmaker[AsyncSession],
) -> FastAPI:
    """FastAPI app backed by the seeded in-memory SQLite database."""
    application = create_app(offline_settings)

    async def _override_sqlite_db() -> AsyncGenerator[AsyncSession]:
        async with sqlite_session_factory() as session:
            yield session

    application.dependency_overrides[get_db] = _override_sqlite_db
    return application
