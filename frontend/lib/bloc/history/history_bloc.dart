import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api_exception.dart';
import '../../data/models/models.dart';
import '../../data/repositories/scheduler_repository.dart';

// ----------------------------------------------------------------------------
// Events
// ----------------------------------------------------------------------------

sealed class HistoryEvent extends Equatable {
  const HistoryEvent();

  @override
  List<Object?> get props => [];
}

/// Load history over REST and start following live assignments.
final class HistoryStarted extends HistoryEvent {
  const HistoryStarted();
}

/// Reload from REST (retry button, or after a reconnect).
final class HistoryRefreshed extends HistoryEvent {
  const HistoryRefreshed();
}

// ----------------------------------------------------------------------------
// State
// ----------------------------------------------------------------------------

enum HistoryStatus { initial, loading, ready, failure }

class HistoryState extends Equatable {
  const HistoryState({
    this.status = HistoryStatus.initial,
    this.assignments = const [],
    this.errorMessage,
  });

  final HistoryStatus status;

  /// Newest first.
  final List<Assignment> assignments;
  final String? errorMessage;

  HistoryState copyWith({
    HistoryStatus? status,
    List<Assignment>? assignments,
    String? errorMessage,
  }) => HistoryState(
    status: status ?? this.status,
    assignments: assignments ?? this.assignments,
    errorMessage: errorMessage,
  );

  @override
  List<Object?> get props => [status, assignments, errorMessage];
}

// ----------------------------------------------------------------------------
// Bloc
// ----------------------------------------------------------------------------

/// The assignment history panel: `GET /assignments` plus live
/// `assignment.created` events prepended as they happen.
class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  HistoryBloc({required SchedulerRepository repository, this.limit = 100})
    : _repository = repository,
      super(const HistoryState()) {
    on<HistoryStarted>(_onStarted);
    on<HistoryRefreshed>((event, emit) => _load(emit));
  }

  final SchedulerRepository _repository;

  /// Maximum number of assignments kept in memory and requested from the API.
  final int limit;

  bool _seenFirstSnapshot = false;

  Future<void> _onStarted(
    HistoryStarted event,
    Emitter<HistoryState> emit,
  ) async {
    final live = emit.forEach<ServerEvent>(
      _repository.events,
      onData: (serverEvent) {
        switch (serverEvent) {
          case AssignmentCreatedEvent(:final assignment):
            return state.copyWith(
              assignments: [
                assignment,
                ...state.assignments.where((a) => a.id != assignment.id),
              ].take(limit).toList(),
            );
          case SchedulerResetEvent():
            return state.copyWith(assignments: []);
          case SnapshotEvent():
            // A snapshot after the first one means we reconnected and may
            // have missed assignments while offline: resync from REST.
            if (_seenFirstSnapshot) add(const HistoryRefreshed());
            _seenFirstSnapshot = true;
            return state;
          default:
            return state;
        }
      },
    );
    await _load(emit);
    await live;
  }

  Future<void> _load(Emitter<HistoryState> emit) async {
    emit(state.copyWith(status: HistoryStatus.loading));
    try {
      final assignments = await _repository.fetchAssignments(limit: limit);
      emit(
        state.copyWith(status: HistoryStatus.ready, assignments: assignments),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(status: HistoryStatus.failure, errorMessage: e.message),
      );
    }
  }
}
