from __future__ import annotations

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin


class Province(Base):
    """Cambodia Capital & 24 Provinces (`cambodia_locations.dart`)."""

    __tablename__ = "provinces"

    code: Mapped[str] = mapped_column(sa.String(40), primary_key=True)
    khmer_name: Mapped[str] = mapped_column(sa.String(120), nullable=False)
    english_name: Mapped[str] = mapped_column(sa.String(120), nullable=False)
    center_lat: Mapped[float] = mapped_column(sa.Float, nullable=False)
    center_lng: Mapped[float] = mapped_column(sa.Float, nullable=False)
    default_zoom: Mapped[float] = mapped_column(sa.Float, default=12.0, nullable=False)
    is_capital: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)


class Agency(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Responsible Ministry or Provincial / Municipal agency (MPWT, PPCH, DPWT, EDC)."""

    __tablename__ = "agencies"

    code: Mapped[str] = mapped_column(sa.String(40), unique=True, nullable=False, index=True)
    khmer_name: Mapped[str] = mapped_column(sa.String(200), nullable=False)
    english_name: Mapped[str] = mapped_column(sa.String(200), nullable=False)
    hotline: Mapped[str | None] = mapped_column(sa.String(32), nullable=True)
    province_code: Mapped[str | None] = mapped_column(
        sa.String(40),
        sa.ForeignKey("provinces.code", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    category_scope: Mapped[str] = mapped_column(sa.String(80), default="all", nullable=False)
