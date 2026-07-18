"""
config.py
=========
Centralised configuration for the FAUNA BATTLER AI backend.

Secrets are loaded from environment variables (and optionally a local `.env`
file via python-dotenv). When credentials are missing the process still boots
into Local-Sandbox Mode so development and offline demos never crash.
"""

from __future__ import annotations

import os
from functools import lru_cache

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass


def _normalize_model(model: str) -> str:
    model = (model or "").strip()
    if not model:
        return "openai/gpt-4o"
    return model if "/" in model else f"openai/{model}"


class Settings:
    """Typed accessor for runtime configuration."""

    def __init__(self) -> None:
        self.supabase_url: str = os.getenv("SUPABASE_URL", "").strip()
        self.supabase_key: str = os.getenv("SUPABASE_KEY", "").strip()

        # OpenRouter first (OpenAI-compatible). OPENAI_* envs remain as aliases.
        self.openrouter_api_key: str = (
            os.getenv("OPENROUTER_API_KEY", "").strip()
            or os.getenv("OPENAI_API_KEY", "").strip()
        )
        self.openai_api_key: str = self.openrouter_api_key

        self.openrouter_base_url: str = os.getenv(
            "OPENROUTER_BASE_URL",
            os.getenv("OPENAI_BASE_URL", "https://openrouter.ai/api/v1"),
        ).strip()
        self.vision_model: str = _normalize_model(
            os.getenv(
                "OPENROUTER_VISION_MODEL",
                os.getenv("OPENAI_VISION_MODEL", "openai/gpt-4o"),
            )
        )

        self.app_env: str = os.getenv("APP_ENV", "development").strip().lower()
        raw_origins = os.getenv("ALLOWED_ORIGINS", "*").strip()
        self.allowed_origins: list[str] = (
            ["*"]
            if raw_origins == "*"
            else [o.strip() for o in raw_origins.split(",") if o.strip()]
        )
        # Explicit demo escape hatch: only when vision key is missing.
        # Default OFF so scans never invent random species.
        self.allow_offline_scan: bool = os.getenv(
            "ALLOW_OFFLINE_SCAN", ""
        ).strip().lower() in {"1", "true", "yes", "on"}

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    @property
    def supabase_configured(self) -> bool:
        return bool(self.supabase_url and self.supabase_key)

    @property
    def vision_configured(self) -> bool:
        return bool(self.openai_api_key)

    @property
    def local_sandbox_mode(self) -> bool:
        """True when vision and/or Supabase credentials are incomplete."""
        return not (self.vision_configured and self.supabase_configured)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
