# ADR 0003: Instant nearest pairing, rather than broadcast/accept

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

The production engine *broadcasts* a package to several riders within a radius, waits for
accept/reject, and widens the radius on retries (Cloud Tasks). This project is about
**visualising** a scheduler, and the brief is: "whenever we add a package, it will be paired
to the nearest rider and both are removed from the scheduler".

## Decision

- A new package pairs instantly with the nearest **available** rider to its **pickup**. A new
  rider pairs instantly with the nearest **waiting** pickup. Both directions are supported.
- Distance: **haversine**, max **5 miles** (`MAX_MATCH_RADIUS_MILES`). If nothing is in range,
  the item waits.
- Ties go to the oldest candidate (first come, first served).
- Paired items are kept with status `assigned` (not deleted), and an `Assignment` record is
  written for the history panel.

## Consequences

- The behaviour is deterministic and easy to follow on a map.
- There's no rider-side decision, retries or offer expiry. These are listed in
  [roadmap.md](../roadmap.md) as a `MatchingStrategy` extension. The pure `matching.py` module
  and the repository boundary were designed so a broadcast strategy can be added without
  touching the API or the UI contract.
