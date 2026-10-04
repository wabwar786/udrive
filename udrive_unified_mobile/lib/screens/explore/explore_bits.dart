import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';

/// Where the phone is, asked for once per app run and shared by the Explore
/// screens. Null when location is off or refused — every screen still works,
/// it just does not say how far things are.
class ExploreLocation {
  ExploreLocation._();

  static LatLng? _cached;
  static Future<LatLng?>? _pending;

  static Future<LatLng?> get() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _pending ??= _read();
  }

  static Future<LatLng?> _read() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final last = await Geolocator.getLastKnownPosition();
      final position = last ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 10),
            ),
          );
      return _cached = LatLng(position.latitude, position.longitude);
    } catch (_) {
      return null;
    } finally {
      _pending = null;
    }
  }

  /// Road distance, roughly: a straight line stretched for hill roads.
  static double roadKm(LatLng from, double latitude, double longitude) =>
      Geolocator.distanceBetween(
              from.latitude, from.longitude, latitude, longitude) /
          1000 *
          1.35;

  static String kmLabel(double km) =>
      km < 10 ? '~${km.toStringAsFixed(1)} km' : '~${km.round()} km';
}

/// A place's cover photograph, or a quiet mountain tile when there is none.
class ExplorePhoto extends StatelessWidget {
  const ExplorePhoto({
    required this.url,
    this.radius = 0,
    this.iconSize = 40,
    super.key,
  });

  final String? url;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final link = ApiConfig.absoluteUrl(url?.trim());
    final Widget fallback = Container(
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(Icons.landscape_rounded,
          size: iconSize, color: AppColors.navy),
    );
    final Widget image = link.isEmpty
        ? fallback
        : Image.network(
            link,
            fit: BoxFit.cover,
            cacheWidth: 900,
            errorBuilder: (_, __, ___) => fallback,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : fallback,
          );
    return radius == 0
        ? image
        : ClipRRect(borderRadius: AppRadii.all(radius), child: image);
  }
}

/// Hands the drive to the phone's own Google Maps app — no API credit used.
Future<void> exploreNavigate(
  BuildContext context,
  double latitude,
  double longitude,
) async {
  final uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1'
    '&destination=$latitude,$longitude&travelmode=driving',
  );
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open directions.')),
    );
  }
}

/// A small grey chip: "4x4 only", "Weak signal".
class ExploreTag extends StatelessWidget {
  const ExploreTag({required this.label, this.dark = false, super.key});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? AppColors.navy : AppColors.surfaceAlt,
        borderRadius: AppRadii.all(7),
      ),
      child: Text(
        label,
        style: AppType.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: dark ? AppText.onInk : AppText.primary,
        ),
      ),
    );
  }
}

/// The tags a place earns from its catalogue row.
List<String> exploreTags({
  required bool fourByFour,
  required bool weakSignal,
  required int familyScore,
}) =>
    [
      if (fourByFour) '4x4 needed',
      if (familyScore >= 70) 'Family friendly',
      if (weakSignal) 'Weak signal',
    ];
