"""
services/vision_service.py
==========================
Vision + Wikipedia enrichment pipeline for FAUNA BATTLER AI.

Flow:
  1. Accept a base64 image payload from the mobile client.
  2. Anti-cheat gate via vision model (or sandbox mock).
  3. Identify the animal species.
  4. Enrich with English Wikipedia REST summary (thumbnail + extract).
  5. Map into FaunaCardModel. Offline, serve the curated fallback index.
"""

from __future__ import annotations

import base64
import binascii
import json
import logging
import random
import re
from typing import Any
from urllib.parse import quote

import httpx
from fastapi import HTTPException

from config import get_settings
from models import FaunaCardModel, Rarity

# OpenRouter speaks the OpenAI Chat Completions API. The `openai` package is
# only the compatible client — traffic goes to openrouter.ai, not api.openai.com.
try:
    from openai import OpenAI, OpenAIError
except ImportError:  # pragma: no cover - missing venv deps
    OpenAI = None  # type: ignore[misc, assignment]
    OpenAIError = Exception  # type: ignore[misc, assignment]

logger = logging.getLogger(__name__)

_SYSTEM_PROMPT = """
You are the Rift Scanner for FAUNA BATTLER AI. Analyse one photograph.

Anti-cheat: set is_living_animal=false when the image shows a phone/computer
screen, printed photo, toy, cartoon, statue, or no animal at all.

If a living animal is physically present, identify its common English name and
estimate combat stats.

Return ONLY raw JSON (no markdown) with exactly these keys:
{
  "is_living_animal": boolean,
  "confident": boolean,
  "name": string,
  "scientific_guess": string,
  "habitat_guess": "Ocean"|"Insect"|"Mammal"|"Avian"|"Reptile"|"Land"|"Desert",
  "rarity": "Common"|"Uncommon"|"Rare"|"Legendary",
  "hp": integer,
  "attack": integer,
  "speed": integer,
  "defense": integer
}
""".strip()

_USER_PROMPT = (
    "Analyse this photograph. Enforce anti-cheat: only real living animals count."
)

_WIKI_HEADERS = {
    "User-Agent": "FaunaBattlerAI/1.0 (educational game; contact@local.dev)",
    "Accept": "application/json",
}

# ---------------------------------------------------------------------------
# Offline fallback index (15 curated wildlife profiles with Wikipedia CDN art)
# ---------------------------------------------------------------------------
_OFFLINE_INDEX: list[dict[str, Any]] = [
    {
        "name": "Street Pigeon",
        "scientific_name": "Columba livia",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/1/10/Columba_livia_%28Rock_Dove%2C_wild%29%2C_Duncansby_Head%2C_Caithness%2C_Scotland_1.jpg/500px-Columba_livia_%28Rock_Dove%2C_wild%29%2C_Duncansby_Head%2C_Caithness%2C_Scotland_1.jpg",
        "habitat": "Avian",
        "rarity": "Common",
        "hp": 45,
        "attack": 18,
        "speed": 55,
        "defense": 12,
        "lore": "Fearless urban survivor, filthy and faster than you would think.",
    },
    {
        "name": "Garden Ant Swarm",
        "scientific_name": "Formicidae",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/af/Fire_ants.jpg/500px-Fire_ants.jpg",
        "habitat": "Insect",
        "rarity": "Common",
        "hp": 40,
        "attack": 22,
        "speed": 30,
        "defense": 15,
        "lore": "One ant is nothing. A thousand is a problem.",
    },
    {
        "name": "House Cat",
        "scientific_name": "Felis catus",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/1/15/Cat_August_2010-4.jpg/500px-Cat_August_2010-4.jpg",
        "habitat": "Mammal",
        "rarity": "Uncommon",
        "hp": 60,
        "attack": 35,
        "speed": 60,
        "defense": 20,
        "lore": "Domesticated in name only.",
    },
    {
        "name": "Urban Crow",
        "scientific_name": "Corvus brachyrhynchos",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/9/91/Corvus_corax_clarionensis%2C_Point_Reyes_National_Seashore.jpg/500px-Corvus_corax_clarionensis%2C_Point_Reyes_National_Seashore.jpg",
        "habitat": "Avian",
        "rarity": "Uncommon",
        "hp": 65,
        "attack": 30,
        "speed": 58,
        "defense": 18,
        "lore": "Remembers every face that has wronged it.",
    },
    {
        "name": "Clownfish",
        "scientific_name": "Amphiprioninae",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/ad/Amphiprion_ocellaris_%28Clown_anemonefish%29_by_Nick_Hobgood.jpg/500px-Amphiprion_ocellaris_%28Clown_anemonefish%29_by_Nick_Hobgood.jpg",
        "habitat": "Ocean",
        "rarity": "Uncommon",
        "hp": 90,
        "attack": 38,
        "speed": 62,
        "defense": 45,
        "lore": "Brightly colored marine fish known for symbiotic mutualisms with sea anemones.",
    },
    {
        "name": "Timber Wolf",
        "scientific_name": "Canis lupus",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/6/68/Eurasian_wolf_2.jpg/500px-Eurasian_wolf_2.jpg",
        "habitat": "Mammal",
        "rarity": "Rare",
        "hp": 120,
        "attack": 62,
        "speed": 55,
        "defense": 48,
        "lore": "A highly social predator that coordinates hunts across vast territories.",
    },
    {
        "name": "Hornet",
        "scientific_name": "Vespa crabro",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b1/VespaCrabroCollezione.jpg/500px-VespaCrabroCollezione.jpg",
        "habitat": "Insect",
        "rarity": "Uncommon",
        "hp": 55,
        "attack": 48,
        "speed": 70,
        "defense": 22,
        "lore": "A large social wasp capable of delivering a powerful defensive sting.",
    },
    {
        "name": "Emperor Penguin",
        "scientific_name": "Aptenodytes forsteri",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a3/Aptenodytes_forsteri_-Snow_Hill_Island%2C_Antarctica_-adults_and_juvenile-8.jpg/500px-Aptenodytes_forsteri_-Snow_Hill_Island%2C_Antarctica_-adults_and_juvenile-8.jpg",
        "habitat": "Avian",
        "rarity": "Legendary",
        "hp": 140,
        "attack": 40,
        "speed": 35,
        "defense": 65,
        "lore": "The tallest and heaviest living penguin species, enduring Antarctic winters.",
    },
    {
        "name": "Red Fox",
        "scientific_name": "Vulpes vulpes",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/d/d2/Portrait_of_a_red_fox_in_Rautas_fj%C3%A4llurskog_%28cropped%29.jpg/500px-Portrait_of_a_red_fox_in_Rautas_fj%C3%A4llurskog_%28cropped%29.jpg",
        "habitat": "Mammal",
        "rarity": "Uncommon",
        "hp": 95,
        "attack": 58,
        "speed": 70,
        "defense": 30,
        "lore": "An adaptable omnivore famous for cunning hunting strategies.",
    },
    {
        "name": "Golden Eagle",
        "scientific_name": "Aquila chrysaetos",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/c/cc/015_Wild_Golden_Eagle_in_flight_at_Pfyn-Finges_%28Switzerland%29_Photo_by_Giles_Laurent.jpg/500px-015_Wild_Golden_Eagle_in_flight_at_Pfyn-Finges_%28Switzerland%29_Photo_by_Giles_Laurent.jpg",
        "habitat": "Avian",
        "rarity": "Rare",
        "hp": 100,
        "attack": 68,
        "speed": 78,
        "defense": 32,
        "lore": "A powerful raptor that strikes from angles prey rarely check.",
    },
    {
        "name": "Green Sea Turtle",
        "scientific_name": "Chelonia mydas",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a3/Green_sea_turtle_%28Chelonia_mydas%29_Moorea.jpg/500px-Green_sea_turtle_%28Chelonia_mydas%29_Moorea.jpg",
        "habitat": "Ocean",
        "rarity": "Rare",
        "hp": 150,
        "attack": 28,
        "speed": 40,
        "defense": 80,
        "lore": "A long-lived marine reptile that grazes seagrass meadows worldwide.",
    },
    {
        "name": "Snow Leopard",
        "scientific_name": "Panthera uncia",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/a/a5/Irbis4.JPG/500px-Irbis4.JPG",
        "habitat": "Mammal",
        "rarity": "Legendary",
        "hp": 150,
        "attack": 70,
        "speed": 68,
        "defense": 38,
        "lore": "An elusive high-altitude predator, a ghost until the moment it is not.",
    },
    {
        "name": "Koala",
        "scientific_name": "Phascolarctos cinereus",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/4/49/Koala_climbing_tree.jpg/500px-Koala_climbing_tree.jpg",
        "habitat": "Mammal",
        "rarity": "Rare",
        "hp": 85,
        "attack": 28,
        "speed": 22,
        "defense": 55,
        "lore": "An arboreal marsupial that lives almost entirely on eucalyptus leaves.",
    },
    {
        "name": "Kangaroo",
        "scientific_name": "Macropus rufus",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/d/df/Forester_kangaroo_%28Macropus_giganteus_tasmaniensis%29_juvenile_hopping_Esk_Valley.jpg/500px-Forester_kangaroo_%28Macropus_giganteus_tasmaniensis%29_juvenile_hopping_Esk_Valley.jpg",
        "habitat": "Mammal",
        "rarity": "Uncommon",
        "hp": 110,
        "attack": 52,
        "speed": 72,
        "defense": 40,
        "lore": "Powerful hoppers that dominate open Australian grasslands.",
    },
    {
        "name": "Raccoon Bandit",
        "scientific_name": "Procyon lotor",
        "image_url": "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3e/Raccoon_in_Central_Park_%2835264%29.jpg/500px-Raccoon_in_Central_Park_%2835264%29.jpg",
        "habitat": "Mammal",
        "rarity": "Uncommon",
        "hp": 70,
        "attack": 38,
        "speed": 45,
        "defense": 25,
        "lore": "Small hands, big plans — a midnight opportunist.",
    },
]

_OFFLINE_BY_NAME: dict[str, dict[str, Any]] = {
    row["name"].lower(): row for row in _OFFLINE_INDEX
}


class VisionService:
    """Vision identification + Wikipedia metadata bridge."""

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
                    "HTTP-Referer": "https://fauna-battler.local",
                    "X-Title": "Fauna Battler AI",
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

    @staticmethod
    def _infer_habitat(text: str, fallback: str = "Mammal") -> str:
        blob = (text or "").lower()
        rules = [
            (
                "Ocean",
                (
                    "marine",
                    "fish",
                    "sea",
                    "ocean",
                    "aquatic",
                    "whale",
                    "shark",
                    "coral",
                    "anemone",
                    "dolphin",
                    "turtle",
                    "reef",
                ),
            ),
            (
                "Insect",
                (
                    "insect",
                    "bug",
                    "spider",
                    "arachnid",
                    "fly",
                    "beetle",
                    "ant",
                    "bee",
                    "wasp",
                    "hornet",
                    "butterfly",
                    "moth",
                ),
            ),
            (
                "Avian",
                (
                    "bird",
                    "avian",
                    "wing",
                    "flight",
                    "eagle",
                    "owl",
                    "pigeon",
                    "crow",
                    "penguin",
                    "falcon",
                    "hawk",
                    "feather",
                ),
            ),
            (
                "Reptile",
                (
                    "reptile",
                    "snake",
                    "lizard",
                    "crocodile",
                    "gecko",
                    "serpent",
                    "monitor",
                    "iguana",
                ),
            ),
            (
                "Mammal",
                (
                    "mammal",
                    "feline",
                    "canine",
                    "wolf",
                    "fox",
                    "cat",
                    "bear",
                    "deer",
                    "lion",
                    "tiger",
                    "leopard",
                    "kangaroo",
                    "koala",
                    "raccoon",
                    "dog",
                ),
            ),
        ]
        for habitat, keys in rules:
            if any(k in blob for k in keys):
                return habitat
        return fallback if fallback else "Mammal"

    @staticmethod
    def _habitat_to_class(habitat: str) -> str:
        mapping = {
            "Insect": "swarm",
            "Avian": "scavenger",
            "Ocean": "scavenger",
            "Mammal": "apex",
            "Land": "apex",
            "Desert": "apex",
            "Reptile": "apex",
        }
        return mapping.get(habitat, "apex")

    @staticmethod
    def _normalize_wiki_thumb(url: str) -> str:
        """Wikimedia thumbs are only valid at certain widths (e.g. 330, 500, 1280)."""
        if not url or "/thumb/" not in url:
            return url
        return re.sub(r"/\d+px-", "/500px-", url)

    def _fetch_wikipedia(self, animal_name: str) -> dict[str, Any]:
        """Query English Wikipedia REST summary for photo + lore."""
        title = quote(animal_name.replace(" ", "_"), safe="")
        url = f"https://en.wikipedia.org/api/rest_v1/page/summary/{title}"
        try:
            with httpx.Client(timeout=8.0, headers=_WIKI_HEADERS) as client:
                response = client.get(url)
                if response.status_code != 200:
                    return {}
                data = response.json()
        except Exception as exc:  # noqa: BLE001
            logger.warning("Wikipedia lookup failed for %s: %s", animal_name, exc)
            return {}

        # Prefer a 500px thumbnail for mobile cards; originals can be multi-MB.
        original = (data.get("originalimage") or {}).get("source") or ""
        thumbnail = self._normalize_wiki_thumb(
            (data.get("thumbnail") or {}).get("source") or ""
        )
        image_url = thumbnail or original
        extract = (data.get("extract") or "").strip()
        description = (data.get("description") or "").strip()
        display = (data.get("displaytitle") or animal_name).strip()
        display = re.sub(r"<[^>]+>", "", display)

        return {
            "name": display or animal_name,
            "scientific_name": description.split(",")[0][:150] if description else "",
            "image_url": image_url,
            "lore": extract[:480] if extract else "",
            "habitat": self._infer_habitat(
                f"{extract} {description} {animal_name} {display}"
            ),
        }

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
        habitat = str(row["habitat"])
        return FaunaCardModel(
            name=str(row["name"]),
            scientific_name=str(row["scientific_name"]),
            image_url=str(row["image_url"]),
            habitat=habitat,
            rarity=Rarity(str(row["rarity"])),
            hp=int(row["hp"]),
            attack=int(row["attack"]),
            speed=int(row["speed"]),
            defense=int(row["defense"]),
            lore=str(row["lore"]),
            creatureClass=self._habitat_to_class(habitat),
        )

    def _enrich_with_wikipedia(
        self,
        *,
        name: str,
        scientific_guess: str,
        habitat_guess: str,
        rarity: Rarity,
        hp: int,
        attack: int,
        speed: int,
        defense: int,
    ) -> FaunaCardModel:
        wiki = self._fetch_wikipedia(name)
        habitat = wiki.get("habitat") or habitat_guess or "Mammal"
        lore = wiki.get("lore") or f"A wild {name} encountered in the field."
        image_url = wiki.get("image_url") or ""
        scientific = wiki.get("scientific_name") or scientific_guess or ""

        # If Wikipedia misses the thumbnail, pull a matching offline asset.
        if not image_url:
            offline = self._offline_card(name)
            image_url = offline.image_url
            if not scientific:
                scientific = offline.scientific_name
            if len(lore) < 40:
                lore = offline.lore

        return FaunaCardModel(
            name=wiki.get("name") or name,
            scientific_name=scientific,
            image_url=image_url,
            habitat=habitat,
            rarity=rarity,
            hp=hp,
            attack=attack,
            speed=speed,
            defense=defense,
            lore=lore,
            creatureClass=self._habitat_to_class(str(habitat)),
        )

    def _request_vision(self, cleaned_b64: str) -> str:
        client = self._get_client()
        if client is None:
            raise RuntimeError("Vision client unavailable")
        response = client.chat.completions.create(
            model=self._settings.vision_model,
            temperature=0.4,
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

        card = self._enrich_with_wikipedia(
            name=name,
            scientific_guess=str(data.get("scientific_guess", "")).strip(),
            habitat_guess=str(data.get("habitat_guess", "Mammal")).strip() or "Mammal",
            rarity=rarity,
            hp=int(data.get("hp", 80)),
            attack=int(data.get("attack", 40)),
            speed=int(data.get("speed", 40)),
            defense=int(data.get("defense", 40)),
        )
        return card, False


vision_service = VisionService()
