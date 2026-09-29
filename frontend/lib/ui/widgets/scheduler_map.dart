import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../bloc/placement/placement_cubit.dart';
import '../../bloc/scheduler/scheduler_bloc.dart';
import '../../data/models/models.dart';
import '../theme.dart';
import 'basemap.dart';
import 'map_lines_layer.dart';
import 'map_markers.dart';
import 'radar_layer.dart';

/// The live map, centred on the admin.
///
/// Layers, bottom to top: basemap tiles (Mapbox or OSM), breathing radar disks (match radius)
/// around waiting packages, drop-off lines, fresh-assignment lines, then markers.
class SchedulerMap extends StatefulWidget {
  const SchedulerMap({required this.controller, super.key});

  final MapController controller;

  @override
  State<SchedulerMap> createState() => _SchedulerMapState();
}

class _SchedulerMapState extends State<SchedulerMap> {
  bool _showRadius = true;
  bool _showDropoffs = false;

  @override
  Widget build(BuildContext context) {
    final placement = context.watch<PlacementCubit>().state;
    final state = context.watch<SchedulerBloc>().state;
    final admin = state.admin!;
    final packages = state.packages.values.toList();
    final riders = state.riders.values.toList();

    return Stack(
      children: [
        MouseRegion(
          cursor: placement.prompt != null
              ? SystemMouseCursors.precise
              : MouseCursor.defer,
          child: FlutterMap(
            mapController: widget.controller,
            options: MapOptions(
              initialCenter: admin.location.toLatLng(),
              initialZoom: 12,
              minZoom: 3,
              maxZoom: 18,
              onTap: (_, point) => context.read<PlacementCubit>().mapTapped(
                Coordinates.fromLatLng(point),
              ),
            ),
            children: [
              const BasemapLayer(),
              if (_showRadius)
                RadarLayer(
                  centers: {
                    for (final p in packages) p.id: p.pickup.toLatLng(),
                  },
                  radiusMiles: state.maxMatchRadiusMiles,
                  color: SchedulerColors.radar,
                ),
              MapLinesLayer(
                lines: [
                  if (_showDropoffs)
                    for (final p in packages)
                      MapLine(
                        from: p.pickup.toLatLng(),
                        to: p.dropoff.toLatLng(),
                        color: SchedulerColors.dropoff.withValues(alpha: 0.7),
                        width: 2,
                        dashed: true,
                      ),
                  for (final a in state.recentAssignments)
                    MapLine(
                      from: a.riderLocation.toLatLng(),
                      to: a.pickup.toLatLng(),
                      color: SchedulerColors.assignment,
                      width: 4,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (_showDropoffs)
                    for (final p in packages)
                      Marker(
                        point: p.dropoff.toLatLng(),
                        width: 22,
                        height: 22,
                        child: MapPin(
                          icon: Icons.flag,
                          color: SchedulerColors.dropoff,
                          filled: false,
                          size: 22,
                          tooltip: 'Drop-off for ${p.id}\n${p.dropoff.label}',
                        ),
                      ),
                  for (final a in state.recentAssignments) ...[
                    Marker(
                      key: ValueKey('asg-pickup-${a.id}'),
                      point: a.pickup.toLatLng(),
                      width: 64,
                      height: 64,
                      child: PulsingPin(
                        color: SchedulerColors.assignment,
                        child: MapPin(
                          icon: Icons.inventory_2,
                          color: SchedulerColors.assignment,
                          tooltip: '${a.packageId} → ${a.riderId}',
                        ),
                      ),
                    ),
                    Marker(
                      key: ValueKey('asg-rider-${a.id}'),
                      point: a.riderLocation.toLatLng(),
                      width: 64,
                      height: 64,
                      child: PulsingPin(
                        color: SchedulerColors.assignment,
                        child: MapPin(
                          icon: Icons.two_wheeler,
                          color: SchedulerColors.assignment,
                          tooltip: '${a.riderName} (${a.riderId})',
                        ),
                      ),
                    ),
                  ],
                  for (final p in packages)
                    Marker(
                      key: ValueKey(p.id),
                      point: p.pickup.toLatLng(),
                      width: 34,
                      height: 34,
                      child: MapPin(
                        icon: Icons.inventory_2,
                        color: SchedulerColors.package,
                        tooltip:
                            '${p.id} · waiting\nPickup: ${p.pickup.label}'
                            '\nDrop-off: ${p.dropoff.label}',
                      ),
                    ),
                  for (final r in riders)
                    Marker(
                      key: ValueKey(r.id),
                      point: r.location.toLatLng(),
                      width: 34,
                      height: 34,
                      child: MapPin(
                        icon: Icons.two_wheeler,
                        color: SchedulerColors.rider,
                        tooltip: '${r.name} (${r.id}) · available',
                      ),
                    ),
                  Marker(
                    point: admin.location.toLatLng(),
                    width: 42,
                    height: 42,
                    child: MapPin(
                      icon: Icons.home_work,
                      color: SchedulerColors.admin,
                      size: 42,
                      tooltip:
                          '${admin.name} (admin)\n'
                          '${admin.location.format()}',
                    ),
                  ),
                  if (placement case PlacingDropoff(:final pickup))
                    Marker(
                      point: pickup.toLatLng(),
                      width: 34,
                      height: 34,
                      child: const MapPin(
                        icon: Icons.inventory_2,
                        color: SchedulerColors.package,
                        filled: false,
                        tooltip: 'New package pickup',
                      ),
                    ),
                ],
              ),
              const BasemapAttribution(),
            ],
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: _LayerToggles(
            showRadius: _showRadius,
            showDropoffs: _showDropoffs,
            radiusMiles: state.maxMatchRadiusMiles,
            onRadiusChanged: (v) => setState(() => _showRadius = v),
            onDropoffsChanged: (v) => setState(() => _showDropoffs = v),
          ),
        ),
        if (placement.prompt case final String prompt)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(child: _PlacementBanner(prompt: prompt)),
          ),
      ],
    );
  }
}

class _LayerToggles extends StatelessWidget {
  const _LayerToggles({
    required this.showRadius,
    required this.showDropoffs,
    required this.radiusMiles,
    required this.onRadiusChanged,
    required this.onDropoffsChanged,
  });

  final bool showRadius;
  final bool showDropoffs;
  final double radiusMiles;
  final ValueChanged<bool> onRadiusChanged;
  final ValueChanged<bool> onDropoffsChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FilterChip(
              label: Text('${radiusMiles.toStringAsFixed(0)} mi match radius'),
              selected: showRadius,
              onSelected: onRadiusChanged,
            ),
            const SizedBox(height: 6),
            FilterChip(
              label: const Text('Drop-offs'),
              selected: showDropoffs,
              onSelected: onDropoffsChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlacementBanner extends StatelessWidget {
  const _PlacementBanner({required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(28),
      color: theme.colorScheme.inverseSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 6, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, color: theme.colorScheme.onInverseSurface),
            const SizedBox(width: 10),
            Text(
              prompt,
              style: TextStyle(color: theme.colorScheme.onInverseSurface),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: context.read<PlacementCubit>().cancel,
              child: Text(
                'Cancel',
                style: TextStyle(color: theme.colorScheme.inversePrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
