import 'dart:convert';

import 'package:broadcast_scheduler_ui/core/api_exception.dart';
import 'package:broadcast_scheduler_ui/data/api/scheduler_api_client.dart';
import 'package:broadcast_scheduler_ui/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/fixtures.dart';

void main() {
  late List<http.Request> requests;

  SchedulerApiClient clientReturning(int status, Object? body) {
    requests = [];
    return SchedulerApiClient(
      baseUri: Uri.parse('http://api.test'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(body == null ? '' : jsonEncode(body), status);
      }),
    );
  }

  test('getAdmin parses the admin', () async {
    final api = clientReturning(200, {
      'name': 'HQ',
      'location': {'lat': 1.5, 'lng': 2.5},
    });
    final admin = await api.getAdmin();
    expect(admin.location, const Coordinates(lat: 1.5, lng: 2.5));
    expect(requests.single.url.toString(), 'http://api.test/admin');
  });

  test('getAssignments sends the limit', () async {
    final api = clientReturning(200, [assignmentJson('asg_1')]);
    final list = await api.getAssignments(limit: 10);
    expect(list.single.id, 'asg_1');
    expect(requests.single.url.queryParameters, {'limit': '10'});
  });

  test('addRider posts JSON', () async {
    final api = clientReturning(201, {
      'rider': riderJson('r'),
      'assignment': null,
    });
    await api.addRider(
      const RiderDraft(name: 'Ali', location: Coordinates(lat: 1, lng: 2)),
    );
    final request = requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/riders');
    expect(request.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(request.body), {
      'name': 'Ali',
      'location': {'lat': 1.0, 'lng': 2.0},
    });
  });

  test('delete and reset use the right verbs', () async {
    final api = clientReturning(204, null);
    await api.removePackage('pkg_1');
    await api.removeRider('rdr_1');
    await api.reset();
    expect(requests.map((r) => '${r.method} ${r.url.path}'), [
      'DELETE /packages/pkg_1',
      'DELETE /riders/rdr_1',
      'POST /scheduler/reset',
    ]);
  });

  test('string detail becomes ApiException message', () async {
    final api = clientReturning(409, {
      'detail': 'Package pkg_1 is already assigned',
    });
    expect(
      () => api.removePackage('pkg_1'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', 409)
            .having((e) => e.message, 'message', contains('already assigned')),
      ),
    );
  });

  test('validation detail list is summarised', () async {
    final api = clientReturning(422, {
      'detail': [
        {
          'loc': ['body', 'location', 'lat'],
          'msg': 'Input should be less than or equal to 90',
        },
      ],
    });
    expect(
      () => api.addRider(
        const RiderDraft(name: 'x', location: Coordinates(lat: 99, lng: 0)),
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'location.lat: Input should be less than or equal to 90',
        ),
      ),
    );
  });

  test('network failure becomes a friendly ApiException', () async {
    final api = SchedulerApiClient(
      baseUri: Uri.parse('http://api.test'),
      httpClient: MockClient((_) => throw http.ClientException('refused')),
    );
    expect(
      api.getAdmin,
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', isNull)
            .having((e) => e.message, 'message', contains('Cannot reach')),
      ),
    );
  });
}
