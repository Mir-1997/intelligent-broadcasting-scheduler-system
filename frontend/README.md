# Frontend: Flutter web (BLoC)

```sh
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
flutter test
flutter build web --release --dart-define=API_BASE_URL=http://localhost:8000
```

The map uses Mapbox Streets when `MAPBOX_TOKEN` is set, and OpenStreetMap tiles otherwise.
Put it in the repo-root `.env` (see `.env.example`); docker compose picks it up automatically,
and locally add `--dart-define-from-file=../.env` to `flutter run` / `flutter build web`.

Design and component guide: [docs/frontend.md](../docs/frontend.md).
