import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Raster tiles for the web build.
///
/// Web renders through flutter_map rather than Google, so the tiles come from a
/// raster source. CARTO's dark basemap is used because it matches the app's
/// palette — a pale map under a near-black interface looks like a window into
/// something else, and the green route is hard to see on light streets.
///
/// CARTO's basemaps are free for reasonable use and carry OpenStreetMap data.
/// The attribution below is required by both and must stay visible.
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

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => onSourceChanged?.call('ONLINE_CARTO'));

    return TileLayer(
      urlTemplate:
          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
      subdomains: const ['a', 'b', 'c', 'd'],
      // Retina tiles on high-density screens; {r} resolves to "@2x".
      retinaMode: RetinaMode.isHighDensity(context),
      userAgentPackageName: 'com.udrive.mobile',
      maxNativeZoom: 20,
    );
  }
}
