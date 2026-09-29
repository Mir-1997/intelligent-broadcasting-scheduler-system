import 'package:broadcast_scheduler_ui/data/models/models.dart';
import 'package:broadcast_scheduler_ui/ui/widgets/clock_builder.dart';
import 'package:broadcast_scheduler_ui/ui/widgets/radar_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const center = LatLng(40.758, -73.9855);

  List<RadarTarget> targets(Map<String, LatLng> centers) => [
    for (final MapEntry(key: id, value: c) in centers.entries)
      RadarTarget(id: id, center: c, since: DateTime.now()),
  ];

  Widget host(Map<String, LatLng> centers, {bool reduceMotion = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: FlutterMap(
            options: const MapOptions(initialCenter: center, initialZoom: 12),
            children: [
              RadarLayer(
                targets: targets(centers),
                policy: const RadiusPolicy(),
                color: Colors.blueGrey,
              ),
            ],
          ),
        ),
      );

  testWidgets('clock survives only as long as its widget', (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      ClockBuilder(
        builder: (_, _) {
          builds++;
          return const SizedBox();
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 600));
    expect(builds, 2); // initial build + one tick after crossing 1 s
    await tester.pumpWidget(const SizedBox());
    await tester.pump(); // flush the frame the last tick already requested
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('animates while there are waiting packages', (tester) async {
    await tester.pumpWidget(host({'pkg_1': center}));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('stays idle with no packages', (tester) async {
    await tester.pumpWidget(host({}));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('respects reduced motion', (tester) async {
    await tester.pumpWidget(host({'pkg_1': center}, reduceMotion: true));
    await tester.pump();
    // No sweep animation; only a once-a-second clock so disks still grow.
    expect(find.byType(ClockBuilder), findsOneWidget);
  });

  testWidgets('stays idle with reduced motion and no packages', (tester) async {
    await tester.pumpWidget(host({}, reduceMotion: true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
