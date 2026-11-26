from __future__ import annotations

from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal
from enum import StrEnum


class RoadClass(StrEnum):
    """Road classification matching `RoadClass` in `lib/domain/models/report_models.dart`."""

    ALLEY = "alley"
    RESIDENTIAL = "residential"
    SECONDARY = "secondary"
    COMMERCIAL = "commercial"
    MAJOR_ARTERY = "majorArtery"

    @property
    def traffic_score(self) -> int:
        return {
            RoadClass.ALLEY: 1,
            RoadClass.RESIDENTIAL: 2,
            RoadClass.SECONDARY: 3,
            RoadClass.COMMERCIAL: 4,
            RoadClass.MAJOR_ARTERY: 5,
        }[self]


@dataclass(frozen=True, slots=True)
class PriorityTierRule:
    """One row in the P5 -> P1 priority threshold guide (`priority_calculator.dart`)."""

    level: int
    score_range: str
    khmer_name: str
    english_name: str
    khmer_sla: str
    english_sla: str
    sla_hours: int


TIER_TABLE: tuple[PriorityTierRule, ...] = (
    PriorityTierRule(
        level=5,
        score_range="4.5 – 5.0",
        khmer_name="បន្ទាន់បំផុត",
        english_name="Critical",
        khmer_sla="ក្នុង ២៤ ម៉ោង",
        english_sla="Within 24h",
        sla_hours=24,
    ),
    PriorityTierRule(
        level=4,
        score_range="3.5 – 4.4",
        khmer_name="អាទិភាពខ្ពស់",
        english_name="High",
        khmer_sla="២–៣ ថ្ងៃ",
        english_sla="2–3 days",
        sla_hours=72,
    ),
    PriorityTierRule(
        level=3,
        score_range="2.5 – 3.4",
        khmer_name="អាទិភាពមធ្យម",
        english_name="Medium",
        khmer_sla="ប្រចាំសប្តាហ៍",
        english_sla="Weekly",
        sla_hours=168,
    ),
    PriorityTierRule(
        level=2,
        score_range="1.5 – 2.4",
        khmer_name="អាទិភាពទាប",
        english_name="Low",
        khmer_sla="រួមតំបន់ជិត",
        english_sla="Batched",
        sla_hours=336,
    ),
    PriorityTierRule(
        level=1,
        score_range="1.0 – 1.4",
        khmer_name="កម្រិតស្រាល",
        english_name="Minor",
        khmer_sla="តាមរដូវកាល",
        english_sla="Seasonal",
        sla_hours=720,
    ),
)

_TIER_BY_LEVEL: dict[int, PriorityTierRule] = {rule.level: rule for rule in TIER_TABLE}


@dataclass(frozen=True, slots=True)
class PriorityBreakdown:
    """Weighted priority breakdown matching `PriorityBreakdown` in `report_models.dart`."""

    traffic_score: int
    severity_score: int
    report_count_score: int
    raw_score: float
    level: int
    khmer_level_name: str
    english_level_name: str
    khmer_sla: str
    english_sla: str
    sla_hours: int


class PriorityCalculator:
    """Calculates weighted 1–5 repair priority matching `priority_calculator.dart`.

    Formula: `Priority Score = (0.4 * Traffic) + (0.3 * Severity) + (0.3 * Reports)`
    Uses `ROUND_HALF_UP` so `.5` boundaries (e.g. `2.5 -> P3`, `3.5 -> P4`, `4.5 -> P5`)
    match Dart's `double.round()` identically.
    """

    @staticmethod
    def score_report_count(count: int) -> int:
        if count <= 1:
            return 1
        if count <= 3:
            return 2
        if count <= 7:
            return 3
        if count <= 14:
            return 4
        return 5

    @classmethod
    def tier_for_level(cls, level: int) -> PriorityTierRule:
        clamped = max(1, min(5, level))
        return _TIER_BY_LEVEL[clamped]

    @classmethod
    def calculate(
        cls,
        *,
        traffic_score: int,
        severity_score: int,
        report_count: int,
    ) -> PriorityBreakdown:
        clamped_traffic = max(1, min(5, traffic_score))
        clamped_severity = max(1, min(5, severity_score))
        count_score = cls.score_report_count(report_count)

        raw = (
            Decimal("0.4") * Decimal(clamped_traffic)
            + Decimal("0.3") * Decimal(clamped_severity)
            + Decimal("0.3") * Decimal(count_score)
        )
        raw_score = float(raw.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))
        rounded_level = int(raw.quantize(Decimal("1"), rounding=ROUND_HALF_UP))
        level = max(1, min(5, rounded_level))
        tier = cls.tier_for_level(level)

        return PriorityBreakdown(
            traffic_score=clamped_traffic,
            severity_score=clamped_severity,
            report_count_score=count_score,
            raw_score=raw_score,
            level=level,
            khmer_level_name=tier.khmer_name,
            english_level_name=tier.english_name,
            khmer_sla=tier.khmer_sla,
            english_sla=tier.english_sla,
            sla_hours=tier.sla_hours,
        )
