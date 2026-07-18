"""
services/species_info_service.py
================================
Shared species reference lookup for FAUNA.

Given a species name (and preferably a scientific binomial) we return a
consistent reference photo, category, Wikipedia URL, and taxon_id so every
player sees identical enrichment for the same taxon.

Consistency is guaranteed by a cache-first strategy:
  1. Look up the species in the Supabase `species_reference` table.
  2. Only on a genuine miss do we hit the iNaturalist taxa API, then persist
     the result so the next lookup (for any player) reuses it.

Scientific binomials are preferred over free-text common names to avoid
ambiguous matches (e.g. "Tiger" matching an insect).
"""

from __future__ import annotations

import logging
from typing import Any, Optional

import httpx

from services.supabase_service import supabase_service

logger = logging.getLogger(__name__)

_INATURALIST_URL = "https://api.inaturalist.org/v1/taxa"
_HEADERS = {"User-Agent": "FaunaBattlerAI/1.0"}

_ICONIC_TO_CATEGORY: dict[str, str] = {
    "Mammalia": "Mammal",
    "Aves": "Bird",
    "Insecta": "Insect",
    "Actinopterygii": "Fish",
    "Reptilia": "Reptile",
    "Amphibia": "Amphibian",
    "Mollusca": "Mollusk",
    "Arachnida": "Arachnid",
}

_ANIMAL_ICONIC: frozenset[str] = frozenset(
    {
        "Animalia",
        "Mammalia",
        "Aves",
        "Reptilia",
        "Amphibia",
        "Actinopterygii",
        "Mollusca",
        "Arachnida",
        "Insecta",
    }
)


def _empty() -> dict[str, Any]:
    return {
        "reference_photo_url": "",
        "category": "Wildlife",
        "wiki_url": "",
        "taxon_id": None,
        "scientific_name": "",
        "preferred_common_name": "",
    }


class SpeciesInfoService:
    """iNaturalist reference lookup with a Supabase-backed shared cache."""

    def get_species_info(
        self, name: str, scientific_name: str = ""
    ) -> dict[str, Any]:
        """Return enrichment for a species.

        Prefers [scientific_name] when provided (deterministic), then falls
        back to the free-text common [name].
        """
        scientific = (scientific_name or "").strip()
        common = (name or "").strip()

        if scientific:
            cached = self._cache_lookup(scientific)
            if cached and cached.get("taxon_id") is not None:
                return cached
            info = self._fetch_by_scientific(scientific)
            if info.get("taxon_id") is not None:
                self._persist(scientific, info)
                if common and common.lower() != scientific.lower():
                    self._persist(common, info)
                return info

        if not common:
            return _empty()

        cached = self._cache_lookup(common)
        if cached and cached.get("taxon_id") is not None:
            return cached

        info = self._fetch_inaturalist(common)
        if info.get("taxon_id") is not None:
            self._persist(common, info)
        return info

    def catalog_rarity_for_taxon(self, taxon_id: int) -> Optional[Any]:
        """Return catalog rarity enum for a taxon when present, else None."""
        from models import Rarity  # local import avoids circular import at load

        try:
            for entry in supabase_service.get_catalog():
                tid = entry.get("taxon_id")
                if tid is None:
                    continue
                if int(tid) != int(taxon_id):
                    continue
                raw = str(entry.get("rarity") or "Common")
                try:
                    return Rarity(raw)
                except ValueError:
                    return Rarity.COMMON
        except Exception as exc:  # noqa: BLE001
            logger.debug("catalog_rarity_for_taxon failed: %s", exc)
        return None

    def _cache_lookup(self, key: str) -> Optional[dict[str, Any]]:
        cached = supabase_service.get_species_reference(key)
        if not cached:
            return None
        return {
            "reference_photo_url": str(cached.get("photo_url") or ""),
            "category": str(cached.get("category") or "Wildlife"),
            "wiki_url": str(cached.get("wiki_url") or ""),
            "taxon_id": cached.get("taxon_id"),
            "scientific_name": str(cached.get("scientific_name") or ""),
            "preferred_common_name": str(cached.get("species_name") or key),
        }

    def _persist(self, key: str, info: dict[str, Any]) -> None:
        supabase_service.upsert_species_reference(
            species_name=key,
            photo_url=info.get("reference_photo_url") or "",
            category=info.get("category") or "Wildlife",
            wiki_url=info.get("wiki_url") or "",
            taxon_id=info.get("taxon_id"),
            scientific_name=info.get("scientific_name") or "",
        )

    @staticmethod
    def _norm(text: str) -> str:
        return " ".join((text or "").strip().lower().split())

    def _pick_best(
        self, query: str, results: list[dict[str, Any]]
    ) -> dict[str, Any] | None:
        """Choose the best animal taxon for a common-name query."""
        animals = [
            r
            for r in results
            if str(r.get("iconic_taxon_name") or "") in _ANIMAL_ICONIC
        ]
        if not animals:
            return None

        q = self._norm(query)
        for r in animals:
            if self._norm(str(r.get("preferred_common_name") or "")) == q:
                return r
        for r in animals:
            pcn = self._norm(str(r.get("preferred_common_name") or ""))
            if pcn and pcn.startswith(q):
                return r
        qwords = set(q.split())
        for r in animals:
            pcn = self._norm(str(r.get("preferred_common_name") or ""))
            if pcn and qwords.issubset(set(pcn.split())):
                return r
        # Also accept exact scientific-name match against the query.
        for r in animals:
            if self._norm(str(r.get("name") or "")) == q:
                return r
        return animals[0]

    def _pick_scientific(
        self, scientific: str, results: list[dict[str, Any]]
    ) -> dict[str, Any] | None:
        """Require an exact (or near-exact) scientific binomial match."""
        animals = [
            r
            for r in results
            if str(r.get("iconic_taxon_name") or "") in _ANIMAL_ICONIC
        ]
        if not animals:
            return None
        q = self._norm(scientific)
        for r in animals:
            if self._norm(str(r.get("name") or "")) == q:
                return r
        # Prefix match for "Ursus maritimus ssp. ..." style names.
        for r in animals:
            sci = self._norm(str(r.get("name") or ""))
            if sci.startswith(q) or q.startswith(sci):
                return r
        return None

    def _row_to_info(self, top: dict[str, Any]) -> dict[str, Any]:
        photo = (top.get("default_photo") or {}).get("medium_url") or ""
        iconic = str(top.get("iconic_taxon_name") or "")
        category = _ICONIC_TO_CATEGORY.get(iconic, "Wildlife")
        wiki_url = str(top.get("wikipedia_url") or "")
        taxon_id = top.get("id")
        scientific_name = str(top.get("name") or "")
        preferred = str(top.get("preferred_common_name") or "").strip()
        return {
            "reference_photo_url": str(photo),
            "category": category,
            "wiki_url": wiki_url,
            "taxon_id": int(taxon_id) if taxon_id is not None else None,
            "scientific_name": scientific_name,
            "preferred_common_name": preferred or scientific_name,
        }

    def _fetch_by_scientific(self, scientific: str) -> dict[str, Any]:
        params = {
            "q": scientific,
            "rank": "species",
            "per_page": 20,
            "iconic_taxa": "Animalia",
        }
        try:
            with httpx.Client(timeout=10.0, headers=_HEADERS) as client:
                response = client.get(_INATURALIST_URL, params=params)
                if response.status_code != 200:
                    return _empty()
                data = response.json()
        except Exception as exc:  # noqa: BLE001
            logger.warning(
                "iNaturalist scientific lookup failed for %s: %s", scientific, exc
            )
            return _empty()

        results = data.get("results") or []
        if not results:
            return _empty()
        top = self._pick_scientific(scientific, results)
        if top is None:
            return _empty()
        return self._row_to_info(top)

    def _fetch_inaturalist(self, name: str) -> dict[str, Any]:
        params = {
            "q": name,
            "rank": "species",
            "per_page": 30,
            "iconic_taxa": "Animalia",
        }
        try:
            with httpx.Client(timeout=10.0, headers=_HEADERS) as client:
                response = client.get(_INATURALIST_URL, params=params)
                if response.status_code != 200:
                    return _empty()
                data = response.json()
        except Exception as exc:  # noqa: BLE001
            logger.warning("iNaturalist lookup failed for %s: %s", name, exc)
            return _empty()

        results = data.get("results") or []
        if not results:
            return _empty()

        top = self._pick_best(name, results)
        if top is None:
            return _empty()
        return self._row_to_info(top)


species_info_service = SpeciesInfoService()
