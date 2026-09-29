import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/models.dart';
import '../geo_shapes.dart';
import 'clock_builder.dart';

/// One waiting package on the radar.
class RadarTarget {
  const RadarTarget({
    required this.id,
    required this.center,
    required this.since,
  });

  /// Stable id, used to stagger the animation phase.
  final String id;
  final LatLng center;

  /// When the package started waiting; its radius grows from here.
  final DateTime since;
}

/// Breathing "radar" disks around waiting packages, showing they are actively
/// searching for a rider within their current search radius.
///
/// Each disk's size follows [policy] (it widens the longer the package waits)
/// and eases outward with a brief edge flash when it grows. The fill breathes
/// and a sonar ring sweeps from the pickup to the edge. Phases are staggered
/// per package so the map feels alive rather than blinking in unison. With
/// reduced motion enabled (OS setting), disks are static and jump in size.
class RadarLayer extends StatefulWidget {
  const RadarLayer({
    required this.targets,
    required this.policy,
    required this.color,
    this.period = const Duration(milliseconds: 2800),
    this.clock = DateTime.now,
    super.key,
  });

  final List<RadarTarget> targets;
  final RadiusPolicy policy;
  final Color color;

  /// Length of one breath / one sonar sweep.
  final Duration period;

  /// Injectable for tests.
  final DateTime Function() clock;

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
    final shouldRun = widget.targets.isNotEmpty && !_reduceMotion;
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
    final animate = !_reduceMotion;
    Widget paint(BuildContext context) => CustomPaint(
      size: camera.size,
      painter: _RadarPainter(
        camera: camera,
        targets: widget.targets,
        policy: widget.policy,
        clock: widget.clock,
        color: widget.color,
        animation: _controller,
        animate: animate,
      ),
    );
    return MobileLayerTransformer(
      // Static disks still need to grow: repaint them once a second.
      child: animate || widget.targets.isEmpty
          ? paint(context)
          : ClockBuilder(clock: widget.clock, builder: (ctx, _) => paint(ctx)),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.camera,
    required this.targets,
    required this.policy,
    required this.clock,
    required this.color,
    required this.animation,
    required this.animate,
  }) : super(repaint: animation);

  final MapCamera camera;
  final List<RadarTarget> targets;
  final RadiusPolicy policy;
  final DateTime Function() clock;
  final Color color;
  final Animation<double> animation;
  final bool animate;

  static const _distance = Distance();

  /// How long a disk takes to ease out to its new size after growing.
  static const _growDuration = Duration(milliseconds: 900);

  @override
  void paint(Canvas canvas, Size size) {
    final now = clock();
    for (final target in targets) {
      final center = target.center;
      final current = policy.radiusAt(target.since, now);
      final (:previous, :sinceGrowth) = policy.lastGrowth(target.since, now);
      // 0 -> 1 over the moments after an expansion; 1 when settled.
      final growth = animate
          ? Curves.easeOutCubic.transform(
              (sinceGrowth.inMicroseconds / _growDuration.inMicroseconds).clamp(
                0.0,
                1.0,
              ),
            )
          : 1.0;
      final miles = previous + (current - previous) * growth;

      final c = camera.getOffsetFromOrigin(center);
      // Pixel radius from a point on the true geodesic edge (correct at any
      // latitude and zoom under Web Mercator).
      final edge = _distance.offset(center, miles * metersPerMile, 90);
      final r = (camera.getOffsetFromOrigin(edge) - c).distance;
      if (r < 1) continue;

      // Staggered phase in [0, 1) per package.
      final phase = animate
          ? (animation.value + _phaseOffset(target.id)) % 1.0
          : 0.0;
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

      // Crisp edge so the match range reads clearly against busy tiles; it
      // flashes brighter and thicker right after the radius grows.
      final flash = current > previous ? 1 - growth : 0.0;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 + 2.5 * flash
          ..color = color.withValues(
            alpha: math.min(1, 0.35 + 0.15 * breath + 0.5 * flash),
          ),
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
      old.targets != targets ||
      old.policy != policy ||
      !animate || // static disks repaint on the once-a-second tick
      old.color != color ||
      old.animate != animate;
}
