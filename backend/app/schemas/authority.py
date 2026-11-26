from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field

from app.schemas.report import ReportResponse


class StaffQueueResponse(BaseModel):
    """Ministry / Provincial agency dispatch queue (`staff_console_page.dart`)."""

    pending_count: int = 0
    critical_p5_count: int = 0
    resolved_count: int = 0
    items: list[ReportResponse] = Field(default_factory=list)


class DispatchCrewRequest(BaseModel):
    """`POST /api/v1/authority/reports/{report_id}/dispatch` request."""

    crew_code: str = Field(default="B-07", min_length=1, max_length=32)
    note: str | None = None


class ResolveWithProofRequest(BaseModel):
    """`POST /api/v1/authority/reports/{report_id}/resolve` request."""

    after_photo_object_key: str | None = None
    after_photo_base64: str | None = None
    crew_code: str | None = None
    fixed_duration_khmer: str = "ជួសជុលរួចរាល់"
    fixed_duration_english: str = "Fixed & verified"
    resolution_note: str | None = None


class AuthorityKpisOut(BaseModel):
    """Ministry SLA & MTTR analytics KPIs (`AnalyticsService`)."""

    total_reports: int = 0
    open_reports: int = 0
    critical_p5_count: int = 0
    resolved_count: int = 0
    avg_mttr_hours: float | None = None
    sla_breach_count: int = 0
    by_province: dict[str, int] = Field(default_factory=dict)
    by_agency: dict[str, int] = Field(default_factory=dict)


class HeatmapFeatureProperties(BaseModel):
    """GeoJSON Feature properties for Ministry spatial heatmap overlays."""

    province_code: str
    english_province: str
    report_count: int
    critical_p5_count: int
    avg_priority_raw: float


class HeatmapFeature(BaseModel):
    """GeoJSON Point Feature."""

    type: Literal["Feature"] = "Feature"
    geometry: dict[str, Any]
    properties: HeatmapFeatureProperties


class ProvinceHeatmapFeatureCollection(BaseModel):
    """GeoJSON FeatureCollection returned by `GET /api/v1/authority/analytics/heatmap`."""

    type: Literal["FeatureCollection"] = "FeatureCollection"
    features: list[HeatmapFeature] = Field(default_factory=list)
