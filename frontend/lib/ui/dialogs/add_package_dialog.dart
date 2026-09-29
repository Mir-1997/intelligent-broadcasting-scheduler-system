import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import 'coordinate_fields.dart';

/// Collects a [PackageDraft] (pickup + drop-off, each with optional address).
class AddPackageDialog extends StatefulWidget {
  const AddPackageDialog({
    required this.pickup,
    required this.dropoff,
    super.key,
  });

  final Coordinates pickup;
  final Coordinates dropoff;

  static Future<PackageDraft?> show(
    BuildContext context, {
    required Coordinates pickup,
    required Coordinates dropoff,
  }) => showDialog<PackageDraft>(
    context: context,
    builder: (_) => AddPackageDialog(pickup: pickup, dropoff: dropoff),
  );

  @override
  State<AddPackageDialog> createState() => _AddPackageDialogState();
}

class _AddPackageDialogState extends State<AddPackageDialog> {
  final _form = GlobalKey<FormState>();
  late final _pickupLat = coordinateController(widget.pickup.lat);
  late final _pickupLng = coordinateController(widget.pickup.lng);
  late final _dropoffLat = coordinateController(widget.dropoff.lat);
  late final _dropoffLng = coordinateController(widget.dropoff.lng);
  final _pickupAddress = TextEditingController();
  final _dropoffAddress = TextEditingController();

  @override
  void dispose() {
    for (final c in [
      _pickupLat,
      _pickupLng,
      _dropoffLat,
      _dropoffLng,
      _pickupAddress,
      _dropoffAddress,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Place _place(
    TextEditingController lat,
    TextEditingController lng,
    TextEditingController address,
  ) {
    final point = CoordinateFields.read(lat, lng);
    return Place(lat: point.lat, lng: point.lng, address: address.text.trim());
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(
      PackageDraft(
        pickup: _place(_pickupLat, _pickupLng, _pickupAddress),
        dropoff: _place(_dropoffLat, _dropoffLng, _dropoffAddress),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heading = Theme.of(context).textTheme.titleSmall;
    return AlertDialog(
      title: const Text('Add package'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pickup (used for matching)', style: heading),
              const SizedBox(height: 8),
              TextFormField(
                controller: _pickupAddress,
                autofocus: true,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Address (optional)',
                ),
              ),
              CoordinateFields(
                latController: _pickupLat,
                lngController: _pickupLng,
              ),
              const SizedBox(height: 20),
              Text('Drop-off', style: heading),
              const SizedBox(height: 8),
              TextFormField(
                controller: _dropoffAddress,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Address (optional)',
                ),
              ),
              CoordinateFields(
                latController: _dropoffLat,
                lngController: _dropoffLng,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add package')),
      ],
    );
  }
}
