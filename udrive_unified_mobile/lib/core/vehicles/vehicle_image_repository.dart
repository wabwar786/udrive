import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';

/// Admin-supplied photographs for each vehicle type.
///
/// The app ships stock illustrations, which are placeholders. Real photographs
/// of the vehicles actually on the road will do more for trust than any amount
/// of layout work, and only someone on the ground can supply those — so they
/// are set in the admin portal rather than shipped in a build.
///
/// An unset or unreachable image falls back to the bundled illustration. A
/// generic picture is a small loss; a broken one is a visible defect.
class VehicleImageRepository {
  VehicleImageRepository(this.api);

  final ApiClient api;

  static const _cacheKey = 'udrive_vehicle_images';

  /// Setting key for a vehicle category, or null if it has no image slot.
  static String? settingKeyFor(String category) {
    switch (category.toLowerCase().replaceAll(' ', '_')) {
      case 'bike':
        return 'vehicle.image.bike';
      case 'car':
        return 'vehicle.image.car';
      case 'ac_car':
        return 'vehicle.image.ac_car';
      case 'hiace':
        return 'vehicle.image.hiace';
      // Both spellings map to the one setting the admin portal already
      // creates, so renaming the category did not orphan an uploaded picture.
      case 'coster':
      case 'coaster':
        return 'vehicle.image.coaster';
      default:
        return null;
    }
  }

  /// Cached URLs, read instantly so the picker never waits on the network.
  ///
  /// An instance method, matching [refresh]. Mixing a static reader with an
  /// instance writer on one class invites calling one the way you call the
  /// other, which is exactly what happened.
  Future<Map<String, String>> cached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return const {};
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return const {};
    }
  }

  /// Refreshes from the API and updates the cache.
  ///
  /// Failures are silent: the picker already has either a cached URL or the
  /// bundled illustration, and neither is worth interrupting a booking for.
  Future<Map<String, String>> refresh() async {
    try {
      final response = await api.getJson(
        '/api/v1/settings/public',
        authenticated: false,
      );

      final payload = response['data'] ?? response;
      if (payload is! Map) return const {};

      final images = <String, String>{};
      payload.forEach((key, value) {
        final name = '$key';
        if (!name.startsWith('vehicle.image.')) return;
        final url = '${value ?? ''}'.trim();
        if (url.startsWith('http')) images[name] = url;
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(images));
      return images;
    } catch (_) {
      return const {};
    }
  }
}
