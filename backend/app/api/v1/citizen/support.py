from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Annotated

import sqlalchemy as sa
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.ws import report_ws_manager
from app.config import get_settings
from app.core.auth import TokenClaims, get_current_user
from app.core.integrity import (
    SpoofRiskLevel,
    evaluate_support_limits,
    verify_device_attestation,
)
from app.core.priority import PriorityCalculator, RoadClass
from app.db.models.report import Report, ReportSupport
from app.db.session import get_db
from app.schemas.report import PriorityBreakdownSchema
from app.schemas.support import SupportActionResponse, SupportCreateRequest

router = APIRouter(prefix="/reports/{report_id}/support", tags=["Citizen Support"])

DbSession = Annotated[AsyncSession, Depends(get_db)]
CurrentUser = Annotated[TokenClaims, Depends(get_current_user)]


def _priority_schema(row: Report) -> PriorityBreakdownSchema:
    road = RoadClass(row.road_class)
    b = PriorityCalculator.calculate(
        traffic_score=road.traffic_score,
        severity_score=row.severity,
        report_count=row.affected_citizens,
    )
    return PriorityBreakdownSchema(
        traffic_score=b.traffic_score,
        severity_score=b.severity_score,
        report_count_score=b.report_count_score,
        raw_score=b.raw_score,
        level=b.level,
        khmer_level_name=b.khmer_level_name,
        english_level_name=b.english_level_name,
        khmer_sla=b.khmer_sla,
        english_sla=b.english_sla,
        sla_hours=b.sla_hours,
    )


@router.post("", response_model=SupportActionResponse)
async def add_support_vote(
    report_id: str,
    payload: SupportCreateRequest,
    db: DbSession,
    current_user: CurrentUser,
) -> SupportActionResponse:
    """Record an 'Affects me' support vote with anti-spoof & 24h cap validation."""
    settings = get_settings()
    if payload.integrity is not None:
        if payload.integrity.risk_level == SpoofRiskLevel.BLOCKED:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Support blocked by location integrity assessment.",
            )
        if payload.integrity.attestation is not None:
            attest = verify_device_attestation(
                provider=payload.integrity.attestation.provider,
                token=payload.integrity.attestation.token,
                mode=settings.integrity_mode,
            )
            if not attest.valid:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=attest.reason or "Device attestation failed.",
                )

    report = await db.scalar(sa.select(Report).where(Report.id == report_id))
    if report is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found.")
    if report.status == "resolved":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Cannot add support to an already resolved report.",
        )
    if report.reporter_user_id is not None and report.reporter_user_id == current_user.sub:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Report creator cannot add a separate support vote to their own report.",
        )

    existing = await db.scalar(
        sa.select(ReportSupport).where(
            ReportSupport.report_id == report_id,
            ReportSupport.user_id == current_user.sub,
        )
    )
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="User has already supported this report.",
        )

    since = datetime.now(UTC) - timedelta(hours=24)
    recent_supports = list(
        (
            await db.execute(
                sa.select(ReportSupport).where(
                    ReportSupport.user_id == current_user.sub,
                    ReportSupport.created_at >= since,
                )
            )
        )
        .scalars()
        .all()
    )
    supports_24h = len(recent_supports)
    remote_province_24h = sum(
        1 for s in recent_supports if s.verification_tier == "remoteProvince"
    )
    allowed, error_msg = evaluate_support_limits(
        supports_used_24h=supports_24h,
        remote_province_supports_24h=remote_province_24h,
        verification_tier=payload.verification_tier.value,
    )
    if not allowed:
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=error_msg)

    support = ReportSupport(
        report_id=report_id,
        user_id=current_user.sub,
        verification_tier=payload.verification_tier.value,
        distance_meters=payload.distance_meters,
        remote_area_english=payload.remote_area,
        support_reason_category=(
            payload.support_reason_category.value
            if payload.support_reason_category
            else None
        ),
        support_reason_note=payload.support_reason_note,
        integrity_risk_level=(
            payload.integrity.risk_level.value if payload.integrity else "trusted"
        ),
    )
    report.affected_citizens += 1
    breakdown = PriorityCalculator.calculate(
        traffic_score=RoadClass(report.road_class).traffic_score,
        severity_score=report.severity,
        report_count=report.affected_citizens,
    )
    report.priority_raw = breakdown.raw_score
    report.priority_level = breakdown.level

    db.add(support)
    await db.commit()
    await report_ws_manager.broadcast_reports_updated()

    return SupportActionResponse(
        report_id=report_id,
        affected_citizens=report.affected_citizens,
        priority=_priority_schema(report),
        verification_tier=payload.verification_tier,
        remote_area=payload.remote_area,
        supports_used_24h=supports_24h + 1,
        remote_province_supports_24h=(
            remote_province_24h
            + (1 if payload.verification_tier.value == "remoteProvince" else 0)
        ),
        joined_by_current_user=True,
    )


@router.delete("", response_model=SupportActionResponse)
async def undo_support_vote(
    report_id: str,
    db: DbSession,
    current_user: CurrentUser,
) -> SupportActionResponse:
    """Undo a citizen's '+1 Support' vote and recalculate weighted priority."""
    report = await db.scalar(sa.select(Report).where(Report.id == report_id))
    if report is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found.")

    support = await db.scalar(
        sa.select(ReportSupport).where(
            ReportSupport.report_id == report_id,
            ReportSupport.user_id == current_user.sub,
        )
    )
    if support is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Support vote not found.")

    await db.delete(support)
    report.affected_citizens = max(1, report.affected_citizens - 1)
    breakdown = PriorityCalculator.calculate(
        traffic_score=RoadClass(report.road_class).traffic_score,
        severity_score=report.severity,
        report_count=report.affected_citizens,
    )
    report.priority_raw = breakdown.raw_score
    report.priority_level = breakdown.level
    await db.commit()
    await report_ws_manager.broadcast_reports_updated()

    return SupportActionResponse(
        report_id=report_id,
        affected_citizens=report.affected_citizens,
        priority=_priority_schema(report),
        verification_tier=None,
        remote_area=None,
        joined_by_current_user=False,
    )
