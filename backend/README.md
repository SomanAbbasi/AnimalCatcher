# FAUNA BATTLER AI - Backend

Python **FastAPI** service that powers the wildlife RPG. It turns a phone photo
into a collectible creature card using **OpenAI GPT-4o Vision**, then persists
the card to a player's **Supabase** PostgreSQL inventory.

## Endpoints

| Method | Path                        | Description                                            |
| ------ | --------------------------- | ------------------------------------------------------ |
| POST   | `/api/scan`                 | Analyse a base64 photo, mint a card, save it, return it |
| GET    | `/api/inventory/{user_id}`  | Fetch a player's full card collection                   |
| GET    | `/health`                   | Liveness + which integrations are configured            |
| GET    | `/docs`                     | Interactive Swagger UI                                  |

### `POST /api/scan`

Request body:

```json
{
  "user_id": "b1c2...uuid",
  "image_base64": "<base64 JPEG/PNG, data-URI prefix optional>",
  "location_lat": 51.5,
  "location_lng": -0.12
}
```

Response:

```json
{
  "card": {
    "name": "Red Fox",
    "rarity": "Uncommon",
    "hp": 120, "attack": 65, "speed": 80, "defense": 50,
    "lore": "A cunning twilight hunter...",
    "trait": "Cunning Ambush"
  },
  "saved": true,
  "is_mystery": false
}
```

Special cases:

- **Anti-cheat (HTTP 400):** if the photo is a screen, printed picture, toy, or
  contains no living animal, the API returns `400` with a
  `"Anomaly Detected: Non-Living Target"` message.
- **Mystery Spawn:** if a living animal is present but the species is uncertain,
  a randomised unstable card is returned with `"is_mystery": true`.

## Setup

1. **Install dependencies**

   ```bash
   cd backend
   python -m venv .venv
   # Windows PowerShell:
   .venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   ```

2. **Configure environment**

   ```bash
   copy .env.example .env   # (Windows)  |  cp .env.example .env  (macOS/Linux)
   ```

   Fill in `SUPABASE_URL`, `SUPABASE_KEY` (service role key), and
   `OPENAI_API_KEY`.

3. **Create the database schema**

   Open the Supabase SQL editor and run [`schema.sql`](schema.sql). It creates
   the `profiles` and `inventory` tables, enables RLS, and adds owner-scoped
   policies.

4. **Run the server**

   ```bash
   uvicorn main:app --reload --host 0.0.0.0 --port 8000
   ```

   Visit http://localhost:8000/docs to try the API.

## Notes

- The backend uses the **service role** Supabase key and therefore bypasses
  RLS. The RLS policies protect the client (anon key) path used by the Flutter
  app. Never ship the service role key inside the mobile app.
- If Supabase is not configured, `/api/scan` still returns a valid card with
  `saved: false`, so the vision pipeline can be tested independently.
- The card JSON contract is defined in [`models.py`](models.py) and mirrored by
  the Flutter `FaunaCard` model.
