import 'package:flutter/material.dart';

Future<bool> confirmReset(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reset scheduler?'),
      content: const Text(
        'Deletes every package, rider and assignment. The admin is kept. '
        'All connected browsers will update.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Reset'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
