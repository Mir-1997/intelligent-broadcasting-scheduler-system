import 'package:flutter/material.dart';

/// A circular map pin with an icon and a hover tooltip.
class MapPin extends StatelessWidget {
  const MapPin({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.size = 34,
    this.filled = true,
    super.key,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 150),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled ? color : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: filled ? Colors.white : color, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: size * 0.55,
          color: filled ? Colors.white : color,
        ),
      ),
    );
  }
}

/// A pin that pulses once when it appears; used for fresh assignments.
class PulsingPin extends StatelessWidget {
  const PulsingPin({required this.child, required this.color, super.key});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      builder: (context, t, child) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 34 + 30 * t,
            height: 34 + 30 * t,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.35 * (1 - t)),
            ),
          ),
          child!,
        ],
      ),
      child: child,
    );
  }
}
