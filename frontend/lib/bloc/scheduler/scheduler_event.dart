part of 'scheduler_bloc.dart';

sealed class SchedulerEvent extends Equatable {
  const SchedulerEvent();

  @override
  List<Object?> get props => [];
}

/// Load the admin over REST, then open the live WebSocket stream.
final class SchedulerStarted extends SchedulerEvent {
  const SchedulerStarted();
}

final class PackageAddRequested extends SchedulerEvent {
  const PackageAddRequested(this.draft);
  final PackageDraft draft;

  @override
  List<Object?> get props => [draft];
}

final class RiderAddRequested extends SchedulerEvent {
  const RiderAddRequested(this.draft);
  final RiderDraft draft;

  @override
  List<Object?> get props => [draft];
}

final class PackageRemoveRequested extends SchedulerEvent {
  const PackageRemoveRequested(this.packageId);
  final String packageId;

  @override
  List<Object?> get props => [packageId];
}

final class RiderRemoveRequested extends SchedulerEvent {
  const RiderRemoveRequested(this.riderId);
  final String riderId;

  @override
  List<Object?> get props => [riderId];
}

final class SimulationRequested extends SchedulerEvent {
  const SimulationRequested(this.draft);
  final SimulationDraft draft;

  @override
  List<Object?> get props => [draft];
}

final class RadiusPolicyUpdateRequested extends SchedulerEvent {
  const RadiusPolicyUpdateRequested(this.policy);
  final RadiusPolicy policy;

  @override
  List<Object?> get props => [policy];
}

final class SchedulerResetRequested extends SchedulerEvent {
  const SchedulerResetRequested();
}

/// The user closed an "assigned" prompt.
final class AssignmentPromptDismissed extends SchedulerEvent {
  const AssignmentPromptDismissed(this.assignmentId);
  final String assignmentId;

  @override
  List<Object?> get props => [assignmentId];
}

/// The error snackbar was shown; clear it from state.
final class SchedulerErrorDismissed extends SchedulerEvent {
  const SchedulerErrorDismissed();
}

final class _AssignmentPromptExpired extends SchedulerEvent {
  const _AssignmentPromptExpired(this.assignmentId);
  final String assignmentId;

  @override
  List<Object?> get props => [assignmentId];
}
