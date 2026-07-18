# FAUNA — Backend

FastAPI service for **AnimalCatcher**: vision scan (OpenRouter), species catalog, XP, and friends via Supabase.

Full setup instructions live in the repo root [README.md](../README.md).

```bash
python -m venv .venv
.\.venv\Scripts\Activate.ps1   # Windows
pip install -r requirements.txt
copy .env.example .env
# Apply schema.sql in Supabase, then:
uvicorn main:app --reload --port 8000
```

Docs: http://localhost:8000/docs
