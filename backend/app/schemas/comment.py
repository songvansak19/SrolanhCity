from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.schemas.ai import IssueCategoryEnum


class SupportVerificationTierEnum(StrEnum):
    """Exact `.name` strings of `SupportVerificationTier` in `report_models.dart`."""

    VERIFIED_NEARBY = "verifiedNearby"
    REMOTE_VILLAGE = "remoteVillage"
    REMOTE_DISTRICT = "remoteDistrict"
    REMOTE_PROVINCE = "remoteProvince"


class SupportReasonCategoryEnum(StrEnum):
    """Exact `.name` strings of `SupportReasonCategory` in `report_models.dart`."""

    DAILY_COMMUTE = "dailyCommute"
    LIVE_OR_FAMILY_NEARBY = "liveOrFamilyNearby"
    SCHOOL_OR_MARKET_ROUTE = "schoolOrMarketRoute"
    BUSINESS_OR_DELIVERY = "businessOrDelivery"
    OTHER = "other"


class CommentCreateRequest(BaseModel):
    """`POST /api/v1/reports/{id}/comments` request (`buildCommentApiPayload`)."""

    model_config = ConfigDict(populate_by_name=True)

    report_id: str | None = None
    text: str
    is_anonymous: bool = Field(default=False, alias="isAnonymous")
    author_name: str | None = Field(default=None, alias="authorName")
    verification_tier: SupportVerificationTierEnum | None = Field(
        default=None, alias="supportTier"
    )
    remote_area: str | None = Field(default=None, alias="supportAreaEnglish")
    support_area_khmer: str | None = Field(default=None, alias="supportAreaKhmer")
    support_reason_category: SupportReasonCategoryEnum | None = Field(
        default=None, alias="supportReasonCategory"
    )
    severity: int | None = Field(default=None, ge=1, le=5)
    voice_transcript: str | None = Field(default=None, alias="voiceTranscript")

    @field_validator("text")
    @classmethod
    def validate_non_empty_text(cls, value: str) -> str:
        trimmed = value.strip()
        if not trimmed:
            raise ValueError("Comment text must not be empty.")
        return trimmed


class CitizenCommentOut(BaseModel):
    """Matches `CitizenComment.toJson()` plus silent verification metadata."""

    model_config = ConfigDict(populate_by_name=True, from_attributes=True)

    id: str
    text: str
    created_at: datetime = Field(alias="createdAt")
    is_original_reporter: bool = Field(default=False, alias="isOriginalReporter")
    is_current_user: bool = Field(default=False, alias="isCurrentUser")
    is_anonymous: bool = Field(default=True, alias="isAnonymous")
    author_name: str | None = Field(default=None, alias="authorName")
    severity: int | None = Field(default=None, ge=1, le=5)
    voice_transcript: str | None = Field(default=None, alias="voiceTranscript")
    verification_tier: SupportVerificationTierEnum | None = Field(
        default=None, alias="supportTier"
    )
    support_area_khmer: str | None = Field(default=None, alias="supportAreaKhmer")
    remote_area: str | None = Field(default=None, alias="supportAreaEnglish")
    support_reason_category: SupportReasonCategoryEnum | None = Field(
        default=None, alias="supportReasonCategory"
    )
    category: IssueCategoryEnum | None = None
