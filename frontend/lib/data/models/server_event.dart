import 'entities.dart';

/// A message received on `/ws/scheduler`. See docs/websocket-events.md.
///
/// Every message is `{"type": ..., "data": {...}, "timestamp": ...}`. The sealed
/// hierarchy lets blocs `switch` exhaustively over event kinds.
sealed class ServerEvent {
  const ServerEvent(this.timestamp);

  /// Parses a decoded JSON message. Unrecognised types become [UnknownEvent]
  /// so that a newer backend never crashes an older client.
  factory ServerEvent.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    final timestamp = DateTime.parse(json['timestamp'] as String);
    Map<String, dynamic> field(String key) => data[key] as Map<String, dynamic>;

    return switch (json['type']) {
      'scheduler.snapshot' => SnapshotEvent(
        SchedulerSnapshot.fromJson(data),
        timestamp,
      ),
      'package.added' => PackageAddedEvent(
        Package.fromJson(field('package')),
        timestamp,
      ),
      'package.removed' => PackageRemovedEvent(
        data['package_id'] as String,
        timestamp,
      ),
      'rider.added' => RiderAddedEvent(
        Rider.fromJson(field('rider')),
        timestamp,
      ),
      'rider.removed' => RiderRemovedEvent(
        data['rider_id'] as String,
        timestamp,
      ),
      'assignment.created' => AssignmentCreatedEvent(
        Assignment.fromJson(field('assignment')),
        timestamp,
      ),
      'admin.updated' => AdminUpdatedEvent(
        Admin.fromJson(field('admin')),
        timestamp,
      ),
      'radius_policy.updated' => RadiusPolicyUpdatedEvent(
        RadiusPolicy.fromJson(field('radius_policy')),
        timestamp,
      ),
      'scheduler.reset' => SchedulerResetEvent(timestamp),
      final Object? other => UnknownEvent('$other', timestamp),
    };
  }

  final DateTime timestamp;
}

/// Full state; always the first message after (re)connecting.
final class SnapshotEvent extends ServerEvent {
  const SnapshotEvent(this.snapshot, DateTime timestamp) : super(timestamp);
  final SchedulerSnapshot snapshot;
}

/// A package was created. Its [Package.status] is `assigned` when it was
/// paired instantly, in which case an [AssignmentCreatedEvent] follows.
final class PackageAddedEvent extends ServerEvent {
  const PackageAddedEvent(this.package, DateTime timestamp) : super(timestamp);
  final Package package;
}

final class PackageRemovedEvent extends ServerEvent {
  const PackageRemovedEvent(this.packageId, DateTime timestamp)
    : super(timestamp);
  final String packageId;
}

/// A rider was created. Like packages, may already be `assigned`.
final class RiderAddedEvent extends ServerEvent {
  const RiderAddedEvent(this.rider, DateTime timestamp) : super(timestamp);
  final Rider rider;
}

final class RiderRemovedEvent extends ServerEvent {
  const RiderRemovedEvent(this.riderId, DateTime timestamp) : super(timestamp);
  final String riderId;
}

/// A package and rider were paired and both left the scheduler.
final class AssignmentCreatedEvent extends ServerEvent {
  const AssignmentCreatedEvent(this.assignment, DateTime timestamp)
    : super(timestamp);
  final Assignment assignment;
}

final class AdminUpdatedEvent extends ServerEvent {
  const AdminUpdatedEvent(this.admin, DateTime timestamp) : super(timestamp);
  final Admin admin;
}

/// The search-radius policy changed; it applies to every waiting package.
final class RadiusPolicyUpdatedEvent extends ServerEvent {
  const RadiusPolicyUpdatedEvent(this.policy, DateTime timestamp)
    : super(timestamp);
  final RadiusPolicy policy;
}

/// Everything except the admin was deleted.
final class SchedulerResetEvent extends ServerEvent {
  const SchedulerResetEvent(super.timestamp);
}

final class UnknownEvent extends ServerEvent {
  const UnknownEvent(this.type, DateTime timestamp) : super(timestamp);
  final String type;
}
