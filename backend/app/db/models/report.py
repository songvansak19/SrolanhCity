from __future__ import annotations

from datetime import datetime

import sqlalchemy as sa
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPrimaryKeyMixin, geom_point_column, utc_now


class Report(TimestampMixin, Base):
    """Master civic incident report (`CivicReport` in `report_models.dart`)."""

    __tablename__ = "reports"

    id: Mapped[str] = mapped_column(sa.String(32), primary_key=True)  # e.g. "#SC-20481"
    category: Mapped[str] = mapped_column(sa.String(32), nullable=False, index=True)
    khmer_title: Mapped[str] = mapped_column(sa.String(240), nullable=False)
    english_title: Mapped[str] = mapped_column(sa.String(240), nullable=False)
    description: Mapped[str] = mapped_column(sa.Text, default="", nullable=False)

    khmer_location: Mapped[str] = mapped_column(sa.String(240), nullable=False)
    english_location: Mapped[str] = mapped_column(sa.String(240), nullable=False)
    lat: Mapped[float] = mapped_column(sa.Float, nullable=False, index=True)
    lng: Mapped[float] = mapped_column(sa.Float, nullable=False, index=True)
    geom: Mapped[str | None] = geom_point_column(nullable=True)

    province_code: Mapped[str] = mapped_column(
        sa.String(40),
        sa.ForeignKey("provinces.code", ondelete="RESTRICT"),
        default="phnom_penh",
        nullable=False,
        index=True,
    )
    khmer_province: Mapped[str] = mapped_column(
        sa.String(120), default="រាជធានីភ្នំពេញ", nullable=False
    )
    english_province: Mapped[str] = mapped_column(
        sa.String(120), default="Phnom Penh", nullable=False
    )

    road_class: Mapped[str] = mapped_column(sa.String(32), default="secondary", nullable=False)
    severity: Mapped[int] = mapped_column(sa.Integer, default=3, nullable=False)
    affected_citizens: Mapped[int] = mapped_column(sa.Integer, default=1, nullable=False)
    priority_raw: Mapped[float] = mapped_column(sa.Float, default=2.0, nullable=False, index=True)
    priority_level: Mapped[int] = mapped_column(sa.Integer, default=2, nullable=False, index=True)

    status: Mapped[str] = mapped_column(
        sa.String(32), default="submitted", nullable=False, index=True
    )
    agency_id: Mapped[str | None] = mapped_column(
        sa.String(36),
        sa.ForeignKey("agencies.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    khmer_agency: Mapped[str] = mapped_column(sa.String(200), default="", nullable=False)
    english_agency: Mapped[str] = mapped_column(sa.String(200), default="", nullable=False)

    reporter_user_id: Mapped[str | None] = mapped_column(
        sa.String(36),
        sa.ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    is_anonymous: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    exif_stripped: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    location_verification_tier: Mapped[str | None] = mapped_column(sa.String(40), nullable=True)

    crew_code: Mapped[str | None] = mapped_column(sa.String(32), nullable=True)
    voice_transcript: Mapped[str | None] = mapped_column(sa.Text, nullable=True)
    citizen_rating: Mapped[int | None] = mapped_column(sa.Integer, nullable=True)
    resolved_after_object_key: Mapped[str | None] = mapped_column(sa.String(255), nullable=True)
    before_date_label: Mapped[str] = mapped_column(sa.String(64), default="", nullable=False)
    after_date_label: Mapped[str] = mapped_column(sa.String(64), default="", nullable=False)
    fixed_duration_khmer: Mapped[str] = mapped_column(sa.String(120), default="", nullable=False)
    fixed_duration_english: Mapped[str] = mapped_column(sa.String(120), default="", nullable=False)
    resolved_at: Mapped[datetime | None] = mapped_column(sa.DateTime(timezone=True), nullable=True)

    photos: Mapped[list[ReportPhoto]] = relationship(
        back_populates="report", cascade="all, delete-orphan"
    )
    comments: Mapped[list[ReportComment]] = relationship(
        back_populates="report", cascade="all, delete-orphan"
    )
    supports: Mapped[list[ReportSupport]] = relationship(
        back_populates="report", cascade="all, delete-orphan"
    )
    timeline_entries: Mapped[list[ReportTimelineEntry]] = relationship(
        back_populates="report", cascade="all, delete-orphan"
    )


class ReportPhoto(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Photo object metadata stored in R2/MinIO (EXIF stripped before persistence)."""

    __tablename__ = "report_photos"

    report_id: Mapped[str] = mapped_column(
        sa.String(32),
        sa.ForeignKey("reports.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    object_key: Mapped[str] = mapped_column(sa.String(255), nullable=False)
    is_after_proof: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    exif_stripped: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)

    report: Mapped[Report] = relationship(back_populates="photos")


class ReportComment(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Citizen or supporter comment attached to a report."""

    __tablename__ = "report_comments"

    report_id: Mapped[str] = mapped_column(
        sa.String(32),
        sa.ForeignKey("reports.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[str | None] = mapped_column(
        sa.String(36),
        sa.ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    text: Mapped[str] = mapped_column(sa.Text, nullable=False)
    is_original_reporter: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    is_anonymous: Mapped[bool] = mapped_column(sa.Boolean, default=True, nullable=False)
    author_name: Mapped[str | None] = mapped_column(sa.String(120), nullable=True)
    severity: Mapped[int | None] = mapped_column(sa.Integer, nullable=True)
    voice_transcript: Mapped[str | None] = mapped_column(sa.Text, nullable=True)
    verification_tier: Mapped[str | None] = mapped_column(sa.String(32), nullable=True)
    remote_area_khmer: Mapped[str | None] = mapped_column(sa.String(200), nullable=True)
    remote_area_english: Mapped[str | None] = mapped_column(sa.String(200), nullable=True)
    support_reason_category: Mapped[str | None] = mapped_column(sa.String(40), nullable=True)

    report: Mapped[Report] = relationship(back_populates="comments")


class ReportSupport(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """Unique citizen 'Affects me' vote with silent GPS / 3-level remote area metadata."""

    __tablename__ = "report_supports"
    __table_args__ = (
        sa.UniqueConstraint("report_id", "user_id", name="uq_report_supports_report_user"),
    )

    report_id: Mapped[str] = mapped_column(
        sa.String(32),
        sa.ForeignKey("reports.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[str] = mapped_column(
        sa.String(36),
        sa.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    verification_tier: Mapped[str] = mapped_column(sa.String(32), nullable=False)
    distance_meters: Mapped[int | None] = mapped_column(sa.Integer, nullable=True)
    remote_area_khmer: Mapped[str | None] = mapped_column(sa.String(200), nullable=True)
    remote_area_english: Mapped[str | None] = mapped_column(sa.String(200), nullable=True)
    support_reason_category: Mapped[str | None] = mapped_column(sa.String(40), nullable=True)
    support_reason_note: Mapped[str | None] = mapped_column(sa.Text, nullable=True)
    integrity_risk_level: Mapped[str] = mapped_column(
        sa.String(16), default="trusted", nullable=False
    )

    report: Mapped[Report] = relationship(back_populates="supports")


class ReportTimelineEntry(UUIDPrimaryKeyMixin, Base):
    """Four-stage status timeline entry (`submitted`, `scheduled`, `crewDispatched`, `resolved`)."""

    __tablename__ = "report_timeline_entries"

    report_id: Mapped[str] = mapped_column(
        sa.String(32),
        sa.ForeignKey("reports.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    stage: Mapped[str] = mapped_column(sa.String(32), nullable=False)
    khmer_title: Mapped[str] = mapped_column(sa.String(200), nullable=False)
    english_title: Mapped[str] = mapped_column(sa.String(200), nullable=False)
    khmer_subtitle: Mapped[str] = mapped_column(sa.String(240), default="", nullable=False)
    english_subtitle: Mapped[str] = mapped_column(sa.String(240), default="", nullable=False)
    complete: Mapped[bool] = mapped_column(sa.Boolean, default=False, nullable=False)
    timestamp: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True), default=utc_now, nullable=False
    )

    report: Mapped[Report] = relationship(back_populates="timeline_entries")
