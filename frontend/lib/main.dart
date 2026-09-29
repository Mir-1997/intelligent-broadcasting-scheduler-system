import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_config.dart';
import 'data/api/scheduler_api_client.dart';
import 'data/realtime/scheduler_socket.dart';
import 'data/repositories/scheduler_repository.dart';

void main() {
  final config = AppConfig.fromEnvironment();
  final repository = SchedulerRepository(
    api: SchedulerApiClient(baseUri: config.apiUri),
    socket: SchedulerSocket(uri: config.schedulerSocketUri),
  );
  runApp(BroadcastSchedulerApp(repository: repository));
}
