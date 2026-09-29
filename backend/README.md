# Backend: FastAPI scheduler service

```sh
uv sync
uv run fastapi dev src/broadcast_scheduler/main.py      # needs the Firestore emulator on :8080
STORAGE_BACKEND=memory uv run fastapi dev src/broadcast_scheduler/main.py   # no emulator
uv run pytest
```

- Swagger UI: <http://localhost:8000/docs>
- Configuration: [`.env.example`](.env.example) and [docs/setup.md](../docs/setup.md)
- Design: [docs/architecture.md](../docs/architecture.md), [docs/matching-algorithm.md](../docs/matching-algorithm.md)
- API: [docs/api-reference.md](../docs/api-reference.md), [docs/websocket-events.md](../docs/websocket-events.md)
