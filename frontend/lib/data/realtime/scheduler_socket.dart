import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/models.dart';

/// State of the live connection, shown in the app bar.
enum ConnectionStatus { connecting, connected, reconnecting, disconnected }

/// Minimal socket abstraction so tests can substitute a fake transport.
abstract interface class SocketConnection {
  Future<void> get ready;
  Stream<dynamic> get stream;
  void send(String message);
  Future<void> close();
}

typedef SocketConnector = SocketConnection Function(Uri uri);

class _ChannelConnection implements SocketConnection {
  _ChannelConnection(Uri uri) : _channel = WebSocketChannel.connect(uri);

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  void send(String message) => _channel.sink.add(message);

  @override
  Future<void> close() async => _channel.sink.close();
}

/// A self-healing connection to `/ws/scheduler`.
///
/// * Emits decoded [ServerEvent]s on [events].
/// * Reconnects with exponential backoff (capped at [maxBackoff]) whenever the
///   connection drops. Because the server sends a fresh `scheduler.snapshot`
///   on every connect, a reconnect fully resynchronises the client.
/// * Sends `"ping"` every [pingInterval] to keep proxies from idling it out.
class SchedulerSocket {
  SchedulerSocket({
    required this.uri,
    SocketConnector? connector,
    this.pingInterval = const Duration(seconds: 25),
    this.initialBackoff = const Duration(milliseconds: 500),
    this.maxBackoff = const Duration(seconds: 10),
  }) : _connector = connector ?? _ChannelConnection.new;

  final Uri uri;
  final Duration pingInterval;
  final Duration initialBackoff;
  final Duration maxBackoff;
  final SocketConnector _connector;

  final _events = StreamController<ServerEvent>.broadcast();
  final _status = StreamController<ConnectionStatus>.broadcast();

  SocketConnection? _connection;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _failedAttempts = 0;
  bool _stopped = true;
  ConnectionStatus _current = ConnectionStatus.disconnected;

  Stream<ServerEvent> get events => _events.stream;

  Stream<ConnectionStatus> get statusChanges => _status.stream;

  ConnectionStatus get status => _current;

  /// Starts connecting. Safe to call more than once.
  void connect() {
    if (!_stopped) return;
    _stopped = false;
    _failedAttempts = 0;
    unawaited(_open());
  }

  Future<void> _open() async {
    _setStatus(
      _failedAttempts == 0
          ? ConnectionStatus.connecting
          : ConnectionStatus.reconnecting,
    );
    final connection = _connector(uri);
    try {
      await connection.ready;
    } catch (_) {
      _scheduleReconnect();
      return;
    }
    if (_stopped) {
      await connection.close();
      return;
    }
    _connection = connection;
    _failedAttempts = 0;
    _setStatus(ConnectionStatus.connected);
    _subscription = connection.stream.listen(
      _onMessage,
      onError: (Object _) => _onClosed(),
      onDone: _onClosed,
      cancelOnError: true,
    );
    _pingTimer = Timer.periodic(pingInterval, (_) => connection.send('ping'));
  }

  void _onMessage(dynamic message) {
    if (message is! String || message == 'pong') return;
    try {
      final decoded = jsonDecode(message) as Map<String, dynamic>;
      _events.add(ServerEvent.fromJson(decoded));
    } on Object {
      // A malformed message must never take the connection down; skip it.
    }
  }

  void _onClosed() {
    _teardownConnection();
    if (!_stopped) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _failedAttempts++;
    _setStatus(ConnectionStatus.reconnecting);
    final exponent = min(_failedAttempts - 1, 10);
    final delay = initialBackoff * pow(2, exponent).toInt();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay > maxBackoff ? maxBackoff : delay, () {
      if (!_stopped) unawaited(_open());
    });
  }

  void _teardownConnection() {
    _pingTimer?.cancel();
    _pingTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    final connection = _connection;
    _connection = null;
    if (connection != null) unawaited(connection.close());
  }

  void _setStatus(ConnectionStatus status) {
    if (_current == status) return;
    _current = status;
    _status.add(status);
  }

  /// Closes the connection and stops reconnecting.
  Future<void> disconnect() async {
    _stopped = true;
    _reconnectTimer?.cancel();
    _teardownConnection();
    _setStatus(ConnectionStatus.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _status.close();
  }
}
