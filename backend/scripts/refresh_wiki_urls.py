"""One-off helper: print verified 500px Wikipedia thumb URLs for offline index."""
from __future__ import annotations

import re

import httpx

UA = {"User-Agent": "FaunaBattlerAI/1.0 (contact@local.dev)"}

ANIMALS = [
    ("Street Pigeon", "Rock dove"),
    ("Garden Ant Swarm", "Fire ant"),
    ("House Cat", "Cat"),
    ("Urban Crow", "Common raven"),
    ("Clownfish", "Clownfish"),
    ("Timber Wolf", "Gray wolf"),
    ("Hornet", "European hornet"),
    ("Emperor Penguin", "Emperor penguin"),
    ("Red Fox", "Red fox"),
    ("Golden Eagle", "Golden eagle"),
    ("Green Sea Turtle", "Green sea turtle"),
    ("Snow Leopard", "Snow leopard"),
    ("Koala", "Koala"),
    ("Kangaroo", "Kangaroo"),
    ("Raccoon Bandit", "Raccoon"),
]


def to_500px(thumb: str) -> str:
    return re.sub(r"/\d+px-", "/500px-", thumb)


def main() -> None:
    with httpx.Client(headers=UA, timeout=20.0) as client:
        for name, wiki in ANIMALS:
            slug = wiki.replace(" ", "_")
            summary = client.get(
                f"https://en.wikipedia.org/api/rest_v1/page/summary/{slug}"
            ).json()
            thumb = to_500px(summary.get("thumbnail", {}).get("source", ""))
            status = client.get(thumb).status_code if thumb else 0
            print(f"{name} ({status})")
            print(f"  {thumb}")


if __name__ == "__main__":
    main()
