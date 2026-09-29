import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../formatting.dart';

/// Chooses how many random packages/riders to spawn around the admin.
class SimulateDialog extends StatefulWidget {
  const SimulateDialog({required this.policy, super.key});

  final RadiusPolicy policy;

  static Future<SimulationDraft?> show(
    BuildContext context, {
    required RadiusPolicy policy,
  }) => showDialog<SimulationDraft>(
    context: context,
    builder: (_) => SimulateDialog(policy: policy),
  );

  @override
  State<SimulateDialog> createState() => _SimulateDialogState();
}

class _SimulateDialogState extends State<SimulateDialog> {
  double _packages = 5;
  double _riders = 5;
  double _radius = 8;

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    String Function(double)? format,
  }) {
    final text = format?.call(value) ?? value.round().toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $text'),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min).round(),
          label: text,
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Simulate traffic'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Spawns random packages and riders around the admin, in random '
              'order. Each goes through normal matching: packages start '
              'searching ${formatRadius(widget.policy.initialRadiusMiles)} '
              'around their pickup and widen over time, so some wait before '
              'they find a rider.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _slider(
              label: 'Packages',
              value: _packages,
              min: 0,
              max: 50,
              onChanged: (v) => setState(() => _packages = v),
            ),
            _slider(
              label: 'Riders',
              value: _riders,
              min: 0,
              max: 50,
              onChanged: (v) => setState(() => _riders = v),
            ),
            _slider(
              label: 'Spawn radius',
              value: _radius,
              min: 1,
              max: 30,
              format: (v) => '${v.round()} mi',
              onChanged: (v) => setState(() => _radius = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _packages + _riders == 0
              ? null
              : () => Navigator.of(context).pop(
                  SimulationDraft(
                    packages: _packages.round(),
                    riders: _riders.round(),
                    radiusMiles: _radius.roundToDouble(),
                  ),
                ),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Run'),
        ),
      ],
    );
  }
}
