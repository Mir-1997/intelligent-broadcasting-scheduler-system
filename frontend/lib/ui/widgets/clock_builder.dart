import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Rebuilds [builder] with the current time every [period], for countdowns.
///
/// Driven by a [Ticker] rather than a periodic `Timer`: tickers belong to the
/// frame scheduler, so they stop with the app. A `Timer` survives a Flutter web
/// hot restart and would keep rebuilding the discarded widget tree, which
/// throws "Trying to render a disposed EngineFlutterView".
class ClockBuilder extends StatefulWidget {
  const ClockBuilder({
    required this.builder,
    this.period = const Duration(seconds: 1),
    this.clock = DateTime.now,
    super.key,
  });

  final Widget Function(BuildContext context, DateTime now) builder;
  final Duration period;

  /// Injectable for tests.
  final DateTime Function() clock;

  @override
  State<ClockBuilder> createState() => _ClockBuilderState();
}

class _ClockBuilderState extends State<ClockBuilder>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  int _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  /// Rebuild only when a new [ClockBuilder.period] starts, not every frame.
  void _onTick(Duration elapsed) {
    final tick = elapsed.inMicroseconds ~/ widget.period.inMicroseconds;
    if (tick != _lastTick) setState(() => _lastTick = tick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.clock());
}
