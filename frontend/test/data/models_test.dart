import 'package:broadcast_scheduler_ui/core/app_config.dart';
import 'package:broadcast_scheduler_ui/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';

void main() {
  group('entities', () {
    test('Package.fromJson parses backend payload', () {
      final p = Package.fromJson(packageJson('pkg_1'));
      expect(p.id, 'pkg_1');
      expect(p.isWaiting, isTrue);
      expect(p.pickup.address, 'Pickup');
      expect(p.dropoff.label, '40.77000, -73.98000');
      expect(p.createdAt.isUtc, isTrue);
      expect(p.createdAt.microsecond, 456);
    });

    test('Rider.fromJson accepts integer coordinates', () {
      final json = riderJson('rdr_1')..['location'] = {'lat': 40, 'lng': -73};
      final r = Rider.fromJson(json);
      expect(r.location, const Coordinates(lat: 40, lng: -73));
      expect(r.isAvailable, isTrue);
    });

    test('Assignment.fromJson maps trigger wire names', () {
      final a = Assignment.fromJson(assignmentJson('asg_1'));
      expect(a.trigger, MatchTrigger.riderAdded);
      expect(a.distanceMiles, 1.234);
      expect(a.riderLocation.lat, 40.75);
    });

    test('drafts serialise to the backend request shape', () {
      const draft = PackageDraft(
        pickup: Place(lat: 1, lng: 2, address: 'A'),
        dropoff: Place(lat: 3, lng: 4),
      );
      expect(draft.toJson(), {
        'pickup': {'lat': 1.0, 'lng': 2.0, 'address': 'A'},
        'dropoff': {'lat': 3.0, 'lng': 4.0, 'address': ''},
      });
      expect(
        const SimulationDraft(packages: 2, riders: 3, radiusMiles: 4).toJson(),
        {'packages': 2, 'riders': 3, 'radius_miles': 4.0},
      );
    });
  });

  group('ServerEvent.fromJson', () {
    test('snapshot', () {
      final e = ServerEvent.fromJson(
        event('scheduler.snapshot', {
          'admin': {
            'name': 'HQ',
            'location': {'lat': 1, 'lng': 2},
          },
          'packages': [packageJson('pkg_1')],
          'riders': [riderJson('rdr_1')],
          'max_match_radius_miles': 5,
        }),
      );
      expect(e, isA<SnapshotEvent>());
      final snap = (e as SnapshotEvent).snapshot;
      expect(snap.packages.single.id, 'pkg_1');
      expect(snap.riders.single.id, 'rdr_1');
      expect(snap.maxMatchRadiusMiles, 5);
    });

    test('every delta type', () {
      expect(
        ServerEvent.fromJson(
          event('package.added', {'package': packageJson('p')}),
        ),
        isA<PackageAddedEvent>(),
      );
      expect(
        ServerEvent.fromJson(event('package.removed', {'package_id': 'p'})),
        isA<PackageRemovedEvent>().having((e) => e.packageId, 'id', 'p'),
      );
      expect(
        ServerEvent.fromJson(event('rider.added', {'rider': riderJson('r')})),
        isA<RiderAddedEvent>(),
      );
      expect(
        ServerEvent.fromJson(event('rider.removed', {'rider_id': 'r'})),
        isA<RiderRemovedEvent>().having((e) => e.riderId, 'id', 'r'),
      );
      expect(
        ServerEvent.fromJson(
          event('assignment.created', {'assignment': assignmentJson('a')}),
        ),
        isA<AssignmentCreatedEvent>(),
      );
      expect(
        ServerEvent.fromJson(
          event('admin.updated', {
            'admin': {
              'name': 'X',
              'location': {'lat': 0, 'lng': 0},
            },
          }),
        ),
        isA<AdminUpdatedEvent>(),
      );
      expect(
        ServerEvent.fromJson(event('scheduler.reset', {})),
        isA<SchedulerResetEvent>(),
      );
    });

    test('unknown types do not throw', () {
      final e = ServerEvent.fromJson(event('something.new', {}));
      expect(
        e,
        isA<UnknownEvent>().having((e) => e.type, 'type', 'something.new'),
      );
    });
  });

  group('AppConfig', () {
    test('derives ws url from http base', () {
      const config = AppConfig(apiBaseUrl: 'http://localhost:8000');
      expect(
        config.schedulerSocketUri.toString(),
        'ws://localhost:8000/ws/scheduler',
      );
    });

    test('derives wss url and keeps a path prefix', () {
      const config = AppConfig(apiBaseUrl: 'https://example.com/api/');
      expect(
        config.schedulerSocketUri.toString(),
        'wss://example.com/api/ws/scheduler',
      );
    });
  });
}
