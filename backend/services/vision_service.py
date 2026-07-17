"""
services/vision_service.py
==========================
Vision identification pipeline for FAUNA (pure collection game).

Flow:
  1. Accept a base64 image payload from the mobile client.
  2. Anti-cheat gate via vision model (or sandbox mock).
  3. Identify the animal species (common name + rarity).
  4. Enrich with the shared species reference (photo/category/wiki) via
     species_info_service (iNaturalist + Supabase cache).
  5. Map into FaunaCardModel. Offline, serve the curated fallback index.
"""

from __future__ import annotations

import base64
import binascii
import json
import logging
import random
from typing import Any

from fastapi import HTTPException

from config import get_settings
from models import FaunaCardModel, Rarity
from services.species_info_service import species_info_service

# OpenRouter speaks the OpenAI Chat Completions API. The `openai` package is
# only the compatible client — traffic goes to openrouter.ai, not api.openai.com.
try:
    from openai import OpenAI, OpenAIError
except ImportError:  # pragma: no cover - missing venv deps
    OpenAI = None  # type: ignore[misc, assignment]
    OpenAIError = Exception  # type: ignore[misc, assignment]

logger = logging.getLogger(__name__)

_SYSTEM_PROMPT = """
You are the species scanner for a wildlife collection app. Analyse one photo.

Anti-cheat: set is_living_animal=false when the image shows a phone/computer
screen, printed photo, toy, cartoon, statue, or no animal at all.

If a living animal is physically present, identify its common English name.

Return ONLY raw JSON (no markdown) with exactly these keys:
{
  "is_living_animal": boolean,
  "confident": boolean,
  "name": string,
  "scientific_guess": string,
  "rarity": "Common"|"Uncommon"|"Rare"|"Legendary"
}
""".strip()

_USER_PROMPT = (
    "Analyse this photograph. Enforce anti-cheat: only real living animals count."
)

# ---------------------------------------------------------------------------
# Offline fallback index (curated wildlife with static reference art).
# Used only in Local-Sandbox Mode (no vision key) or on vision failure.
# ---------------------------------------------------------------------------
_OFFLINE_INDEX: list[dict[str, Any]] = [
    {
        "name": "Street Pigeon",
        "scientific_name": "Columba livia",
        "rarity": "Common",
        "category": "Bird",
        "reference_photo_url": "https://inaturalist-open-data.s3.amazonaws.com/photos/12345/medium.jpg",
        "wiki_url": "https://en.wikipedia.org/wiki/Rock_dove",
    },
    {
        "name": "House Cat",
        "scientific_name": "Felis catus",
        "rarity": "Uncommon",
        "category": "Mammal",
        "reference_photo_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/1/15/Cat_August_2010-4.jpg/500px-Cat_August_2010-4.jpg",
        "wiki_url": "https://en.wikipedia.org/wiki/Cat",
    },
    {
        "name": "Red Fox",
        "scientific_name": "Vulpes vulpes",
        "rarity": "Uncommon",
        "category": "Mammal",
        "reference_photo_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/d/d2/Portrait_of_a_red_fox_in_Rautas_fj%C3%A4llurskog_%28cropped%29.jpg/500px-Portrait_of_a_red_fox_in_Rautas_fj%C3%A4llurskog_%28cropped%29.jpg",
        "wiki_url": "https://en.wikipedia.org/wiki/Red_fox",
    },
    {
        "name": "Raccoon Bandit",
        "scientific_name": "Procyon lotor",
        "rarity": "Uncommon",
        "category": "Mammal",
        "reference_photo_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3e/Raccoon_in_Central_Park_%2835264%29.jpg/500px-Raccoon_in_Central_Park_%2835264%29.jpg",
        "wiki_url": "https://en.wikipedia.org/wiki/Raccoon",
    },
    {
        "name": "Golden Eagle",
        "scientific_name": "Aquila chrysaetos",
        "rarity": "Rare",
        "category": "Bird",
        "reference_photo_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/c/cc/015_Wild_Golden_Eagle_in_flight_at_Pfyn-Finges_%28Switzerland%29_Photo_by_Giles_Laurent.jpg/500px-015_Wild_Golden_Eagle_in_flight_at_Pfyn-Finges_%28Switzerland%29_Photo_by_Giles_Laurent.jpg",
        "wiki_url": "https://en.wikipedia.org/wiki/Golden_eagle",
    },
    {
        "name": "Snow Leopard",
        "scientific_name": "Panthera uncia",
        "rarity": "Legendary",
        "category": "Mammal",
        "reference_photo_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a5/Irbis4.JPG/500px-Irbis4.JPG",
        "wiki_url": "https://en.wikipedia.org/wiki/Snow_leopard",
    },
]

_OFFLINE_BY_NAME: dict[str, dict[str, Any]] = {
    row["name"].lower(): row for row in _OFFLINE_INDEX
}


class VisionService:
    """Vision identification + shared species reference bridge."""

    def __init__(self) -> None:
        self._settings = get_settings()
        self._client: Any = None

    def _get_client(self) -> Any:
        if not self._settings.vision_configured or OpenAI is None:
            if self._settings.vision_configured and OpenAI is None:
                logger.warning(
                    "OPENROUTER_API_KEY is set but the `openai` package is missing. "
                    "Activate .venv and run: pip install -r requirements.txt"
                )
            return None
        if self._client is None:
            self._client = OpenAI(
                api_key=self._settings.openrouter_api_key,
                base_url=self._settings.openrouter_base_url,
                default_headers={
                    "HTTP-Referer": "https://fauna-dex.local",
                    "X-Title": "Fauna Dex",
                },
            )
        return self._client

    @staticmethod
    def _validate_base64(image_base64: str) -> str:
        cleaned = image_base64.strip()
        if cleaned.startswith("data:") and "," in cleaned:
            cleaned = cleaned.split(",", 1)[1]
        try:
            base64.b64decode(cleaned, validate=True)
        except (binascii.Error, ValueError) as exc:
            raise HTTPException(
                status_code=422, detail="Invalid base64 image payload."
            ) from exc
        return cleaned

    @staticmethod
    def _extract_json(raw: str) -> dict[str, Any]:
        text = (raw or "").strip()
        if text.startswith("```"):
            text = text.strip("`")
            if text.lower().startswith("json"):
                text = text[4:]
            text = text.strip()
        return json.loads(text)

    def _offline_card(self, preferred_name: str | None = None) -> FaunaCardModel:
        matched = None
        if preferred_name:
            needle = preferred_name.lower().strip()
            matched = _OFFLINE_BY_NAME.get(needle)
            if matched is None:
                for key, row in _OFFLINE_BY_NAME.items():
                    if needle in key or key in needle:
                        matched = row
                        break
        row = matched or random.choice(_OFFLINE_INDEX)
        return FaunaCardModel(
            name=str(row["name"]),
            scientific_name=str(row["scientific_name"]),
            rarity=Rarity(str(row["rarity"])),
            reference_photo_url=str(row["reference_photo_url"]),
            category=str(row["category"]),
            wiki_url=str(row["wiki_url"]),
        )

    def _build_card(
        self, *, name: str, scientific_guess: str, rarity: Rarity
    ) -> FaunaCardModel:
        info = species_info_service.get_species_info(name)
        reference_photo = info.get("reference_photo_url") or ""
        category = info.get("category") or "Wildlife"
        wiki_url = info.get("wiki_url") or ""
        taxon_id = info.get("taxon_id")
        # Prefer iNaturalist's verified scientific name over the LLM's guess.
        scientific_name = info.get("scientific_name") or scientific_guess

        # If the shared reference has no photo, borrow a curated offline asset.
        if not reference_photo:
            offline = self._offline_card(name)
            reference_photo = offline.reference_photo_url
            if category == "Wildlife":
                category = offline.category
            if not wiki_url:
                wiki_url = offline.wiki_url

        return FaunaCardModel(
            name=name,
            scientific_name=scientific_name,
            rarity=rarity,
            reference_photo_url=reference_photo,
            category=category,
            wiki_url=wiki_url,
            taxon_id=taxon_id,
        )

    def _request_vision(self, cleaned_b64: str) -> str:
        client = self._get_client()
        if client is None:
            raise RuntimeError("Vision client unavailable")
        response = client.chat.completions.create(
            model=self._settings.vision_model,
            temperature=0.4,
            max_tokens=300,
            messages=[
                {"role": "system", "content": _SYSTEM_PROMPT},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": _USER_PROMPT},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{cleaned_b64}",
                                "detail": "low",
                            },
                        },
                    ],
                },
            ],
        )
        return response.choices[0].message.content or ""

    def analyze_animal(self, image_base64: str) -> tuple[FaunaCardModel, bool]:
        """Return (card, is_mystery). Raises HTTP 400 on anti-cheat failure."""
        cleaned = self._validate_base64(image_base64)

        # Local-Sandbox Mode: no vision key — serve curated wildlife profiles.
        if not self._settings.vision_configured:
            logger.info("Local-Sandbox Mode: returning offline wildlife profile")
            return self._offline_card(), False

        try:
            raw = self._request_vision(cleaned)
            data = self._extract_json(raw)
        except (OpenAIError, json.JSONDecodeError, RuntimeError) as exc:
            logger.warning("Vision failed (%s); using offline index", exc)
            return self._offline_card(), True

        if not data.get("is_living_animal", False):
            raise HTTPException(
                status_code=400,
                detail=(
                    "Anomaly Detected: Non-Living Target. Point your camera at a "
                    "real animal outdoors to capture it."
                ),
            )

        name = str(data.get("name", "")).strip()
        if not data.get("confident", True) or not name:
            return self._offline_card(), True

        try:
            rarity = Rarity(str(data.get("rarity", "Common")).strip().capitalize())
        except ValueError:
            rarity = Rarity.COMMON

        card = self._build_card(
            name=name,
            scientific_guess=str(data.get("scientific_guess", "")).strip(),
            rarity=rarity,
        )
        return card, False


vision_service = VisionService()
