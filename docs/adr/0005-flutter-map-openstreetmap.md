# ADR 0005: flutter_map with OpenStreetMap; custom circle and line rendering on web

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

The app targets **Flutter web only**. `google_maps_flutter` needs an API key and billing,
and its web support wraps the JS SDK. `flutter_map` is pure Flutter and needs no key when
used with OpenStreetMap tiles.

While building the map, an end-to-end check with headless Chrome showed that on Flutter web
(3.41, CanvasKit), **`CircleLayer` with metre radii and `PolylineLayer` from flutter_map 8.3
rendered nothing**. The same layers render correctly on the Dart VM (confirmed with a golden
test). `PolygonLayer` and markers worked on web.

## Decision

- Use `flutter_map` + OSM tiles.
- Draw the 5-mile match radius with **`RadarLayer`**, a `CustomPainter` using `drawCircle`
  (pixel radius taken from a geodesic edge point). It is animated as a breathing radar disk.
  An earlier version used a `PolygonLayer` of 72 geodesic vertices; the painter replaced it
  so the disk could be animated cheaply.
- Draw pickup→drop-off and rider→pickup lines with **`MapLinesLayer`**, a small
  `CustomPainter` that projects through `MapCamera.getOffsetFromOrigin` inside
  `MobileLayerTransformer`, like flutter_map's own layers do.

## Consequences

- No API keys, and the rendering works on every platform.
- The circles are geodesically accurate at any zoom level, and animating them costs one
  repaint of one layer per frame.
- If a future flutter_map release fixes the web issue, both workarounds can be swapped back in
  a few lines each (they are isolated in `ui/widgets/radar_layer.dart` and `ui/widgets/map_lines_layer.dart`).
- OSM's public tile servers have a usage policy; production use should switch tile provider
  ([setup.md](../setup.md#production-notes)).
