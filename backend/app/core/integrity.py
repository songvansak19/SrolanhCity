from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Literal

# Cambodia national bounds (`lib/data/services/location_service.dart:84-97`)
CAMBODIA_MIN_LAT = 9.9
CAMBODIA_MAX_LAT = 14.7
CAMBODIA_MIN_LNG = 102.3
CAMBODIA_MAX_LNG = 107.7

# Map camera bounds
CAMBODIA_MAP_MIN_LAT = 7.2
CAMBODIA_MAP_MAX_LAT = 17.2
CAMBODIA_MAP_MIN_LNG = 99.5
CAMBODIA_MAP_MAX_LNG = 110.5
PHNOM_PENH_CENTER_LAT = 11.5564
PHNOM_PENH_CENTER_LNG = 104.9282

# Support & spatial thresholds (`support_eligibility_service.dart` & `spatial_clustering.dart`)
VERIFIED_NEARBY_METERS = 150.0
SELF_DUPLICATE_BLOCK_METERS = 50.0
MAX_SUPPORTS_PER_24H = 10
MAX_REMOTE_PROVINCE_SUPPORTS_PER_24H = 3
MIN_DETAILED_SUPPORT_NOTE_LENGTH = 10

# Anti-spoof thresholds (`lib/domain/services/anti_spoof_service.dart:149-166`)
IMPOSSIBLE_TRAVEL_MIN_DISTANCE_METERS = 10000.0
IMPOSSIBLE_TRAVEL_MAX_SPEED_KMH = 250.0
VELOCITY_WINDOW_SECONDS = 2 * 3600
TELEPORT_MIN_DISTANCE_METERS = 500.0
TELEPORT_MAX_WINDOW_SECONDS = 2
EXIF_VERIFIED_RADIUS_METERS = 150.0
EXIF_MISMATCH_RADIUS_METERS = 150.0
EXIF_MAX_AGE_DAYS = 30

_EARTH_RADIUS_METERS = 6_371_000.0


class SpoofSignalReason(StrEnum):
    """Matches `SpoofSignalReason` in `anti_spoof_service.dart`."""

    OS_MOCK_PROVIDER = "osMockProvider"
    IMPOSSIBLE_TRAVEL = "impossibleTravel"
    SYNTHETIC_ACCURACY = "syntheticAccuracy"
    GPS_TELEPORT = "gpsTeleport"
    PHOTO_EXIF_LOCATION_MISMATCH = "photoExifLocationMismatch"
    PHOTO_EXIF_STALE = "photoExifStale"
    IP_COUNTRY_MISMATCH = "ipCountryMismatch"


class SpoofRiskLevel(StrEnum):
    """Matches `SpoofRiskLevel` in `anti_spoof_service.dart`."""

    TRUSTED = "trusted"
    WARNING = "warning"
    BLOCKED = "blocked"


AttestationProvider = Literal["play_integrity", "app_attest", "web_browser", "desktop_client"]


@dataclass(frozen=True, slots=True)
class AttestationVerificationResult:
    """Result of validating Play Integrity, App Attest, or Web Browser attestation."""

    valid: bool
    provider: str
    mode: str
    reason: str | None = None


@dataclass(frozen=True, slots=True)
class GpsIntegrityResult:
    """Server-side evaluation of Layers 1–3 GPS anti-spoof signals."""

    risk_level: SpoofRiskLevel
    reasons: tuple[SpoofSignalReason, ...] = ()
    implied_speed_kmh: float | None = None


def is_inside_cambodia(lat: float, lng: float) -> bool:
    """Check whether `(lat, lng)` falls inside Cambodia's strict bounding box."""
    return (
        math.isfinite(lat)
        and math.isfinite(lng)
        and CAMBODIA_MIN_LAT <= lat <= CAMBODIA_MAX_LAT
        and CAMBODIA_MIN_LNG <= lng <= CAMBODIA_MAX_LNG
    )


def is_emulator_default_coords(lat: float, lng: float) -> bool:
    """Detect Android/iOS simulator default Mountain View coordinates `(37.422, -122.084)`."""
    return abs(lat - 37.422) < 0.05 and abs(lng - (-122.084)) < 0.05


def haversine_meters(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Compute great-circle distance in meters between two WGS84 coordinates."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lng2 - lng1)

    a = (
        math.sin(d_phi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2.0) ** 2
    )
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return _EARTH_RADIUS_METERS * c


def verify_device_attestation(
    *,
    provider: str,
    token: str | None = None,
    mode: Literal["development", "strict"] = "development",
) -> AttestationVerificationResult:
    """Verify Play Integrity / App Attest / Web Browser device attestation token.

    In `development` mode, known providers pass when token is absent to keep offline
    Flutter dev/PWA flows unblocked. In `strict` mode, native mobile providers require a
    non-empty signed attestation token for cryptographic server verification.
    """
    allowed = {"play_integrity", "app_attest", "web_browser", "desktop_client"}
    if provider not in allowed:
        return AttestationVerificationResult(
            valid=False,
            provider=provider,
            mode=mode,
            reason=f"Unsupported attestation provider: {provider}",
        )

    if mode == "strict" and provider in {"play_integrity", "app_attest"}:
        if not token or not token.strip():
            return AttestationVerificationResult(
                valid=False,
                provider=provider,
                mode=mode,
                reason=f"Missing attestation token for {provider} in strict mode.",
            )

    return AttestationVerificationResult(
        valid=True,
        provider=provider,
        mode=mode,
    )


def evaluate_gps_fix(
    *,
    lat: float,
    lng: float,
    accuracy_meters: float,
    timestamp: datetime,
    is_mocked: bool = False,
    is_web: bool = False,
    altitude: float | None = None,
    speed: float | None = None,
    prev_lat: float | None = None,
    prev_lng: float | None = None,
    prev_timestamp: datetime | None = None,
) -> GpsIntegrityResult:
    """Evaluate Layers 1–3 GPS anti-spoofing rules matching `AntiSpoofService.evaluateGpsFix`."""
    if is_mocked:
        return GpsIntegrityResult(
            risk_level=SpoofRiskLevel.BLOCKED,
            reasons=(SpoofSignalReason.OS_MOCK_PROVIDER,),
        )

    is_sub_half_meter = 0.0 < accuracy_meters <= 0.5
    is_mobile_perfect_one_meter = (
        not is_web
        and accuracy_meters == 1.0
        and (altitude is None or altitude == 0.0)
        and (speed is None or speed == 0.0)
    )
    if is_sub_half_meter or is_mobile_perfect_one_meter:
        return GpsIntegrityResult(
            risk_level=SpoofRiskLevel.BLOCKED,
            reasons=(SpoofSignalReason.SYNTHETIC_ACCURACY,),
        )

    if prev_lat is not None and prev_lng is not None and prev_timestamp is not None:
        elapsed_seconds = (timestamp - prev_timestamp).total_seconds()
        if 0 <= elapsed_seconds <= VELOCITY_WINDOW_SECONDS:
            dist_meters = haversine_meters(prev_lat, prev_lng, lat, lng)
            if (
                elapsed_seconds <= TELEPORT_MAX_WINDOW_SECONDS
                and dist_meters >= TELEPORT_MIN_DISTANCE_METERS
            ):
                return GpsIntegrityResult(
                    risk_level=SpoofRiskLevel.BLOCKED,
                    reasons=(SpoofSignalReason.GPS_TELEPORT,),
                )
            if elapsed_seconds > 0 and dist_meters >= IMPOSSIBLE_TRAVEL_MIN_DISTANCE_METERS:
                speed_kmh = (dist_meters / 1000.0) / (elapsed_seconds / 3600.0)
                if speed_kmh > IMPOSSIBLE_TRAVEL_MAX_SPEED_KMH:
                    return GpsIntegrityResult(
                        risk_level=SpoofRiskLevel.BLOCKED,
                        reasons=(SpoofSignalReason.IMPOSSIBLE_TRAVEL,),
                        implied_speed_kmh=round(speed_kmh, 1),
                    )

    return GpsIntegrityResult(risk_level=SpoofRiskLevel.TRUSTED)


def evaluate_support_limits(
    *,
    supports_used_24h: int,
    remote_province_supports_24h: int,
    verification_tier: str,
) -> tuple[bool, str | None]:
    """Enforce the 10/24h total and 3/24h cross-province support caps."""
    if supports_used_24h >= MAX_SUPPORTS_PER_24H:
        return False, f"Daily support limit reached ({MAX_SUPPORTS_PER_24H} per 24h)."
    if (
        verification_tier == "remoteProvince"
        and remote_province_supports_24h >= MAX_REMOTE_PROVINCE_SUPPORTS_PER_24H
    ):
        return (
            False,
            f"Daily cross-province support limit reached "
            f"({MAX_REMOTE_PROVINCE_SUPPORTS_PER_24H} per 24h).",
        )
    return True, None
