import 'package:flutter/material.dart';

/// Colours with meaning, used consistently across map markers, lists and prompts.
abstract final class SchedulerColors {
  static const admin = Color(0xFF6A1B9A);
  static const package = Color(0xFFE65100);
  static const rider = Color(0xFF1565C0);
  static const assignment = Color(0xFF2E7D32);
  static const dropoff = Color(0xFF616161);

  /// Deep slate used for the breathing match-radius disks.
  static const radar = Color(0xFF37474F);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3949AB));
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
  );
}
