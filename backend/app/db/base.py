from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import sqlalchemy as sa
from geoalchemy2 import Geometry
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    """SQLAlchemy 2.0 DeclarativeBase with deterministic constraint naming."""

    metadata = sa.MetaData(naming_convention=NAMING_CONVENTION)


def utc_now() -> datetime:
    """Return a timezone-aware UTC timestamp."""
    return datetime.now(UTC)


class TimestampMixin:
    """UTC `created_at` and `updated_at` columns."""

    created_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True),
        default=utc_now,
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        sa.DateTime(timezone=True),
        default=utc_now,
        onupdate=utc_now,
        nullable=False,
    )


class UUIDPrimaryKeyMixin:
    """UUID string primary key mixin."""

    id: Mapped[str] = mapped_column(
        sa.String(36),
        primary_key=True,
        default=lambda: str(uuid4()),
    )


def geom_point_column(*, nullable: bool = True) -> sa.Column[str]:
    """Portable POINT column: PostGIS GEOMETRY(POINT, 4326) on PostgreSQL, Text elsewhere.

    Allows Alembic & live PostgreSQL 16/PostGIS 3.4 to use native spatial indexes and
    `ST_DWithin`, while offline SQLite (`sqlite+aiosqlite:///:memory:`) tests can create
    and query every ORM table without requiring SpatiaLite.
    """
    point_type = sa.Text().with_variant(
        Geometry("POINT", srid=4326, spatial_index=False),
        "postgresql",
    )
    return mapped_column(point_type, nullable=nullable)  # type: ignore[return-value]
