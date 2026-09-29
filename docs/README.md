# Documentation

Read in this order if you're new to the project:

1. [architecture.md](architecture.md): how the pieces fit together, with sequence diagrams
2. [matching-algorithm.md](matching-algorithm.md): the core rule and why it is race-free
3. [websocket-events.md](websocket-events.md): how the frontend learns about changes
4. [api-reference.md](api-reference.md): REST endpoints
5. [data-model.md](data-model.md): what is stored in Firestore
6. [frontend.md](frontend.md): the Flutter/BLoC side
7. [setup.md](setup.md): configuration, deployment options, troubleshooting
8. [testing.md](testing.md): the test strategy

Decisions and their reasons are in [adr/](adr/):

| ADR | Decision |
|---|---|
| [0001](adr/0001-firestore-only-storage.md) | Firestore only; proximity is computed in the app |
| [0002](adr/0002-realtime-websockets.md) | FastAPI WebSockets for realtime; snapshot on connect |
| [0003](adr/0003-instant-nearest-pairing.md) | Instant nearest pairing instead of broadcast/accept |
| [0004](adr/0004-websocket-as-ui-source-of-truth.md) | UI state comes only from the socket, not REST responses |
| [0005](adr/0005-flutter-map-openstreetmap.md) | `flutter_map` + OpenStreetMap; custom circle/line layers on web |

Ideas for what's next: [roadmap.md](roadmap.md).
