import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../network/api_config.dart';

/// Raster tiles for the web build.
///
/// These are **Google's own map tiles**, served through the UDrive API rather
/// than fetched directly. Google's Map Tiles API returns the same cartography
/// the Maps SDK draws, as plain raster images, which flutter_map renders on
/// Flutter's own canvas — so the map looks like Google's without the platform
/// view that made `google_maps_flutter_web` unreliable here.
///
/// Proxying keeps the key on the server. A tile URL built in the browser would
/// carry the key in plain sight of anyone who opens devtools.
///
/// If the proxy cannot serve a tile — no key configured, Map Tiles API not
/// enabled, quota reached — OpenStreetMap is used instead. A usable map beats a
/// blank one, and the difference is visible enough that a misconfiguration will
/// not go unnoticed.
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
        .addPostFrameCallback((_) => onSourceChanged?.call('GOOGLE_TILES'));

    // Built by concatenation, not through ApiConfig.uri: that percent-encodes
    // the path, which would turn {z}/{x}/{y} into %7Bz%7D and leave flutter_map
    // with no placeholders to substitute.
    final googleTiles =
        '${ApiConfig.baseUrl}/api/v1/places/tiles/{z}/{x}/{y}';

    return TileLayer(
      urlTemplate: googleTiles,
      userAgentPackageName: 'com.udrive.mobile',
      maxNativeZoom: 22,
      // Shown while a tile loads and if it fails. Without it a slow tile leaves
      // a transparent hole that reads as a broken map.
      errorTileCallback: (tile, error, stackTrace) {},
      fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    );
  }
}
