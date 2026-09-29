import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/history/history_bloc.dart';
import '../../bloc/scheduler/scheduler_bloc.dart';
import '../../data/models/models.dart';
import '../dialogs/radius_settings_dialog.dart';
import '../formatting.dart';
import '../theme.dart';
import 'clock_builder.dart';

/// Tabs: what's in the scheduler right now, and the assignment history.
class SidePanel extends StatelessWidget {
  const SidePanel({required this.onFocus, super.key});

  /// Called when the user picks an item, so the map can pan to it.
  final ValueChanged<Coordinates> onFocus;

  @override
  Widget build(BuildContext context) {
    final count = context.select(
      (SchedulerBloc b) => b.state.packages.length + b.state.riders.length,
    );
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: 'Scheduler ($count)'),
              const Tab(text: 'History'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _SchedulerTab(onFocus: onFocus),
                _HistoryTab(onFocus: onFocus),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SchedulerTab extends StatelessWidget {
  const _SchedulerTab({required this.onFocus});

  final ValueChanged<Coordinates> onFocus;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SchedulerBloc>().state;
    final packages = state.packages.values.toList();
    final riders = state.riders.values.toList();
    final bloc = context.read<SchedulerBloc>();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _RadiusPolicyCard(policy: state.radiusPolicy),
        _SectionHeader(
          icon: Icons.inventory_2,
          color: SchedulerColors.package,
          title: 'Waiting packages',
          count: packages.length,
        ),
        if (packages.isEmpty)
          const _EmptyHint('No packages waiting. Every package has a rider.'),
        for (final p in packages)
          ListTile(
            dense: true,
            leading: const Icon(
              Icons.inventory_2,
              color: SchedulerColors.package,
            ),
            title: Text(p.id),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pickup: ${p.pickup.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                _SearchRadiusText(package: p, policy: state.radiusPolicy),
              ],
            ),
            isThreeLine: true,
            onTap: () => onFocus(p.pickup.coordinates),
            trailing: IconButton(
              tooltip: 'Remove from scheduler',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => bloc.add(PackageRemoveRequested(p.id)),
            ),
          ),
        const Divider(),
        _SectionHeader(
          icon: Icons.two_wheeler,
          color: SchedulerColors.rider,
          title: 'Available riders',
          count: riders.length,
        ),
        if (riders.isEmpty)
          const _EmptyHint('No riders waiting for a package.'),
        for (final r in riders)
          ListTile(
            dense: true,
            leading: const Icon(
              Icons.two_wheeler,
              color: SchedulerColors.rider,
            ),
            title: Text('${r.name} · ${r.id}'),
            subtitle: Text(
              '${r.location.format()}\nAdded ${formatTime(r.createdAt)}',
            ),
            isThreeLine: true,
            onTap: () => onFocus(r.location),
            trailing: IconButton(
              tooltip: 'Remove from scheduler',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => bloc.add(RiderRemoveRequested(r.id)),
            ),
          ),
      ],
    );
  }
}

/// Summary of the radius policy, with a button to change it.
class _RadiusPolicyCard extends StatelessWidget {
  const _RadiusPolicyCard({required this.policy});

  final RadiusPolicy policy;

  Future<void> _edit(BuildContext context) async {
    final bloc = context.read<SchedulerBloc>();
    final updated = await RadiusSettingsDialog.show(context, policy);
    if (updated != null) bloc.add(RadiusPolicyUpdateRequested(updated));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: ListTile(
        leading: const Icon(Icons.radar, color: SchedulerColors.radar),
        title: const Text('Search radius'),
        subtitle: Text(
          'Starts ${formatRadius(policy.initialRadiusMiles)} · '
          '+${formatRadius(policy.incrementMiles)} every '
          '${formatInterval(policy.interval)}\n'
          'Up to ${formatRadius(policy.maxRadiusMiles)}',
          style: theme.textTheme.bodySmall,
        ),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Change search radius',
          icon: const Icon(Icons.tune),
          onPressed: () => _edit(context),
        ),
        onTap: () => _edit(context),
      ),
    );
  }
}

/// A waiting package's current radius and a live countdown to its next growth.
class _SearchRadiusText extends StatelessWidget {
  const _SearchRadiusText({required this.package, required this.policy});

  final Package package;
  final RadiusPolicy policy;

  @override
  Widget build(BuildContext context) {
    return ClockBuilder(
      builder: (context, now) {
        final radius = policy.radiusAt(package.createdAt, now);
        final next = policy.nextExpansionAt(package.createdAt, now);
        final text = next == null
            ? 'Searching ${formatRadius(radius)} (max)'
            : 'Searching ${formatRadius(radius)} · '
                  '${formatRadius(policy.radiusAt(package.createdAt, next))} in '
                  '${formatCountdown(next.difference(now))}';
        return Row(
          children: [
            const Icon(Icons.timer_outlined, size: 14),
            const SizedBox(width: 4),
            Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
          ],
        );
      },
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.onFocus});

  final ValueChanged<Coordinates> onFocus;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HistoryBloc>().state;
    switch (state.status) {
      case HistoryStatus.initial || HistoryStatus.loading
          when state.assignments.isEmpty:
        return const Center(child: CircularProgressIndicator());
      case HistoryStatus.failure when state.assignments.isEmpty:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(state.errorMessage ?? 'Could not load history'),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () =>
                    context.read<HistoryBloc>().add(const HistoryRefreshed()),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      default:
        break;
    }
    if (state.assignments.isEmpty) {
      return const _EmptyHint('No assignments yet. Add a package and a rider.');
    }
    return ListView.separated(
      itemCount: state.assignments.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final a = state.assignments[index];
        return ListTile(
          dense: true,
          leading: const Icon(
            Icons.check_circle,
            color: SchedulerColors.assignment,
          ),
          title: Text('${a.packageId} → ${a.riderId}'),
          subtitle: Text(
            '${a.riderName} · ${formatMiles(a.distanceMiles)} · '
            '${describeTrigger(a.trigger)}\n${formatTime(a.createdAt)}',
          ),
          isThreeLine: true,
          onTap: () => onFocus(a.pickup.coordinates),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final Color color;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          Badge(label: Text('$count'), backgroundColor: color),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}
