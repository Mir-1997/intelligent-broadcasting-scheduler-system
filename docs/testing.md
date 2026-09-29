# Testing

## Backend: 103 tests (`backend/tests/`)

```sh
cd backend
uv run pytest                        # 85 run; the 18 Firestore variants are skipped

# everything, including the real Firestore emulator:
cd ..
firebase emulators:exec --only firestore --project demo-broadcast-scheduler \
  "cd backend && uv run pytest"

uv run ruff check . && uv run ruff format --check .
```

| File | Level | Covers |
|---|---|---|
| `test_geo.py` | unit | haversine against known distances, symmetry, radius boundary, tie-breaking, random points stay inside the radius, seed determinism |
| `test_matching.py` | unit | id format/uniqueness, skipping assigned candidates, oldest wins ties, out of range, `pair()` updates both sides without mutating its inputs; radius growth per interval and cap, next-expansion time, policy validation, per-package reach, one rider per package in a sweep |
| `test_repository_contract.py` | contract, **run once per backend** | admin round-trip; waiting vs. pairing in both directions; nearest wins; out of range waits; **5 concurrent packages vs 1 rider → exactly 1 assignment** (and the mirror); history order and limit; delete 404/409 rules; reset keeps the admin; riders reach only packages whose radius grew that far; `match_waiting` pairs grown packages oldest-first and is idempotent; radius policy survives reset |
| `test_api.py` | HTTP (TestClient, in-memory) | every endpoint, radius policy seed / update / validation (an update pairs packages now in reach), validation errors, status filters, simulate counts, reset, OpenAPI paths |
| `test_websocket.py` | WebSocket (TestClient) | first message is the snapshot; `*.added` → `assignment.created` order; removal/admin/reset events; fan-out to 2 clients; ping/pong; unsubscribe on disconnect |
| `test_radius_expansion.py` | service (real clock, 1 s timer) | a waiting package pairs once its radius grows to reach a rider; idle with nothing waiting or at the cap; policy update is published |
| `test_realtime.py` | unit | hub fan-out, unsubscribe, slow client closed on overflow |
| `test_firestore_client.py` | unit | emulator vs real-project client construction, key-file loading, `.env` beats shell variables |

The `repository` fixture in `conftest.py` is parametrised over `memory` and `firestore`. The
Firestore variant is marked `@pytest.mark.firestore` and skipped unless
`FIRESTORE_EMULATOR_HOST` is set. Each Firestore test gets its own random `COLLECTION_PREFIX`
and cleans up afterwards.

## Frontend: 55 tests (`frontend/test/`)

```sh
cd frontend
flutter test
flutter analyze
dart format --output=none --set-exit-if-changed lib test
```

| File | Covers |
|---|---|
| `data/models_test.dart` | JSON parsing of every entity (int/float coordinates, microsecond timestamps), draft serialisation, every `ServerEvent` type, unknown types, `AppConfig` ws/wss URL derivation |
| `data/scheduler_api_client_test.dart` | URLs, verbs, bodies; 409/422 error extraction; network failure → friendly `ApiException` |
| `data/scheduler_socket_test.dart` | decoding and ignoring junk; ping interval; **exact exponential backoff timings** (`fake_async`); reconnect after drop; `disconnect()` stops retries |
| `bloc/scheduler_bloc_test.dart` | the pure reducer for every event (including idempotency); start-up sequence; admin load failure doesn't connect; prompt expiry timer; dismiss; commands and `pendingRequests`; error surfacing and dismissal |
| `bloc/history_bloc_test.dart` | load then live prepend with de-duplication; reset; reload on second snapshot; failure |
| `bloc/placement_cubit_test.dart` | 1-click rider and 2-click package flows; idle taps ignored; cancel |
| `ui/widgets_test.dart` | prompt text names the package and rider ids, dismiss dispatches the event, "+N more" overflow; side panel lists and remove button; history tab |
| `ui/radar_layer_test.dart` | radar animates while packages wait, idles when none do, and stays static with reduced motion |

## Manual end-to-end check

With the emulator, the API and the web app running:

1. **Simulate** 10 packages / 6 riders. Some prompts appear, and the side panel counts equal
   waiting + available.
2. **Add Rider → Pick on map** inside a package's radar disk. A prompt names both ids, and the items
   leave the map and panel.
3. Open a second tab and add an item in the first: it appears in both.
4. Stop the API: the badge shows **Reconnecting…**. Start it again: the badge shows **Live**
   and the state resyncs.
5. **Reset**: everything clears in both tabs; the admin stays.

This check was also scripted with headless Chrome during development. The screenshots in
`docs/images/` come from those runs.

## CI

`.github/workflows/ci.yml` runs on pushes to `main` and on pull requests:

- **backend:** uv sync → ruff (lint + format) → pytest inside `firebase emulators:exec`, so all 103 run
- **frontend:** format check → analyze → test → `flutter build web`
