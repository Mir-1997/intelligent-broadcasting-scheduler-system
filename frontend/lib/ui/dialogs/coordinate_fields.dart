import 'package:flutter/material.dart';

import '../../data/models/models.dart';

/// Validated latitude/longitude text fields, shared by the add dialogs.
class CoordinateFields extends StatelessWidget {
  const CoordinateFields({
    required this.latController,
    required this.lngController,
    this.label,
    super.key,
  });

  final TextEditingController latController;
  final TextEditingController lngController;
  final String? label;

  static String? _validate(String? value, double limit) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'Enter a number';
    if (parsed < -limit || parsed > limit) return 'Must be within ±$limit';
    return null;
  }

  /// Reads the two controllers; call only after the form validated.
  static Coordinates read(
    TextEditingController lat,
    TextEditingController lng,
  ) => Coordinates(
    lat: double.parse(lat.text.trim()),
    lng: double.parse(lng.text.trim()),
  );

  @override
  Widget build(BuildContext context) {
    const keyboard = TextInputType.numberWithOptions(
      signed: true,
      decimal: true,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: latController,
            decoration: InputDecoration(
              labelText: '${label ?? ''} latitude'.trim(),
            ),
            keyboardType: keyboard,
            validator: (v) => _validate(v, 90),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: lngController,
            decoration: InputDecoration(
              labelText: '${label ?? ''} longitude'.trim(),
            ),
            keyboardType: keyboard,
            validator: (v) => _validate(v, 180),
          ),
        ),
      ],
    );
  }
}

TextEditingController coordinateController(double value) =>
    TextEditingController(text: value.toStringAsFixed(6));
