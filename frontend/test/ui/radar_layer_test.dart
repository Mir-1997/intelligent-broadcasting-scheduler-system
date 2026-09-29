import 'package:broadcast_scheduler_ui/ui/widgets/radar_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const center = LatLng(40.758, -73.9855);

  Widget host(Map<String, LatLng> centers, {bool reduceMotion = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: FlutterMap(
            options: const MapOptions(initialCenter: center, initialZoom: 12),
            children: [
              RadarLayer(
                centers: centers,
                radiusMiles: 5,
                color: Colors.blueGrey,
              ),
            ],
          ),
        ),
      );

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
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
