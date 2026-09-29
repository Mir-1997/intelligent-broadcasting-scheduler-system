import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Public Mapbox token (`pk.…`), read from the `MAPBOX_TOKEN` env variable in
/// the repo's `.env` via `--dart-define-from-file=../.env` (or docker compose).
///
/// Restrict it to your site's URLs in the Mapbox dashboard: it ships in the
/// JS bundle. Without one the map falls back to OpenStreetMap tiles.
const mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');

/// Mapbox style used when a token is set, e.g. `streets-v12` or `navigation-day-v1`.
const mapboxStyle = String.fromEnvironment(
  'MAPBOX_STYLE',
  defaultValue: 'streets-v12',
);

const _userAgent = 'dev.tayyabmir.broadcast_scheduler_ui';

/// The raster basemap: Mapbox Streets when [mapboxToken] is set, else OpenStreetMap.
class BasemapLayer extends StatelessWidget {
  const BasemapLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final retina = RetinaMode.isHighDensity(context);
    if (mapboxToken.isNotEmpty) {
      return TileLayer(
        urlTemplate:
            'https://api.mapbox.com/styles/v1/mapbox/{style}/tiles/256/{z}/{x}/{y}{r}'
            '?access_token={token}',
        additionalOptions: const {'style': mapboxStyle, 'token': mapboxToken},
        retinaMode: retina,
        userAgentPackageName: _userAgent,
        maxZoom: 19,
      );
    }
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: _userAgent,
      maxZoom: 19,
    );
  }
}

/// Attribution required by whichever basemap [BasemapLayer] is showing.
class BasemapAttribution extends StatelessWidget {
  const BasemapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return RichAttributionWidget(
      attributions: [
        if (mapboxToken.isNotEmpty) const TextSourceAttribution('Mapbox'),
        const TextSourceAttribution('OpenStreetMap contributors'),
      ],
    );
  }
}
