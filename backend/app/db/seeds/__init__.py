from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import sqlalchemy as sa
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models.agency import Agency, Province


@dataclass(frozen=True, slots=True)
class ProvinceSeed:
    code: str
    khmer_name: str
    english_name: str
    center_lat: float
    center_lng: float
    default_zoom: float = 12.0
    is_capital: bool = False


# Exact 25 official Capital & Provinces matching `lib/domain/models/cambodia_locations.dart`
CAMBODIA_PROVINCES: tuple[ProvinceSeed, ...] = (
    ProvinceSeed("phnom_penh", "រាជធានីភ្នំពេញ", "Phnom Penh", 11.5564, 104.9282, 13.0, True),
    ProvinceSeed("siem_reap", "ខេត្តសៀមរាប", "Siem Reap", 13.3633, 103.8564, 13.0),
    ProvinceSeed("preah_sihanouk", "ខេត្តព្រះសីហនុ", "Preah Sihanouk", 10.6275, 103.5221, 13.0),
    ProvinceSeed("battambang", "ខេត្តបាត់ដំបង", "Battambang", 13.0957, 103.2022, 13.0),
    ProvinceSeed("kampot", "ខេត្តកំពត", "Kampot", 10.6104, 104.1814, 13.0),
    ProvinceSeed("kandal", "ខេត្តកណ្តាល", "Kandal", 11.4833, 104.9500, 12.6),
    ProvinceSeed("kampong_cham", "ខេត្តកំពង់ចាម", "Kampong Cham", 11.9934, 105.4635),
    ProvinceSeed("banteay_meanchey", "ខេត្តបន្ទាយមានជ័យ", "Banteay Meanchey", 13.5859, 102.9737),
    ProvinceSeed("takeo", "ខេត្តតាកែវ", "Takeo", 10.9908, 104.7850),
    ProvinceSeed("kampong_speu", "ខេត្តកំពង់ស្ពឺ", "Kampong Speu", 11.4533, 104.5209),
    ProvinceSeed("kampong_chhnang", "ខេត្តកំពង់ឆ្នាំង", "Kampong Chhnang", 12.2500, 104.6667),
    ProvinceSeed("kampong_thom", "ខេត្តកំពង់ធំ", "Kampong Thom", 12.7111, 104.8887),
    ProvinceSeed("pursat", "ខេត្តពោធិ៍សាត់", "Pursat", 12.5388, 103.9192),
    ProvinceSeed("prey_veng", "ខេត្តព្រៃវែង", "Prey Veng", 11.4868, 105.3253),
    ProvinceSeed("svay_rieng", "ខេត្តស្វាយរៀង", "Svay Rieng", 11.0879, 105.7993),
    ProvinceSeed("tbong_khmum", "ខេត្តត្បូងឃ្មុំ", "Tbong Khmum", 11.8891, 105.8760),
    ProvinceSeed("kep", "ខេត្តកែប", "Kep", 10.4829, 104.3167),
    ProvinceSeed("koh_kong", "ខេត្តកោះកុង", "Koh Kong", 11.6153, 102.9838),
    ProvinceSeed("kratie", "ខេត្តក្រចេះ", "Kratie", 12.4881, 106.0188),
    ProvinceSeed("stung_treng", "ខេត្តស្ទឹងត្រែង", "Stung Treng", 13.5259, 105.9683),
    ProvinceSeed("ratanakiri", "ខេត្តរតនគិរី", "Ratanakiri", 13.7394, 106.9873),
    ProvinceSeed("mondulkiri", "ខេត្តមណ្ឌលគិរី", "Mondulkiri", 12.4558, 107.1881),
    ProvinceSeed("preah_vihear", "ខេត្តព្រះវិហារ", "Preah Vihear", 13.8073, 104.9805),
    ProvinceSeed("oddar_meanchey", "ខេត្តឧត្តរមានជ័យ", "Oddar Meanchey", 14.1818, 103.5176),
    ProvinceSeed("pailin", "ខេត្តប៉ៃលិន", "Pailin", 12.8490, 102.6093),
)

DEFAULT_AGENCIES: tuple[dict[str, Any], ...] = (
    {
        "code": "MPWT",
        "khmer_name": "ក្រសួងសាធារណការ និងដឹកជញ្ជូន (MPWT)",
        "english_name": "Ministry of Public Works & Transport (MPWT)",
        "hotline": "1190",
        "province_code": None,
        "category_scope": "pothole:majorArtery",
    },
    {
        "code": "PPCH",
        "khmer_name": "រដ្ឋបាលរាជធានីភ្នំពេញ (PPCH)",
        "english_name": "Phnom Penh Capital Hall (PPCH)",
        "hotline": None,
        "province_code": "phnom_penh",
        "category_scope": "pothole,other",
    },
    {
        "code": "PPCH_DRAIN",
        "khmer_name": "មន្ទីរសាធារណការ និងប្រព័ន្ធលូ រាជធានីភ្នំពេញ",
        "english_name": "Dept. of Public Works & Drainage (PPCH)",
        "hotline": None,
        "province_code": "phnom_penh",
        "category_scope": "drain",
    },
    {
        "code": "EDC",
        "khmer_name": "អគ្គិសនីកម្ពុជា (EDC)",
        "english_name": "Electricité du Cambodge (EDC)",
        "hotline": "1298",
        "province_code": None,
        "category_scope": "streetlight",
    },
    {
        "code": "DPWT",
        "khmer_name": "មន្ទីរសាធារណការ និងដឹកជញ្ជូនខេត្ត (DPWT)",
        "english_name": "Provincial Dept. of Public Works & Transport (DPWT)",
        "hotline": "1190",
        "province_code": None,
        "category_scope": "pothole,drain",
    },
    {
        "code": "WASTE_ADMIN",
        "khmer_name": "រដ្ឋបាលក្រុង/ខណ្ឌ និងសេវាប្រមូលសំរាម",
        "english_name": "Khan / Municipal Admin & Waste Management",
        "hotline": None,
        "province_code": None,
        "category_scope": "trash,other",
    },
)


async def seed_reference_data(session: AsyncSession) -> dict[str, int]:
    """Idempotently seed all 25 official Cambodia provinces and default agencies."""
    provinces_inserted = 0
    agencies_inserted = 0

    for item in CAMBODIA_PROVINCES:
        existing = await session.scalar(
            sa.select(Province).where(Province.code == item.code)
        )
        if existing is None:
            session.add(
                Province(
                    code=item.code,
                    khmer_name=item.khmer_name,
                    english_name=item.english_name,
                    center_lat=item.center_lat,
                    center_lng=item.center_lng,
                    default_zoom=item.default_zoom,
                    is_capital=item.is_capital,
                )
            )
            provinces_inserted += 1

    await session.flush()

    for agency in DEFAULT_AGENCIES:
        existing_agency = await session.scalar(
            sa.select(Agency).where(Agency.code == agency["code"])
        )
        if existing_agency is None:
            session.add(Agency(**agency))
            agencies_inserted += 1

    await session.commit()
    return {
        "provinces_inserted": provinces_inserted,
        "agencies_inserted": agencies_inserted,
    }
