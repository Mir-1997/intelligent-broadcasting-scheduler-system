import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

double _toDouble(Object? value) => (value! as num).toDouble();

/// A WGS84 coordinate, mirroring the backend `Location` schema.
class Coordinates extends Equatable {
  const Coordinates({required this.lat, required this.lng});

  factory Coordinates.fromJson(Map<String, dynamic> json) =>
      Coordinates(lat: _toDouble(json['lat']), lng: _toDouble(json['lng']));

  factory Coordinates.fromLatLng(LatLng point) =>
      Coordinates(lat: point.latitude, lng: point.longitude);

  final double lat;
  final double lng;

  LatLng toLatLng() => LatLng(lat, lng);

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  /// `40.75800, -73.98550`
  String format() => '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

  @override
  List<Object?> get props => [lat, lng];
}

/// A coordinate with an optional address, mirroring the backend `Place` schema.
class Place extends Equatable {
  const Place({required this.lat, required this.lng, this.address = ''});

  factory Place.fromJson(Map<String, dynamic> json) => Place(
    lat: _toDouble(json['lat']),
    lng: _toDouble(json['lng']),
    address: json['address'] as String? ?? '',
  );

  final double lat;
  final double lng;
  final String address;

  Coordinates get coordinates => Coordinates(lat: lat, lng: lng);

  LatLng toLatLng() => LatLng(lat, lng);

  /// The address if there is one, otherwise the formatted coordinates.
  String get label => address.isNotEmpty ? address : coordinates.format();

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'address': address};

  @override
  List<Object?> get props => [lat, lng, address];
}
