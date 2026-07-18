"""
models.py
=========
Shared Pydantic schemas for FAUNA (pure collection game).

These models are the JSON contract between FastAPI and the Flutter client.
Combat stats were removed in the collect-and-catalog pivot; a card now carries
its identity (name/rarity), the shared species reference (photo/category/wiki),
and the player's personal capture metadata (photo path lives client-side).
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


class FaunaCardModel(BaseModel):
    """A collected species card (identity + shared reference + capture meta)."""

    card_id: str = Field(default_factory=lambda: str(uuid4()))
    user_id: Optional[str] = None
    name: str
    scientific_name: str = ""
    rarity: Rarity
    # Stable iNaturalist taxon id — the conflict-free key for dex matching.
    taxon_id: Optional[int] = None
    # Shared, consistent-for-everyone species reference (from iNaturalist cache).
    reference_photo_url: str = ""
    category: str = "Wildlife"
    wiki_url: str = ""
    lore: str = ""
    # Player-specific capture metadata.
    captured_at: Optional[str] = None
    capture_lat: Optional[float] = None
    capture_lng: Optional[float] = None


class SpeciesInfoResponse(BaseModel):
    """Shared reference data for a single species name."""

    name: str
    reference_photo_url: str = ""
    category: str = "Wildlife"
    wiki_url: str = ""
    # Stable iNaturalist taxon id — required so guest seed hydration can
    # unlock the matching dex tile (matching by name alone is unreliable).
    taxon_id: Optional[int] = None
    scientific_name: str = ""


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
    # XP awarded for this scan (+50 new species, +5 repeat) and the resulting
    # profile totals. Zero / current values when Supabase is not configured.
    xp_awarded: int = 0
    xp: int = 0
    level: int = 1
    # Stable taxon id of the scanned species (for client-side dex unlock).
    taxon_id: Optional[int] = None


class InventoryResponse(BaseModel):
    user_id: str
    count: int
    cards: list[FaunaCardModel]


class ProfileResponse(BaseModel):
    user_id: str
    username: str = ""
    xp: int = 0
    level: int = 1
    species_count: int = 0


# ---------------------------------------------------------------------------
# Friends
# ---------------------------------------------------------------------------
class FriendActionRequest(BaseModel):
    user_id: str
    friend_id: str


class UserSearchResult(BaseModel):
    user_id: str
    username: str
    level: int = 1


class FriendSummary(BaseModel):
    user_id: str
    username: str
    level: int = 1
    xp: int = 0
    species_count: int = 0


# ---------------------------------------------------------------------------
# Species catalog / dex
# ---------------------------------------------------------------------------
class CatalogEntry(BaseModel):
    """One species in the fixed master catalog (the dex)."""

    taxon_id: int
    dex_number: int
    name: str
    scientific_name: str = ""
    category: str = "Wildlife"
    rarity: Rarity = Rarity.COMMON
    reference_photo_url: str = ""


class CollectionProgress(BaseModel):
    """A player's dex completion, overall and per category.

    `by_category` maps a category name to {"caught": int, "total": int}.
    """

    total: int = 0
    caught: int = 0
    by_category: dict[str, dict[str, int]] = Field(default_factory=dict)
    caught_taxon_ids: list[int] = Field(default_factory=list)
