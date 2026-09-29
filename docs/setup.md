# Setup and configuration

## Prerequisites

| Tool | Version used | For |
|---|---|---|
| Python | 3.12 | backend |
| [uv](https://docs.astral.sh/uv/) | 0.12 | backend dependencies (`brew install uv`) |
| Flutter | 3.41 (Dart 3.11) | frontend |
| Firebase CLI | 13+ | Firestore emulator (`npm i -g firebase-tools`) |
| Java | 21+ | required by the emulator |
| Docker | optional | `docker compose up` |
| Chrome | any recent | running the web app |

## Local development

```sh
# Terminal 1: Firestore emulator. Emulator UI at http://localhost:4000
firebase emulators:start --only firestore --project demo-broadcast-scheduler

# Terminal 2: API with auto-reload at http://localhost:8000 (docs at /docs)
cd backend
uv sync
uv run fastapi dev src/broadcast_scheduler/main.py

# Terminal 3: web app with hot reload
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

`firebase.json` pins the emulator to port 8080 and the emulator UI to port 4000. The project
id `demo-broadcast-scheduler` uses Firebase's `demo-` convention: it needs no real project or
login and can never reach production.

The emulator keeps data in memory. To keep data between runs, add
`--import=./.emulator-data --export-on-exit`.

### Without the emulator

```sh
STORAGE_BACKEND=memory uv run fastapi dev src/broadcast_scheduler/main.py
```

This uses the same API, events and matching rules, backed by an in-process store that is
cleared on restart.

## Configuration reference (backend)

Settings come from `backend/.env` (copy `backend/.env.example`) and environment variables.
Names are case-insensitive. Precedence: `backend/.env` > environment > defaults. Without a
`.env` (Docker, CI), plain environment variables apply.

| Variable | Default | Description |
|---|---|---|
| `STORAGE_BACKEND` | `firestore` | `firestore` or `memory` |
| `FIRESTORE_EMULATOR_HOST` | `localhost:8080` | Emulator address. **Set it to an empty string to use a real project.** |
| `GCP_PROJECT_ID` | `demo-broadcast-scheduler` | Firebase / GCP project id |
| `GOOGLE_APPLICATION_CREDENTIALS` | *(unset)* | Service-account key path for a real project; unset means Application Default Credentials |
| `FIRESTORE_DATABASE` | `(default)` | Named Firestore database |
| `COLLECTION_PREFIX` | *(empty)* | Prefix for every collection |
| `MAX_MATCH_RADIUS_MILES` | `5` | Pairing radius |
| `ADMIN_NAME` / `ADMIN_LAT` / `ADMIN_LNG` | `Admin HQ` / `40.7580` / `-73.9855` | Admin seed, used only if `admin/default` doesn't exist yet |
| `CORS_ORIGINS` | `["*"]` | JSON list of allowed browser origins |
| `WEBSOCKET_QUEUE_SIZE` | `1000` | Undelivered events per socket before that client is dropped |

Changing `ADMIN_*` after the first run has no effect, because the document already exists.
Use `PUT /admin` instead, or delete `admin/default`.

## Using a real Firebase project

> **Use a project (or a named database) that is not your production data.** The collections
> are called `admin`, `packages`, `riders` and `assignments`, and `POST /scheduler/reset`
> deletes **every document** in the last three. If you share a project with another app, set
> a `COLLECTION_PREFIX` (e.g. `ibs_`) or a separate `FIRESTORE_DATABASE`.

1. In the [Firebase console](https://console.firebase.google.com), create or pick a project,
   then open **Build → Firestore Database → Create database** (Native mode). To isolate this
   app inside an existing project, create an extra *named* database (e.g. `scheduler`) and set
   `FIRESTORE_DATABASE=scheduler`.
2. Credentials: **Project settings → Service accounts → Generate new private key**. Save the
   JSON somewhere outside the repo. The default `firebase-adminsdk` account can already read
   and write Firestore.
3. Create `backend/.env`:

   ```ini
   FIRESTORE_EMULATOR_HOST=
   GCP_PROJECT_ID=your-project-id
   FIRESTORE_DATABASE=(default)
   COLLECTION_PREFIX=ibs_
   GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/your-key.json
   # ADMIN_NAME=... ADMIN_LAT=... ADMIN_LNG=...   (seeded once, on first start)
   ```

   `FIRESTORE_EMULATOR_HOST=` must be present and **empty**; otherwise the app uses the emulator.

   `backend/.env` **takes precedence over** variables exported by your shell, so a
   `GOOGLE_APPLICATION_CREDENTIALS` or `GCP_PROJECT_ID` set in `~/.zshrc` for another project
   can't leak in. The file is found from any working directory.

4. Run it and check the startup log line:

   ```sh
   cd backend
   uv run fastapi dev src/broadcast_scheduler/main.py
   # INFO ... Firestore: REAL project, project=your-project-id, database=(default), collection_prefix='ibs_'
   ```

5. Optional: deploy the deny-all client rules with
   `firebase deploy --only firestore:rules --project your-project-id` (skip this on a shared
   project, because it replaces that project's existing rules).

No composite indexes are needed (see [data-model.md](data-model.md#queries-and-indexes)).
With Docker Compose, put the same variables under the `api` service and mount the key file.

## Docker Compose

```sh
docker compose up --build
```

| Service | Port | Image |
|---|---|---|
| `firestore` | 8080 | `gcr.io/google.com/cloudsdktool/google-cloud-cli:emulators` |
| `api` | 8000 | `backend/Dockerfile` (python:3.12-slim + uv, one uvicorn worker) |
| `web` | 8081 | `frontend/Dockerfile` (Flutter build → nginx) |

`API_BASE_URL` is a **build argument** of `web`, because it is compiled into the JS bundle
and used by *the browser*. Keep it `http://localhost:8000` locally. For a deployment, set it
to the public API URL and rebuild.

## Production notes

- Run the API with **exactly one worker** (the WebSocket hub is in-process; see
  [ADR 0002](adr/0002-realtime-websockets.md)).
- Put it behind a proxy that supports WebSockets (nginx needs `proxy_http_version 1.1` and the
  `Upgrade`/`Connection` headers). The client's 25 s ping keeps idle-timeout proxies happy.
- Restrict `CORS_ORIGINS`, and add auth before exposing it publicly (see [roadmap.md](roadmap.md)).
- OpenStreetMap's public tile servers have a
  [usage policy](https://operations.osmfoundation.org/policies/tiles/). For anything beyond
  personal use, switch `urlTemplate` in `scheduler_map.dart` to a tile provider.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| UI stuck on "Could not reach the scheduler server" | The API isn't running, or `API_BASE_URL` is wrong. Check `curl localhost:8000/health`. |
| Badge shows **Reconnecting…** | The WebSocket can't connect. Check the API logs; a proxy may be stripping `Upgrade` headers. |
| API errors or hangs at startup | `FIRESTORE_EMULATOR_HOST` points to an emulator that isn't running. Start it, or use `STORAGE_BACKEND=memory`. |
| `DefaultCredentialsError` | You're targeting a real project without credentials. Set `GOOGLE_APPLICATION_CREDENTIALS`, or keep using the emulator. |
| Emulator won't start: port 8080 in use | Another process has the port. Change `emulators.firestore.port` in `firebase.json` and `FIRESTORE_EMULATOR_HOST` to match. |
| Edits made in the emulator UI don't appear | Only writes through the API emit events. Reload the page to resync (see architecture "Known limits"). |
| Admin location didn't change after editing `.env` | The seed only applies to an empty database. Use `PUT /admin`. |
