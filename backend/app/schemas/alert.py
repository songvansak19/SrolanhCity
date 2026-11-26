from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class AlertItemOut(BaseModel):
    """Matches `AlertItem.toJson()` in `lib/domain/models/report_models.dart`."""

    model_config = ConfigDict(populate_by_name=True, from_attributes=True)

    id: str
    report_id: str = Field(alias="reportId")
    khmer_title: str = Field(alias="khmerTitle")
    english_title: str = Field(alias="englishTitle")
    khmer_subtitle: str = Field(default="", alias="khmerSubtitle")
    english_subtitle: str = Field(default="", alias="englishSubtitle")
    created_at: datetime = Field(alias="createdAt")
    is_read: bool = Field(default=False, alias="isRead")


class AlertListResponse(BaseModel):
    """Paginated citizen alerts list + unread counter."""

    unread_count: int = 0
    items: list[AlertItemOut] = Field(default_factory=list)


class AlertDeleteResponse(BaseModel):
    """Soft-delete response preserving the removed alert for immediate Undo."""

    deleted: AlertItemOut | None = None
    restorable: bool = True


class AlertRestoreRequest(BaseModel):
    """Restore one or more soft-deleted alerts (`restoreAlert` / `restoreAlerts`)."""

    alert_ids: list[str] = Field(default_factory=list)
    index: int | None = None


class AlertBulkClearResponse(BaseModel):
    """Bulk clear response for `clearReadAlerts` or `clearAllAlerts`."""

    cleared_ids: list[str] = Field(default_factory=list)
    cleared_count: int = 0
