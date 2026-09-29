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

enum PackageStatus { waiting, assigned }

enum RiderStatus { available, assigned }

/// Which arrival caused an assignment.
enum MatchTrigger {
  packageAdded('package_added'),
  riderAdded('rider_added');

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
    required this.maxMatchRadiusMiles,
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
        maxMatchRadiusMiles: (json['max_match_radius_miles'] as num).toDouble(),
      );

  final Admin admin;
  final List<Package> packages;
  final List<Rider> riders;
  final double maxMatchRadiusMiles;

  @override
  List<Object?> get props => [admin, packages, riders, maxMatchRadiusMiles];
}
