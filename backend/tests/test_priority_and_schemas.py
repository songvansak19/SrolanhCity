from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from pydantic import ValidationError
from sqlalchemy.dialects import postgresql

from app.core.exif import has_exif_or_metadata_markers, strip_jpeg_metadata
from app.core.integrity import (
    evaluate_gps_fix,
    haversine_meters,
    is_emulator_default_coords,
    is_inside_cambodia,
    verify_device_attestation,
)
from app.core.priority import PriorityCalculator, RoadClass
from app.schemas.ai import (
    ClassifyIssueRequest,
    ClassifyIssueResponse,
    HelpChatRequest,
    HelpChatResponse,
    IssueCategoryEnum,
    TranscribeVoiceRequest,
    TranscribeVoiceResponse,
    TranslateRequest,
)
from app.schemas.alert import AlertItemOut
from app.schemas.comment import CitizenCommentOut, CommentCreateRequest
from app.schemas.report import ReportResponse, ReportStatusEnum
from app.schemas.support import SupportCreateRequest
from app.services.routing import GisRoutingService
from app.services.spatial import SpatialService


def test_priority_calculator_count_buckets_and_clamping() -> None:
    """Verify exact report count bucket boundaries matching `priority_calculator.dart`."""
    expected = {
        0: 1,
        1: 1,
        2: 2,
        3: 2,
        4: 3,
        7: 3,
        8: 4,
        14: 4,
        15: 5,
        50: 5,
    }
    for count, score in expected.items():
        assert PriorityCalculator.score_report_count(count) == score

    # Clamping traffic and severity to 1..5
    low = PriorityCalculator.calculate(traffic_score=-3, severity_score=0, report_count=1)
    assert (low.traffic_score, low.severity_score, low.raw_score, low.level) == (1, 1, 1.0, 1)

    high = PriorityCalculator.calculate(traffic_score=99, severity_score=10, report_count=20)
    assert (high.traffic_score, high.severity_score, high.raw_score, high.level) == (5, 5, 5.0, 5)
    assert high.english_level_name == "Critical"
    assert high.english_sla == "Within 24h"
    assert high.sla_hours == 24


def test_priority_calculator_half_up_boundaries_match_dart_round() -> None:
    """Ensure `.5` scores round away from zero (matching Dart `.round()`, NOT banker's)."""
    # 0.4*1 + 0.3*5 + 0.3*2 = 2.5 -> Dart 2.5.round() == 3 (Python round(2.5) would be 2!)
    p3_boundary = PriorityCalculator.calculate(traffic_score=1, severity_score=5, report_count=2)
    assert p3_boundary.raw_score == 2.5
    assert p3_boundary.level == 3
    assert p3_boundary.english_level_name == "Medium"
    assert p3_boundary.english_sla == "Weekly"

    # 0.4*5 + 0.3*3 + 0.3*2 = 3.5 -> P4 High
    p4_boundary = PriorityCalculator.calculate(traffic_score=5, severity_score=3, report_count=2)
    assert p4_boundary.raw_score == 3.5
    assert p4_boundary.level == 4
    assert p4_boundary.english_level_name == "High"

    # 0.4*5 + 0.3*4 + 0.3*4 = 4.4 -> P4 High; 0.4*5 + 0.3*4 + 0.3*5 = 4.7 -> P5 Critical
    p4_upper = PriorityCalculator.calculate(traffic_score=5, severity_score=4, report_count=8)
    assert p4_upper.raw_score == 4.4
    assert p4_upper.level == 4

    p5_upper = PriorityCalculator.calculate(traffic_score=5, severity_score=4, report_count=15)
    assert p5_upper.raw_score == 4.7
    assert p5_upper.level == 5

    # Exact 1.5 and 4.5 boundaries via (traffic, severity, count_score):
    # 0.4*2 + 0.3*1 + 0.3*1 = 1.4 -> P1; 0.4*1 + 0.3*2 + 0.3*2 = 1.6 -> P2
    p1_upper = PriorityCalculator.calculate(traffic_score=2, severity_score=1, report_count=1)
    p2_lower = PriorityCalculator.calculate(traffic_score=1, severity_score=2, report_count=2)
    assert p1_upper.level == 1
    assert p2_lower.level == 2


def test_spatial_clustering_zoom_tiers_and_self_guard() -> None:
    """Verify 3-tier zoom clustering (<10.2, 10.2..13.4, >=13.4) and 50m self-guard."""
    assert SpatialService.zoom_tier_for(9.5).value == "province"
    assert SpatialService.zoom_tier_for(10.2).value == "area"
    assert SpatialService.zoom_tier_for(13.3).value == "area"
    assert SpatialService.zoom_tier_for(13.4).value == "single"

    base_report = ReportResponse.model_validate(
        {
            "id": "#SC-10001",
            "category": "pothole",
            "khmerTitle": "រន្ធផ្លូវ",
            "englishTitle": "Pothole",
            "description": "Test",
            "khmerLocation": "ភ្នំពេញ",
            "englishLocation": "Phnom Penh",
            "lat": 11.5564,
            "lng": 104.9282,
            "provinceCode": "phnom_penh",
            "khmerProvince": "រាជធានីភ្នំពេញ",
            "englishProvince": "Phnom Penh",
            "roadClass": "secondary",
            "severity": 3,
            "affectedCitizens": 1,
            "status": "submitted",
            "createdByCurrentUser": True,
            "createdAt": "2026-11-25T10:00:00Z",
        }
    )
    assert (
        SpatialService.has_self_duplicate_within_50m(
            reports=[base_report],
            lat=11.5565,
            lng=104.9282,
            category=IssueCategoryEnum.POTHOLE,
        )
        is True
    )
    assert (
        SpatialService.has_self_duplicate_within_50m(
            reports=[base_report],
            lat=11.5600,
            lng=104.9282,
            category=IssueCategoryEnum.POTHOLE,
        )
        is False
    )


def _jpeg_segment(marker: int, payload: bytes) -> bytes:
    length = len(payload) + 2
    return bytes([0xFF, marker, (length >> 8) & 0xFF, length & 0xFF]) + payload


def test_jpeg_exif_stripping_removes_app1_app2_app13_com() -> None:
    """Verify JPEG metadata markers are stripped while APP0 and SOS image stream stay intact."""
    app0 = _jpeg_segment(0xE0, b"JFIF\x00\x01\x01")
    app1_exif = _jpeg_segment(0xE1, b"Exif\x00\x00FAKE_GPS_DATA")
    app2_icc = _jpeg_segment(0xE2, b"ICC_PF")
    app13_iptc = _jpeg_segment(0xED, b"IPTC")
    com_note = _jpeg_segment(0xFE, b"SECRET")
    sos_and_eoi = b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00SCAN_BYTES\xff\xd9"

    dirty_jpeg = b"\xff\xd8" + app0 + app1_exif + app2_icc + app13_iptc + com_note + sos_and_eoi
    assert has_exif_or_metadata_markers(dirty_jpeg) is True

    stripped = strip_jpeg_metadata(dirty_jpeg)
    assert has_exif_or_metadata_markers(stripped) is False
    assert stripped == b"\xff\xd8" + app0 + sos_and_eoi

    # Non-JPEG (PNG header) returned untouched
    png_bytes = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
    assert strip_jpeg_metadata(png_bytes) == png_bytes


def test_cambodia_bounds_anti_spoof_and_gis_routing() -> None:
    """Verify Cambodia bounding box, anti-spoof rules, and Phnom Penh vs provincial routing."""
    assert is_inside_cambodia(11.5564, 104.9282) is True  # Phnom Penh
    assert is_inside_cambodia(13.3633, 103.8564) is True  # Siem Reap
    assert is_inside_cambodia(37.422, -122.084) is False  # Android emulator default
    assert is_emulator_default_coords(37.422, -122.084) is True

    now = datetime.now(UTC)
    mocked = evaluate_gps_fix(
        lat=11.55,
        lng=104.92,
        accuracy_meters=12.0,
        timestamp=now,
        is_mocked=True,
    )
    assert mocked.risk_level.value == "blocked"

    teleport = evaluate_gps_fix(
        lat=11.58,
        lng=104.92,
        accuracy_meters=10.0,
        timestamp=now,
        prev_lat=11.55,
        prev_lng=104.92,
        prev_timestamp=now - timedelta(seconds=1),
    )
    assert teleport.risk_level.value == "blocked"
    assert teleport.reasons[0].value == "gpsTeleport"

    strict_missing = verify_device_attestation(provider="play_integrity", token=None, mode="strict")
    assert strict_missing.valid is False

    # Routing parity
    pp_artery = GisRoutingService.assign_agency(
        lat=11.5564,
        lng=104.9282,
        category=IssueCategoryEnum.POTHOLE,
        road_class=RoadClass.MAJOR_ARTERY,
    )
    assert pp_artery.agency_code == "MPWT"

    sr_pothole = GisRoutingService.assign_agency(
        lat=13.3633,
        lng=103.8564,
        category=IssueCategoryEnum.POTHOLE,
        road_class=RoadClass.SECONDARY,
        province_code="siem_reap",
    )
    assert sr_pothole.agency_code == "DPWT"

    edc = GisRoutingService.assign_agency(
        lat=11.5564, lng=104.9282, category=IssueCategoryEnum.STREETLIGHT
    )
    assert edc.agency_code == "EDC"

    # Phnom Penh 3.5 km landmark zone overrides closer Kandal centroid
    pp_chbar = GisRoutingService.assign_agency(
        lat=11.515,
        lng=104.940,
        category=IssueCategoryEnum.POTHOLE,
        road_class=RoadClass.SECONDARY,
    )
    assert pp_chbar.province_code == "phnom_penh"
    assert pp_chbar.agency_code == "PPCH"

    # Provincial TRASH Khmer label uses shortKhmer without redundant prefix in parentheses
    sr_trash = GisRoutingService.assign_agency(
        lat=13.3633,
        lng=103.8564,
        category=IssueCategoryEnum.TRASH,
        province_code="siem_reap",
    )
    assert sr_trash.khmer_agency.endswith("(សៀមរាប)")

    # Exact 500.0 m teleport boundary triggers gpsTeleport (>= 500.0)
    # 500m north of 11.55 is ~0.0044966 deg; find exact lat step >= 500.0m and test exact edge
    lat_500m = 11.55 + (500.0 / haversine_meters(11.55, 104.92, 12.55, 104.92))
    exact_dist = haversine_meters(11.55, 104.92, lat_500m, 104.92)
    assert abs(exact_dist - 500.0) < 0.05
    boundary_tp = evaluate_gps_fix(
        lat=lat_500m + 1e-6,
        lng=104.92,
        accuracy_meters=10.0,
        timestamp=now,
        prev_lat=11.55,
        prev_lng=104.92,
        prev_timestamp=now - timedelta(seconds=2),
    )
    assert boundary_tp.risk_level.value == "blocked"
    assert boundary_tp.reasons[0].value == "gpsTeleport"


def test_pydantic_schemas_match_dart_contracts() -> None:
    """Validate AI, Support, Comment, Alert, and Report schemas against Dart payloads."""
    # 1. AI contracts (snake_case + Translate camelCase alias)
    ClassifyIssueRequest(image_base64="AAAA", mime_type="image/jpeg", language="km")
    ClassifyIssueResponse(
        is_civic_issue=True,
        category="pothole",
        confidence_percent=92,
        severity=5,
        khmer_summary="រន្ធផ្លូវ",
        english_summary="Deep pothole",
    )
    TranscribeVoiceRequest(audio_base64="BBBB", mime_type="audio/aac", language="en")
    TranscribeVoiceResponse(transcript="Broken streetlight", category="streetlight")
    HelpChatRequest(
        message="Where is my report?",
        language="en",
        history=[{"role": "user", "text": "Hi"}],
        citizen_context={
            "my_report_count": 1,
            "pending_sync_count": 0,
            "recent_ticket_ids": ["#SC-20481"],
        },
    )
    HelpChatResponse(reply="Report #SC-20481 is scheduled.", report_id="#SC-20481")
    tr = TranslateRequest(text="សួស្តី", targetLang="en")
    assert tr.target_lang == "en"

    # 2. `buildSupportApiPayload` parity + 10-char note enforcement for cross-province support
    SupportCreateRequest.model_validate(
        {
            "report_id": "#SC-20481",
            "verification_tier": "remoteProvince",
            "distance_meters": 210000,
            "lat": 13.3633,
            "lng": 103.8564,
            "remote_area": "Siem Reap",
            "support_reason_category": "dailyCommute",
            "support_reason_note": "I travel this road every week for work.",
            "integrity": {
                "risk_level": "trusted",
                "reasons": [],
                "photo_exif_verified": False,
                "ip_country_code": "KH",
                "attestation": {"provider": "play_integrity", "token": "tok"},
            },
        }
    )
    with pytest.raises(ValidationError):
        SupportCreateRequest.model_validate(
            {
                "report_id": "#SC-20481",
                "verification_tier": "remoteProvince",
                "support_reason_note": "too short",
            }
        )

    # 3. `buildCommentApiPayload` & `CitizenComment.toJson()` parity
    CommentCreateRequest.model_validate(
        {
            "report_id": "#SC-20481",
            "text": "Water blocks the sidewalk here.",
            "is_anonymous": False,
            "author_name": "Dara",
            "verification_tier": "remoteVillage",
            "remote_area": "Boeung Keng Kang",
        }
    )
    comment_out = CitizenCommentOut.model_validate(
        {
            "id": "c-1",
            "text": "Flooded drain",
            "createdAt": "2026-11-25T10:00:00Z",
            "isOriginalReporter": False,
            "isCurrentUser": True,
            "isAnonymous": False,
            "authorName": "Dara",
            "supportTier": "remoteDistrict",
            "supportAreaEnglish": "Toul Kork",
        }
    )
    assert comment_out.verification_tier is not None
    assert comment_out.verification_tier.value == "remoteDistrict"

    # 4. `AlertItem.toJson()` & `CivicReport.toJson()` parity (camelCase)
    alert = AlertItemOut.model_validate(
        {
            "id": "alert-1",
            "reportId": "#SC-20481",
            "khmerTitle": "ក្រុមការងារបានចេញដំណើរ",
            "englishTitle": "Crew Dispatched",
            "khmerSubtitle": "ក្រុម B-07",
            "englishSubtitle": "Crew B-07",
            "createdAt": "2026-11-25T10:00:00Z",
            "isRead": False,
        }
    )
    assert alert.report_id == "#SC-20481"

    report = ReportResponse.model_validate(
        {
            "id": "#SC-20481",
            "category": "pothole",
            "khmerTitle": "រន្ធផ្លូវ",
            "englishTitle": "Road pothole",
            "description": "Large pothole",
            "khmerLocation": "មហាវិថីនរោត្តម",
            "englishLocation": "Norodom Blvd",
            "lat": 11.5564,
            "lng": 104.9282,
            "provinceCode": "phnom_penh",
            "khmerProvince": "រាជធានីភ្នំពេញ",
            "englishProvince": "Phnom Penh",
            "roadClass": "majorArtery",
            "severity": 5,
            "affectedCitizens": 4,
            "status": "submitted",
            "khmerAgency": "ក្រសួងសាធារណការ និងដឹកជញ្ជូន (MPWT)",
            "englishAgency": "Ministry of Public Works & Transport (MPWT)",
            "isAnonymous": True,
            "exifStripped": True,
            "createdAt": "2026-11-25T10:00:00Z",
            "timeline": [
                {
                    "stage": "submitted",
                    "khmerTitle": "បានដាក់ស្នើ",
                    "englishTitle": "Submitted",
                    "complete": True,
                }
            ],
            "citizenComments": [],
        }
    )
    assert report.province_code == "phnom_penh"
    assert report.affected_citizens == 4


def test_postgis_geography_cast_cluster_priority_and_exact_teleport_boundary(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Verify PostGIS Geography cast, resolved cluster priority exclusion, and == 500m teleport."""
    clause = SpatialService.build_postgis_within_clause(
        lat=11.5564, lng=104.9282, radius_meters=150.0
    )
    compiled = str(clause.compile(dialect=postgresql.dialect()))
    assert "ST_DWithin" in compiled
    assert "geography(POINT,4326)" in compiled
    assert "CAST(reports.geom AS TEXT)" not in compiled

    def _make_report(
        rid: str, status: ReportStatusEnum, level_sev: int, lng: float
    ) -> ReportResponse:
        traffic = 5 if level_sev == 5 else 2
        count = 15 if level_sev == 5 else 2
        b = PriorityCalculator.calculate(
            traffic_score=traffic,
            severity_score=level_sev,
            report_count=count,
        )
        return ReportResponse.model_validate(
            {
                "id": rid,
                "category": "pothole",
                "khmerTitle": "T",
                "englishTitle": "T",
                "description": "T",
                "khmerLocation": "PP",
                "englishLocation": "PP",
                "lat": 11.5564,
                "lng": lng,
                "provinceCode": "phnom_penh",
                "khmerProvince": "រាជធានីភ្នំពេញ",
                "englishProvince": "Phnom Penh",
                "roadClass": "majorArtery" if level_sev == 5 else "residential",
                "severity": level_sev,
                "affectedCitizens": count,
                "status": status.value,
                "createdAt": "2026-11-25T10:00:00Z",
                "priority": {
                    "trafficScore": b.traffic_score,
                    "severityScore": b.severity_score,
                    "reportCountScore": b.report_count_score,
                    "rawScore": b.raw_score,
                    "level": b.level,
                    "khmerLevelName": b.khmer_level_name,
                    "englishLevelName": b.english_level_name,
                    "khmerSla": b.khmer_sla,
                    "englishSla": b.english_sla,
                    "slaHours": b.sla_hours,
                },
            }
        )

    resolved_p5 = _make_report("#SC-R5", ReportStatusEnum.RESOLVED, 5, 104.9282)
    open_p2 = _make_report("#SC-O2", ReportStatusEnum.SUBMITTED, 2, 104.9283)
    assert resolved_p5.priority is not None and resolved_p5.priority.level == 5
    assert open_p2.priority is not None and open_p2.priority.level == 2

    prov_view = SpatialService.cluster_reports_for_viewport(
        reports=[resolved_p5, open_p2],
        min_lat=11.0,
        min_lng=104.0,
        max_lat=12.0,
        max_lng=105.5,
        zoom=9.0,
        include_resolved=True,
    )
    assert prov_view.provinces[0].max_priority_level == 2

    area_view = SpatialService.cluster_reports_for_viewport(
        reports=[resolved_p5, open_p2],
        min_lat=11.0,
        min_lng=104.0,
        max_lat=12.0,
        max_lng=105.5,
        zoom=12.0,
        include_resolved=True,
    )
    assert area_view.areas[0].max_priority_level == 2

    all_resolved_view = SpatialService.cluster_reports_for_viewport(
        reports=[resolved_p5],
        min_lat=11.0,
        min_lng=104.0,
        max_lat=12.0,
        max_lng=105.5,
        zoom=9.0,
        include_resolved=True,
    )
    assert all_resolved_view.provinces[0].max_priority_level == 1
    assert all_resolved_view.provinces[0].all_resolved is True

    # Exact 500.0 m boundary check
    monkeypatch.setattr("app.core.integrity.haversine_meters", lambda *_args: 500.0)
    now = datetime.now(UTC)
    exact_500 = evaluate_gps_fix(
        lat=11.555,
        lng=104.92,
        accuracy_meters=10.0,
        timestamp=now,
        prev_lat=11.55,
        prev_lng=104.92,
        prev_timestamp=now - timedelta(seconds=2),
    )
    assert exact_500.risk_level.value == "blocked"
    assert exact_500.reasons[0].value == "gpsTeleport"
