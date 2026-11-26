"""Core domain helpers: auth/RBAC, anti-spoof integrity, EXIF stripping, and priority scoring."""

from app.core.auth import (
    TokenClaims,
    UserRole,
    create_access_token,
    decode_access_token,
    get_current_user,
    get_current_user_optional,
    require_roles,
)
from app.core.exif import has_exif_or_metadata_markers, strip_jpeg_metadata
from app.core.integrity import (
    CAMBODIA_MAX_LAT,
    CAMBODIA_MAX_LNG,
    CAMBODIA_MIN_LAT,
    CAMBODIA_MIN_LNG,
    MAX_REMOTE_PROVINCE_SUPPORTS_PER_24H,
    MAX_SUPPORTS_PER_24H,
    MIN_DETAILED_SUPPORT_NOTE_LENGTH,
    SELF_DUPLICATE_BLOCK_METERS,
    VERIFIED_NEARBY_METERS,
    haversine_meters,
    is_inside_cambodia,
    verify_device_attestation,
)
from app.core.priority import (
    TIER_TABLE,
    PriorityBreakdown,
    PriorityCalculator,
    PriorityTierRule,
    RoadClass,
)

__all__ = [
    "CAMBODIA_MAX_LAT",
    "CAMBODIA_MAX_LNG",
    "CAMBODIA_MIN_LAT",
    "CAMBODIA_MIN_LNG",
    "MAX_REMOTE_PROVINCE_SUPPORTS_PER_24H",
    "MAX_SUPPORTS_PER_24H",
    "MIN_DETAILED_SUPPORT_NOTE_LENGTH",
    "PriorityBreakdown",
    "PriorityCalculator",
    "PriorityTierRule",
    "RoadClass",
    "SELF_DUPLICATE_BLOCK_METERS",
    "TIER_TABLE",
    "TokenClaims",
    "UserRole",
    "VERIFIED_NEARBY_METERS",
    "create_access_token",
    "decode_access_token",
    "get_current_user",
    "get_current_user_optional",
    "has_exif_or_metadata_markers",
    "haversine_meters",
    "is_inside_cambodia",
    "require_roles",
    "strip_jpeg_metadata",
    "verify_device_attestation",
]
