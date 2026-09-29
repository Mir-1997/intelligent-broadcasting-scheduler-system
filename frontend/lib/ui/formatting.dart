import 'package:intl/intl.dart';

import '../data/models/models.dart';

final _time = DateFormat('HH:mm:ss');

String formatTime(DateTime time) => _time.format(time.toLocal());

String formatMiles(double miles) => '${miles.toStringAsFixed(2)} mi';

String describeTrigger(MatchTrigger trigger) => switch (trigger) {
  MatchTrigger.packageAdded => 'new package found a rider',
  MatchTrigger.riderAdded => 'new rider found a package',
};
