"""
services/supabase_service.py
============================
Persistence helpers for FAUNA BATTLER AI.

When SUPABASE_URL / SUPABASE_KEY are absent the service operates as a no-op
in Local-Sandbox Mode (save returns False, inventory returns []).

SQL migration (run in Supabase SQL editor):

```sql
-- FAUNA BATTLER AI schema
CREATE TABLE IF NOT EXISTS profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username VARCHAR(50) UNIQUE NOT NULL,
    player_rank INT DEFAULT 1 NOT NULL,
    gold INT DEFAULT 150 NOT NULL,
    wild_essence INT DEFAULT 30 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

CREATE TABLE IF NOT EXISTS user_cards (
    card_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(user_id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    scientific_name VARCHAR(150),
    image_url TEXT NOT NULL,
    habitat VARCHAR(50) NOT NULL,
    rarity VARCHAR(30) NOT NULL,
    max_hp INT NOT NULL,
    attack INT NOT NULL,
    speed INT NOT NULL,
    defense INT NOT NULL,
    lore TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_user_cards_user_id ON user_cards(user_id);
```
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import HTTPException

from config import get_settings
from models import FaunaCardModel, Rarity

logger = logging.getLogger(__name__)


class SupabaseService:
    """Thin wrapper around the Supabase Postgres client."""

    CARDS_TABLE = "user_cards"

    def __init__(self) -> None:
        self._settings = get_settings()
        self._client: Any = None

    def _get_client(self) -> Any:
        if not self._settings.supabase_configured:
            return None
        if self._client is None:
            try:
                from supabase import create_client

                self._client = create_client(
                    self._settings.supabase_url,
                    self._settings.supabase_key,
                )
            except Exception as exc:  # noqa: BLE001
                logger.error("Supabase client init failed: %s", exc)
                return None
        return self._client

    @staticmethod
    def _card_to_row(user_id: str, card: FaunaCardModel) -> dict[str, Any]:
        return {
            "user_id": user_id,
            "name": card.name,
            "scientific_name": card.scientific_name,
            "image_url": card.image_url or "https://upload.wikimedia.org/wikipedia/commons/thumb/6/65/No-Image-Placeholder.svg/640px-No-Image-Placeholder.svg.png",
            "habitat": card.habitat,
            "rarity": card.rarity.value if hasattr(card.rarity, "value") else str(card.rarity),
            "max_hp": card.hp,
            "attack": card.attack,
            "speed": card.speed,
            "defense": card.defense,
            "lore": card.lore,
        }

    @staticmethod
    def _row_to_card(row: dict[str, Any]) -> FaunaCardModel:
        rarity_raw = row.get("rarity", "Common")
        try:
            rarity = Rarity(str(rarity_raw))
        except ValueError:
            rarity = Rarity.COMMON
        return FaunaCardModel(
            card_id=str(row.get("card_id") or row.get("id") or ""),
            user_id=str(row.get("user_id") or "") or None,
            name=str(row["name"]),
            scientific_name=str(row.get("scientific_name") or ""),
            image_url=str(row.get("image_url") or ""),
            habitat=str(row.get("habitat") or "Mammal"),
            rarity=rarity,
            hp=int(row.get("max_hp") or row.get("hp") or 50),
            attack=int(row.get("attack") or 30),
            speed=int(row.get("speed") or 30),
            defense=int(row.get("defense") or 30),
            lore=str(row.get("lore") or ""),
        )

    def save_card(self, user_id: str, card: FaunaCardModel) -> bool:
        client = self._get_client()
        if client is None:
            return False
        row = self._card_to_row(user_id, card)
        try:
            result = client.table(self.CARDS_TABLE).insert(row).execute()
            return bool(result.data)
        except Exception as exc:  # noqa: BLE001
            logger.error("save_card failed: %s", exc)
            raise HTTPException(status_code=502, detail=f"Database error: {exc}") from exc

    def get_cards(self, user_id: str) -> list[FaunaCardModel]:
        client = self._get_client()
        if client is None:
            return []
        try:
            result = (
                client.table(self.CARDS_TABLE)
                .select("*")
                .eq("user_id", user_id)
                .order("created_at", desc=True)
                .execute()
            )
            rows = result.data or []
            return [self._row_to_card(r) for r in rows]
        except Exception as exc:  # noqa: BLE001
            logger.error("get_cards failed: %s", exc)
            raise HTTPException(status_code=502, detail=f"Database error: {exc}") from exc


supabase_service = SupabaseService()
