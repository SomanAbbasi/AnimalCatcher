"""
models.py
=========
Shared Pydantic schemas for FAUNA BATTLER AI.

These models are the JSON contract between FastAPI and the Flutter client.
"""

from __future__ import annotations

from enum import Enum
from typing import Optional
from uuid import uuid4

from pydantic import BaseModel, Field


class Rarity(str, Enum):
    COMMON = "Common"
    UNCOMMON = "Uncommon"
    RARE = "Rare"
    LEGENDARY = "Legendary"


class Habitat(str, Enum):
    OCEAN = "Ocean"
    INSECT = "Insect"
    MAMMAL = "Mammal"
    AVIAN = "Avian"
    REPTILE = "Reptile"
    LAND = "Land"
    DESERT = "Desert"


class FaunaCardModel(BaseModel):
    """Unified minted creature card (vision + Wikipedia enrichment)."""

    card_id: str = Field(default_factory=lambda: str(uuid4()))
    user_id: Optional[str] = None
    name: str
    scientific_name: str = ""
    image_url: str = ""
    habitat: str = Habitat.MAMMAL.value
    rarity: Rarity
    hp: int = Field(..., ge=1, le=999, description="Max / current HP at mint time")
    attack: int = Field(..., ge=1, le=999)
    speed: int = Field(..., ge=1, le=999)
    defense: int = Field(..., ge=1, le=999)
    lore: str = ""
    creatureClass: str = "apex"

    @property
    def max_hp(self) -> int:
        return self.hp


class ScanRequest(BaseModel):
    user_id: str
    image_base64: str
    location_lat: Optional[float] = None
    location_lng: Optional[float] = None


class ScanResponse(BaseModel):
    card: FaunaCardModel
    saved: bool
    is_mystery: bool = False
    local_sandbox: bool = False


class InventoryResponse(BaseModel):
    user_id: str
    count: int
    cards: list[FaunaCardModel]
