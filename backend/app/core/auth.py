from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

from app.config import get_settings

_bearer_scheme = HTTPBearer(auto_error=False)


class UserRole(StrEnum):
    """Citizen and Ministry/Authority RBAC roles."""

    GUEST = "guest"
    CITIZEN = "citizen"
    AGENCY_STAFF = "agency_staff"
    MINISTRY_ADMIN = "ministry_admin"


class TokenClaims(BaseModel):
    """JWT claims payload for authenticated guest, citizen, or authority users."""

    sub: str
    role: UserRole = UserRole.GUEST
    khmer_name: str = "ភ្ញៀវ"
    english_name: str = "Guest"
    province_code: str | None = None
    agency_code: str | None = None
    iat: int | None = None
    exp: int | None = None


def create_access_token(
    *,
    subject: str,
    role: UserRole = UserRole.GUEST,
    khmer_name: str = "ភ្ញៀវ",
    english_name: str = "Guest",
    province_code: str | None = None,
    agency_code: str | None = None,
    expires_delta: timedelta | None = None,
) -> str:
    """Create a signed HS256 JWT token via PyJWT."""
    settings = get_settings()
    now = datetime.now(UTC)
    expire = now + (
        expires_delta or timedelta(minutes=settings.jwt_access_token_expire_minutes)
    )
    payload = {
        "sub": subject,
        "role": role.value,
        "khmer_name": khmer_name,
        "english_name": english_name,
        "province_code": province_code,
        "agency_code": agency_code,
        "iat": int(now.timestamp()),
        "exp": int(expire.timestamp()),
    }
    return jwt.encode(
        payload,
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )


def decode_access_token(token: str) -> TokenClaims:
    """Verify and decode a JWT access token."""
    settings = get_settings()
    try:
        decoded = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
        )
        return TokenClaims.model_validate(decoded)
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


async def get_current_user_optional(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer_scheme)],
) -> TokenClaims | None:
    """Return decoded `TokenClaims` when Bearer token is present, else `None`."""
    if credentials is None or not credentials.credentials:
        return None
    return decode_access_token(credentials.credentials)


async def get_current_user(
    claims: Annotated[TokenClaims | None, Depends(get_current_user_optional)],
) -> TokenClaims:
    """Require a valid Bearer token (guest, citizen, or authority)."""
    if claims is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication credentials required.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return claims


def require_roles(*allowed_roles: UserRole) -> Callable[..., TokenClaims]:
    """Build a FastAPI dependency enforcing one of `allowed_roles`."""

    async def _role_guard(
        claims: Annotated[TokenClaims, Depends(get_current_user)],
    ) -> TokenClaims:
        if claims.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient role permissions for this operation.",
            )
        return claims

    return _role_guard
