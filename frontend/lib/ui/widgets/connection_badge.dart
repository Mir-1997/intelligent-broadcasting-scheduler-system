import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/scheduler/scheduler_bloc.dart';
import '../../data/realtime/scheduler_socket.dart';

/// Shows whether the live WebSocket feed is up.
class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.select((SchedulerBloc b) => b.state.connection);
    final (label, color) = switch (status) {
      ConnectionStatus.connected => ('Live', Colors.green),
      ConnectionStatus.connecting => ('Connecting…', Colors.amber),
      ConnectionStatus.reconnecting => ('Reconnecting…', Colors.orange),
      ConnectionStatus.disconnected => ('Offline', Colors.red),
    };
    return Tooltip(
      message: 'Realtime feed: /ws/scheduler',
      child: Chip(
        avatar: Icon(Icons.circle, size: 12, color: color),
        label: Text(label),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
