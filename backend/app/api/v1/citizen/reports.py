from __future__ import annotations

import base64
from datetime import UTC, datetime, timedelta
from typing import Annotated
from uuid import uuid4

import sqlalchemy as sa
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.v1.ws import report_ws_manager
from app.core.auth import (
    TokenClaims,
    UserRole,
    get_current_user,
    get_current_user_optional,
)
from app.core.exif import strip_jpeg_metadata
from app.core.integrity import is_inside_cambodia
from app.core.priority import PriorityCalculator, RoadClass
from app.db.models.report import (
    Report,
    ReportComment,
    ReportPhoto,
    ReportSupport,
    ReportTimelineEntry,
)
from app.db.session import get_db
from app.schemas.ai import IssueCategoryEnum
from app.schemas.comment import (
    CitizenCommentOut,
    SupportReasonCategoryEnum,
    SupportVerificationTierEnum,
)
from app.schemas.report import (
    LocationVerificationTierEnum,
    MapViewportResponse,
    PriorityBreakdownSchema,
    ReportCreateRequest,
    ReportQuickEditRequest,
    ReportRatingRequest,
    ReportResponse,
    ReportStatusEnum,
    RoadClassEnum,
    TimelineEntrySchema,
)
from app.services.routing import GisRoutingService
from app.services.spatial import SpatialService

router = APIRouter(prefix="/reports", tags=["Citizen Reports"])

DbSession = Annotated[AsyncSession, Depends(get_db)]
CurrentUser = Annotated[TokenClaims, Depends(get_current_user)]
OptionalUser = Annotated[TokenClaims | None, Depends(get_current_user_optional)]

_WITHDRAWAL_WINDOW = timedelta(minutes=15)


def _as_utc(dt: datetime | None) -> datetime | None:
    if dt is None or dt.tzinfo is not None:
        return dt
    return dt.replace(tzinfo=UTC)


def report_to_response(
    row: Report,
    *,
    current_user_id: str | None = None,
    comments: list[ReportComment] | None = None,
    timeline: list[ReportTimelineEntry] | None = None,
    supports: list[ReportSupport] | None = None,
    photos: list[ReportPhoto] | None = None,
    nearby_duplicate_ids: list[str] | None = None,
) -> ReportResponse:
    """Convert an ORM `Report` row into the Flutter-compatible `ReportResponse`."""
    road_class = RoadClass(row.road_class)
    breakdown = PriorityCalculator.calculate(
        traffic_score=road_class.traffic_score,
        severity_score=row.severity,
        report_count=row.affected_citizens,
    )
    priority_schema = PriorityBreakdownSchema(
        traffic_score=breakdown.traffic_score,
        severity_score=breakdown.severity_score,
        report_count_score=breakdown.report_count_score,
        raw_score=breakdown.raw_score,
        level=breakdown.level,
        khmer_level_name=breakdown.khmer_level_name,
        english_level_name=breakdown.english_level_name,
        khmer_sla=breakdown.khmer_sla,
        english_sla=breakdown.english_sla,
        sla_hours=breakdown.sla_hours,
    )

    comment_items = [
        CitizenCommentOut(
            id=c.id,
            text=c.text,
            created_at=_as_utc(c.created_at) or c.created_at,
            is_original_reporter=c.is_original_reporter,
            is_current_user=(current_user_id is not None and c.user_id == current_user_id),
            is_anonymous=c.is_anonymous,
            author_name=c.author_name,
            severity=c.severity,
            voice_transcript=c.voice_transcript,
            verification_tier=(
                SupportVerificationTierEnum(c.verification_tier)
                if c.verification_tier
                else None
            ),
            support_area_khmer=c.remote_area_khmer,
            remote_area=c.remote_area_english,
            support_reason_category=(
                SupportReasonCategoryEnum(c.support_reason_category)
                if c.support_reason_category
                else None
            ),
        )
        for c in (comments or [])
    ]

    timeline_items = [
        TimelineEntrySchema(
            stage=ReportStatusEnum(t.stage),
            khmer_title=t.khmer_title,
            english_title=t.english_title,
            khmer_subtitle=t.khmer_subtitle,
            english_subtitle=t.english_subtitle,
            complete=t.complete,
            timestamp=_as_utc(t.timestamp),
        )
        for t in (timeline or [])
    ]

    user_support: ReportSupport | None = None
    if current_user_id is not None and supports:
        for sup in supports:
            if sup.user_id == current_user_id:
                user_support = sup
                break

    is_creator = current_user_id is not None and row.reporter_user_id == current_user_id
    joined_by_user = user_support is not None
    photo_keys = [
        p.object_key for p in (photos or []) if not p.is_after_proof and p.object_key
    ]
    primary_photo = photo_keys[0] if photo_keys else None
    extra_photos = photo_keys[1:] if len(photo_keys) > 1 else []
    return ReportResponse(
        id=row.id,
        category=IssueCategoryEnum(row.category),
        khmer_title=row.khmer_title,
        english_title=row.english_title,
        description=row.description or "",
        khmer_location=row.khmer_location,
        english_location=row.english_location,
        lat=row.lat,
        lng=row.lng,
        province_code=row.province_code,
        khmer_province=row.khmer_province,
        english_province=row.english_province,
        road_class=RoadClassEnum(row.road_class),
        severity=row.severity,
        affected_citizens=row.affected_citizens,
        status=ReportStatusEnum(row.status),
        khmer_agency=row.khmer_agency or "",
        english_agency=row.english_agency or "",
        local_photo_path=primary_photo,
        additional_local_photo_paths=extra_photos,
        resolved_after_asset_path=row.resolved_after_object_key,
        is_anonymous=row.is_anonymous,
        exif_stripped=row.exif_stripped,
        is_mine=is_creator or joined_by_user,
        created_by_current_user=is_creator,
        joined_by_current_user=joined_by_user,
        user_support_tier=(
            SupportVerificationTierEnum(user_support.verification_tier)
            if user_support and user_support.verification_tier
            else None
        ),
        user_support_distance_meters=(
            float(user_support.distance_meters)
            if user_support and user_support.distance_meters is not None
            else None
        ),
        user_support_area_khmer=user_support.remote_area_khmer if user_support else None,
        user_support_area_english=user_support.remote_area_english if user_support else None,
        user_support_reason=(
            (user_support.support_reason_note or user_support.support_reason_category)
            if user_support
            else None
        ),
        location_verification_tier=(
            LocationVerificationTierEnum(row.location_verification_tier)
            if row.location_verification_tier
            else None
        ),
        crew_code=row.crew_code,
        voice_transcript=row.voice_transcript,
        citizen_rating=row.citizen_rating,
        before_date_label=row.before_date_label or "",
        after_date_label=row.after_date_label or "",
        fixed_duration_khmer=row.fixed_duration_khmer or "",
        fixed_duration_english=row.fixed_duration_english or "",
        created_at=_as_utc(row.created_at) or row.created_at,
        priority=priority_schema,
        timeline=timeline_items,
        citizen_comments=comment_items,
        nearby_duplicate_ids=list(nearby_duplicate_ids or []),
    )


@router.get("", response_model=MapViewportResponse)
async def list_reports_viewport(
    db: DbSession,
    current_user: OptionalUser,
    min_lat: Annotated[float, Query(ge=-90.0, le=90.0)] = 9.9,
    min_lng: Annotated[float, Query(ge=-180.0, le=180.0)] = 102.3,
    max_lat: Annotated[float, Query(ge=-90.0, le=90.0)] = 14.7,
    max_lng: Annotated[float, Query(ge=-180.0, le=180.0)] = 107.7,
    zoom: Annotated[float, Query(ge=1.0, le=22.0)] = 13.0,
    province_code: Annotated[str | None, Query()] = None,
    category: Annotated[IssueCategoryEnum | None, Query()] = None,
    include_resolved: Annotated[bool, Query()] = True,
) -> MapViewportResponse:
    """Viewport bbox + 3-tier zoom clustering matching `buildMapViewportQuery`."""
    stmt = (
        sa.select(Report)
        .options(
            selectinload(Report.comments),
            selectinload(Report.timeline_entries),
            selectinload(Report.supports),
            selectinload(Report.photos),
        )
        .where(
            Report.lat >= min_lat,
            Report.lat <= max_lat,
            Report.lng >= min_lng,
            Report.lng <= max_lng,
        )
    )
    if province_code:
        stmt = stmt.where(Report.province_code == province_code)
    if category:
        stmt = stmt.where(Report.category == category.value)
    if not include_resolved:
        stmt = stmt.where(Report.status != ReportStatusEnum.RESOLVED.value)

    rows = list((await db.execute(stmt)).scalars().all())
    uid = current_user.sub if current_user else None
    responses = [
        report_to_response(
            r,
            current_user_id=uid,
            comments=list(r.comments),
            timeline=list(r.timeline_entries),
            supports=list(r.supports),
            photos=list(r.photos),
        )
        for r in rows
    ]
    return SpatialService.cluster_reports_for_viewport(
        reports=responses,
        min_lat=min_lat,
        min_lng=min_lng,
        max_lat=max_lat,
        max_lng=max_lng,
        zoom=zoom,
        province_code=province_code,
        category=category,
        include_resolved=include_resolved,
    )


@router.post("", response_model=ReportResponse, status_code=status.HTTP_201_CREATED)
async def create_report(
    payload: ReportCreateRequest,
    db: DbSession,
    current_user: OptionalUser,
) -> ReportResponse:
    """Create a civic report with Cambodia bounds check, EXIF stripping, GIS routing & priority."""
    if not is_inside_cambodia(payload.lat, payload.lng):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="Coordinates must be inside Cambodia bounds (lat 9.9..14.7, lng 102.3..107.7).",
        )

    exif_stripped = payload.exif_stripped
    stripped_photo_data_uri: str | None = None
    if payload.photo_base64:
        try:
            raw_bytes = base64.b64decode(payload.photo_base64, validate=True)
            stripped_bytes = strip_jpeg_metadata(raw_bytes)
            exif_stripped = True
            stripped_photo_data_uri = (
                f"data:image/jpeg;base64,{base64.b64encode(stripped_bytes).decode('ascii')}"
            )
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid base64 image payload.",
            ) from exc

    uid = current_user.sub if current_user else None
    nearby_duplicate_ids: list[str] = []
    if not payload.force_create_new:
        bbox = SpatialService.build_viewport_bbox_bounds(
            payload.lat, payload.lng, radius_meters=200.0
        )
        candidate_stmt = (
            sa.select(Report)
            .options(selectinload(Report.supports))
            .where(
                Report.status != ReportStatusEnum.RESOLVED.value,
                Report.category == payload.category.value,
                Report.lat >= bbox["min_lat"],
                Report.lat <= bbox["max_lat"],
                Report.lng >= bbox["min_lng"],
                Report.lng <= bbox["max_lng"],
            )
        )
        candidate_rows = list((await db.execute(candidate_stmt)).scalars().all())
        candidate_responses = [
            report_to_response(r, current_user_id=uid, supports=list(r.supports))
            for r in candidate_rows
        ]
        if uid is not None and SpatialService.has_self_duplicate_within_50m(
            reports=candidate_responses,
            lat=payload.lat,
            lng=payload.lng,
            category=payload.category,
        ):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="You already reported or joined an open issue of this category within 50m.",
            )
        nearby_matches = SpatialService.find_nearby_duplicates(
            reports=candidate_responses,
            lat=payload.lat,
            lng=payload.lng,
            category=payload.category,
        )
        nearby_duplicate_ids = [match.id for match, _dist in nearby_matches]

    road_class = RoadClass(payload.road_class.value)
    routing = GisRoutingService.assign_agency(
        lat=payload.lat,
        lng=payload.lng,
        category=payload.category,
        road_class=road_class,
        province_code=payload.province_code,
    )
    breakdown = PriorityCalculator.calculate(
        traffic_score=road_class.traffic_score,
        severity_score=payload.severity,
        report_count=1,
    )

    now = datetime.now(UTC)
    report_id = f"#SC-{uuid4().hex[:5].upper()}"
    kh_title = payload.khmer_title.strip() or f"របាយការណ៍ {payload.category.value}"
    en_title = payload.english_title.strip() or f"Civic {payload.category.value} report"
    loc_label = f"{payload.lat:.4f}, {payload.lng:.4f}"
    kh_loc = payload.khmer_location.strip() or routing.khmer_province or loc_label
    en_loc = payload.english_location.strip() or routing.english_province or loc_label

    report = Report(
        id=report_id,
        category=payload.category.value,
        khmer_title=kh_title,
        english_title=en_title,
        description=payload.description.strip(),
        khmer_location=kh_loc,
        english_location=en_loc,
        lat=payload.lat,
        lng=payload.lng,
        geom=SpatialService.to_wkt_point(payload.lat, payload.lng),
        province_code=routing.province_code,
        khmer_province=routing.khmer_province,
        english_province=routing.english_province,
        road_class=road_class.value,
        severity=payload.severity,
        affected_citizens=1,
        priority_raw=breakdown.raw_score,
        priority_level=breakdown.level,
        status=ReportStatusEnum.SUBMITTED.value,
        khmer_agency=routing.khmer_agency,
        english_agency=routing.english_agency,
        reporter_user_id=uid,
        is_anonymous=payload.is_anonymous,
        exif_stripped=exif_stripped,
        location_verification_tier=(
            payload.location_verification_tier.value
            if payload.location_verification_tier
            else None
        ),
        voice_transcript=payload.voice_transcript,
        before_date_label=now.strftime("%Y-%m-%d"),
        after_date_label="",
        fixed_duration_khmer="",
        fixed_duration_english="",
        created_at=now,
        updated_at=now,
    )
    timeline_entries = [
        ReportTimelineEntry(
            report_id=report_id,
            stage=ReportStatusEnum.SUBMITTED.value,
            khmer_title="បានទទួល",
            english_title="Received",
            khmer_subtitle=routing.khmer_agency,
            english_subtitle=routing.english_agency,
            complete=True,
            timestamp=now,
        ),
        ReportTimelineEntry(
            report_id=report_id,
            stage=ReportStatusEnum.SCHEDULED.value,
            khmer_title="បានផ្ទៀងផ្ទាត់ និងកំណត់អាទិភាព",
            english_title="Verified & prioritised",
            khmer_subtitle=f"P{breakdown.level} · {breakdown.khmer_sla}",
            english_subtitle=f"P{breakdown.level} · {breakdown.english_sla}",
            complete=False,
            timestamp=now,
        ),
        ReportTimelineEntry(
            report_id=report_id,
            stage=ReportStatusEnum.CREW_DISPATCHED.value,
            khmer_title="ក្រុមជួសជុលនៅទីតាំង",
            english_title="Crew on-site",
            khmer_subtitle="រង់ចាំការចាត់តាំងក្រុមជួសជុល",
            english_subtitle="Awaiting crew dispatch",
            complete=False,
            timestamp=now,
        ),
        ReportTimelineEntry(
            report_id=report_id,
            stage=ReportStatusEnum.RESOLVED.value,
            khmer_title="បានដោះស្រាយ",
            english_title="Resolved",
            khmer_subtitle="ប៉ាន់ស្មាន · តម្រូវឲ្យមានរូបភាពបញ្ជាក់ក្រោយជួសជុល",
            english_subtitle="Est. · Before & After photo required to close",
            complete=False,
            timestamp=now,
        ),
    ]
    photo_rows: list[ReportPhoto] = []
    if stripped_photo_data_uri is not None:
        photo_rows.append(
            ReportPhoto(
                report_id=report_id,
                object_key=stripped_photo_data_uri,
                is_after_proof=False,
                exif_stripped=True,
            )
        )
    db.add(report)
    db.add_all(timeline_entries)
    db.add_all(photo_rows)
    await db.commit()
    await report_ws_manager.broadcast_reports_updated()

    return report_to_response(
        report,
        current_user_id=uid,
        comments=[],
        timeline=timeline_entries,
        supports=[],
        photos=photo_rows,
        nearby_duplicate_ids=nearby_duplicate_ids,
    )


@router.get("/{report_id}", response_model=ReportResponse)
async def get_report_detail(
    report_id: str,
    db: DbSession,
    current_user: OptionalUser,
) -> ReportResponse:
    """Fetch a single report with timeline & comments."""
    stmt = (
        sa.select(Report)
        .options(
            selectinload(Report.comments),
            selectinload(Report.timeline_entries),
            selectinload(Report.supports),
            selectinload(Report.photos),
        )
        .where(Report.id == report_id)
    )
    row = (await db.execute(stmt)).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found.")
    return report_to_response(
        row,
        current_user_id=current_user.sub if current_user else None,
        comments=list(row.comments),
        timeline=list(row.timeline_entries),
        supports=list(row.supports),
        photos=list(row.photos),
    )


@router.patch("/{report_id}", response_model=ReportResponse)
async def quick_edit_report(
    report_id: str,
    payload: ReportQuickEditRequest,
    db: DbSession,
    current_user: CurrentUser,
) -> ReportResponse:
    """Quick-edit description & severity within the 15-min `submitted` window."""
    stmt = (
        sa.select(Report)
        .options(
            selectinload(Report.comments),
            selectinload(Report.timeline_entries),
            selectinload(Report.supports),
            selectinload(Report.photos),
        )
        .where(Report.id == report_id)
    )
    row = (await db.execute(stmt)).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found.")
    is_admin = current_user.role in {UserRole.AGENCY_STAFF, UserRole.MINISTRY_ADMIN}
    if row.reporter_user_id != current_user.sub and not is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the original reporter or authority staff can edit this report.",
        )
    if row.status != ReportStatusEnum.SUBMITTED.value:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Quick edit is only allowed while status is 'submitted'.",
        )
    created = row.created_at if row.created_at.tzinfo else row.created_at.replace(tzinfo=UTC)
    if datetime.now(UTC) - created > _WITHDRAWAL_WINDOW:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="15-minute quick-edit window has expired.",
        )

    row.description = payload.description.strip()
    row.severity = payload.severity
    breakdown = PriorityCalculator.calculate(
        traffic_score=RoadClass(row.road_class).traffic_score,
        severity_score=row.severity,
        report_count=row.affected_citizens,
    )
    row.priority_raw = breakdown.raw_score
    row.priority_level = breakdown.level
    await db.commit()
    await report_ws_manager.broadcast_reports_updated()
    return report_to_response(
        row,
        current_user_id=current_user.sub,
        comments=list(row.comments),
        timeline=list(row.timeline_entries),
        supports=list(row.supports),
        photos=list(row.photos),
    )


@router.delete("/{report_id}", status_code=status.HTTP_200_OK)
async def withdraw_report(
    report_id: str,
    db: DbSession,
    current_user: CurrentUser,
) -> dict[str, str]:
    """Withdraw a report within the 15-min `submitted` window."""
    row = await db.scalar(sa.select(Report).where(Report.id == report_id))
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found.")
    is_admin = current_user.role in {UserRole.AGENCY_STAFF, UserRole.MINISTRY_ADMIN}
    if row.reporter_user_id != current_user.sub and not is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the original reporter or authority staff can withdraw this report.",
        )
    if row.status != ReportStatusEnum.SUBMITTED.value:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Report can only be withdrawn while status is 'submitted'.",
        )
    created = row.created_at if row.created_at.tzinfo else row.created_at.replace(tzinfo=UTC)
    if datetime.now(UTC) - created > _WITHDRAWAL_WINDOW:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="15-minute withdrawal window has expired.",
        )

    await db.delete(row)
    await db.commit()
    await report_ws_manager.broadcast_reports_updated()
    return {"status": "withdrawn", "report_id": report_id}


@router.post("/{report_id}/rating", response_model=ReportResponse)
async def rate_resolved_report(
    report_id: str,
    payload: ReportRatingRequest,
    db: DbSession,
    current_user: CurrentUser,
) -> ReportResponse:
    """Record a citizen's 1–5 satisfaction rating on a resolved repair."""
    stmt = (
        sa.select(Report)
        .options(
            selectinload(Report.comments),
            selectinload(Report.timeline_entries),
            selectinload(Report.supports),
            selectinload(Report.photos),
        )
        .where(Report.id == report_id)
    )
    row = (await db.execute(stmt)).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found.")
    is_creator = row.reporter_user_id is not None and row.reporter_user_id == current_user.sub
    is_supporter = any(s.user_id == current_user.sub for s in row.supports)
    is_admin = current_user.role in {UserRole.AGENCY_STAFF, UserRole.MINISTRY_ADMIN}
    if not (is_creator or is_supporter or is_admin):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Only the original reporter, a supporter, or authority staff can rate this report."
            ),
        )
    if row.status != ReportStatusEnum.RESOLVED.value:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only resolved reports can be rated.",
        )
    row.citizen_rating = payload.rating
    await db.commit()
    await report_ws_manager.broadcast_reports_updated()
    return report_to_response(
        row,
        current_user_id=current_user.sub,
        comments=list(row.comments),
        timeline=list(row.timeline_entries),
        supports=list(row.supports),
        photos=list(row.photos),
    )
