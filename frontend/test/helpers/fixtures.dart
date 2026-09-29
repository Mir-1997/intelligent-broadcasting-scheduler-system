import 'package:broadcast_scheduler_ui/data/models/models.dart';

final t0 = DateTime.utc(2026, 9, 23, 10);

const admin = Admin(
  name: 'HQ',
  location: Coordinates(lat: 40.758, lng: -73.9855),
);

Package package(String id, {PackageStatus status = PackageStatus.waiting}) =>
    Package(
      id: id,
      pickup: const Place(lat: 40.76, lng: -73.98, address: 'Pickup'),
      dropoff: const Place(lat: 40.77, lng: -73.98),
      status: status,
      createdAt: t0,
    );

Rider rider(String id, {RiderStatus status = RiderStatus.available}) => Rider(
  id: id,
  name: 'Rider $id',
  location: const Coordinates(lat: 40.75, lng: -73.99),
  status: status,
  createdAt: t0,
);

Assignment assignment(
  String id, {
  String pkg = 'pkg_1',
  String rdr = 'rdr_1',
}) => Assignment(
  id: id,
  packageId: pkg,
  riderId: rdr,
  riderName: 'Ali',
  distanceMiles: 1.2,
  pickup: const Place(lat: 40.76, lng: -73.98),
  dropoff: const Place(lat: 40.77, lng: -73.98),
  riderLocation: const Coordinates(lat: 40.75, lng: -73.99),
  trigger: MatchTrigger.packageAdded,
  createdAt: t0,
);

SchedulerSnapshot snapshot({
  List<Package> packages = const [],
  List<Rider> riders = const [],
}) => SchedulerSnapshot(
  admin: admin,
  packages: packages,
  riders: riders,
  maxMatchRadiusMiles: 5,
);

/// JSON exactly as the backend serialises it.
Map<String, dynamic> packageJson(String id, {String status = 'waiting'}) => {
  'id': id,
  'pickup': {'lat': 40.76, 'lng': -73.98, 'address': 'Pickup'},
  'dropoff': {'lat': 40.77, 'lng': -73.98, 'address': ''},
  'status': status,
  'created_at': '2026-09-23T10:00:00.123456Z',
  'assigned_rider_id': null,
  'assigned_at': null,
};

Map<String, dynamic> riderJson(String id, {String status = 'available'}) => {
  'id': id,
  'name': 'Ali',
  'location': {'lat': 40.75, 'lng': -73.99},
  'status': status,
  'created_at': '2026-09-23T10:00:00Z',
  'assigned_package_id': null,
  'assigned_at': null,
};

Map<String, dynamic> assignmentJson(String id) => {
  'id': id,
  'package_id': 'pkg_1',
  'rider_id': 'rdr_1',
  'rider_name': 'Ali',
  'distance_miles': 1.234,
  'pickup': {'lat': 40.76, 'lng': -73.98, 'address': 'Pickup'},
  'dropoff': {'lat': 40.77, 'lng': -73.98, 'address': ''},
  'rider_location': {'lat': 40.75, 'lng': -73.99},
  'trigger': 'rider_added',
  'created_at': '2026-09-23T10:00:01Z',
};

Map<String, dynamic> event(String type, Map<String, dynamic> data) => {
  'type': type,
  'data': data,
  'timestamp': '2026-09-23T10:00:02Z',
};
