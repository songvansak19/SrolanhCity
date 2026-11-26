from __future__ import annotations

from datetime import UTC, datetime
from typing import Annotated
from uuid import uuid4

import sqlalchemy as sa
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.ws import report_ws_manager
from app.core.auth import TokenClaims, UserRole, get_current_user, get_current_user_optional
from app.db.models.report import Report, ReportComment
from app.db.session import get_db
from app.schemas.comment import (
    CitizenCommentOut,
    CommentCreateRequest,
    SupportReasonCategoryEnum,
    SupportVerificationTierEnum,
)

router = APIRouter(prefix="/reports/{report_id}/comments", tags=["Citizen Comments"])

DbSession = Annotated[AsyncSession, Depends(get_db)]
CurrentUser = Annotated[TokenClaims, Depends(get_current_user)]
OptionalUser = Annotated[TokenClaims | None, Depends(get_current_user_optional)]


def _to_comment_out(
    row: ReportComment,
    *,
    current_user_id: str | None = None,
) -> CitizenCommentOut:
    return CitizenCommentOut(
        id=row.id,
        text=row.text,
        created_at=row.created_at,
        is_original_reporter=row.is_original_reporter,
        is_current_user=(current_user_id is not None and row.user_id == current_user_id),
        is_anonymous=row.is_anonymous,
        author_name=row.author_name,
        severity=row.severity,
        voice_transcript=row.voice_transcript,
        verification_tier=(
            SupportVerificationTierEnum(row.verification_tier)
            if row.verification_tier
            else None
        ),
        support_area_khmer=row.remote_area_khmer,
        remote_area=row.remote_area_english,
        support_reason_category=(
            SupportReasonCategoryEnum(row.support_reason_category)
            if row.support_reason_category
            else None
        ),
    )


@router.get("", response_model=list[CitizenCommentOut])
async def list_comments(
    report_id: str,
    db: DbSession,
    current_user: OptionalUser,
) -> list[CitizenCommentOut]:
    """List citizen comments for a report ordered chronologically."""
    stmt = (
        sa.select(ReportComment)
        .where(ReportComment.report_id == report_id)
        .order_by(ReportComment.created_at.asc())
    )
    rows = list((await db.execute(stmt)).scalars().all())
    uid = current_user.sub if current_user else None
    return [_to_comment_out(r, current_user_id=uid) for r in rows]


@router.post("", response_model=CitizenCommentOut, status_code=status.HTTP_201_CREATED)
async def add_comment(
    report_id: str,
    payload: CommentCreateRequest,
    db: DbSession,
    current_user: OptionalUser,
) -> CitizenCommentOut:
    """Post a citizen comment with silent GPS `verification_tier` & `remote_area`."""
    report = await db.scalar(sa.select(Report).where(Report.id == report_id))
    if report is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found.")

    uid = current_user.sub if current_user else None
    is_original_reporter = uid is not None and report.reporter_user_id == uid
    author_name = (
        None
        if payload.is_anonymous
        else (payload.author_name.strip() if payload.author_name else None)
    )
    comment = ReportComment(
        id=f"c-{uuid4().hex[:12]}",
        report_id=report_id,
        user_id=uid,
        text=payload.text,
        is_original_reporter=is_original_reporter,
        is_anonymous=payload.is_anonymous,
        author_name=author_name,
        severity=payload.severity,
        voice_transcript=payload.voice_transcript,
        verification_tier=(
            None
            if is_original_reporter or payload.verification_tier is None
            else payload.verification_tier.value
        ),
        remote_area_khmer=payload.support_area_khmer,
        remote_area_english=payload.remote_area,
        support_reason_category=(
            payload.support_reason_category.value
            if payload.support_reason_category
            else None
        ),
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
    )
    db.add(comment)
    await db.commit()
    await report_ws_manager.broadcast_reports_updated()
    return _to_comment_out(comment, current_user_id=uid)


@router.delete("/{comment_id}", status_code=status.HTTP_200_OK)
async def delete_comment(
    report_id: str,
    comment_id: str,
    db: DbSession,
    current_user: CurrentUser,
) -> dict[str, str]:
    """Delete a citizen comment (author or authority staff; never original reporter entry)."""
    comment = await db.scalar(
        sa.select(ReportComment).where(
            ReportComment.id == comment_id,
            ReportComment.report_id == report_id,
        )
    )
    if comment is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Comment not found.")
    if comment.is_original_reporter:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Original reporter entry cannot be deleted.",
        )
    is_admin = current_user.role in {UserRole.AGENCY_STAFF, UserRole.MINISTRY_ADMIN}
    if comment.user_id != current_user.sub and not is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only the comment author or authority staff can delete this comment.",
        )
    await db.delete(comment)
    await db.commit()
    await report_ws_manager.broadcast_reports_updated()
    return {"status": "deleted", "comment_id": comment_id}
