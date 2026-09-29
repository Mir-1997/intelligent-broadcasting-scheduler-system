import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/models.dart';

/// Where we are in the "click the map to add something" flow.
sealed class PlacementState extends Equatable {
  const PlacementState();

  /// Instruction shown in the banner over the map, if placing.
  String? get prompt => null;

  @override
  List<Object?> get props => [];
}

final class PlacementIdle extends PlacementState {
  const PlacementIdle();
}

final class PlacingRider extends PlacementState {
  const PlacingRider();

  @override
  String get prompt => "Click the map to set the rider's location";
}

final class PlacingPickup extends PlacementState {
  const PlacingPickup();

  @override
  String get prompt => 'Click the map to set the package pickup';
}

final class PlacingDropoff extends PlacementState {
  const PlacingDropoff(this.pickup);
  final Coordinates pickup;

  @override
  String get prompt => 'Now click the map to set the drop-off';

  @override
  List<Object?> get props => [pickup];
}

/// Terminal: the UI opens the rider dialog pre-filled with [location].
final class RiderPlaced extends PlacementState {
  const RiderPlaced(this.location);
  final Coordinates location;

  @override
  List<Object?> get props => [location];
}

/// Terminal: the UI opens the package dialog pre-filled with both points.
final class PackagePlaced extends PlacementState {
  const PackagePlaced(this.pickup, this.dropoff);
  final Coordinates pickup;
  final Coordinates dropoff;

  @override
  List<Object?> get props => [pickup, dropoff];
}

/// A small state machine for placing riders (1 click) and packages (2 clicks).
class PlacementCubit extends Cubit<PlacementState> {
  PlacementCubit() : super(const PlacementIdle());

  void startRider() => emit(const PlacingRider());

  void startPackage() => emit(const PlacingPickup());

  void cancel() => emit(const PlacementIdle());

  /// Map tap handler; ignored unless a placement is in progress.
  void mapTapped(Coordinates point) {
    switch (state) {
      case PlacingRider():
        emit(RiderPlaced(point));
      case PlacingPickup():
        emit(PlacingDropoff(point));
      case PlacingDropoff(:final pickup):
        emit(PackagePlaced(pickup, point));
      case PlacementIdle() || RiderPlaced() || PackagePlaced():
        break;
    }
  }
}
