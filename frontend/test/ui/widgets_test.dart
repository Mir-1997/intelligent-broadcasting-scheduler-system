import 'package:bloc_test/bloc_test.dart';
import 'package:broadcast_scheduler_ui/bloc/history/history_bloc.dart';
import 'package:broadcast_scheduler_ui/bloc/scheduler/scheduler_bloc.dart';
import 'package:broadcast_scheduler_ui/data/models/models.dart';
import 'package:broadcast_scheduler_ui/ui/widgets/assignment_prompts.dart';
import 'package:broadcast_scheduler_ui/ui/widgets/side_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fixtures.dart';

class MockSchedulerBloc extends MockBloc<SchedulerEvent, SchedulerState>
    implements SchedulerBloc {}

class MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

void main() {
  late MockSchedulerBloc scheduler;
  late MockHistoryBloc history;

  setUp(() {
    scheduler = MockSchedulerBloc();
    history = MockHistoryBloc();
  });

  Widget host(Widget child) => MultiBlocProvider(
    providers: [
      BlocProvider<SchedulerBloc>.value(value: scheduler),
      BlocProvider<HistoryBloc>.value(value: history),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );

  testWidgets('assignment prompt names package and rider, and dismisses', (
    tester,
  ) async {
    when(() => scheduler.state).thenReturn(
      SchedulerState(
        recentAssignments: [assignment('a1', pkg: 'pkg_42', rdr: 'rdr_7')],
      ),
    );
    await tester.pumpWidget(host(const AssignmentPrompts()));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Package pkg_42 assigned to rider rdr_7',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('1.20 mi'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    verify(
      () => scheduler.add(const AssignmentPromptDismissed('a1')),
    ).called(1);
  });

  testWidgets('prompts overflow into a "+N more" chip', (tester) async {
    when(() => scheduler.state).thenReturn(
      SchedulerState(
        recentAssignments: [for (var i = 0; i < 6; i++) assignment('a$i')],
      ),
    );
    await tester.pumpWidget(host(const AssignmentPrompts(maxVisible: 4)));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(4));
    expect(find.text('+2 more — see History'), findsOneWidget);
  });

  testWidgets('side panel lists waiting items and removes them', (
    tester,
  ) async {
    when(() => scheduler.state).thenReturn(
      SchedulerState(
        packages: {'pkg_1': package('pkg_1')},
        riders: {'rdr_1': rider('rdr_1')},
      ),
    );
    when(
      () => history.state,
    ).thenReturn(const HistoryState(status: HistoryStatus.ready));

    await tester.pumpWidget(host(SidePanel(onFocus: (_) {})));
    expect(find.text('Scheduler (2)'), findsOneWidget);
    expect(find.text('pkg_1'), findsOneWidget);
    expect(find.text('Rider rdr_1 · rdr_1'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove from scheduler').first);
    verify(
      () => scheduler.add(const PackageRemoveRequested('pkg_1')),
    ).called(1);
  });

  testWidgets('waiting package shows its search radius and countdown', (
    tester,
  ) async {
    final since = DateTime.now().subtract(const Duration(seconds: 35));
    when(() => scheduler.state).thenReturn(
      SchedulerState(
        packages: {
          'pkg_1': Package(
            id: 'pkg_1',
            pickup: const Place(lat: 40.76, lng: -73.98),
            dropoff: const Place(lat: 40.77, lng: -73.98),
            status: PackageStatus.waiting,
            createdAt: since,
          ),
        },
      ),
    );
    when(
      () => history.state,
    ).thenReturn(const HistoryState(status: HistoryStatus.ready));

    await tester.pumpWidget(host(SidePanel(onFocus: (_) {})));
    expect(find.text('Starts 1 mi · +2 mi every 30 s\nUp to 15 mi'), findsOne);
    // 35 s in: grown once to 3 mi, next growth to 5 mi in ~25 s.
    expect(find.textContaining('Searching 3 mi · 5 mi in 0:2'), findsOne);
  });

  testWidgets('radius settings dialog applies a new policy', (tester) async {
    when(() => scheduler.state).thenReturn(const SchedulerState());
    when(
      () => history.state,
    ).thenReturn(const HistoryState(status: HistoryStatus.ready));
    await tester.pumpWidget(host(SidePanel(onFocus: (_) {})));

    await tester.tap(find.byTooltip('Change search radius'));
    await tester.pumpAndSettle();
    expect(find.text('Starting radius: 1 mi'), findsOne);
    expect(
      find.text(
        'Starts at 1 mi, grows 2 mi every 30 s, and reaches the 15 mi cap '
        'after 3 min 30 s.',
      ),
      findsOne,
    );

    // Drag the "Increase by" slider (0-10 mi) all the way right.
    await tester.drag(find.byType(Slider).at(1), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Increase by: 10 mi'), findsOne);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    verify(
      () => scheduler.add(
        const RadiusPolicyUpdateRequested(RadiusPolicy(incrementMiles: 10)),
      ),
    ).called(1);
  });

  testWidgets('history tab shows assignments', (tester) async {
    when(() => scheduler.state).thenReturn(const SchedulerState());
    when(() => history.state).thenReturn(
      HistoryState(
        status: HistoryStatus.ready,
        assignments: [assignment('a1')],
      ),
    );
    await tester.pumpWidget(host(SidePanel(onFocus: (_) {})));
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('pkg_1 → rdr_1'), findsOneWidget);
  });
}
