"""
services/supabase_service.py
============================
Persistence helpers for FAUNA.

When SUPABASE_URL / SUPABASE_KEY are absent the service operates as a no-op
in Local-Sandbox Mode (saves return False, reads return []/None).

See backend/schema.sql for the full migration (user_cards + species_reference).
"""

from __future__ import annotations

import logging
import math
from typing import Any, Optional

from fastapi import HTTPException

from config import get_settings
from models import FaunaCardModel, Rarity

logger = logging.getLogger(__name__)


def compute_level(xp: int) -> int:
    """Shared level curve: level = floor(sqrt(xp / 100)) + 1."""
    if xp <= 0:
        return 1
    return int(math.floor(math.sqrt(xp / 100))) + 1


def normalize_name(name: str) -> str:
    """Case/whitespace-insensitive key used as a fallback when no taxon id."""
    return " ".join((name or "").strip().lower().split())


_PLACEHOLDER_PHOTO = (
    "https://upload.wikimedia.org/wikipedia/commons/thumb/6/65/"
    "No-Image-Placeholder.svg/640px-No-Image-Placeholder.svg.png"
)


class SupabaseService:
    """Thin wrapper around the Supabase Postgres client."""

    CARDS_TABLE = "user_cards"
    SPECIES_TABLE = "species_reference"
    PROFILES_TABLE = "profiles"
    FRIENDS_TABLE = "friendships"
    CATALOG_TABLE = "species_catalog"

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

    # ------------------------------------------------------------------
    # Player cards
    # ------------------------------------------------------------------
    @staticmethod
    def _card_to_row(user_id: str, card: FaunaCardModel) -> dict[str, Any]:
        return {
            "user_id": user_id,
            "name": card.name,
            "scientific_name": card.scientific_name,
            "taxon_id": card.taxon_id,
            "normalized_name": normalize_name(card.name),
            "rarity": card.rarity.value
            if hasattr(card.rarity, "value")
            else str(card.rarity),
            "reference_photo_url": card.reference_photo_url or _PLACEHOLDER_PHOTO,
            "category": card.category,
            "wiki_url": card.wiki_url,
            "lore": card.lore,
            "captured_at": card.captured_at,
            "capture_lat": card.capture_lat,
            "capture_lng": card.capture_lng,
        }

    @staticmethod
    def _row_to_card(row: dict[str, Any]) -> FaunaCardModel:
        rarity_raw = row.get("rarity", "Common")
        try:
            rarity = Rarity(str(rarity_raw))
        except ValueError:
            rarity = Rarity.COMMON
        taxon_raw = row.get("taxon_id")
        return FaunaCardModel(
            card_id=str(row.get("card_id") or row.get("id") or ""),
            user_id=str(row.get("user_id") or "") or None,
            name=str(row["name"]),
            scientific_name=str(row.get("scientific_name") or ""),
            taxon_id=int(taxon_raw) if taxon_raw is not None else None,
            rarity=rarity,
            reference_photo_url=str(row.get("reference_photo_url") or ""),
            category=str(row.get("category") or "Wildlife"),
            wiki_url=str(row.get("wiki_url") or ""),
            lore=str(row.get("lore") or ""),
            captured_at=(str(row["captured_at"]) if row.get("captured_at") else None),
            capture_lat=row.get("capture_lat"),
            capture_lng=row.get("capture_lng"),
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
            raise HTTPException(
                status_code=502, detail=f"Database error: {exc}"
            ) from exc

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
            raise HTTPException(
                status_code=502, detail=f"Database error: {exc}"
            ) from exc

    # ------------------------------------------------------------------
    # Shared species reference cache
    # ------------------------------------------------------------------
    def get_species_reference(self, species_name: str) -> Optional[dict[str, Any]]:
        client = self._get_client()
        if client is None:
            return None
        try:
            result = (
                client.table(self.SPECIES_TABLE)
                .select("*")
                .eq("species_name", species_name)
                .limit(1)
                .execute()
            )
            rows = result.data or []
            return rows[0] if rows else None
        except Exception as exc:  # noqa: BLE001
            logger.error("get_species_reference failed: %s", exc)
            return None

    def upsert_species_reference(
        self,
        *,
        species_name: str,
        photo_url: str,
        category: str,
        wiki_url: str,
        taxon_id: Optional[int] = None,
        scientific_name: str = "",
    ) -> bool:
        client = self._get_client()
        if client is None:
            return False
        row = {
            "species_name": species_name,
            "photo_url": photo_url,
            "category": category,
            "wiki_url": wiki_url,
            "taxon_id": taxon_id,
            "scientific_name": scientific_name,
        }
        try:
            client.table(self.SPECIES_TABLE).upsert(
                row, on_conflict="species_name"
            ).execute()
            return True
        except Exception as exc:  # noqa: BLE001
            logger.error("upsert_species_reference failed: %s", exc)
            return False

    # ------------------------------------------------------------------
    # Profiles + XP / levels
    # ------------------------------------------------------------------
    def get_profile(self, user_id: str) -> Optional[dict[str, Any]]:
        """Fetch a profile row (with xp/level). None when off or missing."""
        client = self._get_client()
        if client is None:
            return None
        try:
            result = (
                client.table(self.PROFILES_TABLE)
                .select("user_id, username, xp, level")
                .eq("user_id", user_id)
                .limit(1)
                .execute()
            )
            rows = result.data or []
            return rows[0] if rows else None
        except Exception as exc:  # noqa: BLE001
            logger.error("get_profile failed: %s", exc)
            return None

    def species_count(self, user_id: str) -> int:
        """Number of distinct species names in a player's collection."""
        client = self._get_client()
        if client is None:
            return 0
        try:
            result = (
                client.table(self.CARDS_TABLE)
                .select("name")
                .eq("user_id", user_id)
                .execute()
            )
            rows = result.data or []
            return len({str(r.get("name")) for r in rows if r.get("name")})
        except Exception as exc:  # noqa: BLE001
            logger.error("species_count failed: %s", exc)
            return 0

    def user_has_species(
        self, user_id: str, name: str, taxon_id: Optional[int] = None
    ) -> bool:
        """True when this player already owns this species.

        Matches on the stable iNaturalist taxon id when available (conflict
        free), otherwise falls back to the normalized (lowercased) name.
        """
        client = self._get_client()
        if client is None:
            return False
        try:
            query = (
                client.table(self.CARDS_TABLE)
                .select("card_id")
                .eq("user_id", user_id)
            )
            if taxon_id is not None:
                query = query.eq("taxon_id", taxon_id)
            else:
                query = query.eq("normalized_name", normalize_name(name))
            result = query.limit(1).execute()
            return bool(result.data)
        except Exception as exc:  # noqa: BLE001
            logger.error("user_has_species failed: %s", exc)
            return False

    def award_xp(self, user_id: str, delta: int) -> tuple[int, int]:
        """Add `delta` XP to a profile, recompute level, persist, and return
        the resulting (xp, level). Returns (0, 1) when Supabase is off."""
        client = self._get_client()
        if client is None:
            return (0, 1)
        try:
            profile = self.get_profile(user_id) or {}
            current = int(profile.get("xp") or 0)
            new_xp = max(0, current + delta)
            new_level = compute_level(new_xp)
            client.table(self.PROFILES_TABLE).update(
                {"xp": new_xp, "level": new_level}
            ).eq("user_id", user_id).execute()
            return (new_xp, new_level)
        except Exception as exc:  # noqa: BLE001
            logger.error("award_xp failed: %s", exc)
            return (0, 1)

    # ------------------------------------------------------------------
    # Friends
    # ------------------------------------------------------------------
    def search_users(
        self, username: str, requester_id: str
    ) -> list[dict[str, Any]]:
        """Case-insensitive username search, excluding the requester."""
        client = self._get_client()
        if client is None:
            return []
        term = username.strip()
        if not term:
            return []
        try:
            result = (
                client.table(self.PROFILES_TABLE)
                .select("user_id, username, level")
                .ilike("username", f"%{term}%")
                .neq("user_id", requester_id)
                .limit(20)
                .execute()
            )
            return result.data or []
        except Exception as exc:  # noqa: BLE001
            logger.error("search_users failed: %s", exc)
            return []

    def _friendship_between(
        self, a: str, b: str
    ) -> Optional[dict[str, Any]]:
        """Return the friendship row in either direction, if any."""
        client = self._get_client()
        if client is None:
            return None
        try:
            result = (
                client.table(self.FRIENDS_TABLE)
                .select("*")
                .or_(
                    f"and(user_id.eq.{a},friend_id.eq.{b}),"
                    f"and(user_id.eq.{b},friend_id.eq.{a})"
                )
                .limit(1)
                .execute()
            )
            rows = result.data or []
            return rows[0] if rows else None
        except Exception as exc:  # noqa: BLE001
            logger.error("_friendship_between failed: %s", exc)
            return None

    def create_friend_request(self, user_id: str, friend_id: str) -> bool:
        """Insert a pending request (idempotent if one already exists)."""
        client = self._get_client()
        if client is None:
            return False
        if user_id == friend_id:
            raise HTTPException(
                status_code=400, detail="You cannot add yourself."
            )
        existing = self._friendship_between(user_id, friend_id)
        if existing is not None:
            # Already pending or accepted in some direction; treat as success.
            return True
        try:
            result = (
                client.table(self.FRIENDS_TABLE)
                .insert(
                    {
                        "user_id": user_id,
                        "friend_id": friend_id,
                        "status": "pending",
                    }
                )
                .execute()
            )
            return bool(result.data)
        except Exception as exc:  # noqa: BLE001
            logger.error("create_friend_request failed: %s", exc)
            raise HTTPException(
                status_code=502, detail=f"Database error: {exc}"
            ) from exc

    def accept_friend_request(self, user_id: str, friend_id: str) -> bool:
        """Accept the pending request that `friend_id` sent to `user_id`."""
        client = self._get_client()
        if client is None:
            return False
        try:
            result = (
                client.table(self.FRIENDS_TABLE)
                .update({"status": "accepted"})
                .eq("user_id", friend_id)
                .eq("friend_id", user_id)
                .eq("status", "pending")
                .execute()
            )
            return bool(result.data)
        except Exception as exc:  # noqa: BLE001
            logger.error("accept_friend_request failed: %s", exc)
            raise HTTPException(
                status_code=502, detail=f"Database error: {exc}"
            ) from exc

    def _profile_summary(self, user_id: str) -> dict[str, Any]:
        profile = self.get_profile(user_id) or {}
        return {
            "user_id": user_id,
            "username": str(profile.get("username") or "player"),
            "level": int(profile.get("level") or 1),
            "xp": int(profile.get("xp") or 0),
            "species_count": self.species_count(user_id),
        }

    def get_accepted_friends(self, user_id: str) -> list[dict[str, Any]]:
        """Accepted friends in both directions, each as a FriendSummary dict."""
        client = self._get_client()
        if client is None:
            return []
        try:
            result = (
                client.table(self.FRIENDS_TABLE)
                .select("user_id, friend_id")
                .or_(f"user_id.eq.{user_id},friend_id.eq.{user_id}")
                .eq("status", "accepted")
                .execute()
            )
            rows = result.data or []
            friend_ids: set[str] = set()
            for r in rows:
                uid = str(r.get("user_id"))
                fid = str(r.get("friend_id"))
                friend_ids.add(fid if uid == user_id else uid)
            return [self._profile_summary(fid) for fid in friend_ids]
        except Exception as exc:  # noqa: BLE001
            logger.error("get_accepted_friends failed: %s", exc)
            return []

    def get_incoming_requests(self, user_id: str) -> list[dict[str, Any]]:
        """Pending requests addressed to this user, as UserSearchResult dicts."""
        client = self._get_client()
        if client is None:
            return []
        try:
            result = (
                client.table(self.FRIENDS_TABLE)
                .select("user_id")
                .eq("friend_id", user_id)
                .eq("status", "pending")
                .execute()
            )
            rows = result.data or []
            out: list[dict[str, Any]] = []
            for r in rows:
                sender = str(r.get("user_id"))
                profile = self.get_profile(sender) or {}
                out.append(
                    {
                        "user_id": sender,
                        "username": str(profile.get("username") or "player"),
                        "level": int(profile.get("level") or 1),
                    }
                )
            return out
        except Exception as exc:  # noqa: BLE001
            logger.error("get_incoming_requests failed: %s", exc)
            return []

    def get_friend_profile(self, user_id: str) -> dict[str, Any]:
        """Read-only friend summary (level, xp, species count)."""
        return self._profile_summary(user_id)

    # ------------------------------------------------------------------
    # Species catalog / dex
    # ------------------------------------------------------------------
    def get_catalog(self) -> list[dict[str, Any]]:
        """Return the full master catalog ordered by dex number."""
        client = self._get_client()
        if client is None:
            return []
        try:
            result = (
                client.table(self.CATALOG_TABLE)
                .select("*")
                .order("dex_number")
                .execute()
            )
            return result.data or []
        except Exception as exc:  # noqa: BLE001
            logger.error("get_catalog failed: %s", exc)
            return []

    def upsert_catalog_entry(
        self,
        *,
        taxon_id: int,
        dex_number: int,
        name: str,
        scientific_name: str,
        category: str,
        rarity: str,
        reference_photo_url: str,
    ) -> bool:
        """Insert/update one catalog row (used by the seed script)."""
        client = self._get_client()
        if client is None:
            return False
        row = {
            "taxon_id": taxon_id,
            "dex_number": dex_number,
            "name": name,
            "scientific_name": scientific_name,
            "category": category,
            "rarity": rarity,
            "reference_photo_url": reference_photo_url,
        }
        try:
            client.table(self.CATALOG_TABLE).upsert(
                row, on_conflict="taxon_id"
            ).execute()
            return True
        except Exception as exc:  # noqa: BLE001
            logger.error("upsert_catalog_entry failed: %s", exc)
            return False

    def ensure_catalog_entry(self, card: FaunaCardModel) -> bool:
        """Open dex: add a scanned species to the shared catalog if new.

        Keyed on the stable taxon id. The catalog grows over time so that a
        species discovered by any player becomes a (locked) dex tile for
        everyone. No-op when the card has no taxon id.
        """
        client = self._get_client()
        if client is None or card.taxon_id is None:
            return False
        try:
            existing = (
                client.table(self.CATALOG_TABLE)
                .select("taxon_id")
                .eq("taxon_id", card.taxon_id)
                .limit(1)
                .execute()
            )
            if existing.data:
                return False  # already catalogued

            top = (
                client.table(self.CATALOG_TABLE)
                .select("dex_number")
                .order("dex_number", desc=True)
                .limit(1)
                .execute()
            )
            next_dex = 1
            if top.data:
                next_dex = int(top.data[0].get("dex_number") or 0) + 1

            rarity = (
                card.rarity.value
                if hasattr(card.rarity, "value")
                else str(card.rarity)
            )
            return self.upsert_catalog_entry(
                taxon_id=int(card.taxon_id),
                dex_number=next_dex,
                name=card.name,
                scientific_name=card.scientific_name,
                category=card.category or "Wildlife",
                rarity=rarity,
                reference_photo_url=card.reference_photo_url or "",
            )
        except Exception as exc:  # noqa: BLE001
            logger.error("ensure_catalog_entry failed: %s", exc)
            return False

    def get_collection_progress(self, user_id: str) -> dict[str, Any]:
        """Compute dex completion (overall + per category) for a player.

        A catalog species counts as caught when the player owns a card with the
        matching taxon id.
        """
        catalog = self.get_catalog()
        total = len(catalog)
        by_category_total: dict[str, int] = {}
        catalog_taxon_ids: set[int] = set()
        for entry in catalog:
            tid = entry.get("taxon_id")
            if tid is None:
                continue
            catalog_taxon_ids.add(int(tid))
            cat = str(entry.get("category") or "Wildlife")
            by_category_total[cat] = by_category_total.get(cat, 0) + 1

        client = self._get_client()
        owned_taxon_ids: set[int] = set()
        if client is not None:
            try:
                result = (
                    client.table(self.CARDS_TABLE)
                    .select("taxon_id")
                    .eq("user_id", user_id)
                    .execute()
                )
                for r in result.data or []:
                    tid = r.get("taxon_id")
                    if tid is not None:
                        owned_taxon_ids.add(int(tid))
            except Exception as exc:  # noqa: BLE001
                logger.error("get_collection_progress failed: %s", exc)

        caught_ids = sorted(owned_taxon_ids & catalog_taxon_ids)
        by_category_caught: dict[str, int] = {}
        for entry in catalog:
            tid = entry.get("taxon_id")
            if tid is not None and int(tid) in owned_taxon_ids:
                cat = str(entry.get("category") or "Wildlife")
                by_category_caught[cat] = by_category_caught.get(cat, 0) + 1

        by_category = {
            cat: {"caught": by_category_caught.get(cat, 0), "total": tot}
            for cat, tot in by_category_total.items()
        }
        return {
            "total": total,
            "caught": len(caught_ids),
            "by_category": by_category,
            "caught_taxon_ids": caught_ids,
        }


supabase_service = SupabaseService()
