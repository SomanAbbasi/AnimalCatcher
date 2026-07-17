"""
services/species_info_service.py
================================
Shared species reference lookup for FAUNA.

Given a species name we return a consistent reference photo, a high-level
category, and a Wikipedia URL so that every player sees the *identical*
reference image and category for e.g. "Red Fox".

Consistency is guaranteed by a cache-first strategy:
  1. Look up the species in the Supabase `species_reference` table.
  2. Only on a genuine miss do we hit the iNaturalist taxa API, then persist
     the result so the next lookup (for any player) reuses it.

When Supabase is not configured the service still works — it just calls
iNaturalist directly every time (no shared cache).
"""

from __future__ import annotations

import logging
from typing import Any

import httpx

from services.supabase_service import supabase_service

logger = logging.getLogger(__name__)

_INATURALIST_URL = "https://api.inaturalist.org/v1/taxa"
_HEADERS = {"User-Agent": "FaunaBattlerAI/1.0"}

# iNaturalist iconic taxon -> player-facing category.
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

# Iconic taxa that are animals. A bare "q=" search on iNaturalist can return a
# plant whose common name contains the query word (e.g. "Lion" -> dandelion,
# "Common Toad" -> toadflax), so we accept only results in this set.
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
    }


class SpeciesInfoService:
    """iNaturalist reference lookup with a Supabase-backed shared cache."""

    def get_species_info(self, name: str) -> dict[str, Any]:
        """Return {reference_photo_url, category, wiki_url} for a species name."""
        key = (name or "").strip()
        if not key:
            return _empty()

        # 1. Cache-first: reuse the shared reference if we've seen this species.
        cached = supabase_service.get_species_reference(key)
        if cached:
            return {
                "reference_photo_url": str(cached.get("photo_url") or ""),
                "category": str(cached.get("category") or "Wildlife"),
                "wiki_url": str(cached.get("wiki_url") or ""),
                "taxon_id": cached.get("taxon_id"),
                "scientific_name": str(cached.get("scientific_name") or ""),
            }

        # 2. Genuine miss -> hit iNaturalist, then persist for everyone else.
        info = self._fetch_inaturalist(key)
        supabase_service.upsert_species_reference(
            species_name=key,
            photo_url=info["reference_photo_url"],
            category=info["category"],
            wiki_url=info["wiki_url"],
            taxon_id=info.get("taxon_id"),
            scientific_name=info.get("scientific_name") or "",
        )
        return info

    @staticmethod
    def _norm(text: str) -> str:
        return " ".join((text or "").strip().lower().split())

    def _pick_best(
        self, query: str, results: list[dict[str, Any]]
    ) -> dict[str, Any] | None:
        """Choose the best animal taxon for a common-name query.

        A bare iNaturalist search sorts by observation count, which can rank an
        unrelated but heavily-observed species first (e.g. "Lion" -> California
        Sea Lion, "Leopard" -> Leopard Slug). We therefore prefer the animal
        result whose *preferred common name* actually matches the query before
        falling back to the first animal result.
        """
        animals = [
            r
            for r in results
            if str(r.get("iconic_taxon_name") or "") in _ANIMAL_ICONIC
        ]
        if not animals:
            return None

        q = self._norm(query)
        # 1. Exact common-name match.
        for r in animals:
            if self._norm(str(r.get("preferred_common_name") or "")) == q:
                return r
        # 2. Common name starts with the query (e.g. "Cheetah" -> "Cheetah").
        for r in animals:
            pcn = self._norm(str(r.get("preferred_common_name") or ""))
            if pcn and pcn.startswith(q):
                return r
        # 3. Query words all present in the common name.
        qwords = set(q.split())
        for r in animals:
            pcn = self._norm(str(r.get("preferred_common_name") or ""))
            if pcn and qwords.issubset(set(pcn.split())):
                return r
        # 4. Fallback: most-observed animal result.
        return animals[0]

    def _fetch_inaturalist(self, name: str) -> dict[str, Any]:
        # Ask for several candidates and bias toward animals; a bare search can
        # otherwise surface a plant that merely shares a common-name word.
        params = {
            "q": name,
            "rank": "species",
            "per_page": 30,
            "iconic_taxa": "Animalia",
        }
        try:
            with httpx.Client(timeout=8.0, headers=_HEADERS) as client:
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

        photo = (top.get("default_photo") or {}).get("medium_url") or ""
        iconic = str(top.get("iconic_taxon_name") or "")
        category = _ICONIC_TO_CATEGORY.get(iconic, "Wildlife")
        wiki_url = str(top.get("wikipedia_url") or "")
        taxon_id = top.get("id")
        # iNaturalist's `name` on a species-rank taxon IS the scientific name.
        scientific_name = str(top.get("name") or "")
        return {
            "reference_photo_url": str(photo),
            "category": category,
            "wiki_url": wiki_url,
            "taxon_id": int(taxon_id) if taxon_id is not None else None,
            "scientific_name": scientific_name,
        }


species_info_service = SpeciesInfoService()
