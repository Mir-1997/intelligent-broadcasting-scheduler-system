# ADR 0002: FastAPI WebSockets for realtime, with a snapshot on every connect

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

The map must learn immediately when a package or rider is added, removed or paired. The
options considered:

| Option | Verdict |
|---|---|
| **FastAPI WebSocket** | ✅ chosen: the backend stays the only interface; it maps naturally to a `Stream` feeding a bloc |
| Server-Sent Events | server→client only, and weaker Flutter support |
| Flutter listening to Firestore directly | bypasses the API, and the spec says the map gets its data from API calls |
| Polling | not realtime, and wasteful |

## Decision

- Endpoint `/ws/scheduler`. **First message = full `scheduler.snapshot`**, then delta events.
- `SchedulerService` publishes an event after every successful write. `EventHub` fans it out to
  per-connection bounded `asyncio.Queue`s, so a slow client can never block a request. A
  client that overflows is closed with 1013 and resyncs on reconnect.
- Order inside the endpoint: **subscribe → read and send snapshot → start draining the
  queue**. This closes the gap in which an event could otherwise be lost.
- Clients must reduce events idempotently and replace state on each snapshot.

## Consequences

- Reconnects are simple and always correct: throw away the state and apply the new snapshot.
- There are no event ids or replay; a full snapshot is cheap at this scale.
- **Single process only**: the hub is in memory. The Dockerfile and `run()` pin one worker.

## Scaling beyond one process

Replace "publish from the service" with "publish from change notifications":

1. Each API instance opens Firestore `on_snapshot` listeners on `packages`, `riders` and
   `assignments`, translates document changes into the same events, and feeds its local
   `EventHub`. As a bonus, writes made outside the API (the console, scripts) also stream to
   clients. **Or**
2. Publish to Redis pub/sub or Google Pub/Sub and have every instance subscribe.

Either way the WebSocket contract ([websocket-events.md](../websocket-events.md)) stays the same.
