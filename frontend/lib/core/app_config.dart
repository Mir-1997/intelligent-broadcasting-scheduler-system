/// Compile-time configuration, supplied with `--dart-define`.
///
/// ```sh
/// flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
/// ```
class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  /// Reads configuration from `--dart-define` values, with local-dev defaults.
  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      apiBaseUrl: String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://localhost:8000',
      ),
    );
  }

  /// Base URL of the FastAPI backend, e.g. `http://localhost:8000`.
  final String apiBaseUrl;

  Uri get apiUri => Uri.parse(apiBaseUrl);

  /// The WebSocket endpoint, derived from [apiBaseUrl] (`http` -> `ws`, `https` -> `wss`).
  Uri get schedulerSocketUri {
    final api = apiUri;
    return api.replace(
      scheme: api.scheme == 'https' ? 'wss' : 'ws',
      path: '${api.path.replaceAll(RegExp(r'/$'), '')}/ws/scheduler',
    );
  }
}
