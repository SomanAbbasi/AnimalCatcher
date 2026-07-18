# animal_catcher

Flutter client for **AnimalCatcher (FAUNA)** — the wildlife collect-and-catalog game.

See the root [README.md](../README.md) for full setup (backend, Supabase, `adb reverse`, friends, and scan accuracy notes).

```bash
flutter pub get
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=BACKEND_BASE_URL=http://localhost:8000
```
