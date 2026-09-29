/// A failed backend call, carrying a message that is safe to show to the user.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  /// HTTP status code, or `null` when the server could not be reached at all.
  final int? statusCode;
  final String message;

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode: $message';
}
