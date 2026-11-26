from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.health import router as health_router
from app.api.v1.router import api_v1_router
from app.config import Settings, get_settings
from app.db.base import Base
from app.db.seeds import seed_reference_data
from app.db.session import get_engine, get_session_factory


def create_app(settings: Settings | None = None) -> FastAPI:
    """Create and configure the FastAPI application instance."""
    cfg = settings or get_settings()

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        if not cfg.offline_stub_db:
            engine = get_engine(cfg.database_url)
            async with engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
            factory = get_session_factory(engine)
            async with factory() as session:
                await seed_reference_data(session)
        yield

    application = FastAPI(
        title=cfg.app_name,
        version="0.1.0",
        debug=cfg.debug,
        docs_url="/docs",
        redoc_url="/redoc",
        lifespan=lifespan,
    )

    application.add_middleware(
        CORSMiddleware,
        allow_origins=cfg.cors_origins,
        allow_origin_regex=cfg.cors_origin_regex,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Root readiness probe (`/health`) + versioned API (`/api/v1/...`, incl. `/api/v1/health`)
    application.include_router(health_router)
    application.include_router(api_v1_router, prefix=cfg.api_v1_prefix)

    return application


app = create_app()
