from __future__ import annotations

from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class Alert(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Targeted citizen notification alert with soft-delete & undo-restore support."""

    __tablename__ = "alerts"

    user_id: Mapped[str | None] = mapped_column(
        sa.String(36),
        sa.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    report_id: Mapped[str] = mapped_column(
        sa.String(32),
        sa.ForeignKey("reports.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    khmer_title: Mapped[str] = mapped_column(sa.String(240), nullable=False)
    english_title: Mapped[str] = mapped_column(sa.String(240), nullable=False)
    khmer_subtitle: Mapped[str] = mapped_column(sa.String(300), default="", nullable=False)
    english_subtitle: Mapped[str] = mapped_column(sa.String(300), default="", nullable=False)
    is_read: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False, index=True)
    is_deleted: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False, index=True)
    deleted_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True), nullable=True)
