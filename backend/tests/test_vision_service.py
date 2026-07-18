"""Unit tests for fail-closed vision parsing (no hallucinated species)."""

from __future__ import annotations

import json

import pytest

from models import Rarity
from services.vision_service import VisionResult, VisionService


class TestVisionResultParsing:
    def test_parses_high_confidence_polar_bear(self):
        raw = json.dumps(
            {
                "is_living_animal": True,
                "confident": True,
                "confidence": 0.95,
                "name": "Polar Bear",
                "scientific_guess": "Ursus maritimus",
                "rarity": "Rare",
                "reason": "white fur, large ursid body, black nose",
            }
        )
        result = VisionService.parse_vision_payload(raw)
        assert result.is_living_animal is True
        assert result.confident is True
        assert result.confidence == pytest.approx(0.95)
        assert result.name == "Polar Bear"
        assert result.scientific_guess == "Ursus maritimus"

    def test_coerces_string_booleans_and_never_defaults_confident_true(self):
        raw = json.dumps(
            {
                "is_living_animal": "true",
                "confident": "false",
                "confidence": "0.4",
                "name": "",
                "scientific_guess": "",
                "rarity": "Common",
                "reason": "blurry",
            }
        )
        result = VisionService.parse_vision_payload(raw)
        assert result.is_living_animal is True
        assert result.confident is False
        assert result.confidence == pytest.approx(0.4)

    def test_strips_markdown_fence(self):
        raw = """```json
{"is_living_animal": true, "confident": true, "confidence": 0.9,
 "name": "Red Fox", "scientific_guess": "Vulpes vulpes",
 "rarity": "Uncommon", "reason": "red coat"}
```"""
        result = VisionService.parse_vision_payload(raw)
        assert result.name == "Red Fox"

    def test_invalid_json_raises(self):
        with pytest.raises(ValueError):
            VisionService.parse_vision_payload("not json at all")


class TestMysteryAndRarity:
    def test_mystery_card_has_no_taxon(self):
        card = VisionService.mystery_card("low confidence")
        assert card.name == "Mystery Spawn"
        assert card.taxon_id is None
        assert card.rarity == Rarity.COMMON
        assert "confidence" in card.lore.lower() or "identify" in card.lore.lower()

    def test_low_confidence_gate_logic(self):
        """Mirrors analyze_animal's confidence gate without calling OpenRouter."""
        low = VisionResult(
            is_living_animal=True,
            confident=True,
            confidence=0.5,
            name="Domestic Cat",
            scientific_guess="Felis catus",
        )
        high = VisionResult(
            is_living_animal=True,
            confident=True,
            confidence=0.85,
            name="Polar Bear",
            scientific_guess="Ursus maritimus",
        )
        assert not (
            low.confident and low.confidence >= 0.7 and bool(low.name or low.scientific_guess)
        )
        assert (
            high.confident
            and high.confidence >= 0.7
            and bool(high.name or high.scientific_guess)
        )

    def test_parse_rarity_variants(self):
        assert VisionService._parse_rarity("Rare") == Rarity.RARE
        assert VisionService._parse_rarity("legendary") == Rarity.LEGENDARY
        assert VisionService._parse_rarity("nope") == Rarity.COMMON


class TestScientificPicker:
    def test_pick_scientific_requires_exact_match(self):
        from services.species_info_service import SpeciesInfoService

        svc = SpeciesInfoService()
        results = [
            {
                "id": 1,
                "name": "Felis catus",
                "preferred_common_name": "Domestic Cat",
                "iconic_taxon_name": "Mammalia",
                "default_photo": {"medium_url": "http://example/cat.jpg"},
                "wikipedia_url": "",
            },
            {
                "id": 41641,
                "name": "Ursus maritimus",
                "preferred_common_name": "Polar Bear",
                "iconic_taxon_name": "Mammalia",
                "default_photo": {"medium_url": "http://example/bear.jpg"},
                "wikipedia_url": "",
            },
        ]
        top = svc._pick_scientific("Ursus maritimus", results)
        assert top is not None
        assert top["id"] == 41641

        miss = svc._pick_scientific("Panthera tigris", results)
        assert miss is None
