import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bloc/history/history_bloc.dart';
import 'bloc/placement/placement_cubit.dart';
import 'bloc/scheduler/scheduler_bloc.dart';
import 'data/repositories/scheduler_repository.dart';
import 'ui/pages/scheduler_page.dart';
import 'ui/theme.dart';

/// Root widget: provides the repository and blocs to the widget tree.
class BroadcastSchedulerApp extends StatelessWidget {
  const BroadcastSchedulerApp({required this.repository, super.key});

  final SchedulerRepository repository;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider.value(
      value: repository,
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) =>
                SchedulerBloc(repository: repository)
                  ..add(const SchedulerStarted()),
          ),
          BlocProvider(
            create: (_) =>
                HistoryBloc(repository: repository)
                  ..add(const HistoryStarted()),
          ),
          BlocProvider(create: (_) => PlacementCubit()),
        ],
        child: MaterialApp(
          title: 'Broadcasting Scheduler',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const SchedulerPage(),
        ),
      ),
    );
  }
}
