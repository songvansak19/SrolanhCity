from __future__ import annotations

from collections import Counter, defaultdict
from datetime import UTC, datetime

from app.core.priority import PriorityCalculator
from app.db.seeds import CAMBODIA_PROVINCES
from app.schemas.authority import (
    AuthorityKpisOut,
    HeatmapFeature,
    HeatmapFeatureProperties,
    ProvinceHeatmapFeatureCollection,
)
from app.schemas.report import ReportResponse

_PROVINCE_COORDS = {
    p.code: (p.center_lat, p.center_lng, p.english_name) for p in CAMBODIA_PROVINCES
}


class AnalyticsService:
    """Ministry / Authority SLA, MTTR, and GeoJSON heatmap calculations."""

    @staticmethod
    def compute_kpis(
        *,
        reports: list[ReportResponse],
        resolved_at_by_id: dict[str, datetime] | None = None,
        now: datetime | None = None,
    ) -> AuthorityKpisOut:
        current_time = now or datetime.now(UTC)
        resolved_map = resolved_at_by_id or {}

        open_reports = 0
        critical_p5_count = 0
        resolved_count = 0
        sla_breach_count = 0
        mttr_hours_samples: list[float] = []
        by_province: Counter[str] = Counter()
        by_agency: Counter[str] = Counter()

        for report in reports:
            by_province[report.province_code] += 1
            if report.english_agency:
                by_agency[report.english_agency] += 1

            level = report.priority.level if report.priority else 2
            sla_hours = PriorityCalculator.tier_for_level(level).sla_hours

            if report.status.value == "resolved":
                resolved_count += 1
                resolved_ts = resolved_map.get(report.id)
                if resolved_ts is not None:
                    elapsed_h = max(
                        0.0,
                        (resolved_ts - report.created_at).total_seconds() / 3600.0,
                    )
                    mttr_hours_samples.append(elapsed_h)
                    if elapsed_h > sla_hours:
                        sla_breach_count += 1
            else:
                open_reports += 1
                if level == 5:
                    critical_p5_count += 1
                age_h = max(0.0, (current_time - report.created_at).total_seconds() / 3600.0)
                if age_h > sla_hours:
                    sla_breach_count += 1

        avg_mttr = (
            round(sum(mttr_hours_samples) / len(mttr_hours_samples), 2)
            if mttr_hours_samples
            else None
        )

        return AuthorityKpisOut(
            total_reports=len(reports),
            open_reports=open_reports,
            critical_p5_count=critical_p5_count,
            resolved_count=resolved_count,
            avg_mttr_hours=avg_mttr,
            sla_breach_count=sla_breach_count,
            by_province=dict(by_province),
            by_agency=dict(by_agency),
        )

    @staticmethod
    def build_province_heatmap(
        reports: list[ReportResponse],
    ) -> ProvinceHeatmapFeatureCollection:
        grouped: dict[str, list[ReportResponse]] = defaultdict(list)
        for report in reports:
            grouped[report.province_code].append(report)

        features: list[HeatmapFeature] = []
        for province_code, items in grouped.items():
            coords = _PROVINCE_COORDS.get(province_code)
            if coords is not None:
                center_lat, center_lng, en_name = coords
            else:
                center_lat = sum(r.lat for r in items) / len(items)
                center_lng = sum(r.lng for r in items) / len(items)
                en_name = items[0].english_province

            critical_p5 = sum(1 for r in items if (r.priority and r.priority.level == 5))
            avg_raw = sum((r.priority.raw_score if r.priority else 2.0) for r in items) / len(items)
            features.append(
                HeatmapFeature(
                    geometry={
                        "type": "Point",
                        "coordinates": [center_lng, center_lat],
                    },
                    properties=HeatmapFeatureProperties(
                        province_code=province_code,
                        english_province=en_name,
                        report_count=len(items),
                        critical_p5_count=critical_p5,
                        avg_priority_raw=round(avg_raw, 2),
                    ),
                )
            )
        return ProvinceHeatmapFeatureCollection(features=features)
