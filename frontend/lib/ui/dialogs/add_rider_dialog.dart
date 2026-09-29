import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import 'coordinate_fields.dart';

/// Collects a [RiderDraft]. Pre-filled with [initial] (a map click, or the admin).
class AddRiderDialog extends StatefulWidget {
  const AddRiderDialog({required this.initial, super.key});

  final Coordinates initial;

  static Future<RiderDraft?> show(BuildContext context, Coordinates initial) =>
      showDialog<RiderDraft>(
        context: context,
        builder: (_) => AddRiderDialog(initial: initial),
      );

  @override
  State<AddRiderDialog> createState() => _AddRiderDialogState();
}

class _AddRiderDialogState extends State<AddRiderDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _lat = coordinateController(widget.initial.lat);
  late final _lng = coordinateController(widget.initial.lng);

  @override
  void dispose() {
    for (final c in [_name, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(
      RiderDraft(
        name: _name.text.trim(),
        location: CoordinateFields.read(_lat, _lng),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add rider'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                maxLength: 60,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              CoordinateFields(latController: _lat, lngController: _lng),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add rider')),
      ],
    );
  }
}
