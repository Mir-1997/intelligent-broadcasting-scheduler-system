import 'package:bloc_test/bloc_test.dart';
import 'package:broadcast_scheduler_ui/bloc/scheduler/scheduler_bloc.dart';
import 'package:broadcast_scheduler_ui/core/api_exception.dart';
import 'package:broadcast_scheduler_ui/data/models/models.dart';
import 'package:broadcast_scheduler_ui/data/realtime/scheduler_socket.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fixtures.dart';
import '../helpers/mocks.dart';

void main() {
  setUpAll(registerFallbacks);

  group('reduceServerEvent', () {
    const empty = SchedulerState();

    test('snapshot replaces everything', () {
      final s = reduceServerEvent(
        empty.copyWith(packages: {'old': package('old')}),
        SnapshotEvent(
          snapshot(packages: [package('p1')], riders: [rider('r1')]),
          t0,
        ),
      );
      expect(s.packages.keys, ['p1']);
      expect(s.riders.keys, ['r1']);
      expect(s.admin, admin);
      expect(s.hasSnapshot, isTrue);
    });

    test('waiting package is added, instantly-assigned one is not', () {
      var s = reduceServerEvent(empty, PackageAddedEvent(package('p1'), t0));
      expect(s.packages.keys, ['p1']);
      s = reduceServerEvent(
        s,
        PackageAddedEvent(package('p2', status: PackageStatus.assigned), t0),
      );
      expect(s.packages.keys, ['p1']);
    });

    test('available rider is added, assigned one is not', () {
      var s = reduceServerEvent(empty, RiderAddedEvent(rider('r1'), t0));
      s = reduceServerEvent(
        s,
        RiderAddedEvent(rider('r2', status: RiderStatus.assigned), t0),
      );
      expect(s.riders.keys, ['r1']);
    });

    test('assignment removes both sides and adds a prompt', () {
      final start = empty.copyWith(
        packages: {'pkg_1': package('pkg_1'), 'pkg_2': package('pkg_2')},
        riders: {'rdr_1': rider('rdr_1')},
      );
      final s = reduceServerEvent(
        start,
        AssignmentCreatedEvent(assignment('a1'), t0),
      );
      expect(s.packages.keys, ['pkg_2']);
      expect(s.riders, isEmpty);
      expect(s.recentAssignments.map((a) => a.id), ['a1']);
    });

    test('replayed assignment is not duplicated', () {
      var s = reduceServerEvent(
        empty,
        AssignmentCreatedEvent(assignment('a1'), t0),
      );
      s = reduceServerEvent(s, AssignmentCreatedEvent(assignment('a2'), t0));
      s = reduceServerEvent(s, AssignmentCreatedEvent(assignment('a1'), t0));
      expect(s.recentAssignments.map((a) => a.id), ['a1', 'a2']);
    });

    test('removals, admin update and reset', () {
      var s = empty.copyWith(
        packages: {'p1': package('p1')},
        riders: {'r1': rider('r1')},
        recentAssignments: [assignment('a1')],
      );
      s = reduceServerEvent(s, PackageRemovedEvent('p1', t0));
      expect(s.packages, isEmpty);
      s = reduceServerEvent(s, RiderRemovedEvent('r1', t0));
      expect(s.riders, isEmpty);
      s = reduceServerEvent(s, RiderRemovedEvent('missing', t0));
      expect(s.riders, isEmpty);

      const moved = Admin(name: 'HQ2', location: Coordinates(lat: 1, lng: 2));
      s = reduceServerEvent(s, AdminUpdatedEvent(moved, t0));
      expect(s.admin, moved);

      const wider = RadiusPolicy(initialRadiusMiles: 4, maxRadiusMiles: 20);
      s = reduceServerEvent(s, RadiusPolicyUpdatedEvent(wider, t0));
      expect(s.radiusPolicy, wider);

      s = reduceServerEvent(
        s.copyWith(packages: {'p': package('p')}),
        SchedulerResetEvent(t0),
      );
      expect(s.packages, isEmpty);
      expect(s.recentAssignments, isEmpty);
      expect(s.admin, moved);
    });

    test('unknown events are ignored', () {
      expect(reduceServerEvent(empty, UnknownEvent('x', t0)), empty);
    });
  });

  group('SchedulerBloc', () {
    late FakeRepositoryHarness harness;

    setUp(() => harness = FakeRepositoryHarness());
    tearDown(() => harness.dispose());

    blocTest<SchedulerBloc, SchedulerState>(
      'loads admin, connects, then applies live events',
      setUp: () => when(
        () => harness.repository.fetchAdmin(),
      ).thenAnswer((_) async => admin),
      build: () => SchedulerBloc(repository: harness.repository),
      act: (bloc) async {
        bloc.add(const SchedulerStarted());
        await Future<void>.delayed(Duration.zero);
        harness.connection.add(ConnectionStatus.connected);
        harness.events.add(
          SnapshotEvent(snapshot(riders: [rider('rdr_1')]), t0),
        );
        await Future<void>.delayed(Duration.zero);
        harness.events.add(PackageAddedEvent(package('pkg_9'), t0));
      },
      expect: () => [
        isA<SchedulerState>().having(
          (s) => s.loadStatus,
          'status',
          SchedulerLoadStatus.loading,
        ),
        isA<SchedulerState>()
            .having((s) => s.loadStatus, 'status', SchedulerLoadStatus.ready)
            .having((s) => s.admin, 'admin', admin),
        isA<SchedulerState>().having(
          (s) => s.connection,
          'connection',
          ConnectionStatus.connected,
        ),
        isA<SchedulerState>()
            .having((s) => s.hasSnapshot, 'snapshot', isTrue)
            .having((s) => s.riders.keys, 'riders', ['rdr_1']),
        isA<SchedulerState>().having((s) => s.packages.keys, 'packages', [
          'pkg_9',
        ]),
      ],
      verify: (_) => verify(() => harness.repository.connect()).called(1),
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'admin load failure does not connect',
      setUp: () => when(
        () => harness.repository.fetchAdmin(),
      ).thenThrow(const ApiException('Cannot reach the scheduler server.')),
      build: () => SchedulerBloc(repository: harness.repository),
      act: (bloc) => bloc.add(const SchedulerStarted()),
      expect: () => [
        isA<SchedulerState>().having(
          (s) => s.loadStatus,
          'status',
          SchedulerLoadStatus.loading,
        ),
        isA<SchedulerState>()
            .having((s) => s.loadStatus, 'status', SchedulerLoadStatus.failure)
            .having((s) => s.errorMessage, 'error', contains('Cannot reach')),
      ],
      verify: (_) => verifyNever(() => harness.repository.connect()),
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'assignment prompt expires after promptDuration',
      setUp: () => when(
        () => harness.repository.fetchAdmin(),
      ).thenAnswer((_) async => admin),
      build: () => SchedulerBloc(
        repository: harness.repository,
        promptDuration: const Duration(milliseconds: 30),
      ),
      act: (bloc) async {
        bloc.add(const SchedulerStarted());
        await Future<void>.delayed(Duration.zero);
        harness.events.add(AssignmentCreatedEvent(assignment('a1'), t0));
      },
      wait: const Duration(milliseconds: 80),
      skip: 2,
      expect: () => [
        isA<SchedulerState>().having(
          (s) => s.recentAssignments.length,
          'prompts',
          1,
        ),
        isA<SchedulerState>().having(
          (s) => s.recentAssignments,
          'prompts',
          isEmpty,
        ),
      ],
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'dismissing a prompt removes only that prompt',
      build: () => SchedulerBloc(repository: harness.repository),
      seed: () => SchedulerState(
        recentAssignments: [assignment('a1'), assignment('a2')],
      ),
      act: (bloc) => bloc.add(const AssignmentPromptDismissed('a1')),
      expect: () => [
        isA<SchedulerState>().having(
          (s) => s.recentAssignments.map((a) => a.id),
          'ids',
          ['a2'],
        ),
      ],
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'commands call the repository and track pending requests',
      setUp: () {
        when(
          () => harness.repository.addPackage(any()),
        ).thenAnswer((_) async {});
        when(() => harness.repository.addRider(any())).thenAnswer((_) async {});
        when(() => harness.repository.simulate(any())).thenAnswer((_) async {});
        when(
          () => harness.repository.removePackage(any()),
        ).thenAnswer((_) async {});
        when(
          () => harness.repository.removeRider(any()),
        ).thenAnswer((_) async {});
        when(() => harness.repository.reset()).thenAnswer((_) async {});
        when(
          () => harness.repository.updateRadiusPolicy(any()),
        ).thenAnswer((_) async {});
      },
      build: () => SchedulerBloc(repository: harness.repository),
      act: (bloc) async {
        bloc.add(
          const PackageAddRequested(
            PackageDraft(
              pickup: Place(lat: 1, lng: 1),
              dropoff: Place(lat: 2, lng: 2),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        bloc
          ..add(
            const RiderAddRequested(
              RiderDraft(name: 'A', location: Coordinates(lat: 1, lng: 1)),
            ),
          )
          ..add(const SimulationRequested(SimulationDraft(packages: 3)))
          ..add(const PackageRemoveRequested('p'))
          ..add(const RiderRemoveRequested('r'))
          ..add(
            const RadiusPolicyUpdateRequested(
              RadiusPolicy(initialRadiusMiles: 2),
            ),
          )
          ..add(const SchedulerResetRequested());
      },
      verify: (bloc) {
        verify(() => harness.repository.addPackage(any())).called(1);
        verify(() => harness.repository.addRider(any())).called(1);
        verify(
          () => harness.repository.simulate(const SimulationDraft(packages: 3)),
        ).called(1);
        verify(() => harness.repository.removePackage('p')).called(1);
        verify(() => harness.repository.removeRider('r')).called(1);
        verify(() => harness.repository.reset()).called(1);
        verify(
          () => harness.repository.updateRadiusPolicy(
            const RadiusPolicy(initialRadiusMiles: 2),
          ),
        ).called(1);
        expect(bloc.state.pendingRequests, 0);
      },
    );

    blocTest<SchedulerBloc, SchedulerState>(
      'command failure surfaces an error that can be dismissed',
      setUp: () =>
          when(() => harness.repository.removePackage(any())).thenThrow(
            const ApiException(
              'Package p is already assigned',
              statusCode: 409,
            ),
          ),
      build: () => SchedulerBloc(repository: harness.repository),
      act: (bloc) async {
        bloc.add(const PackageRemoveRequested('p'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const SchedulerErrorDismissed());
      },
      expect: () => [
        isA<SchedulerState>().having((s) => s.isBusy, 'busy', isTrue),
        isA<SchedulerState>()
            .having((s) => s.isBusy, 'busy', isFalse)
            .having(
              (s) => s.errorMessage,
              'error',
              'Package p is already assigned',
            ),
        isA<SchedulerState>().having((s) => s.errorMessage, 'error', isNull),
      ],
    );
  });
}
