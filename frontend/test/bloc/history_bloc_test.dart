import 'package:bloc_test/bloc_test.dart';
import 'package:broadcast_scheduler_ui/bloc/history/history_bloc.dart';
import 'package:broadcast_scheduler_ui/core/api_exception.dart';
import 'package:broadcast_scheduler_ui/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fixtures.dart';
import '../helpers/mocks.dart';

void main() {
  late FakeRepositoryHarness harness;

  setUp(() => harness = FakeRepositoryHarness());
  tearDown(() => harness.dispose());

  List<String> ids(HistoryState s) => s.assignments.map((a) => a.id).toList();

  blocTest<HistoryBloc, HistoryState>(
    'loads history then prepends live assignments without duplicates',
    setUp: () => when(
      () => harness.repository.fetchAssignments(limit: any(named: 'limit')),
    ).thenAnswer((_) async => [assignment('a1')]),
    build: () => HistoryBloc(repository: harness.repository),
    act: (bloc) async {
      bloc.add(const HistoryStarted());
      await Future<void>.delayed(Duration.zero);
      harness.events
        ..add(AssignmentCreatedEvent(assignment('a2'), t0))
        ..add(AssignmentCreatedEvent(assignment('a2'), t0));
    },
    expect: () => [
      isA<HistoryState>().having(
        (s) => s.status,
        'status',
        HistoryStatus.loading,
      ),
      isA<HistoryState>().having(ids, 'ids', ['a1']),
      isA<HistoryState>().having(ids, 'ids', ['a2', 'a1']),
    ],
  );

  blocTest<HistoryBloc, HistoryState>(
    'reset clears history',
    setUp: () => when(
      () => harness.repository.fetchAssignments(limit: any(named: 'limit')),
    ).thenAnswer((_) async => [assignment('a1')]),
    build: () => HistoryBloc(repository: harness.repository),
    act: (bloc) async {
      bloc.add(const HistoryStarted());
      await Future<void>.delayed(Duration.zero);
      harness.events.add(SchedulerResetEvent(t0));
    },
    skip: 2,
    expect: () => [isA<HistoryState>().having(ids, 'ids', isEmpty)],
  );

  blocTest<HistoryBloc, HistoryState>(
    'a second snapshot (reconnect) triggers a reload',
    setUp: () => when(
      () => harness.repository.fetchAssignments(limit: any(named: 'limit')),
    ).thenAnswer((_) async => []),
    build: () => HistoryBloc(repository: harness.repository),
    act: (bloc) async {
      bloc.add(const HistoryStarted());
      await Future<void>.delayed(Duration.zero);
      harness.events.add(SnapshotEvent(snapshot(), t0));
      await Future<void>.delayed(Duration.zero);
      harness.events.add(SnapshotEvent(snapshot(), t0));
      await Future<void>.delayed(Duration.zero);
    },
    verify: (_) => verify(
      () => harness.repository.fetchAssignments(limit: any(named: 'limit')),
    ).called(2),
  );

  blocTest<HistoryBloc, HistoryState>(
    'load failure is reported',
    setUp: () => when(
      () => harness.repository.fetchAssignments(limit: any(named: 'limit')),
    ).thenThrow(const ApiException('boom')),
    build: () => HistoryBloc(repository: harness.repository),
    act: (bloc) => bloc.add(const HistoryRefreshed()),
    expect: () => [
      isA<HistoryState>().having(
        (s) => s.status,
        'status',
        HistoryStatus.loading,
      ),
      isA<HistoryState>()
          .having((s) => s.status, 'status', HistoryStatus.failure)
          .having((s) => s.errorMessage, 'error', 'boom'),
    ],
  );
}
