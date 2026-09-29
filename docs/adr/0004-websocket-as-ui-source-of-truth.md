# ADR 0004: UI state comes only from WebSocket events

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

`POST /packages` returns the created package and any assignment. The same facts also arrive
as `package.added` / `assignment.created` on the socket. Applying both creates questions: what
if the response arrives before, or after, the events? What if the same assignment shows up
twice?

## Decision

The frontend treats REST as **commands and one-off reads** (`GET /admin`, `GET /assignments`).
It **never** applies a command's response to live state. `SchedulerBloc` changes the map and
side panel only by reducing WebSocket events (`reduceServerEvent`).

## Consequences

- **One code path** updates the UI, the same for the tab that issued the command and for
  every other tab. There are no duplicate-merging rules.
- While the socket is down, commands still succeed, but their effects appear only after the
  reconnect snapshot. The connection badge makes that state visible ("Reconnecting…").
- Command failures (404/409/422/network) still surface immediately through `errorMessage`
  and a SnackBar.
