import 'dart:async';

import 'package:broadcast_scheduler_ui/data/models/models.dart';
import 'package:broadcast_scheduler_ui/data/realtime/scheduler_socket.dart';
import 'package:broadcast_scheduler_ui/data/repositories/scheduler_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockSchedulerRepository extends Mock implements SchedulerRepository {}

/// A repository mock wired to controllable event/connection streams.
class FakeRepositoryHarness {
  FakeRepositoryHarness() {
    when(() => repository.events).thenAnswer((_) => events.stream);
    when(
      () => repository.connectionChanges,
    ).thenAnswer((_) => connection.stream);
    when(() => repository.connect()).thenReturn(null);
  }

  final repository = MockSchedulerRepository();
  final events = StreamController<ServerEvent>.broadcast();
  final connection = StreamController<ConnectionStatus>.broadcast();

  Future<void> dispose() async {
    await events.close();
    await connection.close();
  }
}

void registerFallbacks() {
  registerFallbackValue(
    const PackageDraft(
      pickup: Place(lat: 0, lng: 0),
      dropoff: Place(lat: 0, lng: 0),
    ),
  );
  registerFallbackValue(
    const RiderDraft(name: 'x', location: Coordinates(lat: 0, lng: 0)),
  );
  registerFallbackValue(const SimulationDraft());
}
