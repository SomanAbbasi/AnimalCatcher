"""
seed_catalog.py
===============
One-time (idempotent) seeder for the FAUNA species catalog / dex.

For every (common_name, scientific_name, category, rarity) in
data/catalog_seed.py this:
  1. Resolves the species on iNaturalist BY ITS SCIENTIFIC NAME (a unique
     binomial), which is deterministic — a bare common-name search would
     otherwise surface an unrelated heavily-observed species.
  2. Warms the shared `species_reference` cache keyed by the common name so a
     later live scan of the same animal reuses the identical, correct data.
  3. Upserts the result into `species_catalog` with a sequential dex_number.
  4. Writes the bundled JSON asset the Flutter app ships for guest/offline use:
     animal_catcher/assets/data/species_catalog.json

Run from the backend directory (with .env configured):
    python seed_catalog.py
"""

from __future__ import annotations

import json
import logging
import time
from pathlib import Path
from typing import Any, Optional

import httpx

from config import get_settings
from data.catalog_seed import CATALOG_SEED
from services.supabase_service import supabase_service

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("seed_catalog")
# Quiet the very chatty HTTP client logs.
logging.getLogger("httpx").setLevel(logging.WARNING)

_INATURALIST_URL = "https://api.inaturalist.org/v1/taxa"
_HEADERS = {"User-Agent": "FaunaBattlerAI/1.0"}

# animal_catcher/assets/data/species_catalog.json (bundled fallback).
_JSON_OUT = (
    Path(__file__).resolve().parent.parent
    / "animal_catcher"
    / "assets"
    / "data"
    / "species_catalog.json"
)

_SLEEP_SECONDS = 0.8


def _norm(text: str) -> str:
    return " ".join((text or "").strip().lower().split())


def resolve_by_scientific(scientific_name: str) -> Optional[dict[str, Any]]:
    """Resolve a taxon deterministically from its scientific binomial."""
    params = {"q": scientific_name, "rank": "species", "per_page": 5}
    try:
        with httpx.Client(timeout=10.0, headers=_HEADERS) as client:
            response = client.get(_INATURALIST_URL, params=params)
            if response.status_code != 200:
                return None
            results = response.json().get("results") or []
    except Exception as exc:  # noqa: BLE001
        logger.warning("lookup failed for %s: %s", scientific_name, exc)
        return None

    if not results:
        return None

    target = _norm(scientific_name)
    top = next((r for r in results if _norm(str(r.get("name") or "")) == target), None)
    top = top or results[0]

    taxon_id = top.get("id")
    if taxon_id is None:
        return None
    return {
        "taxon_id": int(taxon_id),
        "scientific_name": str(top.get("name") or scientific_name),
        "reference_photo_url": str(
            (top.get("default_photo") or {}).get("medium_url") or ""
        ),
        "wiki_url": str(top.get("wikipedia_url") or ""),
    }


def main() -> None:
    settings = get_settings()
    if not settings.supabase_configured:
        logger.warning(
            "Supabase is not configured; the catalog table will NOT be written. "
            "The bundled JSON asset will still be generated."
        )

    entries: list[dict] = []
    seen_taxon_ids: set[int] = set()
    dex_number = 0

    for common_name, scientific_name, category, rarity in CATALOG_SEED:
        info = resolve_by_scientific(scientific_name)
        time.sleep(_SLEEP_SECONDS)
        if info is None:
            logger.warning("SKIP  %-30s (%s not found)", common_name, scientific_name)
            continue

        taxon_id = info["taxon_id"]
        if taxon_id in seen_taxon_ids:
            logger.warning("DUP   %-30s -> taxon %s already added", common_name, taxon_id)
            continue
        seen_taxon_ids.add(taxon_id)

        photo = info["reference_photo_url"]
        wiki = info["wiki_url"]
        sci = info["scientific_name"]

        # Warm the shared cache keyed by common name so live scans reuse it.
        if settings.supabase_configured:
            supabase_service.upsert_species_reference(
                species_name=common_name,
                photo_url=photo,
                category=category,
                wiki_url=wiki,
                taxon_id=taxon_id,
                scientific_name=sci,
            )

        dex_number += 1
        entry = {
            "taxon_id": taxon_id,
            "dex_number": dex_number,
            "name": common_name,
            "scientific_name": sci,
            "category": category,
            "rarity": rarity,
            "reference_photo_url": photo,
        }
        entries.append(entry)

        if settings.supabase_configured:
            ok = supabase_service.upsert_catalog_entry(**entry)
            status = "OK  " if ok else "FAIL"
        else:
            status = "JSON"
        logger.info(
            "%s #%03d %-30s [%s] %s (taxon=%s)",
            status,
            dex_number,
            common_name,
            category,
            sci,
            taxon_id,
        )

    _JSON_OUT.parent.mkdir(parents=True, exist_ok=True)
    _JSON_OUT.write_text(json.dumps(entries, indent=2), encoding="utf-8")
    logger.info(
        "\nDone. %d catalog entries. JSON written to %s",
        len(entries),
        _JSON_OUT,
    )


if __name__ == "__main__":
    main()
