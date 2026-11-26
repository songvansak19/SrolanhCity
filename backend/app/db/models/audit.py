from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class AuditLog(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Immutable audit log for Ministry dispatch, resolution, and moderation actions."""

    __tablename__ = "audit_logs"

    actor_user_id: Mapped[str | None] = mapped_column(sa.String(36), nullable=True, index=True)
    actor_role: Mapped[str] = mapped_column(sa.String(32), nullable=False)
    action: Mapped[str] = mapped_column(sa.String(80), nullable=False, index=True)
    target_type: Mapped[str] = mapped_column(sa.String(64), nullable=False)
    target_id: Mapped[str] = mapped_column(sa.String(64), nullable=False, index=True)
    details_json: Mapped[str] = mapped_column(sa.Text, default="{}", nullable=False)
