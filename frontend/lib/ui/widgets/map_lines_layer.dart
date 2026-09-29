import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// A straight line between two coordinates.
class MapLine {
  const MapLine({
    required this.from,
    required this.to,
    required this.color,
    this.width = 3,
    this.dashed = false,
  });

  final LatLng from;
  final LatLng to;
  final Color color;
  final double width;
  final bool dashed;
}

/// Draws [MapLine]s with plain `drawLine` calls.
///
/// Stands in for flutter_map's `PolylineLayer`, whose painter (saveLayer +
/// blend modes) drew nothing on Flutter web in our testing. Our lines are
/// short two-point segments, so a minimal painter is enough.
class MapLinesLayer extends StatelessWidget {
  const MapLinesLayer({required this.lines, super.key});

  final List<MapLine> lines;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        size: camera.size,
        painter: _LinesPainter(lines, camera),
      ),
    );
  }
}

class _LinesPainter extends CustomPainter {
  _LinesPainter(this.lines, this.camera);

  final List<MapLine> lines;
  final MapCamera camera;

  static const _dash = 7.0;
  static const _gap = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      final paint = Paint()
        ..color = line.color
        ..strokeWidth = line.width
        ..strokeCap = StrokeCap.round;
      final a = camera.getOffsetFromOrigin(line.from);
      final b = camera.getOffsetFromOrigin(line.to);
      if (!line.dashed) {
        canvas.drawLine(a, b, paint);
        continue;
      }
      final length = (b - a).distance;
      if (length == 0) continue;
      final step = (b - a) / length;
      for (var d = 0.0; d < length; d += _dash + _gap) {
        canvas.drawLine(
          a + step * d,
          a + step * math.min(d + _dash, length),
          paint,
        );
      }
    }
  }

  // Purely decorative: never swallow pointer events meant for the map.
  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_LinesPainter old) =>
      old.lines != lines || old.camera != camera;
}
