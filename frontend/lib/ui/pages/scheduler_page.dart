import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../bloc/placement/placement_cubit.dart';
import '../../bloc/scheduler/scheduler_bloc.dart';
import '../../data/models/models.dart';
import '../dialogs/add_package_dialog.dart';
import '../dialogs/add_rider_dialog.dart';
import '../dialogs/confirm_reset_dialog.dart';
import '../dialogs/simulate_dialog.dart';
import '../theme.dart';
import '../widgets/assignment_prompts.dart';
import '../widgets/connection_badge.dart';
import '../widgets/scheduler_map.dart';
import '../widgets/side_panel.dart';

/// Below this width the side panel moves into an end drawer.
const _wideLayoutBreakpoint = 960.0;
const _focusZoom = 15.0;

/// The one screen of the app: toolbar, live map and side panel.
class SchedulerPage extends StatefulWidget {
  const SchedulerPage({super.key});

  @override
  State<SchedulerPage> createState() => _SchedulerPageState();
}

class _SchedulerPageState extends State<SchedulerPage> {
  final _map = MapController();
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _focus(Coordinates point) {
    _scaffold.currentState?.closeEndDrawer();
    _map.move(point.toLatLng(), _focusZoom);
  }

  Coordinates get _adminLocation =>
      context.read<SchedulerBloc>().state.admin!.location;

  Future<void> _addRider(Coordinates initial) async {
    final draft = await AddRiderDialog.show(context, initial);
    if (draft != null && mounted) {
      context.read<SchedulerBloc>().add(RiderAddRequested(draft));
    }
  }

  Future<void> _addPackage(Coordinates pickup, Coordinates dropoff) async {
    final draft = await AddPackageDialog.show(
      context,
      pickup: pickup,
      dropoff: dropoff,
    );
    if (draft != null && mounted) {
      context.read<SchedulerBloc>().add(PackageAddRequested(draft));
    }
  }

  Future<void> _simulate() async {
    final bloc = context.read<SchedulerBloc>();
    final draft = await SimulateDialog.show(
      context,
      matchRadiusMiles: bloc.state.maxMatchRadiusMiles,
    );
    if (draft != null) bloc.add(SimulationRequested(draft));
  }

  Future<void> _reset() async {
    final bloc = context.read<SchedulerBloc>();
    if (await confirmReset(context)) bloc.add(const SchedulerResetRequested());
  }

  /// Opens the matching dialog once a map placement completes.
  void _onPlacement(BuildContext context, PlacementState placement) {
    final cubit = context.read<PlacementCubit>();
    switch (placement) {
      case RiderPlaced(:final location):
        cubit.cancel();
        _addRider(location);
      case PackagePlaced(:final pickup, :final dropoff):
        cubit.cancel();
        _addPackage(pickup, dropoff);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<SchedulerBloc, SchedulerState>(
          listenWhen: (a, b) =>
              b.errorMessage != null && a.errorMessage != b.errorMessage,
          listener: (context, state) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
            context.read<SchedulerBloc>().add(const SchedulerErrorDismissed());
          },
        ),
        BlocListener<SchedulerBloc, SchedulerState>(
          listenWhen: (a, b) => a.admin != null && a.admin != b.admin,
          listener: (context, state) =>
              _map.move(state.admin!.location.toLatLng(), _map.camera.zoom),
        ),
        BlocListener<PlacementCubit, PlacementState>(listener: _onPlacement),
      ],
      child: BlocBuilder<SchedulerBloc, SchedulerState>(
        buildWhen: (a, b) =>
            a.loadStatus != b.loadStatus ||
            (a.admin == null) != (b.admin == null),
        builder: (context, state) => switch (state.loadStatus) {
          SchedulerLoadStatus.ready => _buildReady(context),
          SchedulerLoadStatus.failure => _LoadFailure(
            message: state.errorMessage,
          ),
          _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
        },
      ),
    );
  }

  Widget _buildReady(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;
    final panel = SidePanel(onFocus: _focus);
    final placement = context.read<PlacementCubit>();

    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        title: Text(wide ? 'Broadcasting Scheduler' : 'Scheduler'),
        bottom: const _BusyIndicator(),
        actions: [
          const ConnectionBadge(),
          SizedBox(width: wide ? 12 : 4),
          _AddMenu(
            label: 'Package',
            icon: Icons.inventory_2,
            color: SchedulerColors.package,
            compact: !wide,
            onPickOnMap: placement.startPackage,
            onEnterCoordinates: () {
              final admin = _adminLocation;
              _addPackage(
                admin,
                Coordinates(lat: admin.lat + 0.01, lng: admin.lng + 0.01),
              );
            },
          ),
          if (wide) const SizedBox(width: 8),
          _AddMenu(
            label: 'Rider',
            icon: Icons.two_wheeler,
            color: SchedulerColors.rider,
            compact: !wide,
            onPickOnMap: placement.startRider,
            onEnterCoordinates: () => _addRider(_adminLocation),
          ),
          if (wide) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _simulate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Simulate'),
            ),
            IconButton(
              tooltip: 'Centre on admin',
              onPressed: () => _focus(_adminLocation),
              icon: const Icon(Icons.my_location),
            ),
            IconButton(
              tooltip: 'Reset scheduler',
              onPressed: _reset,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ] else ...[
            PopupMenuButton<VoidCallback>(
              tooltip: 'More',
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                PopupMenuItem(value: _simulate, child: const Text('Simulate')),
                PopupMenuItem(
                  value: () => _focus(_adminLocation),
                  child: const Text('Centre on admin'),
                ),
                PopupMenuItem(
                  value: _reset,
                  child: const Text('Reset scheduler'),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Scheduler & history',
              onPressed: () => _scaffold.currentState?.openEndDrawer(),
              icon: const Icon(Icons.view_sidebar_outlined),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      endDrawer: wide
          ? null
          : Drawer(width: 380, child: SafeArea(child: panel)),
      body: Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                SchedulerMap(controller: _map),
                // Bounded so the prompt stack scrolls instead of overflowing;
                // empty space inside does not intercept map clicks.
                const Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  bottom: 96,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: AssignmentPrompts(),
                  ),
                ),
              ],
            ),
          ),
          if (wide) ...[
            const VerticalDivider(width: 1),
            SizedBox(width: 380, child: panel),
          ],
        ],
      ),
    );
  }
}

class _AddMenu extends StatelessWidget {
  const _AddMenu({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPickOnMap,
    required this.onEnterCoordinates,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final Color color;

  /// Icon-only trigger for narrow screens.
  final bool compact;
  final VoidCallback onPickOnMap;
  final VoidCallback onEnterCoordinates;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.ads_click),
          onPressed: onPickOnMap,
          child: const Text('Pick on map'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_location_alt),
          onPressed: onEnterCoordinates,
          child: const Text('Enter coordinates'),
        ),
      ],
      builder: (context, controller, _) {
        void toggle() =>
            controller.isOpen ? controller.close() : controller.open();
        return compact
            ? IconButton(
                tooltip: 'Add $label',
                onPressed: toggle,
                icon: Icon(icon, color: color),
              )
            : OutlinedButton.icon(
                onPressed: toggle,
                icon: Icon(icon, color: color),
                label: Text('Add $label'),
              );
      },
    );
  }
}

class _BusyIndicator extends StatelessWidget implements PreferredSizeWidget {
  const _BusyIndicator();

  @override
  Size get preferredSize => const Size.fromHeight(3);

  @override
  Widget build(BuildContext context) {
    final busy = context.select((SchedulerBloc b) => b.state.isBusy);
    return SizedBox(
      height: 3,
      child: busy ? const LinearProgressIndicator() : null,
    );
  }
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message ?? 'Could not reach the scheduler server.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () =>
                  context.read<SchedulerBloc>().add(const SchedulerStarted()),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
