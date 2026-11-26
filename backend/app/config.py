from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables or `.env`."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "SrolanhCity API"
    app_env: Literal["development", "staging", "production", "test"] = "development"
    debug: bool = True
    api_v1_prefix: str = "/api/v1"

    @field_validator("debug", mode="before")
    @classmethod
    def coerce_debug_bool(cls, value: object) -> object:
        if isinstance(value, str):
            lowered = value.strip().lower()
            if lowered in {"release", "prod", "production", "0", "false", "no", "off"}:
                return False
            if lowered in {"debug", "dev", "development", "1", "true", "yes", "on"}:
                return True
        return value

    # PostgreSQL 16 / PostGIS 3.4
    database_url: str = (
        "postgresql+asyncpg://srolanhcity:srolanhcity@localhost:5432/srolanhcity"
    )

    # Redis 7
    redis_url: str = "redis://localhost:6379/0"

    # MinIO / Cloudflare R2 (S3-compatible)
    s3_endpoint_url: str = "http://localhost:9000"
    s3_access_key: str = "minioadmin"
    s3_secret_key: str = "minioadmin"
    s3_bucket_name: str = "srolanhcity-media"
    s3_region: str = "auto"

    # Gemini AI Proxy (kept server-side only)
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.5-flash"

    # Auth (PyJWT)
    jwt_secret_key: str = "change-me-in-production-use-32-plus-chars"
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 1440

    # CORS — includes live GitHub Pages PWA origin + local dev servers
    cors_origins: list[str] = Field(
        default_factory=lambda: [
            "https://songvansak19.github.io",
            "http://localhost:3000",
            "http://localhost:8080",
            "http://127.0.0.1:8080",
        ]
    )
    cors_origin_regex: str = r"^https?://(localhost|127\.0\.0\.1|10\.0\.2\.2)(:\d+)?$"

    # Anti-spoof & offline safety
    integrity_mode: Literal["development", "strict"] = "development"
    offline_stub_db: bool = False


@lru_cache
def get_settings() -> Settings:
    """Return cached application settings."""
    return Settings()
