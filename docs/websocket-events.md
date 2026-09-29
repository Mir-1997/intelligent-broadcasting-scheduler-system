# WebSocket event contract: `/ws/scheduler`

This is how the frontend learns that a package or rider was added, removed or paired.

```
ws://localhost:8000/ws/scheduler      (wss:// behind TLS)
```

## Protocol

1. The client connects. There are no query parameters and no auth (see [roadmap](roadmap.md)).
2. The server's **first message is always `scheduler.snapshot`**, the complete current state.
3. Every later message is a **delta event**, in the order the server committed the changes.
4. The client *may* send the text frame `ping`; the server answers `pong`. The Flutter client
   pings every 25 s so idle proxies don't close the connection. Any other client text is
   ignored.
5. When the client reconnects, it gets a fresh snapshot. The client should **replace** its
   state with it.

Server close codes: normal closure, or **1013** ("try again later") if the client fell
more than `WEBSOCKET_QUEUE_SIZE` (default 1000) events behind. Reconnect when you get it.

## Envelope

Every message except `pong` is a JSON text frame:

```json
{
  "type": "assignment.created",
  "data": { "...": "type-specific payload" },
  "timestamp": "2026-09-23T06:20:26.222Z"
}
```

`timestamp` is when the server published the event (UTC, ISO-8601).

## Event catalogue

| `type` | `data` | Sent when | Client action |
|---|---|---|---|
| `scheduler.snapshot` | `SchedulerState`: `{admin, packages[], riders[], max_match_radius_miles}` (only *waiting* packages and *available* riders) | first message on every connection | replace all state |
| `package.added` | `{package: Package}` | `POST /packages` (also during `/simulate`) | if `status == "waiting"`, add it; if `"assigned"`, ignore it (an `assignment.created` follows) |
| `package.removed` | `{package_id}` | `DELETE /packages/{id}` | remove it |
| `rider.added` | `{rider: Rider}` | `POST /riders` | if `status == "available"`, add it; otherwise ignore |
| `rider.removed` | `{rider_id}` | `DELETE /riders/{id}` | remove it |
| `assignment.created` | `{assignment: Assignment}` | a pairing happened | remove `package_id` and `rider_id` from the scheduler, show the prompt, prepend to history |
| `admin.updated` | `{admin: Admin}` | `PUT /admin` | update the map centre |
| `scheduler.reset` | `{}` | `POST /scheduler/reset` | clear packages, riders and history |

Schemas for `Package`, `Rider`, `Assignment` and `Admin` are in
[api-reference.md](api-reference.md#schemas) and [data-model.md](data-model.md).

## Ordering and idempotency

- For a single write, events arrive in this order: **`*.added` first, then
  `assignment.created`** if the item paired.
- **Why is an instantly-paired item still announced with `*.added`?** So that every creation
  is observable, e.g. for logging or future "flash on arrival" effects. Clients that only
  render the scheduler just skip non-waiting items.
- Around (re)connect, an event may duplicate information already in the snapshot. The
  reference reducer (`reduceServerEvent` in `frontend/lib/bloc/scheduler/scheduler_bloc.dart`)
  is idempotent:
  - adds are upserts keyed by id
  - removes of a missing id do nothing
  - assignments are de-duplicated by id
- Unknown `type`s must be ignored (the Flutter client maps them to `UnknownEvent`), so the
  server can add event types without breaking older clients.

## Example session

```text
← {"type":"scheduler.snapshot","data":{"admin":{"name":"Admin HQ","location":{"lat":40.758,"lng":-73.9855}},"packages":[],"riders":[],"max_match_radius_miles":5.0},"timestamp":"…"}

   (someone POSTs a rider, then a package 0.77 mi away)

← {"type":"rider.added","data":{"rider":{"id":"rdr_c14661b1","name":"Ali","status":"available",…}},"timestamp":"…"}
← {"type":"package.added","data":{"package":{"id":"pkg_ff2b6b8f","status":"assigned","assigned_rider_id":"rdr_c14661b1",…}},"timestamp":"…"}
← {"type":"assignment.created","data":{"assignment":{"id":"asg_f09805ff","package_id":"pkg_ff2b6b8f","rider_id":"rdr_c14661b1","rider_name":"Ali","distance_miles":0.768,"trigger":"package_added",…}},"timestamp":"…"}

→ ping
← pong
```

## Trying it from a terminal

```sh
# Python (the `websockets` package comes with uvicorn[standard])
cd backend && uv run python -c "
import asyncio, websockets
async def main():
    async with websockets.connect('ws://localhost:8000/ws/scheduler') as ws:
        async for message in ws:
            print(message)
asyncio.run(main())"
```

Then, in another terminal, `curl -X POST localhost:8000/simulate -H 'content-type: application/json' -d '{}'`.
