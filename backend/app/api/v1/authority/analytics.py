from __future__ import annotations

from typing import Annotated

import sqlalchemy as sa
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.citizen.reports import report_to_response
from app.core.auth import TokenClaims, UserRole, require_roles
from app.db.models.report import Report
from app.db.session import get_db
from app.schemas.authority import AuthorityKpisOut, ProvinceHeatmapFeatureCollection
from app.services.analytics import AnalyticsService

router = APIRouter(prefix="/authority/analytics", tags=["Authority Analytics"])

_STAFF_GUARD = require_roles(UserRole.AGENCY_STAFF, UserRole.MINISTRY_ADMIN)
DbSession = Annotated[AsyncSession, Depends(get_db)]
StaffUser = Annotated[TokenClaims, Depends(_STAFF_GUARD)]


@router.get("/kpis", response_model=AuthorityKpisOut)
async def get_authority_kpis(
    db: DbSession,
    _staff: StaffUser,
) -> AuthorityKpisOut:
    """Compute Ministry MTTR, open P5 criticals, and SLA breach metrics."""
    rows = list((await db.execute(sa.select(Report))).scalars().all())
    reports = [report_to_response(r) for r in rows]
    resolved_map = {r.id: r.resolved_at for r in rows if r.resolved_at is not None}
    return AnalyticsService.compute_kpis(reports=reports, resolved_at_by_id=resolved_map)


@router.get("/heatmap", response_model=ProvinceHeatmapFeatureCollection)
async def get_province_heatmap(
    db: DbSession,
    _staff: StaffUser,
) -> ProvinceHeatmapFeatureCollection:
    """Build GeoJSON FeatureCollection of provincial report density & priority."""
    rows = list((await db.execute(sa.select(Report))).scalars().all())
    reports = [report_to_response(r) for r in rows]
    return AnalyticsService.build_province_heatmap(reports)
