import 'package:equatable/equatable.dart';

import 'geo.dart';

DateTime? _parseDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

/// The dispatcher; their location is the map's centre.
class Admin extends Equatable {
  const Admin({required this.name, required this.location});

  factory Admin.fromJson(Map<String, dynamic> json) => Admin(
    name: json['name'] as String,
    location: Coordinates.fromJson(json['location'] as Map<String, dynamic>),
  );

  final String name;
  final Coordinates location;

  @override
  List<Object?> get props => [name, location];
}

/// How far a waiting package searches for a rider, growing the longer it waits.
///
/// Mirrors the backend's `RadiusPolicy`: a package starts at
/// [initialRadiusMiles] and every [interval] it waits, its radius grows by
/// [incrementMiles], up to [maxRadiusMiles]. The radius is derived from the
/// package's age, so the UI computes it locally from the same rule.
class RadiusPolicy extends Equatable {
  const RadiusPolicy({
    this.initialRadiusMiles = 1,
    this.incrementMiles = 2,
    this.interval = const Duration(seconds: 30),
    this.maxRadiusMiles = 15,
  });

  factory RadiusPolicy.fromJson(Map<String, dynamic> json) => RadiusPolicy(
    initialRadiusMiles: (json['initial_radius_miles'] as num).toDouble(),
    incrementMiles: (json['increment_miles'] as num).toDouble(),
    interval: Duration(
      milliseconds: ((json['interval_seconds'] as num) * 1000).round(),
    ),
    maxRadiusMiles: (json['max_radius_miles'] as num).toDouble(),
  );

  final double initialRadiusMiles;
  final double incrementMiles;
  final Duration interval;
  final double maxRadiusMiles;

  Map<String, dynamic> toJson() => {
    'initial_radius_miles': initialRadiusMiles,
    'increment_miles': incrementMiles,
    'interval_seconds': interval.inMilliseconds / 1000,
    'max_radius_miles': maxRadiusMiles,
  };

  /// Completed intervals since [since] (0 if the clock reads earlier).
  int _steps(DateTime since, DateTime now) {
    final waited = now.difference(since);
    return waited.isNegative
        ? 0
        : waited.inMicroseconds ~/ interval.inMicroseconds;
  }

  double _radiusAfter(int steps) =>
      (initialRadiusMiles + incrementMiles * steps).clamp(0, maxRadiusMiles);

  /// Search radius of a package that started waiting at [since], as of [now].
  double radiusAt(DateTime since, DateTime now) =>
      _radiusAfter(_steps(since, now));

  /// Radius just before the most recent expansion, and how far into the
  /// current interval [now] is. Lets the map ease a disk from its old size.
  ({double previous, Duration sinceGrowth}) lastGrowth(
    DateTime since,
    DateTime now,
  ) {
    final steps = _steps(since, now);
    return (
      previous: _radiusAfter(steps == 0 ? 0 : steps - 1),
      sinceGrowth: steps == 0
          ? now.difference(since)
          : now.difference(since) - interval * steps,
    );
  }

  /// When that package's radius next grows, or null once it is capped.
  DateTime? nextExpansionAt(DateTime since, DateTime now) {
    if (incrementMiles == 0 || radiusAt(since, now) >= maxRadiusMiles) {
      return null;
    }
    return since.add(interval * (_steps(since, now) + 1));
  }

  RadiusPolicy copyWith({
    double? initialRadiusMiles,
    double? incrementMiles,
    Duration? interval,
    double? maxRadiusMiles,
  }) => RadiusPolicy(
    initialRadiusMiles: initialRadiusMiles ?? this.initialRadiusMiles,
    incrementMiles: incrementMiles ?? this.incrementMiles,
    interval: interval ?? this.interval,
    maxRadiusMiles: maxRadiusMiles ?? this.maxRadiusMiles,
  );

  @override
  List<Object?> get props => [
    initialRadiusMiles,
    incrementMiles,
    interval,
    maxRadiusMiles,
  ];
}

enum PackageStatus { waiting, assigned }

enum RiderStatus { available, assigned }

/// Which arrival caused an assignment.
enum MatchTrigger {
  packageAdded('package_added'),
  riderAdded('rider_added'),
  radiusExpanded('radius_expanded');

  const MatchTrigger(this.wireName);

  final String wireName;

  static MatchTrigger fromWire(String value) =>
      values.firstWhere((t) => t.wireName == value);
}

class Package extends Equatable {
  const Package({
    required this.id,
    required this.pickup,
    required this.dropoff,
    required this.status,
    required this.createdAt,
    this.assignedRiderId,
  });

  factory Package.fromJson(Map<String, dynamic> json) => Package(
    id: json['id'] as String,
    pickup: Place.fromJson(json['pickup'] as Map<String, dynamic>),
    dropoff: Place.fromJson(json['dropoff'] as Map<String, dynamic>),
    status: PackageStatus.values.byName(json['status'] as String),
    createdAt: _parseDate(json['created_at'])!,
    assignedRiderId: json['assigned_rider_id'] as String?,
  );

  final String id;
  final Place pickup;
  final Place dropoff;
  final PackageStatus status;
  final DateTime createdAt;
  final String? assignedRiderId;

  bool get isWaiting => status == PackageStatus.waiting;

  @override
  List<Object?> get props => [
    id,
    pickup,
    dropoff,
    status,
    createdAt,
    assignedRiderId,
  ];
}

class Rider extends Equatable {
  const Rider({
    required this.id,
    required this.name,
    required this.location,
    required this.status,
    required this.createdAt,
    this.assignedPackageId,
  });

  factory Rider.fromJson(Map<String, dynamic> json) => Rider(
    id: json['id'] as String,
    name: json['name'] as String,
    location: Coordinates.fromJson(json['location'] as Map<String, dynamic>),
    status: RiderStatus.values.byName(json['status'] as String),
    createdAt: _parseDate(json['created_at'])!,
    assignedPackageId: json['assigned_package_id'] as String?,
  );

  final String id;
  final String name;
  final Coordinates location;
  final RiderStatus status;
  final DateTime createdAt;
  final String? assignedPackageId;

  bool get isAvailable => status == RiderStatus.available;

  @override
  List<Object?> get props => [
    id,
    name,
    location,
    status,
    createdAt,
    assignedPackageId,
  ];
}

/// A package/rider pairing, denormalised so it can be shown without lookups.
class Assignment extends Equatable {
  const Assignment({
    required this.id,
    required this.packageId,
    required this.riderId,
    required this.riderName,
    required this.distanceMiles,
    required this.pickup,
    required this.dropoff,
    required this.riderLocation,
    required this.trigger,
    required this.createdAt,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) => Assignment(
    id: json['id'] as String,
    packageId: json['package_id'] as String,
    riderId: json['rider_id'] as String,
    riderName: json['rider_name'] as String,
    distanceMiles: (json['distance_miles'] as num).toDouble(),
    pickup: Place.fromJson(json['pickup'] as Map<String, dynamic>),
    dropoff: Place.fromJson(json['dropoff'] as Map<String, dynamic>),
    riderLocation: Coordinates.fromJson(
      json['rider_location'] as Map<String, dynamic>,
    ),
    trigger: MatchTrigger.fromWire(json['trigger'] as String),
    createdAt: _parseDate(json['created_at'])!,
  );

  final String id;
  final String packageId;
  final String riderId;
  final String riderName;
  final double distanceMiles;
  final Place pickup;
  final Place dropoff;
  final Coordinates riderLocation;
  final MatchTrigger trigger;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id];
}

/// Everything currently in the scheduler. Payload of `GET /scheduler/state`
/// and of the `scheduler.snapshot` WebSocket event.
class SchedulerSnapshot extends Equatable {
  const SchedulerSnapshot({
    required this.admin,
    required this.packages,
    required this.riders,
    required this.radiusPolicy,
  });

  factory SchedulerSnapshot.fromJson(Map<String, dynamic> json) =>
      SchedulerSnapshot(
        admin: Admin.fromJson(json['admin'] as Map<String, dynamic>),
        packages: (json['packages'] as List<dynamic>)
            .map((p) => Package.fromJson(p as Map<String, dynamic>))
            .toList(),
        riders: (json['riders'] as List<dynamic>)
            .map((r) => Rider.fromJson(r as Map<String, dynamic>))
            .toList(),
        radiusPolicy: RadiusPolicy.fromJson(
          json['radius_policy'] as Map<String, dynamic>,
        ),
      );

  final Admin admin;
  final List<Package> packages;
  final List<Rider> riders;
  final RadiusPolicy radiusPolicy;

  @override
  List<Object?> get props => [admin, packages, riders, radiusPolicy];
}
