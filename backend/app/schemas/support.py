from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.core.integrity import (
    MIN_DETAILED_SUPPORT_NOTE_LENGTH,
    SpoofRiskLevel,
    SpoofSignalReason,
)
from app.schemas.comment import SupportReasonCategoryEnum, SupportVerificationTierEnum
from app.schemas.report import PriorityBreakdownSchema


class DeviceAttestationSchema(BaseModel):
    """Matches `DeviceIntegrityAttestation.toJson()` in `anti_spoof_service.dart`."""

    provider: Literal["play_integrity", "app_attest", "web_browser", "desktop_client"]
    token: str | None = None


class IntegrityPayloadSchema(BaseModel):
    """Matches `SpoofAssessment.toIntegrityJson()` in `anti_spoof_service.dart`."""

    risk_level: SpoofRiskLevel
    reasons: list[SpoofSignalReason] = Field(default_factory=list)
    photo_exif_verified: bool = False
    implied_speed_kmh: float | None = None
    exif_distance_meters: int | None = None
    ip_country_code: str | None = Field(default=None, min_length=2, max_length=2)
    attestation: DeviceAttestationSchema | None = None


class SupportCreateRequest(BaseModel):
    """`POST /api/v1/reports/{id}/support` matching `buildSupportApiPayload`."""

    model_config = ConfigDict(populate_by_name=True)

    report_id: str | None = None
    verification_tier: SupportVerificationTierEnum
    distance_meters: int | None = Field(default=None, ge=0)
    lat: float | None = Field(default=None, ge=-90.0, le=90.0)
    lng: float | None = Field(default=None, ge=-180.0, le=180.0)
    remote_area: str | None = None
    support_reason_category: SupportReasonCategoryEnum | None = None
    support_reason_note: str | None = None
    integrity: IntegrityPayloadSchema | None = None

    @model_validator(mode="after")
    def validate_remote_support_reason(self) -> SupportCreateRequest:
        requires_note = (
            self.verification_tier == SupportVerificationTierEnum.REMOTE_PROVINCE
            or self.support_reason_category == SupportReasonCategoryEnum.OTHER
        )
        if requires_note:
            note = (self.support_reason_note or "").strip()
            if len(note) < MIN_DETAILED_SUPPORT_NOTE_LENGTH:
                raise ValueError(
                    f"support_reason_note must be at least "
                    f"{MIN_DETAILED_SUPPORT_NOTE_LENGTH} characters for "
                    f"cross-province or 'other' support."
                )
        return self


class SupportActionResponse(BaseModel):
    """Response returned after adding or undoing 'Affects me' support."""

    report_id: str
    affected_citizens: int = Field(ge=1)
    priority: PriorityBreakdownSchema
    verification_tier: SupportVerificationTierEnum | None = None
    remote_area: str | None = None
    supports_used_24h: int = 0
    remote_province_supports_24h: int = 0
    joined_by_current_user: bool = True
