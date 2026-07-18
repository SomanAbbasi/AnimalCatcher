"""
services/vision_service.py
==========================
Vision identification pipeline for FAUNA (pure collection game).

Fail-closed contract:
  - Never invent a collectible species on failure or low confidence.
  - Uncertain IDs become Mystery Spawn (is_mystery=True).
  - Provider / config failures raise HTTP 503 (retryable).
  - Anti-cheat non-living targets raise HTTP 400.
"""

from __future__ import annotations

import base64
import binascii
import json
import logging
import random
from typing import Any, Optional

from fastapi import HTTPException
from pydantic import BaseModel, Field, field_validator

from config import get_settings
from models import FaunaCardModel, Rarity
from services.species_info_service import species_info_service

try:
    from openai import OpenAI, OpenAIError
except ImportError:  # pragma: no cover
    OpenAI = None  # type: ignore[misc, assignment]
    OpenAIError = Exception  # type: ignore[misc, assignment]

logger = logging.getLogger(__name__)

# Minimum model confidence (0-1) required to mint a real species card.
_MIN_CONFIDENCE = 0.7

_SYSTEM_PROMPT = """
You are the species identification scanner for FAUNA, a real-world wildlife
collection app. Analyse ONE photograph carefully.

Anti-cheat (is_living_animal):
- Set is_living_animal=false if the image shows a phone/computer screen,
  a printed photo of an animal, a toy, plush, statue, drawing, cartoon,
  AI-generated fake animal, or no animal at all.
- Set is_living_animal=true only when a real animal body is visible in the
  photograph (live animal or a clear photo of a real animal in the scene).

Identification rules (NO HALLUCINATION):
- Identify the species ONLY when diagnostic traits are clearly visible
  (shape, size cues, coloration, distinctive markings, body plan).
- Prefer a precise scientific binomial in scientific_guess when known
  (e.g. "Ursus maritimus" for Polar Bear). Never invent a binomial.
- Use the standard English common name in "name" (e.g. "Polar Bear").
- If you are not sure, set confident=false, confidence below 0.7, and
  leave name and scientific_guess as empty strings. Do NOT guess.
- Never substitute a common pet (e.g. Domestic Cat / Dog) for wildlife
  that merely shares a loose silhouette.
- Never return a random popular animal to fill the fields.

Return ONLY raw JSON (no markdown, no commentary) with exactly these keys:
{
  "is_living_animal": boolean,
  "confident": boolean,
  "confidence": number,
  "name": string,
  "scientific_guess": string,
  "rarity": "Common"|"Uncommon"|"Rare"|"Legendary",
  "reason": string
}

confidence must be a number from 0.0 to 1.0 reflecting certainty.
reason is a short phrase of the traits you used (or why you are unsure).
""".strip()

_USER_PROMPT = (
    "Identify the animal in this photograph. If unsure, return confident=false "
    "with empty name/scientific_guess. Do not invent a species."
)

# Curated offline profiles — ONLY when ALLOW_OFFLINE_SCAN=1 and no vision key.
_OFFLINE_INDEX: list[dict[str, Any]] = [
    {
        "name": "Street Pigeon",
        "scientific_name": "Columba livia",
        "rarity": "Common",
        "category": "Bird",
        "reference_photo_url": (
            "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4d/"
            "Columba_livia_Rabat.jpg/500px-Columba_livia_Rabat.jpg"
        ),
        "wiki_url": "https://en.wikipedia.org/wiki/Rock_dove",
        "taxon_id": 3017,
    },
    {
        "name": "House Cat",
        "scientific_name": "Felis catus",
        "rarity": "Uncommon",
        "category": "Mammal",
        "reference_photo_url": (
            "https://upload.wikimedia.org/wikipedia/commons/thumb/1/15/"
            "Cat_August_2010-4.jpg/500px-Cat_August_2010-4.jpg"
        ),
        "wiki_url": "https://en.wikipedia.org/wiki/Cat",
        "taxon_id": 118552,
    },
]


class VisionResult(BaseModel):
    """Strict schema for the vision model JSON payload."""

    is_living_animal: bool = False
    confident: bool = False
    confidence: float = 0.0
    name: str = ""
    scientific_guess: str = ""
    rarity: str = "Common"
    reason: str = ""

    @field_validator("is_living_animal", "confident", mode="before")
    @classmethod
    def _coerce_bool(cls, value: Any) -> bool:
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)):
            return bool(value)
        if isinstance(value, str):
            return value.strip().lower() in {"1", "true", "yes", "y"}
        return False

    @field_validator("confidence", mode="before")
    @classmethod
    def _coerce_confidence(cls, value: Any) -> float:
        try:
            score = float(value)
        except (TypeError, ValueError):
            return 0.0
        return max(0.0, min(1.0, score))

    @field_validator("name", "scientific_guess", "rarity", "reason", mode="before")
    @classmethod
    def _coerce_str(cls, value: Any) -> str:
        if value is None:
            return ""
        return str(value).strip()


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
        # Recover embedded JSON if the model wraps with prose.
        if not text.startswith("{"):
            start = text.find("{")
            end = text.rfind("}")
            if start >= 0 and end > start:
                text = text[start : end + 1]
        return json.loads(text)

    @staticmethod
    def parse_vision_payload(raw: str) -> VisionResult:
        """Parse + validate model output. Raises ValueError on bad JSON/shape."""
        data = VisionService._extract_json(raw)
        if not isinstance(data, dict):
            raise ValueError("Vision payload is not a JSON object")
        return VisionResult.model_validate(data)

    @staticmethod
    def mystery_card(reason: str = "") -> FaunaCardModel:
        lore = (
            "The scanner could not identify this animal with enough confidence. "
            "Try a clearer photo of a real animal."
        )
        if reason:
            lore = f"{lore} ({reason})"
        return FaunaCardModel(
            name="Mystery Spawn",
            scientific_name="",
            rarity=Rarity.COMMON,
            reference_photo_url="",
            category="Wildlife",
            wiki_url="",
            taxon_id=None,
            lore=lore,
        )

    def _offline_card(self, preferred_name: str | None = None) -> FaunaCardModel:
        """Explicit demo-only path (ALLOW_OFFLINE_SCAN). Never used as fail-open."""
        matched = None
        if preferred_name:
            needle = preferred_name.lower().strip()
            for row in _OFFLINE_INDEX:
                if row["name"].lower() == needle:
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
            taxon_id=row.get("taxon_id"),
        )

    def _build_card(
        self, *, name: str, scientific_guess: str, rarity: Rarity
    ) -> Optional[FaunaCardModel]:
        """Enrich via taxonomy. Returns None if taxon cannot be resolved safely."""
        info = species_info_service.get_species_info(
            name, scientific_name=scientific_guess
        )
        taxon_id = info.get("taxon_id")
        if taxon_id is None:
            logger.info(
                "No taxon resolved for name=%r scientific=%r — refusing card",
                name,
                scientific_guess,
            )
            return None

        # Prefer verified iNaturalist labels over free-text model output.
        display_name = str(info.get("preferred_common_name") or name).strip() or name
        scientific_name = str(info.get("scientific_name") or scientific_guess).strip()
        category = str(info.get("category") or "Wildlife")
        wiki_url = str(info.get("wiki_url") or "")
        reference_photo = str(info.get("reference_photo_url") or "")
        # Never borrow another species' artwork when the photo is missing.

        catalog_rarity = species_info_service.catalog_rarity_for_taxon(int(taxon_id))
        final_rarity = catalog_rarity or rarity

        return FaunaCardModel(
            name=display_name,
            scientific_name=scientific_name,
            rarity=final_rarity,
            reference_photo_url=reference_photo,
            category=category,
            wiki_url=wiki_url,
            taxon_id=int(taxon_id),
        )

    def _request_vision(self, cleaned_b64: str) -> str:
        client = self._get_client()
        if client is None:
            raise RuntimeError("Vision client unavailable")
        response = client.chat.completions.create(
            model=self._settings.vision_model,
            temperature=0,
            max_tokens=500,
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
                                "detail": "high",
                            },
                        },
                    ],
                },
            ],
        )
        return response.choices[0].message.content or ""

    @staticmethod
    def _parse_rarity(raw: str) -> Rarity:
        text = (raw or "Common").strip()
        # Model may send "common" / "COMMON" / "Common".
        for candidate in (text, text.capitalize(), text.title()):
            try:
                return Rarity(candidate)
            except ValueError:
                continue
        return Rarity.COMMON

    def analyze_animal(self, image_base64: str) -> tuple[FaunaCardModel, bool]:
        """Return (card, is_mystery).

        Raises:
          HTTP 400 — anti-cheat (non-living target)
          HTTP 503 — scanner unavailable / provider failure
        """
        cleaned = self._validate_base64(image_base64)

        if not self._settings.vision_configured:
            if self._settings.allow_offline_scan:
                logger.info("ALLOW_OFFLINE_SCAN: returning curated offline card")
                return self._offline_card(), False
            raise HTTPException(
                status_code=503,
                detail=(
                    "Species scanner is unavailable (vision API key not configured). "
                    "Set OPENROUTER_API_KEY, or ALLOW_OFFLINE_SCAN=1 for demo mode."
                ),
            )

        try:
            raw = self._request_vision(cleaned)
            result = self.parse_vision_payload(raw)
        except (OpenAIError, json.JSONDecodeError, RuntimeError, ValueError) as exc:
            logger.warning("Vision failed (%s); refusing hallucinated fallback", exc)
            raise HTTPException(
                status_code=503,
                detail=(
                    "Species scanner temporarily unavailable. "
                    "Please retry in a moment."
                ),
            ) from exc

        if not result.is_living_animal:
            raise HTTPException(
                status_code=400,
                detail=(
                    "Anomaly Detected: Non-Living Target. Point your camera at a "
                    "real animal outdoors to capture it."
                ),
            )

        name = result.name.strip()
        scientific = result.scientific_guess.strip()
        high_confidence = (
            result.confident
            and result.confidence >= _MIN_CONFIDENCE
            and bool(name or scientific)
        )
        if not high_confidence:
            logger.info(
                "Low-confidence ID (confident=%s score=%.2f name=%r) -> Mystery",
                result.confident,
                result.confidence,
                name,
            )
            return self.mystery_card(result.reason), True

        rarity = self._parse_rarity(result.rarity)
        card = self._build_card(
            name=name or scientific,
            scientific_guess=scientific,
            rarity=rarity,
        )
        if card is None:
            return self.mystery_card("could not resolve species in taxonomy"), True
        return card, False


vision_service = VisionService()
