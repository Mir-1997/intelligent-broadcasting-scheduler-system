import 'package:bloc_test/bloc_test.dart';
import 'package:broadcast_scheduler_ui/bloc/placement/placement_cubit.dart';
import 'package:broadcast_scheduler_ui/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const a = Coordinates(lat: 1, lng: 1);
const b = Coordinates(lat: 2, lng: 2);

void main() {
  blocTest<PlacementCubit, PlacementState>(
    'rider placement takes one click',
    build: PlacementCubit.new,
    act: (c) => c
      ..startRider()
      ..mapTapped(a),
    expect: () => [const PlacingRider(), const RiderPlaced(a)],
  );

  blocTest<PlacementCubit, PlacementState>(
    'package placement takes pickup then drop-off',
    build: PlacementCubit.new,
    act: (c) => c
      ..startPackage()
      ..mapTapped(a)
      ..mapTapped(b),
    expect: () => [
      const PlacingPickup(),
      const PlacingDropoff(a),
      const PackagePlaced(a, b),
    ],
  );

  blocTest<PlacementCubit, PlacementState>(
    'taps are ignored when idle, and cancel resets',
    build: PlacementCubit.new,
    act: (c) => c
      ..mapTapped(a)
      ..startPackage()
      ..cancel(),
    expect: () => [const PlacingPickup(), const PlacementIdle()],
  );

  test('prompts guide the user', () {
    expect(const PlacementIdle().prompt, isNull);
    expect(const PlacingPickup().prompt, contains('pickup'));
    expect(const PlacingDropoff(a).prompt, contains('drop-off'));
  });
}
