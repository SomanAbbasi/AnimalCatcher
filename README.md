# AnimalCatcher (FAUNA)

Real-world wildlife **collect-and-catalog** game: photograph (or pick from gallery) a living animal, get a species card, fill your Pokédex-style dex, earn XP, and add friends.

| Folder | Stack | Role |
|--------|--------|------|
| [`animal_catcher/`](animal_catcher/) | Flutter | Mobile client (Android / iOS) |
| [`backend/`](backend/) | FastAPI + OpenRouter + Supabase | Scan, catalog, XP, friends API |

---

## Features

- **Scan** — Camera or gallery → vision ID via OpenRouter (GPT-4o). Fail-closed: low confidence → Mystery Spawn; never invents a random species on errors.
- **Species dex** — Shared catalog (~160 curated animals + open growth). Locked tiles show silhouettes until you catch that taxon.
- **XP & levels** — `level = floor(sqrt(xp / 100)) + 1` (+50 new species, +5 repeat).
- **Zoo geofence** — Scans blocked within ~1.5 km of a zoo/aquarium (fail-open on network errors).
- **Friends** — Search by username, send/accept requests, view level / XP / species count (signed-in accounts only).
- **Awards** — Client-side milestones for discovery, XP, rarity, and categories.

---

## Prerequisites

- Python **3.11+**
- Flutter **3.x** (SDK `^3.12` in `animal_catcher/pubspec.yaml`)
- Android device/emulator (or iOS)
- [OpenRouter](https://openrouter.ai/) API key (vision)
- [Supabase](https://supabase.com/) project (auth + Postgres) for online save / friends

---

## Backend setup

```bash
cd backend
python -m venv .venv

# Windows PowerShell
.\.venv\Scripts\Activate.ps1

pip install -r requirements.txt
copy .env.example .env
```

Edit `.env`:

| Variable | Purpose |
|----------|---------|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_KEY` | **Service role** key (server only — never put in the app) |
| `OPENROUTER_API_KEY` | Vision provider key |
| `OPENROUTER_VISION_MODEL` | Default `openai/gpt-4o` |
| `ALLOW_OFFLINE_SCAN` | `1` only for demo without a vision key (default off) |

Apply the database schema in the Supabase SQL editor:

- Run [`backend/schema.sql`](backend/schema.sql) (profiles, user_cards, species_catalog, friendships, RLS, etc.)

Optional: seed the master catalog (writes Supabase + Flutter asset):

```bash
python seed_catalog.py
```

Start the API:

```bash
# USB phone + adb reverse (recommended)
uvicorn main:app --reload --port 8000

# Wi-Fi / LAN phone — bind all interfaces
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

- Health: http://localhost:8000/health  
- Docs: http://localhost:8000/docs  

### Main API routes

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/scan` | Identify animal, mint card, XP, grow catalog |
| `GET` | `/api/inventory/{user_id}` | Player cards |
| `GET` | `/api/catalog` | Master species dex |
| `GET` | `/api/collection/progress/{user_id}` | Caught / total by taxon |
| `GET` | `/api/species?name=` | Shared reference photo / category / taxon |
| `GET` | `/api/profile/{user_id}` | XP, level, species count |
| `GET` | `/api/users/search` | Friend search |
| `POST` | `/api/friends/request` | Send friend request |
| `POST` | `/api/friends/accept` | Accept request |
| `GET` | `/api/friends/{user_id}` | Accepted friends |
| `GET` | `/api/friends/{user_id}/requests` | Incoming requests |

Identification rules (accuracy):

- High-detail vision, temperature `0`, confidence ≥ `0.7` required
- Taxonomy prefers **scientific name**, then common name (iNaturalist)
- Unsure / unresolved taxon → **Mystery Spawn** (no dex unlock, no species XP)
- Scanner down → HTTP **503** (client shows an error — no fake Domestic Cat)

---

## Flutter app setup

```bash
cd animal_catcher
flutter pub get
```

### USB device (Galaxy / physical phone)

On the PC, once per USB session:

```bash
adb reverse tcp:8000 tcp:8000
```

Then:

```bash
flutter run --dart-define=BACKEND_BASE_URL=http://localhost:8000
```

### Optional Supabase (login / friends)

```bash
flutter run ^
  --dart-define=BACKEND_BASE_URL=http://localhost:8000 ^
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co ^
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

(Use the **anon/publishable** key in the app — not the service role.)

### Emulator note

Android emulator → host machine is often `http://10.0.2.2:8000` instead of `localhost`.

---

## How to add friends

1. Create a **real account** (not Guest) with a unique username.
2. Open the **Friends** tab.
3. Search the other player’s username → send request.
4. They accept under incoming requests.
5. Tap a friend to see level, XP, and species discovered.

Guest mode can scan locally for testing; friends require Supabase auth.

---

## Project layout

```
AnimalCatcher/
├── animal_catcher/          # Flutter client
│   ├── lib/screens/         # Scan, Collection, Profile, Friends, Awards
│   ├── lib/services/        # API, auth, geofence
│   ├── lib/state/           # Session / dex progress
│   └── assets/data/         # Bundled species_catalog.json
└── backend/                 # FastAPI
    ├── main.py
    ├── schema.sql
    ├── services/vision_service.py
    ├── services/species_info_service.py
    └── seed_catalog.py
```

---

## Tests

```bash
# Backend
cd backend
python -m pytest tests/ -q

# Flutter
cd animal_catcher
flutter test
```

---

## Security notes

- Never commit `.env` or service-role keys.
- Anti-cheat is model-based (screens / toys / non-living → HTTP 400); gallery uploads are allowed for testing.
- Zoo restriction is client-side geofencing via Overpass.

---

## License

Private / personal project unless otherwise stated by the repository owner.
