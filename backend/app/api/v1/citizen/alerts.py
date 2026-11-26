from __future__ import annotations

from datetime import UTC, datetime
from typing import Annotated, Literal

import sqlalchemy as sa
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import TokenClaims, get_current_user
from app.db.models.alert import Alert
from app.db.session import get_db
from app.schemas.alert import (
    AlertBulkClearResponse,
    AlertDeleteResponse,
    AlertItemOut,
    AlertListResponse,
    AlertRestoreRequest,
)

router = APIRouter(prefix="/alerts", tags=["Citizen Alerts"])

DbSession = Annotated[AsyncSession, Depends(get_db)]
CurrentUser = Annotated[TokenClaims, Depends(get_current_user)]


def _to_alert_out(row: Alert) -> AlertItemOut:
    return AlertItemOut(
        id=row.id,
        report_id=row.report_id,
        khmer_title=row.khmer_title,
        english_title=row.english_title,
        khmer_subtitle=row.khmer_subtitle,
        english_subtitle=row.english_subtitle,
        created_at=row.created_at,
        is_read=row.is_read,
    )


@router.get("", response_model=AlertListResponse)
async def list_alerts(
    db: DbSession,
    current_user: CurrentUser,
) -> AlertListResponse:
    """List non-deleted alerts for the active citizen sorted newest first."""
    stmt = (
        sa.select(Alert)
        .where(
            Alert.is_deleted.is_(False),
            Alert.user_id == current_user.sub,
        )
        .order_by(Alert.created_at.desc())
    )
    result = await db.execute(stmt)
    rows = list(result.scalars().all())
    items = [_to_alert_out(row) for row in rows]
    unread_count = sum(1 for item in items if not item.is_read)
    return AlertListResponse(unread_count=unread_count, items=items)


@router.post("/{alert_id}/read", response_model=AlertItemOut)
async def mark_alert_read(
    alert_id: str,
    db: DbSession,
    current_user: CurrentUser,
) -> AlertItemOut:
    """Mark a single alert as read (`markAlertRead`)."""
    alert = await db.scalar(
        sa.select(Alert).where(Alert.id == alert_id, Alert.is_deleted.is_(False))
    )
    if alert is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert not found.")
    if alert.user_id != current_user.sub:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot modify another user's alert.",
        )
    alert.is_read = True
    await db.commit()
    return _to_alert_out(alert)


@router.post("/read-all")
async def mark_all_alerts_read(
    db: DbSession,
    current_user: CurrentUser,
) -> dict[str, int]:
    """Mark all alerts owned by the active citizen as read (`markAllAlertsRead`)."""
    stmt = sa.select(Alert).where(
        Alert.is_deleted.is_(False),
        Alert.is_read.is_(False),
        Alert.user_id == current_user.sub,
    )
    rows = list((await db.execute(stmt)).scalars().all())
    for row in rows:
        row.is_read = True
    await db.commit()
    return {"marked_read": len(rows)}


@router.delete("/{alert_id}", response_model=AlertDeleteResponse)
async def soft_delete_alert(
    alert_id: str,
    db: DbSession,
    current_user: CurrentUser,
) -> AlertDeleteResponse:
    """Soft-delete a single alert and return it for immediate Undo (`removeAlert`)."""
    alert = await db.scalar(
        sa.select(Alert).where(Alert.id == alert_id, Alert.is_deleted.is_(False))
    )
    if alert is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Alert not found.")
    if alert.user_id != current_user.sub:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot delete another user's alert.",
        )
    alert.is_deleted = True
    alert.deleted_at = datetime.now(UTC)
    await db.commit()
    return AlertDeleteResponse(deleted=_to_alert_out(alert), restorable=True)


@router.post("/restore", response_model=AlertListResponse)
async def restore_alerts(
    payload: AlertRestoreRequest,
    db: DbSession,
    current_user: CurrentUser,
) -> AlertListResponse:
    """Restore soft-deleted alerts (`restoreAlert` / `restoreAlerts`)."""
    if not payload.alert_ids:
        return AlertListResponse(unread_count=0, items=[])
    stmt = sa.select(Alert).where(
        Alert.id.in_(payload.alert_ids),
        Alert.user_id == current_user.sub,
    )
    rows = list((await db.execute(stmt)).scalars().all())
    for row in rows:
        row.is_deleted = False
        row.deleted_at = None
    await db.commit()
    items = [_to_alert_out(row) for row in rows]
    unread_count = sum(1 for item in items if not item.is_read)
    return AlertListResponse(unread_count=unread_count, items=items)


@router.delete("", response_model=AlertBulkClearResponse)
async def bulk_clear_alerts(
    db: DbSession,
    current_user: CurrentUser,
    mode: Annotated[Literal["read", "all"], Query()] = "read",
) -> AlertBulkClearResponse:
    """Soft-delete read alerts (`clearReadAlerts`) or all alerts (`clearAllAlerts`)."""
    stmt = sa.select(Alert).where(
        Alert.is_deleted.is_(False),
        Alert.user_id == current_user.sub,
    )
    if mode == "read":
        stmt = stmt.where(Alert.is_read.is_(True))
    rows = list((await db.execute(stmt)).scalars().all())
    now = datetime.now(UTC)
    cleared_ids: list[str] = []
    for row in rows:
        row.is_deleted = True
        row.deleted_at = now
        cleared_ids.append(row.id)
    await db.commit()
    return AlertBulkClearResponse(cleared_ids=cleared_ids, cleared_count=len(cleared_ids))
