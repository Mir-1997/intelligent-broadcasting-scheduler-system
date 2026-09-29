import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../geo_shapes.dart';

/// Breathing "radar" disks around waiting packages, showing they are actively
/// searching for a rider within [radiusMiles].
///
/// Each disk is a soft translucent fill whose opacity breathes in and out,
/// with a sonar ring sweeping from the pickup to the edge of the match range.
/// Phases are staggered per package so the map feels alive rather than
/// blinking in unison. With reduced motion enabled (OS setting), disks are static.
class RadarLayer extends StatefulWidget {
  const RadarLayer({
    required this.centers,
    required this.radiusMiles,
    required this.color,
    this.period = const Duration(milliseconds: 2800),
    super.key,
  });

  /// One entry per waiting package: a stable id (for the phase) and its pickup.
  final Map<String, LatLng> centers;
  final double radiusMiles;
  final Color color;

  /// Length of one breath / one sonar sweep.
  final Duration period;

  @override
  State<RadarLayer> createState() => _RadarLayerState();
}

class _RadarLayerState extends State<RadarLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(RadarLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  /// Only tick while there is something to animate.
  void _syncAnimation() {
    final shouldRun = widget.centers.isNotEmpty && !_reduceMotion;
    if (shouldRun && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldRun && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: CustomPaint(
        size: camera.size,
        painter: _RadarPainter(
          camera: camera,
          centers: widget.centers,
          radiusMeters: widget.radiusMiles * metersPerMile,
          color: widget.color,
          animation: _controller,
          animate: !_reduceMotion,
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.camera,
    required this.centers,
    required this.radiusMeters,
    required this.color,
    required this.animation,
    required this.animate,
  }) : super(repaint: animation);

  final MapCamera camera;
  final Map<String, LatLng> centers;
  final double radiusMeters;
  final Color color;
  final Animation<double> animation;
  final bool animate;

  static const _distance = Distance();

  @override
  void paint(Canvas canvas, Size size) {
    for (final MapEntry(key: id, value: center) in centers.entries) {
      final c = camera.getOffsetFromOrigin(center);
      // Pixel radius from a point on the true geodesic edge (correct at any
      // latitude and zoom under Web Mercator).
      final edge = _distance.offset(center, radiusMeters, 90);
      final r = (camera.getOffsetFromOrigin(edge) - c).distance;
      if (r < 1) continue;

      // Staggered phase in [0, 1) per package.
      final phase = animate ? (animation.value + _phaseOffset(id)) % 1.0 : 0.0;
      final breath = animate ? 0.5 - 0.5 * math.cos(2 * math.pi * phase) : 0.5;

      // 1. Base disk: soft fill with a slightly darker core, breathing.
      final baseAlpha = 0.14 + 0.10 * breath;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: baseAlpha + 0.06),
              color.withValues(alpha: baseAlpha),
              color.withValues(alpha: baseAlpha * 0.75),
            ],
            stops: const [0, 0.7, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );

      // Crisp edge so the match range reads clearly against busy tiles.
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: 0.35 + 0.15 * breath),
      );

      if (!animate) continue;

      // 2. Sonar ring sweeping outward, easing out and fading as it travels.
      final t = Curves.easeOut.transform(phase);
      final ringRadius = r * t;
      final fade = 1 - t;
      canvas.drawCircle(
        c,
        ringRadius,
        Paint()..color = color.withValues(alpha: 0.16 * fade),
      );
      canvas.drawCircle(
        c,
        ringRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color.withValues(alpha: 0.85 * fade),
      );
    }
  }

  static double _phaseOffset(String id) => (id.hashCode & 0x3ff) / 1024;

  // Purely decorative: never swallow pointer events meant for the map.
  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.camera != camera ||
      old.centers != centers ||
      old.radiusMeters != radiusMeters ||
      old.color != color ||
      old.animate != animate;
}
