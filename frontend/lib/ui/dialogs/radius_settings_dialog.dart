import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../formatting.dart';

/// Edits how waiting packages' search radius grows: the starting radius, how
/// much it widens each time the timer runs out, the timer itself and the cap.
class RadiusSettingsDialog extends StatefulWidget {
  const RadiusSettingsDialog({required this.initial, super.key});

  final RadiusPolicy initial;

  static Future<RadiusPolicy?> show(
    BuildContext context,
    RadiusPolicy initial,
  ) => showDialog<RadiusPolicy>(
    context: context,
    builder: (_) => RadiusSettingsDialog(initial: initial),
  );

  @override
  State<RadiusSettingsDialog> createState() => _RadiusSettingsDialogState();
}

// Slider ranges. Values set elsewhere (e.g. via the API) are clamped into them.
const _startRange = (min: 0.5, max: 10.0, step: 0.5);
const _incrementRange = (min: 0.0, max: 10.0, step: 0.5);
const _intervalRange = (min: 5.0, max: 300.0, step: 5.0);
const _maxRange = (min: 1.0, max: 50.0, step: 1.0);

class _RadiusSettingsDialogState extends State<RadiusSettingsDialog> {
  late double _start = _clamp(widget.initial.initialRadiusMiles, _startRange);
  late double _increment = _clamp(
    widget.initial.incrementMiles,
    _incrementRange,
  );
  late double _intervalSeconds = _clamp(
    widget.initial.interval.inSeconds.toDouble(),
    _intervalRange,
  );
  late double _max = _clamp(widget.initial.maxRadiusMiles, _maxRange);

  static double _clamp(
    double value,
    ({double min, double max, double step}) range,
  ) => value.clamp(range.min, range.max);

  RadiusPolicy get _policy => RadiusPolicy(
    initialRadiusMiles: _start,
    incrementMiles: _increment,
    interval: Duration(seconds: _intervalSeconds.round()),
    maxRadiusMiles: _max,
  );

  /// The cap can never sit below the starting radius; moving one drags the other.
  void _setStart(double v) => setState(() {
    _start = v;
    if (_max < v) _max = v.ceilToDouble();
  });

  void _setMax(double v) => setState(() {
    _max = v;
    if (_start > v) _start = v;
  });

  Widget _slider({
    required String label,
    required double value,
    required ({double min, double max, double step}) range,
    required String text,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $text'),
        Slider(
          value: value,
          min: range.min,
          max: range.max,
          divisions: ((range.max - range.min) / range.step).round(),
          label: text,
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final interval = Duration(seconds: _intervalSeconds.round());
    return AlertDialog(
      title: const Text('Search radius'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Every new package starts searching for a rider close by. '
                'Each time its timer runs out, the search widens. Changes '
                'apply to every waiting package right away.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _slider(
                label: 'Starting radius',
                value: _start,
                range: _startRange,
                text: formatRadius(_start),
                onChanged: _setStart,
              ),
              _slider(
                label: 'Increase by',
                value: _increment,
                range: _incrementRange,
                text: _increment == 0 ? 'off' : formatRadius(_increment),
                onChanged: (v) => setState(() => _increment = v),
              ),
              _slider(
                label: 'Timer',
                value: _intervalSeconds,
                range: _intervalRange,
                text: formatInterval(interval),
                onChanged: (v) => setState(() => _intervalSeconds = v),
              ),
              _slider(
                label: 'Maximum radius',
                value: _max,
                range: _maxRange,
                text: formatRadius(_max),
                onChanged: _setMax,
              ),
              const SizedBox(height: 4),
              Text(
                describeRadiusGrowth(_policy),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            const defaults = RadiusPolicy();
            _start = defaults.initialRadiusMiles;
            _increment = defaults.incrementMiles;
            _intervalSeconds = defaults.interval.inSeconds.toDouble();
            _max = defaults.maxRadiusMiles;
          }),
          child: const Text('Defaults'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _policy == widget.initial
              ? null
              : () => Navigator.of(context).pop(_policy),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
