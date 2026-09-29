import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_exception.dart';
import '../../data/models/models.dart';
import '../../data/realtime/scheduler_socket.dart';
import '../../data/repositories/scheduler_repository.dart';

part 'scheduler_event.dart';
part 'scheduler_state.dart';

/// Owns the live scheduler view: admin, waiting packages, available riders,
/// connection status and the transient "package assigned" prompts.
///
/// State changes come *only* from [ServerEvent]s on the WebSocket (reduced by
/// [reduceServerEvent]); user commands are fire-and-forget REST calls whose
/// effects arrive back through the socket.
class SchedulerBloc extends Bloc<SchedulerEvent, SchedulerState> {
  SchedulerBloc({
    required SchedulerRepository repository,
    this.promptDuration = const Duration(seconds: 6),
  }) : _repository = repository,
       super(const SchedulerState()) {
    on<SchedulerStarted>(_onStarted);
    on<PackageAddRequested>(
      (e, emit) => _command(emit, () => _repository.addPackage(e.draft)),
    );
    on<RiderAddRequested>(
      (e, emit) => _command(emit, () => _repository.addRider(e.draft)),
    );
    on<PackageRemoveRequested>(
      (e, emit) => _command(emit, () => _repository.removePackage(e.packageId)),
    );
    on<RiderRemoveRequested>(
      (e, emit) => _command(emit, () => _repository.removeRider(e.riderId)),
    );
    on<SimulationRequested>(
      (e, emit) => _command(emit, () => _repository.simulate(e.draft)),
    );
    on<RadiusPolicyUpdateRequested>(
      (e, emit) =>
          _command(emit, () => _repository.updateRadiusPolicy(e.policy)),
    );
    on<SchedulerResetRequested>((e, emit) => _command(emit, _repository.reset));
    on<AssignmentPromptDismissed>(
      (e, emit) => emit(_withoutPrompt(e.assignmentId)),
    );
    on<_AssignmentPromptExpired>(
      (e, emit) => emit(_withoutPrompt(e.assignmentId)),
    );
    on<SchedulerErrorDismissed>(
      (e, emit) => emit(state.copyWith(errorMessage: () => null)),
    );
  }

  final SchedulerRepository _repository;

  /// How long an assignment prompt (and its map highlight) stays visible.
  final Duration promptDuration;

  final List<Timer> _promptTimers = [];

  Future<void> _onStarted(
    SchedulerStarted event,
    Emitter<SchedulerState> emit,
  ) async {
    emit(
      state.copyWith(
        loadStatus: SchedulerLoadStatus.loading,
        errorMessage: () => null,
      ),
    );
    try {
      final admin = await _repository.fetchAdmin();
      emit(state.copyWith(loadStatus: SchedulerLoadStatus.ready, admin: admin));
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          loadStatus: SchedulerLoadStatus.failure,
          errorMessage: () => e.message,
        ),
      );
      return;
    }

    // Subscribe before connecting so the snapshot can't be missed.
    final streams = Future.wait([
      emit.forEach<ConnectionStatus>(
        _repository.connectionChanges,
        onData: (status) => state.copyWith(connection: status),
      ),
      emit.forEach<ServerEvent>(
        _repository.events,
        onData: (serverEvent) {
          if (serverEvent is AssignmentCreatedEvent) {
            _schedulePromptExpiry(serverEvent.assignment.id);
          }
          return reduceServerEvent(state, serverEvent);
        },
      ),
    ]);
    _repository.connect();
    await streams;
  }

  Future<void> _command(
    Emitter<SchedulerState> emit,
    Future<void> Function() call,
  ) async {
    emit(state.copyWith(pendingRequests: state.pendingRequests + 1));
    String? error;
    try {
      await call();
    } on ApiException catch (e) {
      error = e.message;
    }
    emit(
      state.copyWith(
        pendingRequests: state.pendingRequests - 1,
        errorMessage: error == null ? null : () => error,
      ),
    );
  }

  void _schedulePromptExpiry(String assignmentId) {
    _promptTimers.add(
      Timer(promptDuration, () {
        if (!isClosed) add(_AssignmentPromptExpired(assignmentId));
      }),
    );
  }

  SchedulerState _withoutPrompt(String assignmentId) => state.copyWith(
    recentAssignments: state.recentAssignments
        .where((a) => a.id != assignmentId)
        .toList(),
  );

  @override
  Future<void> close() {
    for (final timer in _promptTimers) {
      timer.cancel();
    }
    return super.close();
  }
}

/// Pure reducer: applies one server event to the state. Idempotent, so a
/// replayed event (e.g. after a reconnect) never corrupts the view.
SchedulerState reduceServerEvent(SchedulerState state, ServerEvent event) {
  switch (event) {
    case SnapshotEvent(:final snapshot):
      return state.copyWith(
        admin: snapshot.admin,
        packages: {for (final p in snapshot.packages) p.id: p},
        riders: {for (final r in snapshot.riders) r.id: r},
        radiusPolicy: snapshot.radiusPolicy,
        hasSnapshot: true,
      );
    case PackageAddedEvent(:final package):
      // An instantly-paired package is followed by assignment.created; it
      // never enters the scheduler view.
      if (!package.isWaiting) return state;
      return state.copyWith(packages: {...state.packages, package.id: package});
    case PackageRemovedEvent(:final packageId):
      return state.copyWith(packages: _without(state.packages, packageId));
    case RiderAddedEvent(:final rider):
      if (!rider.isAvailable) return state;
      return state.copyWith(riders: {...state.riders, rider.id: rider});
    case RiderRemovedEvent(:final riderId):
      return state.copyWith(riders: _without(state.riders, riderId));
    case AssignmentCreatedEvent(:final assignment):
      return state.copyWith(
        packages: _without(state.packages, assignment.packageId),
        riders: _without(state.riders, assignment.riderId),
        recentAssignments: [
          assignment,
          ...state.recentAssignments.where((a) => a.id != assignment.id),
        ],
      );
    case AdminUpdatedEvent(:final admin):
      return state.copyWith(admin: admin);
    case RadiusPolicyUpdatedEvent(:final policy):
      return state.copyWith(radiusPolicy: policy);
    case SchedulerResetEvent():
      return state.copyWith(packages: {}, riders: {}, recentAssignments: []);
    case UnknownEvent():
      return state;
  }
}

Map<String, T> _without<T>(Map<String, T> map, String key) =>
    map.containsKey(key) ? (Map.of(map)..remove(key)) : map;
