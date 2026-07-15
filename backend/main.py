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

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from config import get_settings
from models import InventoryResponse, ScanRequest, ScanResponse
from services.supabase_service import supabase_service
from services.vision_service import vision_service

settings = get_settings()

app = FastAPI(
    title="FAUNA BATTLER AI",
    description="Backend for the real-world wildlife RPG: vision-based card "
    "minting and player inventory.",
    version="1.0.0",
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

    # Step 2: best-effort persistence.
    saved = False
    if settings.supabase_configured:
        try:
            saved = supabase_service.save_card(payload.user_id, card)
        except HTTPException:
            # Persistence failed but the card is still valid; surface saved=False
            # rather than losing the player's capture entirely.
            saved = False

    # Step 3: respond.
    return ScanResponse(
        card=card,
        saved=saved,
        is_mystery=is_mystery,
        local_sandbox=settings.local_sandbox_mode or not settings.vision_configured,
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


# ---------------------------------------------------------------------------
# Root
# ---------------------------------------------------------------------------
@app.get("/", tags=["system"])
def root() -> dict:
    return {
        "name": "FAUNA BATTLER AI",
        "docs": "/docs",
        "health": "/health",
    }
