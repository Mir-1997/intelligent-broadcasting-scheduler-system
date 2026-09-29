import 'package:equatable/equatable.dart';

import 'geo.dart';

/// Body of `POST /packages`.
class PackageDraft extends Equatable {
  const PackageDraft({required this.pickup, required this.dropoff});

  final Place pickup;
  final Place dropoff;

  Map<String, dynamic> toJson() => {
    'pickup': pickup.toJson(),
    'dropoff': dropoff.toJson(),
  };

  @override
  List<Object?> get props => [pickup, dropoff];
}

/// Body of `POST /riders`.
class RiderDraft extends Equatable {
  const RiderDraft({required this.name, required this.location});

  final String name;
  final Coordinates location;

  Map<String, dynamic> toJson() => {
    'name': name,
    'location': location.toJson(),
  };

  @override
  List<Object?> get props => [name, location];
}

/// Body of `POST /simulate`.
class SimulationDraft extends Equatable {
  const SimulationDraft({
    this.packages = 5,
    this.riders = 5,
    this.radiusMiles = 8,
  });

  final int packages;
  final int riders;
  final double radiusMiles;

  Map<String, dynamic> toJson() => {
    'packages': packages,
    'riders': riders,
    'radius_miles': radiusMiles,
  };

  @override
  List<Object?> get props => [packages, riders, radiusMiles];
}
