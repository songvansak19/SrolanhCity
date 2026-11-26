from __future__ import annotations

import base64
import binascii
import json
import math
import time
from collections import defaultdict, deque
from typing import Any

from google import genai
from google.genai import types
from pydantic import ValidationError

from app.config import Settings, get_settings
from app.schemas.ai import (
    ClassifyIssueRequest,
    ClassifyIssueResponse,
    HelpChatRequest,
    HelpChatResponse,
    IssueCategoryEnum,
    TranscribeVoiceRequest,
    TranscribeVoiceResponse,
    TranslateRequest,
    TranslateResponse,
)


class AiUnconfiguredError(RuntimeError):
    """Raised when `GEMINI_API_KEY` is not configured."""


class AiRateLimitError(RuntimeError):
    """Raised when a client exceeds the AI sliding-window rate limit."""


class AiInvalidInputError(ValueError):
    """Raised when base64 media input is malformed."""


class AiPayloadTooLargeError(ValueError):
    """Raised when decoded media exceeds maximum allowed payload size."""


class AiUpstreamResponseError(RuntimeError):
    """Raised when the upstream Gemini API returns invalid or non-dict JSON."""


class SlidingWindowRateLimiter:
    """In-memory sliding-window limiter (Redis-backed drop-in hook in production)."""

    def __init__(self, *, max_requests: int = 20, window_seconds: int = 60) -> None:
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    def check_and_record(self, client_key: str, *, now: float | None = None) -> None:
        ts = now if now is not None else time.monotonic()
        cutoff = ts - self.window_seconds
        stale_keys = [
            key
            for key, timestamps in self._hits.items()
            if key != client_key and (not timestamps or timestamps[-1] < cutoff)
        ]
        for key in stale_keys:
            del self._hits[key]

        bucket = self._hits[client_key]
        while bucket and bucket[0] < cutoff:
            bucket.popleft()
        if len(bucket) >= self.max_requests:
            if not bucket:
                del self._hits[client_key]
            raise AiRateLimitError(
                f"AI rate limit exceeded ({self.max_requests} requests / {self.window_seconds}s)."
            )
        bucket.append(ts)


class AiProxyService:
    """Server-side Gemini proxy (`google-genai`) with explicit unconfigured & rate-limit paths."""

    MAX_IMAGE_BYTES: int = 10 * 1024 * 1024  # 10 MiB
    MAX_AUDIO_BYTES: int = 20 * 1024 * 1024  # 20 MiB

    def __init__(
        self,
        settings: Settings | None = None,
        rate_limiter: SlidingWindowRateLimiter | None = None,
    ) -> None:
        self.settings = settings or get_settings()
        self.rate_limiter = rate_limiter or SlidingWindowRateLimiter()

    def _require_client(self) -> genai.Client:
        api_key = self.settings.gemini_api_key.strip()
        if not api_key:
            raise AiUnconfiguredError(
                "Gemini AI proxy is not configured on this server (missing GEMINI_API_KEY)."
            )
        return genai.Client(api_key=api_key)

    @staticmethod
    def _decode_base64_payload(
        encoded: str,
        *,
        max_bytes: int,
        label: str,
    ) -> bytes:
        # Quick upper bound before allocating decoded buffer (~4/3 expansion + padding)
        if len(encoded) > ((max_bytes + 2) // 3) * 4 + 8:
            raise AiPayloadTooLargeError(
                f"{label} payload exceeds maximum allowed size ({max_bytes} bytes)."
            )
        try:
            raw = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError) as exc:
            raise AiInvalidInputError(f"Invalid base64 {label} payload.") from exc
        if len(raw) > max_bytes:
            raise AiPayloadTooLargeError(
                f"{label} payload exceeds maximum allowed size ({max_bytes} bytes)."
            )
        return raw

    @staticmethod
    def _parse_json_dict(raw_text: str | None) -> dict[str, Any]:
        try:
            parsed = json.loads(raw_text or "{}")
        except json.JSONDecodeError as exc:
            raise AiUpstreamResponseError("Upstream AI provider returned malformed JSON.") from exc
        if not isinstance(parsed, dict):
            raise AiUpstreamResponseError("Upstream AI provider returned non-object JSON.")
        return parsed

    @staticmethod
    def _require_strict_bool(value: Any, *, field_name: str) -> bool:
        if not isinstance(value, bool):
            raise AiUpstreamResponseError(
                f"Upstream AI provider returned non-boolean field '{field_name}'."
            )
        return value

    @staticmethod
    def _require_strict_int(value: Any, *, field_name: str) -> int:
        if (
            isinstance(value, bool)
            or not isinstance(value, (int, float))
            or not math.isfinite(value)
        ):
            raise AiUpstreamResponseError(
                f"Upstream AI provider returned invalid numeric field '{field_name}'."
            )
        return int(value)

    @staticmethod
    def _require_optional_str(value: Any, *, field_name: str) -> str | None:
        if value is not None and not isinstance(value, str):
            raise AiUpstreamResponseError(
                f"Upstream AI provider returned non-string field '{field_name}'."
            )
        return value

    async def classify_issue(
        self,
        payload: ClassifyIssueRequest,
        *,
        client_key: str = "anonymous",
    ) -> ClassifyIssueResponse:
        self.rate_limiter.check_and_record(client_key)
        image_bytes = self._decode_base64_payload(
            payload.image_base64,
            max_bytes=self.MAX_IMAGE_BYTES,
            label="image",
        )
        client = self._require_client()
        prompt = (
            "You are SrolanhCity's Cambodia civic infrastructure classifier. "
            "Inspect the image and respond ONLY with JSON containing keys: "
            "is_civic_issue (bool), "
            "category ('pothole'|'streetlight'|'drain'|'trash'|'other'|null), "
            "confidence_percent (1..99), severity (2, 3, or 5), "
            "khmer_summary, english_summary, khmer_reason, english_reason. "
            f"Preferred language: {payload.language}. "
            f"User hint: {payload.description_hint or 'none'}."
        )
        response = await client.aio.models.generate_content(
            model=self.settings.gemini_model,
            contents=[
                types.Part.from_bytes(data=image_bytes, mime_type=payload.mime_type),
                prompt,
            ],
            config=types.GenerateContentConfig(response_mime_type="application/json"),
        )
        data = self._parse_json_dict(response.text)
        try:
            is_civic_issue = self._require_strict_bool(
                data.get("is_civic_issue", False), field_name="is_civic_issue"
            )
            raw_cat = self._require_optional_str(data.get("category"), field_name="category")
            valid_cats = {c.value for c in IssueCategoryEnum}
            category = IssueCategoryEnum(raw_cat) if raw_cat in valid_cats else None
            raw_sev = self._require_strict_int(
                data.get("severity", 3), field_name="severity"
            )
            normalized_sev = 2 if raw_sev <= 2 else (5 if raw_sev >= 4 else 3)
            confidence = max(
                1,
                min(
                    99,
                    self._require_strict_int(
                        data.get("confidence_percent", 85),
                        field_name="confidence_percent",
                    ),
                ),
            )
            return ClassifyIssueResponse(
                is_civic_issue=is_civic_issue,
                category=category,
                confidence_percent=confidence,
                severity=normalized_sev,
                khmer_summary=data.get("khmer_summary"),
                english_summary=data.get("english_summary"),
                khmer_reason=data.get("khmer_reason"),
                english_reason=data.get("english_reason"),
            )
        except (TypeError, ValueError, OverflowError, ValidationError) as exc:
            raise AiUpstreamResponseError(
                "Upstream AI provider returned invalid classification fields."
            ) from exc

    async def transcribe_voice(
        self,
        payload: TranscribeVoiceRequest,
        *,
        client_key: str = "anonymous",
    ) -> TranscribeVoiceResponse:
        self.rate_limiter.check_and_record(client_key)
        audio_bytes = self._decode_base64_payload(
            payload.audio_base64,
            max_bytes=self.MAX_AUDIO_BYTES,
            label="audio",
        )
        client = self._require_client()
        prompt = (
            "Transcribe this Khmer/English civic issue voice memo and return ONLY JSON "
            "with keys: transcript (string) and "
            "category ('pothole'|'streetlight'|'drain'|'trash'|'other'|null). "
            f"Expected language: {payload.language}."
        )
        response = await client.aio.models.generate_content(
            model=self.settings.gemini_model,
            contents=[
                types.Part.from_bytes(data=audio_bytes, mime_type=payload.mime_type),
                prompt,
            ],
            config=types.GenerateContentConfig(response_mime_type="application/json"),
        )
        data = self._parse_json_dict(response.text)
        try:
            raw_cat = self._require_optional_str(data.get("category"), field_name="category")
            valid_cats = {c.value for c in IssueCategoryEnum}
            category = IssueCategoryEnum(raw_cat) if raw_cat in valid_cats else None
            raw_transcript = self._require_optional_str(
                data.get("transcript"), field_name="transcript"
            )
            transcript = (raw_transcript or "").strip() or "(inaudible)"
            return TranscribeVoiceResponse(transcript=transcript, category=category)
        except (TypeError, ValueError, ValidationError) as exc:
            raise AiUpstreamResponseError(
                "Upstream AI provider returned invalid transcription fields."
            ) from exc

    async def help_chat(
        self,
        payload: HelpChatRequest,
        *,
        client_key: str = "anonymous",
    ) -> HelpChatResponse:
        self.rate_limiter.check_and_record(client_key)
        client = self._require_client()
        history_text = "\n".join(f"{t.role}: {t.text}" for t in payload.history[-8:])
        ctx = payload.citizen_context.model_dump() if payload.citizen_context else {}
        prompt = (
            "You are the SrolanhCity Civic Assistant for Cambodia (hotlines: MPWT 1190, "
            "EDC 1298, Emergency 117). Reply concisely in the requested language and "
            "return ONLY JSON with keys: reply (string), report_id (nullable string), "
            f"suggested_action (nullable string).\nLanguage: {payload.language}\n"
            f"Citizen context: {json.dumps(ctx)}\nHistory:\n{history_text}\nUser: {payload.message}"
        )
        response = await client.aio.models.generate_content(
            model=self.settings.gemini_model,
            contents=prompt,
            config=types.GenerateContentConfig(response_mime_type="application/json"),
        )
        data = self._parse_json_dict(response.text)
        try:
            raw_reply = self._require_optional_str(data.get("reply"), field_name="reply")
            reply = (raw_reply or "").strip() or "Please contact MPWT 1190 or EDC 1298."
            return HelpChatResponse(
                reply=reply,
                report_id=data.get("report_id"),
                suggested_action=data.get("suggested_action"),
            )
        except (TypeError, ValueError, ValidationError) as exc:
            raise AiUpstreamResponseError(
                "Upstream AI provider returned invalid help-chat fields."
            ) from exc

    async def translate_text(
        self,
        payload: TranslateRequest,
        *,
        client_key: str = "anonymous",
    ) -> TranslateResponse:
        self.rate_limiter.check_and_record(client_key)
        client = self._require_client()
        prompt = (
            f"Translate the following civic report comment into '{payload.target_lang}' "
            "(either Khmer 'km' or English 'en'). Respond ONLY with JSON containing "
            "translated_text (string) and source_lang ('km'|'en'|null).\n\n"
            f"Text: {payload.text}"
        )
        response = await client.aio.models.generate_content(
            model=self.settings.gemini_model,
            contents=prompt,
            config=types.GenerateContentConfig(response_mime_type="application/json"),
        )
        data = self._parse_json_dict(response.text)
        try:
            raw_translated = self._require_optional_str(
                data.get("translated_text"), field_name="translated_text"
            )
            raw_source_lang = self._require_optional_str(
                data.get("source_lang"), field_name="source_lang"
            )
            translated = (raw_translated or "").strip() or payload.text
            source_lang = raw_source_lang or payload.source_lang
            return TranslateResponse(
                translated_text=translated,
                target_lang=payload.target_lang,
                source_lang=source_lang if source_lang in {"en", "km"} else None,
                provider="gemini_proxy",
            )
        except (TypeError, ValueError, ValidationError) as exc:
            raise AiUpstreamResponseError(
                "Upstream AI provider returned invalid translation fields."
            ) from exc
