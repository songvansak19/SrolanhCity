from __future__ import annotations

from dataclasses import dataclass

from app.core.integrity import haversine_meters, is_inside_cambodia
from app.core.priority import RoadClass
from app.db.seeds import CAMBODIA_PROVINCES, ProvinceSeed
from app.schemas.ai import IssueCategoryEnum


@dataclass(frozen=True, slots=True)
class RoutingAssignment:
    """Result of GIS province & agency routing (`GisRoutingResult` parity)."""

    province_code: str
    khmer_province: str
    english_province: str
    agency_code: str
    khmer_agency: str
    english_agency: str
    road_class: RoadClass


_PROVINCE_BY_CODE: dict[str, ProvinceSeed] = {p.code: p for p in CAMBODIA_PROVINCES}

_PHNOM_PENH_LANDMARK_POINTS: tuple[tuple[float, float], ...] = (
    (11.5564, 104.9282),
    (11.5620, 104.9228),
    (11.5498, 104.9210),
    (11.5656, 104.9142),
    (11.5730, 104.8990),
    (11.5415, 104.9110),
    (11.5680, 104.8810),
    (11.5845, 104.9335),
    (11.5290, 104.9380),
    (11.5315, 104.8920),
)
_PHNOM_PENH_ZONE_RADIUS_METERS = 3500.0


def _short_khmer(khmer_name: str) -> str:
    """Match `ProvinceOption.shortKhmer` in `cambodia_locations.dart:51-59`."""
    for prefix in ("រាជធានី", "ខេត្ត"):
        if khmer_name.startswith(prefix):
            return khmer_name[len(prefix) :]
    return khmer_name


class GisRoutingService:
    """Automatic Ministry / Provincial agency assignment for Phnom Penh & 24 provinces.

    Matches `lib/domain/services/gis_routing_service.dart:313-365`.
    """

    @staticmethod
    def resolve_province(
        *,
        lat: float,
        lng: float,
        province_code: str | None = None,
    ) -> ProvinceSeed | None:
        if province_code and province_code in _PROVINCE_BY_CODE:
            return _PROVINCE_BY_CODE[province_code]
        if not is_inside_cambodia(lat, lng):
            return None
        best_pp_distance = min(
            haversine_meters(lat, lng, lm_lat, lm_lng)
            for lm_lat, lm_lng in _PHNOM_PENH_LANDMARK_POINTS
        )
        if best_pp_distance <= _PHNOM_PENH_ZONE_RADIUS_METERS:
            return _PROVINCE_BY_CODE["phnom_penh"]
        return min(
            CAMBODIA_PROVINCES,
            key=lambda prov: haversine_meters(lat, lng, prov.center_lat, prov.center_lng),
        )

    @classmethod
    def assign_agency(
        cls,
        *,
        lat: float,
        lng: float,
        category: IssueCategoryEnum,
        road_class: RoadClass = RoadClass.SECONDARY,
        province_code: str | None = None,
        khmer_district: str | None = None,
        english_district: str | None = None,
    ) -> RoutingAssignment:
        province = cls.resolve_province(lat=lat, lng=lng, province_code=province_code)
        if province is None:
            return RoutingAssignment(
                province_code="outside_cambodia",
                khmer_province="ក្រៅប្រទេសកម្ពុជា",
                english_province="Outside Cambodia",
                agency_code="OUTSIDE",
                khmer_agency="រង់ចាំផ្ទៀងផ្ទាត់តំបន់កម្ពុជា",
                english_agency="Awaiting Cambodia Area Verification",
                road_class=road_class,
            )

        is_pp = province.code == "phnom_penh"
        kh_district = khmer_district or ("ខណ្ឌដូនពេញ" if is_pp else province.khmer_name)
        en_district = english_district or ("Khan Daun Penh" if is_pp else province.english_name)

        if is_pp:
            if category == IssueCategoryEnum.POTHOLE and road_class == RoadClass.MAJOR_ARTERY:
                code = "MPWT"
                kh_agency = "ក្រសួងសាធារណការ និងដឹកជញ្ជូន (MPWT)"
                en_agency = "Ministry of Public Works & Transport (MPWT)"
            elif category == IssueCategoryEnum.POTHOLE:
                code = "PPCH"
                kh_agency = f"រដ្ឋបាលរាជធានីភ្នំពេញ · {kh_district}"
                en_agency = f"Phnom Penh Capital Hall · {en_district}"
            elif category == IssueCategoryEnum.STREETLIGHT:
                code = "EDC"
                kh_agency = "អគ្គិសនីកម្ពុជា (EDC)"
                en_agency = "Electricité du Cambodge (EDC)"
            elif category == IssueCategoryEnum.DRAIN:
                code = "PPCH_DRAIN"
                kh_agency = "មន្ទីរសាធារណការ និងប្រព័ន្ធលូ រាជធានីភ្នំពេញ"
                en_agency = "Dept. of Public Works & Drainage (PPCH)"
            elif category == IssueCategoryEnum.TRASH:
                code = "WASTE_ADMIN"
                kh_agency = f"រដ្ឋបាល{kh_district} និងសេវាប្រមូលសំរាម"
                en_agency = f"{en_district} Admin & Waste Management"
            else:
                code = "PPCH"
                kh_agency = f"រដ្ឋបាលរាជធានីភ្នំពេញ · {kh_district}"
                en_agency = f"Phnom Penh Capital Hall · {en_district}"
        else:
            if category == IssueCategoryEnum.POTHOLE and road_class == RoadClass.MAJOR_ARTERY:
                code = "MPWT"
                kh_agency = "ក្រសួងសាធារណការ និងដឹកជញ្ជូន (MPWT)"
                en_agency = "Ministry of Public Works & Transport (MPWT)"
            elif category == IssueCategoryEnum.POTHOLE:
                code = "DPWT"
                kh_agency = f"មន្ទីរសាធារណការ និងដឹកជញ្ជូន {province.khmer_name} (DPWT)"
                en_agency = f"Dept. of Public Works & Transport · {province.english_name} (DPWT)"
            elif category == IssueCategoryEnum.STREETLIGHT:
                code = "EDC"
                kh_agency = f"អគ្គិសនីកម្ពុជា · សាខា{province.khmer_name} (EDC)"
                en_agency = f"Electricité du Cambodge · {province.english_name} (EDC)"
            elif category == IssueCategoryEnum.DRAIN:
                code = "DPWT"
                kh_agency = f"មន្ទីរសាធារណការ និងប្រព័ន្ធលូ {province.khmer_name}"
                en_agency = f"{province.english_name} Public Works & Drainage"
            elif category == IssueCategoryEnum.TRASH:
                code = "WASTE_ADMIN"
                short_kh = _short_khmer(province.khmer_name)
                kh_agency = f"រដ្ឋបាល{kh_district} និងសេវាប្រមូលសំរាម ({short_kh})"
                en_agency = f"{en_district} Admin & Waste Management ({province.english_name})"
            else:
                code = "WASTE_ADMIN"
                kh_agency = f"រដ្ឋបាល{kh_district} · {province.khmer_name}"
                en_agency = f"{en_district} Admin · {province.english_name}"

        return RoutingAssignment(
            province_code=province.code,
            khmer_province=province.khmer_name,
            english_province=province.english_name,
            agency_code=code,
            khmer_agency=kh_agency,
            english_agency=en_agency,
            road_class=road_class,
        )
