from __future__ import annotations

from typing import Any

from fastapi import APIRouter

from app.config import get_settings
from app.db.session import check_db_health

router = APIRouter(tags=["Health"])


@router.get("/health", summary="Readiness and service health probe")
async def health_check() -> dict[str, Any]:
    """Return service readiness status for Docker, load balancers, and offline tests."""
    settings = get_settings()
    db_status = await check_db_health()
    return {
        "status": "ok",
        "service": settings.app_name,
        "environment": settings.app_env,
        "checks": {
            "database": db_status,
            "redis": {"status": "configured" if settings.redis_url else "unconfigured"},
            "storage": {"status": "configured" if settings.s3_bucket_name else "unconfigured"},
            "ai_proxy": {
                "status": "configured" if settings.gemini_api_key.strip() else "unconfigured"
            },
        },
    }
