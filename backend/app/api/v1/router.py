from __future__ import annotations

from fastapi import APIRouter

from app.api.v1.ai import router as ai_router
from app.api.v1.authority.analytics import router as authority_analytics_router
from app.api.v1.authority.queue import router as authority_queue_router
from app.api.v1.citizen.alerts import router as citizen_alerts_router
from app.api.v1.citizen.auth import router as citizen_auth_router
from app.api.v1.citizen.comments import router as citizen_comments_router
from app.api.v1.citizen.reports import router as citizen_reports_router
from app.api.v1.citizen.support import router as citizen_support_router
from app.api.v1.health import router as health_router
from app.api.v1.ws import router as ws_router

api_v1_router = APIRouter()
api_v1_router.include_router(health_router)
api_v1_router.include_router(ws_router)
api_v1_router.include_router(ai_router)
api_v1_router.include_router(citizen_auth_router)
api_v1_router.include_router(citizen_reports_router)
api_v1_router.include_router(citizen_support_router)
api_v1_router.include_router(citizen_comments_router)
api_v1_router.include_router(citizen_alerts_router)
api_v1_router.include_router(authority_queue_router)
api_v1_router.include_router(authority_analytics_router)
