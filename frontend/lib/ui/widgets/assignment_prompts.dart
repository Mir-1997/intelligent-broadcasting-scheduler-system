import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/scheduler/scheduler_bloc.dart';
import '../../data/models/models.dart';
import '../formatting.dart';
import '../theme.dart';

/// Stacked "Package X assigned to rider Y" prompts over the map.
///
/// Driven entirely by [SchedulerState.recentAssignments]; each prompt goes
/// away on its own after the bloc's prompt duration, or when closed.
class AssignmentPrompts extends StatelessWidget {
  const AssignmentPrompts({this.maxVisible = 4, super.key});

  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final recent = context.select(
      (SchedulerBloc bloc) => bloc.state.recentAssignments,
    );
    if (recent.isEmpty) return const SizedBox.shrink();

    final hidden = recent.length - maxVisible;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final assignment in recent.take(maxVisible))
              _AssignmentPromptCard(
                key: ValueKey(assignment.id),
                assignment: assignment,
              ),
            if (hidden > 0)
              Chip(
                label: Text('+$hidden more — see History'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentPromptCard extends StatelessWidget {
  const _AssignmentPromptCard({required this.assignment, super.key});

  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, -12 * (1 - t)),
          child: child,
        ),
      ),
      child: Card(
        elevation: 6,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: SchedulerColors.assignment, width: 1.5),
        ),
        child: ListTile(
          leading: const CircleAvatar(
            backgroundColor: SchedulerColors.assignment,
            foregroundColor: Colors.white,
            child: Icon(Icons.check),
          ),
          title: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Package '),
                TextSpan(
                  text: assignment.packageId,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' assigned to rider '),
                TextSpan(
                  text: assignment.riderId,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          subtitle: Text(
            '${assignment.riderName} · ${formatMiles(assignment.distanceMiles)}'
            ' from pickup · ${describeTrigger(assignment.trigger)}',
            style: theme.textTheme.bodySmall,
          ),
          trailing: IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close),
            onPressed: () => context.read<SchedulerBloc>().add(
              AssignmentPromptDismissed(assignment.id),
            ),
          ),
        ),
      ),
    );
  }
}
