part of 'scheduler_bloc.dart';

enum SchedulerLoadStatus { initial, loading, ready, failure }

class SchedulerState extends Equatable {
  const SchedulerState({
    this.loadStatus = SchedulerLoadStatus.initial,
    this.admin,
    this.packages = const {},
    this.riders = const {},
    this.maxMatchRadiusMiles = 5,
    this.connection = ConnectionStatus.disconnected,
    this.hasSnapshot = false,
    this.recentAssignments = const [],
    this.pendingRequests = 0,
    this.errorMessage,
  });

  final SchedulerLoadStatus loadStatus;
  final Admin? admin;

  /// Waiting packages, keyed by id, in arrival order.
  final Map<String, Package> packages;

  /// Available riders, keyed by id, in arrival order.
  final Map<String, Rider> riders;
  final double maxMatchRadiusMiles;
  final ConnectionStatus connection;

  /// True once the first WebSocket snapshot arrived.
  final bool hasSnapshot;

  /// Assignments currently shown as prompts / highlighted on the map, newest
  /// first. Each one expires after the bloc's prompt duration.
  final List<Assignment> recentAssignments;

  /// Number of REST commands in flight; drives the progress indicator.
  final int pendingRequests;

  /// A transient error to show once, then cleared via [SchedulerErrorDismissed].
  final String? errorMessage;

  bool get isBusy => pendingRequests > 0;

  SchedulerState copyWith({
    SchedulerLoadStatus? loadStatus,
    Admin? admin,
    Map<String, Package>? packages,
    Map<String, Rider>? riders,
    double? maxMatchRadiusMiles,
    ConnectionStatus? connection,
    bool? hasSnapshot,
    List<Assignment>? recentAssignments,
    int? pendingRequests,
    String? Function()? errorMessage,
  }) {
    return SchedulerState(
      loadStatus: loadStatus ?? this.loadStatus,
      admin: admin ?? this.admin,
      packages: packages ?? this.packages,
      riders: riders ?? this.riders,
      maxMatchRadiusMiles: maxMatchRadiusMiles ?? this.maxMatchRadiusMiles,
      connection: connection ?? this.connection,
      hasSnapshot: hasSnapshot ?? this.hasSnapshot,
      recentAssignments: recentAssignments ?? this.recentAssignments,
      pendingRequests: pendingRequests ?? this.pendingRequests,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    loadStatus,
    admin,
    packages,
    riders,
    maxMatchRadiusMiles,
    connection,
    hasSnapshot,
    recentAssignments,
    pendingRequests,
    errorMessage,
  ];
}
