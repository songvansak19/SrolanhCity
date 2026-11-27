from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.ai import IssueCategoryEnum
from app.schemas.comment import CitizenCommentOut, SupportVerificationTierEnum


class ReportStatusEnum(StrEnum):
    """Exact `.name` strings of `ReportStatus` in `report_models.dart`."""

    SUBMITTED = "submitted"
    SCHEDULED = "scheduled"
    CREW_DISPATCHED = "crewDispatched"
    RESOLVED = "resolved"


class RoadClassEnum(StrEnum):
    """Exact `.name` strings of `RoadClass` in `report_models.dart`."""

    ALLEY = "alley"
    RESIDENTIAL = "residential"
    SECONDARY = "secondary"
    COMMERCIAL = "commercial"
    MAJOR_ARTERY = "majorArtery"


class SyncStatusEnum(StrEnum):
    """Exact `.name` strings of `SyncStatus` in `report_models.dart`."""

    SYNCED = "synced"
    PENDING_SYNC = "pendingSync"


class ReportSortEnum(StrEnum):
    """Exact `.name` strings of `ReportSortOption` in `report_models.dart`."""

    NEWEST = "newest"
    HIGHEST_PRIORITY = "highestPriority"
    MOST_AFFECTED = "mostAffected"


class LocationVerificationTierEnum(StrEnum):
    """Exact `.name` strings of `ReportLocationVerificationTier`."""

    PHOTO_EXIF_VERIFIED = "photoExifVerified"
    LIVE_CAMERA_VERIFIED = "liveCameraVerified"
    VERIFIED_ON_SITE = "verifiedOnSite"


class ClusterTierEnum(StrEnum):
    """Map viewport clustering zoom tiers (`MapClusterService`)."""

    PROVINCE = "province"
    AREA = "area"
    SINGLE = "single"


class PriorityBreakdownSchema(BaseModel):
    """Weighted priority breakdown matching `PriorityBreakdown` (`report_models.dart`)."""

    model_config = ConfigDict(populate_by_name=True, from_attributes=True)

    traffic_score: int = Field(ge=1, le=5, alias="trafficScore")
    severity_score: int = Field(ge=1, le=5, alias="severityScore")
    report_count_score: int = Field(ge=1, le=5, alias="reportCountScore")
    raw_score: float = Field(alias="rawScore")
    level: int = Field(ge=1, le=5)
    khmer_level_name: str = Field(alias="khmerLevelName")
    english_level_name: str = Field(alias="englishLevelName")
    khmer_sla: str = Field(alias="khmerSla")
    english_sla: str = Field(alias="englishSla")
    sla_hours: int = Field(default=168, alias="slaHours")


class TimelineEntrySchema(BaseModel):
    """Matches `TimelineEntry.toJson()` in `report_models.dart`."""

    model_config = ConfigDict(populate_by_name=True, from_attributes=True)

    stage: ReportStatusEnum
    khmer_title: str = Field(alias="khmerTitle")
    english_title: str = Field(alias="englishTitle")
    khmer_subtitle: str = Field(default="", alias="khmerSubtitle")
    english_subtitle: str = Field(default="", alias="englishSubtitle")
    complete: bool = False
    timestamp: datetime | None = None


class BeforeAfterProofSchema(BaseModel):
    """Before/after verification proof metadata (`report_models.dart`)."""

    model_config = ConfigDict(populate_by_name=True)

    before_photo_url: str | None = Field(default=None, alias="beforePhotoUrl")
    after_photo_url: str | None = Field(default=None, alias="afterPhotoUrl")
    before_date_label: str = Field(default="", alias="beforeDateLabel")
    after_date_label: str = Field(default="", alias="afterDateLabel")
    fixed_duration_khmer: str = Field(default="", alias="fixedDurationKhmer")
    fixed_duration_english: str = Field(default="", alias="fixedDurationEnglish")
    crew_code: str | None = Field(default=None, alias="crewCode")


class ReportCreateRequest(BaseModel):
    """Create / merge report payload accepting both snake_case and Flutter camelCase keys."""

    model_config = ConfigDict(populate_by_name=True)

    category: IssueCategoryEnum
    khmer_title: str = Field(default="", alias="khmerTitle")
    english_title: str = Field(default="", alias="englishTitle")
    description: str = ""
    khmer_location: str = Field(default="", alias="khmerLocation")
    english_location: str = Field(default="", alias="englishLocation")
    lat: float = Field(ge=-90.0, le=90.0)
    lng: float = Field(ge=-180.0, le=180.0)
    province_code: str | None = Field(default=None, alias="provinceCode")
    road_class: RoadClassEnum = Field(default=RoadClassEnum.SECONDARY, alias="roadClass")
    severity: int = Field(default=3, ge=1, le=5)
    is_anonymous: bool = Field(default=True, alias="isAnonymous")
    exif_stripped: bool = Field(default=True, alias="exifStripped")
    location_verification_tier: LocationVerificationTierEnum | None = Field(
        default=None, alias="locationVerificationTier"
    )
    voice_transcript: str | None = Field(default=None, alias="voiceTranscript")
    photo_base64: str | None = Field(default=None, alias="photoBase64")
    photo_verification_token: str | None = Field(
        default=None, alias="photoVerificationToken"
    )
    force_create_new: bool = Field(default=False, alias="forceCreateNew")


class ReportQuickEditRequest(BaseModel):
    """15-minute withdrawal/quick-edit payload (`CivicReport` while `submitted`)."""

    description: str = Field(min_length=1)
    severity: int = Field(ge=1, le=5)


class ReportRatingRequest(BaseModel):
    """Citizen 1–5 satisfaction rating on a resolved report."""

    rating: int = Field(ge=1, le=5)


class ReportResponse(BaseModel):
    """Full civic report matching `CivicReport.toJson()` (`report_models.dart`)."""

    model_config = ConfigDict(populate_by_name=True, from_attributes=True)

    id: str
    category: IssueCategoryEnum
    khmer_title: str = Field(alias="khmerTitle")
    english_title: str = Field(alias="englishTitle")
    description: str = ""
    khmer_location: str = Field(alias="khmerLocation")
    english_location: str = Field(alias="englishLocation")
    lat: float
    lng: float
    province_code: str = Field(default="phnom_penh", alias="provinceCode")
    khmer_province: str = Field(default="រាជធានីភ្នំពេញ", alias="khmerProvince")
    english_province: str = Field(default="Phnom Penh", alias="englishProvince")
    road_class: RoadClassEnum = Field(default=RoadClassEnum.SECONDARY, alias="roadClass")
    severity: int = Field(ge=1, le=5)
    affected_citizens: int = Field(default=1, ge=1, alias="affectedCitizens")
    status: ReportStatusEnum = ReportStatusEnum.SUBMITTED
    khmer_agency: str = Field(default="", alias="khmerAgency")
    english_agency: str = Field(default="", alias="englishAgency")
    photo_asset_path: str | None = Field(default=None, alias="photoAssetPath")
    local_photo_path: str | None = Field(default=None, alias="localPhotoPath")
    additional_local_photo_paths: list[str] = Field(
        default_factory=list, alias="additionalLocalPhotoPaths"
    )
    resolved_after_asset_path: str | None = Field(
        default=None, alias="resolvedAfterAssetPath"
    )
    is_anonymous: bool = Field(default=True, alias="isAnonymous")
    exif_stripped: bool = Field(default=True, alias="exifStripped")
    is_mine: bool = Field(default=False, alias="isMine")
    created_by_current_user: bool = Field(default=False, alias="createdByCurrentUser")
    joined_by_current_user: bool = Field(default=False, alias="joinedByCurrentUser")
    user_support_tier: SupportVerificationTierEnum | None = Field(
        default=None, alias="userSupportTier"
    )
    user_support_distance_meters: float | None = Field(
        default=None, alias="userSupportDistanceMeters"
    )
    user_support_area_khmer: str | None = Field(default=None, alias="userSupportAreaKhmer")
    user_support_area_english: str | None = Field(
        default=None, alias="userSupportAreaEnglish"
    )
    user_support_reason: str | None = Field(default=None, alias="userSupportReason")
    location_verification_tier: LocationVerificationTierEnum | None = Field(
        default=None, alias="locationVerificationTier"
    )
    sync_status: SyncStatusEnum = Field(default=SyncStatusEnum.SYNCED, alias="syncStatus")
    crew_code: str | None = Field(default=None, alias="crewCode")
    voice_transcript: str | None = Field(default=None, alias="voiceTranscript")
    citizen_rating: int | None = Field(default=None, ge=1, le=5, alias="citizenRating")
    before_date_label: str = Field(default="", alias="beforeDateLabel")
    after_date_label: str = Field(default="", alias="afterDateLabel")
    fixed_duration_khmer: str = Field(default="", alias="fixedDurationKhmer")
    fixed_duration_english: str = Field(default="", alias="fixedDurationEnglish")
    created_at: datetime = Field(alias="createdAt")
    priority: PriorityBreakdownSchema | None = None
    timeline: list[TimelineEntrySchema] = Field(default_factory=list)
    citizen_comments: list[CitizenCommentOut] = Field(
        default_factory=list, alias="citizenComments"
    )
    nearby_duplicate_ids: list[str] = Field(
        default_factory=list, alias="nearbyDuplicateIds"
    )


class MapViewportQuery(BaseModel):
    """Query parameters matching `ReportRepository.buildMapViewportQuery`."""

    min_lat: float = Field(ge=-90.0, le=90.0)
    min_lng: float = Field(ge=-180.0, le=180.0)
    max_lat: float = Field(ge=-90.0, le=90.0)
    max_lng: float = Field(ge=-180.0, le=180.0)
    zoom: float = Field(default=13.0, ge=1.0, le=22.0)
    province_code: str | None = None
    category: IssueCategoryEnum | None = None
    include_resolved: bool = True


class ProvinceClusterItemSchema(BaseModel):
    """Zoom < 10.2 province-level cluster item (`ProvinceClusterItem`)."""

    tier: ClusterTierEnum = ClusterTierEnum.PROVINCE
    province_code: str
    khmer_province: str
    english_province: str
    lat: float
    lng: float
    count: int
    max_priority_level: int = Field(ge=1, le=5)
    all_resolved: bool = False


class AreaClusterItemSchema(BaseModel):
    """10.2 <= Zoom < 13.4 adaptive grid cluster (`AreaClusterItem`)."""

    tier: ClusterTierEnum = ClusterTierEnum.AREA
    cluster_id: str
    lat: float
    lng: float
    count: int
    max_priority_level: int = Field(ge=1, le=5)
    dominant_category: IssueCategoryEnum
    all_resolved: bool = False


class SingleReportPinItemSchema(BaseModel):
    """Zoom >= 13.4 or singleton pin (`SingleReportPinItem`)."""

    tier: ClusterTierEnum = ClusterTierEnum.SINGLE
    report: ReportResponse


class MapViewportResponse(BaseModel):
    """Unified 3-tier viewport response for `GET /api/v1/reports`."""

    tier: ClusterTierEnum
    zoom: float
    total_matching: int = 0
    provinces: list[ProvinceClusterItemSchema] = Field(default_factory=list)
    areas: list[AreaClusterItemSchema] = Field(default_factory=list)
    pins: list[SingleReportPinItemSchema] = Field(default_factory=list)
