import 'package:intl/intl.dart';

import '../data/models/models.dart';

final _time = DateFormat('HH:mm:ss');

String formatTime(DateTime time) => _time.format(time.toLocal());

String formatMiles(double miles) => '${miles.toStringAsFixed(2)} mi';

String describeTrigger(MatchTrigger trigger) => switch (trigger) {
  MatchTrigger.packageAdded => 'new package found a rider',
  MatchTrigger.riderAdded => 'new rider found a package',
  MatchTrigger.radiusExpanded => 'search radius grew to reach a rider',
};

/// `1 mi`, `2.5 mi`: whole miles without a trailing `.0`.
String formatRadius(double miles) =>
    '${miles == miles.roundToDouble() ? miles.toStringAsFixed(0) : miles.toStringAsFixed(1)} mi';

/// `45 s`, `2 min`, `1 min 30 s`.
String formatInterval(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  if (minutes == 0) return '${d.inSeconds} s';
  return seconds == 0 ? '$minutes min' : '$minutes min $seconds s';
}

/// `0:07`, `2:30`: a countdown, rounded up so it never shows `0:00` early.
String formatCountdown(Duration d) {
  final total = d.isNegative ? 0 : (d.inMilliseconds / 1000).ceil();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

/// One sentence describing how a package's search radius grows under [p].
String describeRadiusGrowth(RadiusPolicy p) {
  final start = 'Starts at ${formatRadius(p.initialRadiusMiles)}';
  if (p.incrementMiles == 0 || p.maxRadiusMiles <= p.initialRadiusMiles) {
    return '$start and stays there.';
  }
  final steps = ((p.maxRadiusMiles - p.initialRadiusMiles) / p.incrementMiles)
      .ceil();
  return '$start, grows ${formatRadius(p.incrementMiles)} every '
      '${formatInterval(p.interval)}, and reaches the '
      '${formatRadius(p.maxRadiusMiles)} cap after '
      '${formatInterval(p.interval * steps)}.';
}
