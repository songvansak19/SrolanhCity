from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Annotated

import sqlalchemy as sa
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.v1.citizen.reports import report_to_response
from app.core.auth import TokenClaims, UserRole, require_roles
from app.db.models.audit import AuditLog
from app.db.models.report import Report, ReportTimelineEntry
from app.db.session import get_db
from app.schemas.authority import (
    DispatchCrewRequest,
    ResolveWithProofRequest,
    StaffQueueResponse,
)
from app.schemas.report import ReportResponse, ReportStatusEnum

router = APIRouter(prefix="/authority", tags=["Authority Queue"])

_STAFF_GUARD = require_roles(UserRole.AGENCY_STAFF, UserRole.MINISTRY_ADMIN)
DbSession = Annotated[AsyncSession, Depends(get_db)]
StaffUser = Annotated[TokenClaims, Depends(_STAFF_GUARD)]


@router.get("/queue", response_model=StaffQueueResponse)
async def get_authority_queue(
    db: DbSession,
    _staff: StaffUser,
    province_code: str | None = None,
) -> StaffQueueResponse:
    """Return open reports sorted by `priority_raw DESC, affected_citizens DESC`."""
    stmt = (
        sa.select(Report)
        .options(
            selectinload(Report.comments),
            selectinload(Report.timeline_entries),
            selectinload(Report.supports),
        )
        .order_by(Report.priority_raw.desc(), Report.affected_citizens.desc())
    )
    if province_code:
        stmt = stmt.where(Report.province_code == province_code)

    rows = list((await db.execute(stmt)).scalars().all())
    open_items: list[ReportResponse] = []
    resolved_count = 0
    critical_p5_count = 0

    for row in rows:
        if row.status == ReportStatusEnum.RESOLVED.value:
            resolved_count += 1
            continue
        if row.priority_level == 5:
            critical_p5_count += 1
        open_items.append(
            report_to_response(
                row,
                comments=list(row.comments),
                timeline=list(row.timeline_entries),
                supports=list(row.supports),
            )
        )

    return StaffQueueResponse(
        pending_count=len(open_items),
        critical_p5_count=critical_p5_count,
        resolved_count=resolved_count,
        items=open_items,
    )


@router.post("/reports/{report_id}/dispatch", response_model=ReportResponse)
async def dispatch_crew(
    report_id: str,
    payload: DispatchCrewRequest,
    db: DbSession,
    staff: StaffUser,
) -> ReportResponse:
    """Approve and dispatch a field crew (`crewDispatched`, default `B-07`)."""
    stmt = (
        sa.select(Report)
        .options(
            selectinload(Report.comments),
            selectinload(Report.timeline_entries),
            selectinload(Report.supports),
        )
        .where(Report.id == report_id)
    )
    row = (await db.execute(stmt)).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found.")

    now = datetime.now(UTC)
    row.status = ReportStatusEnum.CREW_DISPATCHED.value
    row.crew_code = payload.crew_code
    entry = ReportTimelineEntry(
        report_id=report_id,
        stage=ReportStatusEnum.CREW_DISPATCHED.value,
        khmer_title="ក្រុមជួសជុលនៅទីតាំង",
        english_title="Crew On-Site",
        khmer_subtitle=f"ក្រុម {payload.crew_code} កំពុងចុះដោះស្រាយ",
        english_subtitle=f"Crew {payload.crew_code} dispatched",
        complete=True,
        timestamp=now,
    )
    db.add(entry)
    db.add(
        AuditLog(
            actor_user_id=staff.sub,
            actor_role=staff.role.value,
            action="dispatch_crew",
            target_type="report",
            target_id=report_id,
            details_json=json.dumps({"crew_code": payload.crew_code}),
        )
    )
    await db.commit()
    return report_to_response(
        row,
        comments=list(row.comments),
        timeline=[*row.timeline_entries, entry],
        supports=list(row.supports),
    )


@router.post("/reports/{report_id}/resolve", response_model=ReportResponse)
async def resolve_report_with_proof(
    report_id: str,
    payload: ResolveWithProofRequest,
    db: DbSession,
    staff: StaffUser,
) -> ReportResponse:
    """Resolve a report with after-repair photo proof & duration labels."""
    stmt = (
        sa.select(Report)
        .options(
            selectinload(Report.comments),
            selectinload(Report.timeline_entries),
            selectinload(Report.supports),
        )
        .where(Report.id == report_id)
    )
    row = (await db.execute(stmt)).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found.")

    now = datetime.now(UTC)
    row.status = ReportStatusEnum.RESOLVED.value
    if payload.crew_code:
        row.crew_code = payload.crew_code
    row.resolved_after_object_key = payload.after_photo_object_key
    row.after_date_label = now.strftime("%Y-%m-%d")
    row.fixed_duration_khmer = payload.fixed_duration_khmer
    row.fixed_duration_english = payload.fixed_duration_english
    row.resolved_at = now

    entry = ReportTimelineEntry(
        report_id=report_id,
        stage=ReportStatusEnum.RESOLVED.value,
        khmer_title="បានដោះស្រាយ",
        english_title="Resolved",
        khmer_subtitle=payload.fixed_duration_khmer,
        english_subtitle=payload.fixed_duration_english,
        complete=True,
        timestamp=now,
    )
    db.add(entry)
    db.add(
        AuditLog(
            actor_user_id=staff.sub,
            actor_role=staff.role.value,
            action="resolve_report",
            target_type="report",
            target_id=report_id,
            details_json=json.dumps(
                {"after_photo_object_key": payload.after_photo_object_key or ""}
            ),
        )
    )
    await db.commit()
    return report_to_response(
        row,
        comments=list(row.comments),
        timeline=[*row.timeline_entries, entry],
        supports=list(row.supports),
    )
