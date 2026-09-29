import 'dart:async';
import 'dart:convert';

import 'package:broadcast_scheduler_ui/data/models/models.dart';
import 'package:broadcast_scheduler_ui/data/realtime/scheduler_socket.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';

class FakeConnection implements SocketConnection {
  FakeConnection({this.fail = false});

  final bool fail;
  final incoming = StreamController<dynamic>();
  final sent = <String>[];
  bool closed = false;

  @override
  Future<void> get ready =>
      fail ? Future.error(Exception('refused')) : Future.value();

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  void send(String message) => sent.add(message);

  @override
  Future<void> close() async {
    closed = true;
    await incoming.close();
  }
}

void main() {
  late List<FakeConnection> connections;
  late List<bool> plan; // per attempt: true = fail

  SchedulerSocket buildSocket() {
    connections = [];
    return SchedulerSocket(
      uri: Uri.parse('ws://test/ws/scheduler'),
      pingInterval: const Duration(seconds: 5),
      initialBackoff: const Duration(seconds: 1),
      maxBackoff: const Duration(seconds: 4),
      connector: (_) {
        final fail =
            connections.length < plan.length && plan[connections.length];
        final c = FakeConnection(fail: fail);
        connections.add(c);
        return c;
      },
    );
  }

  test('connects, decodes events and ignores junk', () {
    fakeAsync((async) {
      plan = [];
      final socket = buildSocket();
      final statuses = <ConnectionStatus>[];
      final events = <ServerEvent>[];
      socket.statusChanges.listen(statuses.add);
      socket.events.listen(events.add);

      socket.connect();
      async.flushMicrotasks();
      expect(statuses, [
        ConnectionStatus.connecting,
        ConnectionStatus.connected,
      ]);

      final conn = connections.single;
      conn.incoming
        ..add(jsonEncode(event('rider.removed', {'rider_id': 'r1'})))
        ..add('pong')
        ..add('{not json')
        ..add(jsonEncode(event('scheduler.reset', {})));
      async.flushMicrotasks();

      expect(events, [isA<RiderRemovedEvent>(), isA<SchedulerResetEvent>()]);
      socket.dispose();
      async.flushMicrotasks();
    });
  });

  test('sends ping periodically', () {
    fakeAsync((async) {
      plan = [];
      final socket = buildSocket()..connect();
      async.elapse(const Duration(seconds: 11));
      expect(connections.single.sent, ['ping', 'ping']);
      socket.dispose();
      async.flushMicrotasks();
    });
  });

  test('reconnects with exponential backoff after failures', () {
    fakeAsync((async) {
      plan = [true, true, true, false];
      final socket = buildSocket();
      final statuses = <ConnectionStatus>[];
      socket.statusChanges.listen(statuses.add);

      socket.connect();
      async.flushMicrotasks();
      expect(connections.length, 1);

      async.elapse(const Duration(seconds: 1)); // backoff 1s
      expect(connections.length, 2);
      async.elapse(const Duration(seconds: 2)); // backoff 2s
      expect(connections.length, 3);
      async.elapse(const Duration(seconds: 3)); // backoff 4s: not yet
      expect(connections.length, 3);
      async.elapse(const Duration(seconds: 1));
      expect(connections.length, 4);
      expect(socket.status, ConnectionStatus.connected);
      expect(statuses.first, ConnectionStatus.connecting);
      expect(statuses.last, ConnectionStatus.connected);

      socket.dispose();
      async.flushMicrotasks();
    });
  });

  test('reconnects when an open connection drops', () {
    fakeAsync((async) {
      plan = [];
      final socket = buildSocket()..connect();
      async.flushMicrotasks();

      connections.single.incoming.close();
      async.flushMicrotasks();
      expect(socket.status, ConnectionStatus.reconnecting);

      async.elapse(const Duration(seconds: 1));
      expect(connections.length, 2);
      expect(socket.status, ConnectionStatus.connected);

      socket.dispose();
      async.flushMicrotasks();
    });
  });

  test('disconnect stops reconnecting', () {
    fakeAsync((async) {
      plan = [true, true];
      final socket = buildSocket()..connect();
      async.flushMicrotasks();
      socket.disconnect();
      async.elapse(const Duration(seconds: 30));
      expect(connections.length, 1);
      expect(socket.status, ConnectionStatus.disconnected);
      socket.dispose();
      async.flushMicrotasks();
    });
  });
}
