# ADR 0001: Firestore is the only datastore; proximity is computed in the app

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

The production `scheduler_engine` keeps live riders and packages in **Redis** and finds
neighbours with `GEORADIUS`, with Firestore/other services as the system of record. For this
project the requirement is "use Firestore for storage". Firestore has **no native geo
radius query**.

## Decision

Use **Firestore only**. For each arrival, read the candidates of the opposite kind
(`status == available/waiting`) inside a transaction and pick the nearest in Python with
haversine (`geo.find_nearest`).

## Consequences

- One datastore to run, emulate and reason about. Local development needs only the Firebase
  emulator.
- **Firestore transactions** give race-free pairing without Redis `WATCH`/`MULTI` retry loops
  ([matching-algorithm.md §5](../matching-algorithm.md#5-atomicity-why-no-rider-is-ever-double-assigned)).
- Cost is O(n) reads per arrival. That's fine for this project's scale. Geohash-bounded queries
  are the planned fix if it grows, and they only touch the repository.
- An `InMemorySchedulerRepository` implements the same protocol for tests and for running
  without the emulator.
