from __future__ import annotations

import math
from collections import Counter, defaultdict
from typing import Any

import sqlalchemy as sa
from geoalchemy2 import Geography
from sqlalchemy.sql.elements import ColumnElement

from app.core.integrity import (
    SELF_DUPLICATE_BLOCK_METERS,
    VERIFIED_NEARBY_METERS,
    haversine_meters,
)
from app.db.models.report import Report
from app.schemas.ai import IssueCategoryEnum
from app.schemas.report import (
    AreaClusterItemSchema,
    ClusterTierEnum,
    MapViewportResponse,
    ProvinceClusterItemSchema,
    ReportResponse,
    SingleReportPinItemSchema,
)


class SpatialService:
    """PostGIS query builder & 3-tier viewport clustering matching Flutter services."""

    DEFAULT_RADIUS_METERS: float = VERIFIED_NEARBY_METERS  # 150.0 m
    HARD_SELF_BLOCK_METERS: float = SELF_DUPLICATE_BLOCK_METERS  # 50.0 m
    PROVINCE_ZOOM_THRESHOLD: float = 10.2
    AREA_ZOOM_THRESHOLD: float = 13.4

    @classmethod
    def zoom_tier_for(cls, zoom: float) -> ClusterTierEnum:
        """Map zoom level to exact Flutter `MapClusterService` tier."""
        if zoom < cls.PROVINCE_ZOOM_THRESHOLD:
            return ClusterTierEnum.PROVINCE
        if zoom < cls.AREA_ZOOM_THRESHOLD:
            return ClusterTierEnum.AREA
        return ClusterTierEnum.SINGLE

    @staticmethod
    def adaptive_grid_cell_degrees(zoom: float) -> float:
        """Adaptive grid cell size matching `MapClusterService`:
        `clamp(0.024 * 2^(12.0 - zoom), 0.008, 0.14)`.
        """
        raw = 0.024 * (2.0 ** (12.0 - zoom))
        return max(0.008, min(0.14, raw))

    @staticmethod
    def build_postgis_within_clause(
        *,
        lat: float,
        lng: float,
        radius_meters: float = DEFAULT_RADIUS_METERS,
    ) -> ColumnElement[bool]:
        """Build a PostGIS `ST_DWithin` geography filter for `Report.geom`."""
        point_wkt = f"SRID=4326;POINT({lng} {lat})"
        return sa.func.ST_DWithin(
            sa.cast(Report.geom, Geography(geometry_type="POINT", srid=4326)),
            sa.func.ST_GeogFromText(point_wkt),
            radius_meters,
        )

    @classmethod
    def find_nearby_duplicates(
        cls,
        *,
        reports: list[ReportResponse],
        lat: float,
        lng: float,
        category: IssueCategoryEnum,
        radius_meters: float = DEFAULT_RADIUS_METERS,
    ) -> list[tuple[ReportResponse, float]]:
        """Find open same-category reports within `radius_meters`, sorted nearest first."""
        matches: list[tuple[ReportResponse, float]] = []
        for report in reports:
            if report.status.value == "resolved" or report.category != category:
                continue
            dist = haversine_meters(lat, lng, report.lat, report.lng)
            if dist <= radius_meters:
                matches.append((report, dist))
        matches.sort(key=lambda pair: (pair[1], pair[0].id))
        return matches

    @classmethod
    def has_self_duplicate_within_50m(
        cls,
        *,
        reports: list[ReportResponse],
        lat: float,
        lng: float,
        category: IssueCategoryEnum,
    ) -> bool:
        """Enforce the 50m hard self-duplicate block (`hardSelfBlockRadiusMeters`)."""
        for report in reports:
            if (
                report.status.value != "resolved"
                and report.category == category
                and (report.created_by_current_user or report.joined_by_current_user)
            ):
                if haversine_meters(lat, lng, report.lat, report.lng) <= cls.HARD_SELF_BLOCK_METERS:
                    return True
        return False

    @classmethod
    def cluster_reports_for_viewport(
        cls,
        *,
        reports: list[ReportResponse],
        min_lat: float,
        min_lng: float,
        max_lat: float,
        max_lng: float,
        zoom: float,
        province_code: str | None = None,
        category: IssueCategoryEnum | None = None,
        include_resolved: bool = True,
    ) -> MapViewportResponse:
        """Filter reports to bbox and group into province / area / single pins."""
        filtered: list[ReportResponse] = []
        for report in reports:
            if not include_resolved and report.status.value == "resolved":
                continue
            if province_code and report.province_code != province_code:
                continue
            if category and report.category != category:
                continue
            if min_lat <= report.lat <= max_lat and min_lng <= report.lng <= max_lng:
                filtered.append(report)

        filtered.sort(
            key=lambda r: (
                -(r.priority.raw_score if r.priority else 0.0),
                -r.created_at.timestamp(),
                r.id,
            )
        )

        tier = cls.zoom_tier_for(zoom)
        if tier == ClusterTierEnum.PROVINCE:
            by_province: dict[str, list[ReportResponse]] = defaultdict(list)
            for r in filtered:
                by_province[r.province_code].append(r)

            provinces: list[ProvinceClusterItemSchema] = []
            for p_code, group in by_province.items():
                avg_lat = sum(r.lat for r in group) / len(group)
                avg_lng = sum(r.lng for r in group) / len(group)
                max_level = cls._max_open_priority(group)
                all_resolved = all(r.status.value == "resolved" for r in group)
                provinces.append(
                    ProvinceClusterItemSchema(
                        province_code=p_code,
                        khmer_province=group[0].khmer_province,
                        english_province=group[0].english_province,
                        lat=round(avg_lat, 5),
                        lng=round(avg_lng, 5),
                        count=len(group),
                        max_priority_level=max_level,
                        all_resolved=all_resolved,
                    )
                )
            return MapViewportResponse(
                tier=tier,
                zoom=zoom,
                total_matching=len(filtered),
                provinces=provinces,
            )

        if tier == ClusterTierEnum.AREA:
            cell_deg = cls.adaptive_grid_cell_degrees(zoom)
            buckets: dict[tuple[int, int], list[ReportResponse]] = defaultdict(list)
            for r in filtered:
                gx = math.floor(r.lat / cell_deg)
                gy = math.floor(r.lng / cell_deg)
                buckets[(gx, gy)].append(r)

            areas: list[AreaClusterItemSchema] = []
            pins: list[SingleReportPinItemSchema] = []
            for (gx, gy), group in buckets.items():
                if len(group) == 1:
                    pins.append(SingleReportPinItemSchema(report=group[0]))
                    continue
                avg_lat = sum(r.lat for r in group) / len(group)
                avg_lng = sum(r.lng for r in group) / len(group)
                max_level = cls._max_open_priority(group)
                dominant = Counter(r.category for r in group).most_common(1)[0][0]
                areas.append(
                    AreaClusterItemSchema(
                        cluster_id=f"grid-{gx}-{gy}",
                        lat=round(avg_lat, 5),
                        lng=round(avg_lng, 5),
                        count=len(group),
                        max_priority_level=max_level,
                        dominant_category=dominant,
                        all_resolved=all(r.status.value == "resolved" for r in group),
                    )
                )
            return MapViewportResponse(
                tier=tier,
                zoom=zoom,
                total_matching=len(filtered),
                areas=areas,
                pins=pins,
            )

        return MapViewportResponse(
            tier=tier,
            zoom=zoom,
            total_matching=len(filtered),
            pins=[SingleReportPinItemSchema(report=r) for r in filtered],
        )

    @staticmethod
    def _max_open_priority(group: list[ReportResponse]) -> int:
        """Compute max priority level across unresolved reports (default `1`)."""
        return max(
            (
                (r.priority.level if r.priority else 1)
                for r in group
                if r.status.value != "resolved"
            ),
            default=1,
        )

    @staticmethod
    def to_wkt_point(lat: float, lng: float) -> str:
        """Format coordinates as EWKT `SRID=4326;POINT(lng lat)`."""
        return f"SRID=4326;POINT({lng} {lat})"

    @staticmethod
    def build_viewport_bbox_bounds(
        lat: float, lng: float, radius_meters: float = 25_000.0
    ) -> dict[str, Any]:
        """Compute fallback bounding box around `(lat, lng)` when map bounds are absent."""
        d_lat = radius_meters / 111_320.0
        cos_lat = max(0.2, math.cos(math.radians(lat)))
        d_lng = radius_meters / (111_320.0 * cos_lat)
        return {
            "min_lat": round(lat - d_lat, 5),
            "min_lng": round(lng - d_lng, 5),
            "max_lat": round(lat + d_lat, 5),
            "max_lng": round(lng + d_lng, 5),
        }
