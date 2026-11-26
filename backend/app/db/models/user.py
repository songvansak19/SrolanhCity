from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class User(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Citizen (guest or phone-verified) or Ministry / Agency staff user."""

    __tablename__ = "users"

    role: Mapped[str] = mapped_column(sa.String(32), default="guest", nullable=False, index=True)
    khmer_name: Mapped[str] = mapped_column(sa.String(120), default="ភ្ញៀវ", nullable=False)
    english_name: Mapped[str] = mapped_column(sa.String(120), default="Guest", nullable=False)
    phone_hash: Mapped[str | None] = mapped_column(
        sa.String(128), unique=True, nullable=True, index=True
    )
    masked_phone: Mapped[str | None] = mapped_column(sa.String(32), nullable=True)
    home_province_code: Mapped[str | None] = mapped_column(
        sa.String(40),
        sa.ForeignKey("provinces.code", ondelete="SET NULL"),
        nullable=True,
    )
    khmer_home_area: Mapped[str] = mapped_column(sa.String(200), default="", nullable=False)
    english_home_area: Mapped[str] = mapped_column(sa.String(200), default="", nullable=False)
    agency_id: Mapped[str | None] = mapped_column(
        sa.String(36),
        sa.ForeignKey("agencies.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    is_active: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
