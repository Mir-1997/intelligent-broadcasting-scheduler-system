# Roadmap: what could come next

Ordered roughly by value for this project.

## Matching

- **Broadcast mode (like the production engine).** Instead of instant assignment, offer a
  package to every rider within an initial radius and let the first to accept win. If nobody
  accepts, widen the radius on each retry up to `max_retry × multiplier`.
  - How to fit it in: a `MatchingStrategy` interface with `InstantNearest` (today) and
    `Broadcast`, plus new events `broadcast.offered`, `broadcast.accepted` and
    `broadcast.expired`, and a retry scheduler (an asyncio task locally, Cloud Tasks in prod).
  - The UI would show an "offers" state on riders with accept/reject buttons that simulate
    the rider app.
- **Re-matching waiting items** when the radius is changed at runtime, or on a periodic sweep.
- **Road distance or ETA** via a routing API (Google Distance Matrix, OSRM). Use haversine to
  pre-filter, then rank the top-k candidates by ETA.
- **Fairness and scoring:** weight distance against rider idle time, vehicle capacity or
  package priority.

## Scale

- **Geohash queries** so each arrival reads only nearby candidates ([matching-algorithm.md §6](matching-algorithm.md#6-scaling-the-candidate-search)).
- **Multiple API instances:** replace the in-process `EventHub` with a Firestore `on_snapshot`
  listener per instance, or Redis/Google Pub/Sub fan-out. See [ADR 0002](adr/0002-realtime-websockets.md#scaling-beyond-one-process).
- **Event ids / sequence numbers** so a reconnecting client can resume from an offset instead
  of taking a full snapshot.

## Product

- **Moving riders:** `PATCH /riders/{id}/location`, plus a simulator that animates riders along
  routes. Re-run matching when a waiting rider moves into range.
- **Delivery lifecycle** after assignment: picked up → in transit → delivered, with the rider
  becoming available again (the production engine's `PackageStatusType`).
- **Auth:** Firebase Auth ID tokens checked by a FastAPI dependency, and on the WebSocket via
  a `?token=` query parameter or a first-message handshake.
- **Admin editing in the UI:** drag the admin pin to call `PUT /admin`.
- **Reverse geocoding** so map clicks fill in real addresses.
- **Metrics panel:** average match distance, wait times, match rate.
