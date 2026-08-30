import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Raster tiles for the web build.
///
/// OpenStreetMap's own tile server is used because it is the one source that
/// needs no key and cannot start needing one. CARTO's basemaps were tried first
/// and now require an API key; a map that stops working when someone else
/// changes their pricing is not a foundation to build on.
///
/// OSM tiles are light, so they are darkened here rather than swapped for a
/// dark provider — see [_darkFilter].
///
/// OSM's tile usage policy covers development and modest production traffic. If
/// UDrive's web traffic ever grows past that, the options are a paid tile
/// provider or Google's Map Tiles API, both of which drop straight into this
/// widget without touching anything else.
class OfflineAwareTileLayer extends StatelessWidget {
  const OfflineAwareTileLayer({
    super.key,
    required this.origin,
    required this.destination,
    this.onSourceChanged,
  });

  final LatLng origin;
  final LatLng destination;
  final ValueChanged<String>? onSourceChanged;

  /// Invert combined with a 180° hue rotation — the same pair CSS dark-map
  /// filters use. Inverting alone turns land grey and water white; rotating the
  /// hue back afterwards restores something close to the original colours at
  /// dark luminance, so roads stay pale against dark land and water stays blue.
  static const ColorFilter _darkFilter = ColorFilter.matrix(<double>[
    0.5740, -1.4300, -0.1440, 0.0000, 255.0000,
    -0.4260, -0.4300, -0.1440, 0.0000, 255.0000,
    -0.4260, -1.4300, 0.8560, 0.0000, 255.0000,
    0.0000, 0.0000, 0.0000, 1.0000, 0.0000,
  ]);

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => onSourceChanged?.call('ONLINE_OSM'));

    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.udrive.mobile',
      maxNativeZoom: 19,
      // Applied per tile rather than over the whole layer, so markers, the
      // route and the pin stay their true colours.
      tileBuilder: (context, tileWidget, tile) => ColorFiltered(
        colorFilter: _darkFilter,
        child: tileWidget,
      ),
    );
  }
}
