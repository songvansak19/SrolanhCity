from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.schemas.ai import (
    ClassifyIssueRequest,
    ClassifyIssueResponse,
    HelpChatRequest,
    HelpChatResponse,
    TranscribeVoiceRequest,
    TranscribeVoiceResponse,
    TranslateRequest,
    TranslateResponse,
)
from app.services.ai_proxy import (
    AiInvalidInputError,
    AiPayloadTooLargeError,
    AiProxyService,
    AiRateLimitError,
    AiUnconfiguredError,
    AiUpstreamResponseError,
)

router = APIRouter(prefix="/ai", tags=["AI Proxy"])

_default_ai_proxy = AiProxyService()


def get_ai_proxy_service() -> AiProxyService:
    """Dependency returning the server-side Gemini proxy service."""
    return _default_ai_proxy


AiServiceDep = Annotated[AiProxyService, Depends(get_ai_proxy_service)]


def _client_key(request: Request) -> str:
    return request.client.host if request.client else "anonymous"


@router.post("/classify-issue", response_model=ClassifyIssueResponse)
async def classify_issue(
    payload: ClassifyIssueRequest,
    request: Request,
    service: AiServiceDep,
) -> ClassifyIssueResponse:
    """Classify a civic issue photo via the server-side Gemini AI proxy."""
    try:
        return await service.classify_issue(payload, client_key=_client_key(request))
    except AiInvalidInputError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except AiPayloadTooLargeError as exc:
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE, detail=str(exc)
        ) from exc
    except AiRateLimitError as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(exc),
        ) from exc
    except AiUnconfiguredError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    except AiUpstreamResponseError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


@router.post("/transcribe-voice", response_model=TranscribeVoiceResponse)
async def transcribe_voice(
    payload: TranscribeVoiceRequest,
    request: Request,
    service: AiServiceDep,
) -> TranscribeVoiceResponse:
    """Transcribe a Khmer/English citizen voice memo ephemerally via Gemini AI."""
    try:
        return await service.transcribe_voice(payload, client_key=_client_key(request))
    except AiInvalidInputError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    except AiPayloadTooLargeError as exc:
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE, detail=str(exc)
        ) from exc
    except AiRateLimitError as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(exc),
        ) from exc
    except AiUnconfiguredError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    except AiUpstreamResponseError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


@router.post("/help-chat", response_model=HelpChatResponse)
async def help_chat(
    payload: HelpChatRequest,
    request: Request,
    service: AiServiceDep,
) -> HelpChatResponse:
    """Answer citizen questions with Cambodia hotline & ticket-aware context."""
    try:
        return await service.help_chat(payload, client_key=_client_key(request))
    except AiRateLimitError as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(exc),
        ) from exc
    except AiUnconfiguredError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    except AiUpstreamResponseError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc


@router.post("/translate", response_model=TranslateResponse)
async def translate_comment(
    payload: TranslateRequest,
    request: Request,
    service: AiServiceDep,
) -> TranslateResponse:
    """Translate citizen comments between Khmer (`km`) and English (`en`)."""
    try:
        return await service.translate_text(payload, client_key=_client_key(request))
    except AiRateLimitError as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(exc),
        ) from exc
    except AiUnconfiguredError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    except AiUpstreamResponseError as exc:
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
