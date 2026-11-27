from __future__ import annotations

from enum import StrEnum
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class IssueCategoryEnum(StrEnum):
    """Exact `.name` strings of `IssueCategory` in `report_models.dart`."""

    POTHOLE = "pothole"
    STREETLIGHT = "streetlight"
    DRAIN = "drain"
    TRASH = "trash"
    OTHER = "other"


LanguageCode = Literal["en", "km"]


class ClassifyIssueRequest(BaseModel):
    """`POST /api/v1/ai/classify-issue` request (`BackendCivicAiService.buildPhotoRequestBody`)."""

    image_base64: str = Field(min_length=1)
    mime_type: str = "image/jpeg"
    language: LanguageCode = "km"
    description_hint: str | None = None

    @field_validator("mime_type")
    @classmethod
    def validate_image_mime(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in {"image/jpeg", "image/jpg", "image/png", "image/webp"}:
            raise ValueError(f"Unsupported image mime_type: {value}")
        return normalized


class ClassifyIssueResponse(BaseModel):
    """`POST /api/v1/ai/classify-issue` response (`parsePhotoResponseJson`)."""

    is_civic_issue: bool
    category: IssueCategoryEnum | None = None
    confidence_percent: int = Field(default=85, ge=1, le=99)
    severity: int = Field(default=3, ge=1, le=5)
    khmer_summary: str | None = None
    english_summary: str | None = None
    khmer_reason: str | None = None
    english_reason: str | None = None
    photo_verification_token: str | None = None


class TranscribeVoiceRequest(BaseModel):
    """`POST /api/v1/ai/transcribe-voice` request (`buildAudioRequestBody`)."""

    audio_base64: str = Field(min_length=1)
    mime_type: str = "audio/aac"
    language: LanguageCode = "km"

    @field_validator("mime_type")
    @classmethod
    def validate_audio_mime(cls, value: str) -> str:
        normalized = value.strip().lower()
        allowed = {
            "audio/wav",
            "audio/mp3",
            "audio/mpeg",
            "audio/aac",
            "audio/webm",
            "audio/m4a",
            "audio/ogg",
        }
        if normalized not in allowed:
            raise ValueError(f"Unsupported audio mime_type: {value}")
        return normalized


class TranscribeVoiceResponse(BaseModel):
    """`POST /api/v1/ai/transcribe-voice` response (`parseAudioResponseJson`)."""

    transcript: str = Field(min_length=1)
    category: IssueCategoryEnum | None = None


class HelpChatTurn(BaseModel):
    """Single conversation turn in `HelpChatRequest.history`."""

    role: Literal["user", "assistant"]
    text: str = Field(min_length=1)


class CitizenContext(BaseModel):
    """Optional summary sent by `HelpAssistantService` (`help_assistant_service.dart`)."""

    my_report_count: int = 0
    pending_sync_count: int = 0
    recent_ticket_ids: list[str] = Field(default_factory=list)


class HelpChatRequest(BaseModel):
    """`POST /api/v1/ai/help-chat` request (`buildHelpChatRequestBody`)."""

    message: str = Field(min_length=1)
    language: LanguageCode = "km"
    history: list[HelpChatTurn] = Field(default_factory=list, max_length=8)
    citizen_context: CitizenContext | None = None


class HelpChatResponse(BaseModel):
    """`POST /api/v1/ai/help-chat` response (`parseHelpChatResponseJson`)."""

    reply: str = Field(min_length=1)
    report_id: str | None = None
    suggested_action: str | None = None


class TranslateRequest(BaseModel):
    """`POST /api/v1/ai/translate` request (`CommentTranslationService.translate`)."""

    model_config = ConfigDict(populate_by_name=True)

    text: str = Field(min_length=1)
    target_lang: LanguageCode = Field(alias="targetLang")
    source_lang: LanguageCode | None = Field(default=None, alias="sourceLang")


class TranslateResponse(BaseModel):
    """`POST /api/v1/ai/translate` response."""

    translated_text: str
    target_lang: LanguageCode
    source_lang: LanguageCode | None = None
    provider: str = "gemini_proxy"
