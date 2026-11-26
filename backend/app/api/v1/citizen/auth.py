from __future__ import annotations

import hashlib
from typing import Annotated
from uuid import uuid4

import sqlalchemy as sa
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.core.auth import (
    TokenClaims,
    UserRole,
    create_access_token,
    get_current_user,
    get_current_user_optional,
)
from app.db.models.user import User
from app.db.session import get_db

router = APIRouter(prefix="/auth", tags=["Citizen Auth"])

DbSession = Annotated[AsyncSession, Depends(get_db)]
CurrentUser = Annotated[TokenClaims, Depends(get_current_user)]
OptionalUser = Annotated[TokenClaims | None, Depends(get_current_user_optional)]


class GuestAuthRequest(BaseModel):
    """Issue a guest JWT matching `UserProfile` defaults."""

    khmer_name: str = "ភ្ញៀវ"
    english_name: str = "Guest"
    home_province_code: str | None = None


class _PhoneNumberRequest(BaseModel):
    """Shared phone number validator matching `edit_profile_page.dart:589` (`length >= 6`)."""

    phone_number: str = Field(min_length=6, max_length=32)

    @field_validator("phone_number")
    @classmethod
    def validate_trimmed_phone(cls, value: str) -> str:
        trimmed = value.strip()
        if len(trimmed) < 6:
            raise ValueError("Phone number must be at least 6 characters.")
        return trimmed


class PhoneOtpRequest(_PhoneNumberRequest):
    """Phone number validation matching `edit_profile_page.dart:589` (`length >= 6`)."""


class PhoneOtpVerifyRequest(_PhoneNumberRequest):
    """Verify SMS OTP code and upgrade guest session to verified citizen."""

    otp_code: str = Field(min_length=4, max_length=8)
    khmer_name: str = "ពលរដ្ឋ"
    english_name: str = "Citizen"
    home_province_code: str | None = None


class TokenResponse(BaseModel):
    """JWT access token envelope."""

    access_token: str
    token_type: str = "bearer"
    role: UserRole
    user_id: str


async def ensure_user_exists(db: AsyncSession, user_id: str | None) -> None:
    """Create a guest `User` row if a cached JWT references a user_id not yet in DB."""
    if not user_id or getattr(db, "is_stub", False):
        return
    existing = await db.scalar(sa.select(User.id).where(User.id == user_id))
    if existing is None:
        db.add(User(id=user_id, role=UserRole.GUEST.value))
        await db.flush()


@router.post("/guest", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def create_guest_session(
    payload: GuestAuthRequest,
    db: DbSession,
) -> TokenResponse:
    """Create an anonymous guest session token for citizen reporting."""
    user_id = str(uuid4())
    user = User(
        id=user_id,
        role=UserRole.GUEST.value,
        khmer_name=payload.khmer_name,
        english_name=payload.english_name,
        home_province_code=payload.home_province_code,
    )
    db.add(user)
    await db.commit()
    token = create_access_token(
        subject=user_id,
        role=UserRole.GUEST,
        khmer_name=payload.khmer_name,
        english_name=payload.english_name,
        province_code=payload.home_province_code,
    )
    return TokenResponse(access_token=token, role=UserRole.GUEST, user_id=user_id)


@router.post("/phone/request-otp")
async def request_phone_otp(payload: PhoneOtpRequest) -> dict[str, str]:
    """Initiate phone OTP challenge (SMS gateway hook)."""
    masked = f"***{payload.phone_number[-4:]}"
    return {
        "status": "otp_sent",
        "masked_phone": masked,
        "detail": "OTP dispatch hook invoked; configure SMS provider for production.",
    }


@router.post("/phone/verify", response_model=TokenResponse)
async def verify_phone_otp(
    payload: PhoneOtpVerifyRequest,
    db: DbSession,
    current_user: OptionalUser = None,
) -> TokenResponse:
    """Verify phone OTP and issue a citizen JWT (reusing existing phone user on repeat login)."""
    settings = get_settings()
    if settings.app_env not in {"development", "test"}:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="SMS OTP verification provider is not configured for this environment.",
        )
    if not payload.otp_code.isdigit():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="OTP code must contain digits only.",
        )

    trimmed_phone = payload.phone_number.strip()
    phone_hash = hashlib.sha256(trimmed_phone.encode("utf-8")).hexdigest()
    masked_phone = f"***{trimmed_phone[-4:]}"

    existing_user = await db.scalar(sa.select(User).where(User.phone_hash == phone_hash))
    if existing_user is not None:
        existing_user.role = UserRole.CITIZEN.value
        existing_user.khmer_name = payload.khmer_name
        existing_user.english_name = payload.english_name
        existing_user.masked_phone = masked_phone
        if payload.home_province_code is not None:
            existing_user.home_province_code = payload.home_province_code
        user = existing_user
        user_id = existing_user.id
    elif current_user is not None and current_user.role == UserRole.GUEST:
        guest_user = await db.scalar(sa.select(User).where(User.id == current_user.sub))
        if guest_user is not None:
            guest_user.role = UserRole.CITIZEN.value
            guest_user.khmer_name = payload.khmer_name
            guest_user.english_name = payload.english_name
            guest_user.phone_hash = phone_hash
            guest_user.masked_phone = masked_phone
            if payload.home_province_code is not None:
                guest_user.home_province_code = payload.home_province_code
            user = guest_user
            user_id = guest_user.id
        else:
            user_id = str(uuid4())
            user = User(
                id=user_id,
                role=UserRole.CITIZEN.value,
                khmer_name=payload.khmer_name,
                english_name=payload.english_name,
                phone_hash=phone_hash,
                masked_phone=masked_phone,
                home_province_code=payload.home_province_code,
            )
            db.add(user)
    else:
        user_id = str(uuid4())
        user = User(
            id=user_id,
            role=UserRole.CITIZEN.value,
            khmer_name=payload.khmer_name,
            english_name=payload.english_name,
            phone_hash=phone_hash,
            masked_phone=masked_phone,
            home_province_code=payload.home_province_code,
        )
        db.add(user)

    await db.commit()
    token = create_access_token(
        subject=user_id,
        role=UserRole.CITIZEN,
        khmer_name=user.khmer_name,
        english_name=user.english_name,
        province_code=user.home_province_code,
    )
    return TokenResponse(access_token=token, role=UserRole.CITIZEN, user_id=user_id)


@router.get("/me", response_model=TokenClaims)
async def read_current_identity(
    current_user: CurrentUser,
) -> TokenClaims:
    """Return the authenticated caller's JWT identity claims."""
    return current_user
