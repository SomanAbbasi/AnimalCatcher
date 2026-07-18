"""
main.py
=======
FastAPI entrypoint for FAUNA BATTLER AI.

Exposes the JSON API consumed by the Flutter client:
    POST /api/scan                 -> analyse a photo, mint + save a card
    GET  /api/inventory/{user_id}  -> fetch a player's collection
    GET  /health                   -> liveness + config diagnostics

Run locally:
    cd backend
    pip install -r requirements.txt
    uvicorn main:app --reload --port 8000
    # Add `--host 0.0.0.0` ONLY if you connect the phone over Wi-Fi (LAN IP)
    # instead of USB. For USB, keep the default host and run once on the PC:
    #     adb reverse tcp:8000 tcp:8000

Interactive docs live at http://localhost:8000/docs
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from config import get_settings
from models import (
    CatalogEntry,
    CollectionProgress,
    FriendActionRequest,
    FriendSummary,
    InventoryResponse,
    ProfileResponse,
    ScanRequest,
    ScanResponse,
    SpeciesInfoResponse,
    UserSearchResult,
)
from services.species_info_service import species_info_service
from services.supabase_service import supabase_service
from services.vision_service import vision_service

settings = get_settings()

app = FastAPI(
    title="FAUNA",
    description="Backend for the real-world wildlife collection game: "
    "vision-based species identification and player collections.",
    version="2.0.0",
)

# ---------------------------------------------------------------------------
# CORS - permissive by default so the mobile app (and web preview) can call in.
# Tighten ALLOWED_ORIGINS in production via env var.
# ---------------------------------------------------------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------
@app.get("/health", tags=["system"])
def health() -> dict:
    """Liveness probe + a quick view of which integrations are configured."""
    return {
        "status": "ok",
        "app_env": settings.app_env,
        "vision_configured": settings.vision_configured,
        "supabase_configured": settings.supabase_configured,
        "local_sandbox_mode": settings.local_sandbox_mode,
    }


# ---------------------------------------------------------------------------
# Core gameplay endpoints
# ---------------------------------------------------------------------------
@app.post("/api/scan", response_model=ScanResponse, tags=["gameplay"])
def scan(payload: ScanRequest) -> ScanResponse:
    """Analyse a captured photo and mint a creature card.

    Flow:
      1. Run the image through the vision service (OpenRouter).
         - Non-living target -> HTTP 400 (anti-cheat).
         - Uncertain species / unparseable output -> a "Mystery Spawn" card.
      2. Persist the resulting card to the player's Supabase cards table.
         - If Supabase is not configured, the scan still succeeds and returns
           the card with `saved = false` so gameplay is never fully blocked.
      3. Return the final card to the client.
    """
    # Step 1: vision analysis (may raise HTTP 400 for anti-cheat).
    card, is_mystery = vision_service.analyze_animal(payload.image_base64)

    # Attach the player's personal capture metadata.
    card = card.model_copy(
        update={
            "user_id": payload.user_id,
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "capture_lat": payload.location_lat,
            "capture_lng": payload.location_lng,
        }
    )

    # Step 2: best-effort persistence + XP award.
    saved = False
    xp_awarded = 0
    xp = 0
    level = 1
    if settings.supabase_configured:
        # Determine novelty BEFORE inserting so the new card doesn't count.
        is_new = not supabase_service.user_has_species(
            payload.user_id, card.name, card.taxon_id
        )
        try:
            saved = supabase_service.save_card(payload.user_id, card)
        except HTTPException:
            # Persistence failed but the card is still valid; surface saved=False
            # rather than losing the player's capture entirely.
            saved = False
        if saved:
            xp_awarded = 50 if is_new else 5
            xp, level = supabase_service.award_xp(payload.user_id, xp_awarded)
            # Open dex: a newly-seen species becomes a tile for everyone.
            supabase_service.ensure_catalog_entry(card)

    # Step 3: respond.
    return ScanResponse(
        card=card,
        saved=saved,
        is_mystery=is_mystery,
        local_sandbox=settings.local_sandbox_mode or not settings.vision_configured,
        xp_awarded=xp_awarded,
        xp=xp,
        level=level,
        taxon_id=card.taxon_id,
    )


@app.get(
    "/api/inventory/{user_id}",
    response_model=InventoryResponse,
    tags=["gameplay"],
)
def inventory(user_id: str) -> InventoryResponse:
    """Retrieve every card in a player's collection."""
    if not user_id.strip():
        raise HTTPException(status_code=422, detail="user_id is required.")

    cards = supabase_service.get_cards(user_id)
    return InventoryResponse(user_id=user_id, count=len(cards), cards=cards)


@app.get("/api/species", response_model=SpeciesInfoResponse, tags=["gameplay"])
def species(name: str) -> SpeciesInfoResponse:
    """Return the shared reference data (photo/category/wiki) for a species.

    Cache-first: reuses the Supabase `species_reference` row when present so
    every player sees the identical reference photo and category. Used by the
    guest/test login to hydrate its seed species via the real live path.
    """
    clean = name.strip()
    if not clean:
        raise HTTPException(status_code=422, detail="name is required.")

    info = species_info_service.get_species_info(clean)
    return SpeciesInfoResponse(
        name=clean,
        reference_photo_url=info["reference_photo_url"],
        category=info["category"],
        wiki_url=info["wiki_url"],
        taxon_id=info.get("taxon_id"),
        scientific_name=str(info.get("scientific_name") or ""),
    )


# ---------------------------------------------------------------------------
# Profiles
# ---------------------------------------------------------------------------
@app.get(
    "/api/profile/{user_id}",
    response_model=ProfileResponse,
    tags=["profile"],
)
def profile(user_id: str) -> ProfileResponse:
    """Return a player's profile (xp/level/species count)."""
    if not user_id.strip():
        raise HTTPException(status_code=422, detail="user_id is required.")

    row = supabase_service.get_profile(user_id) or {}
    return ProfileResponse(
        user_id=user_id,
        username=str(row.get("username") or ""),
        xp=int(row.get("xp") or 0),
        level=int(row.get("level") or 1),
        species_count=supabase_service.species_count(user_id),
    )


# ---------------------------------------------------------------------------
# Species catalog / dex
# ---------------------------------------------------------------------------
@app.get("/api/catalog", response_model=list[CatalogEntry], tags=["catalog"])
def catalog() -> list[CatalogEntry]:
    """Return the fixed master species catalog (the dex), ordered by number."""
    rows = supabase_service.get_catalog()
    entries: list[CatalogEntry] = []
    for r in rows:
        try:
            entries.append(CatalogEntry(**r))
        except Exception:  # noqa: BLE001 - skip malformed rows defensively
            continue
    return entries


@app.get(
    "/api/collection/progress/{user_id}",
    response_model=CollectionProgress,
    tags=["catalog"],
)
def collection_progress(user_id: str) -> CollectionProgress:
    """Return a player's dex completion (overall + per category)."""
    if not user_id.strip():
        raise HTTPException(status_code=422, detail="user_id is required.")
    return CollectionProgress(**supabase_service.get_collection_progress(user_id))


# ---------------------------------------------------------------------------
# Friends
# ---------------------------------------------------------------------------
@app.get(
    "/api/users/search",
    response_model=list[UserSearchResult],
    tags=["friends"],
)
def search_users(username: str, requester_id: str) -> list[UserSearchResult]:
    """Search players by (partial) username, excluding the requester."""
    rows = supabase_service.search_users(username, requester_id)
    return [UserSearchResult(**r) for r in rows]


@app.post("/api/friends/request", tags=["friends"])
def send_friend_request(payload: FriendActionRequest) -> dict:
    """Send a pending friend request from user_id -> friend_id."""
    ok = supabase_service.create_friend_request(
        payload.user_id, payload.friend_id
    )
    return {"ok": ok}


@app.post("/api/friends/accept", tags=["friends"])
def accept_friend_request(payload: FriendActionRequest) -> dict:
    """Accept the pending request that friend_id sent to user_id."""
    ok = supabase_service.accept_friend_request(
        payload.user_id, payload.friend_id
    )
    return {"ok": ok}


@app.get(
    "/api/friends/{user_id}",
    response_model=list[FriendSummary],
    tags=["friends"],
)
def list_friends(user_id: str) -> list[FriendSummary]:
    """List a player's accepted friends."""
    rows = supabase_service.get_accepted_friends(user_id)
    return [FriendSummary(**r) for r in rows]


@app.get(
    "/api/friends/{user_id}/requests",
    response_model=list[UserSearchResult],
    tags=["friends"],
)
def list_incoming_requests(user_id: str) -> list[UserSearchResult]:
    """List pending friend requests addressed to this player."""
    rows = supabase_service.get_incoming_requests(user_id)
    return [UserSearchResult(**r) for r in rows]


# ---------------------------------------------------------------------------
# Root
# ---------------------------------------------------------------------------
@app.get("/", tags=["system"])
def root() -> dict:
    return {
        "name": "FAUNA",
        "docs": "/docs",
        "health": "/health",
    }
