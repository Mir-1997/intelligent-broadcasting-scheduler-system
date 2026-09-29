import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_exception.dart';
import '../models/models.dart';

/// Thin typed wrapper over the backend's REST API.
///
/// Every failure surfaces as an [ApiException] with a user-presentable message.
class SchedulerApiClient {
  SchedulerApiClient({required Uri baseUri, http.Client? httpClient})
    : _baseUri = baseUri,
      _http = httpClient ?? http.Client();

  final Uri _baseUri;
  final http.Client _http;

  Future<Admin> getAdmin() async =>
      Admin.fromJson(await _send('GET', '/admin') as Map<String, dynamic>);

  Future<SchedulerSnapshot> getState() async => SchedulerSnapshot.fromJson(
    await _send('GET', '/scheduler/state') as Map<String, dynamic>,
  );

  Future<List<Assignment>> getAssignments({int limit = 50}) async {
    final body = await _send('GET', '/assignments', query: {'limit': '$limit'});
    return (body as List<dynamic>)
        .map((a) => Assignment.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  Future<void> addPackage(PackageDraft draft) =>
      _send('POST', '/packages', body: draft.toJson());

  Future<void> addRider(RiderDraft draft) =>
      _send('POST', '/riders', body: draft.toJson());

  Future<void> removePackage(String id) => _send('DELETE', '/packages/$id');

  Future<void> removeRider(String id) => _send('DELETE', '/riders/$id');

  Future<void> simulate(SimulationDraft draft) =>
      _send('POST', '/simulate', body: draft.toJson());

  Future<void> updateRadiusPolicy(RadiusPolicy policy) =>
      _send('PUT', '/settings/radius', body: policy.toJson());

  Future<void> reset() => _send('POST', '/scheduler/reset');

  void close() => _http.close();

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final basePath = _baseUri.path.replaceAll(RegExp(r'/$'), '');
    final uri = _baseUri.replace(
      path: '$basePath$path',
      queryParameters: query,
    );
    final request = http.Request(method, uri);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } on http.ClientException {
      throw const ApiException('Cannot reach the scheduler server.');
    }

    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(
        _errorMessage(decoded) ?? 'Request failed',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  /// FastAPI errors are `{"detail": "..."}` or, for validation (422),
  /// `{"detail": [{"loc": [...], "msg": "..."}]}`.
  static String? _errorMessage(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final detail = decoded['detail'];
    if (detail is String) return detail;
    if (detail is List<dynamic> && detail.isNotEmpty) {
      final first = detail.first as Map<String, dynamic>;
      final location = (first['loc'] as List<dynamic>? ?? []).skip(1).join('.');
      return location.isEmpty
          ? '${first['msg']}'
          : '$location: ${first['msg']}';
    }
    return null;
  }
}
