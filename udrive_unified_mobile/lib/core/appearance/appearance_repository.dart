import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import '../widgets/service_selector.dart';

/// Loads the Home hero artwork that admins configure in the admin portal.
///
/// Each service can have its own image URL, set under the
/// `home.hero.<service>.imageUrl` system setting. When a URL is present the
/// hero shows that picture; when it is absent or fails to load, the built-in
/// vector illustration is used. That means the app is never broken by a bad or
/// missing URL, and changing artwork needs no new app build.
///
/// The last successful response is cached in shared preferences so the correct
/// artwork appears immediately on the next launch instead of flashing the
/// fallback while the network call is in flight.
class AppearanceRepository {
  AppearanceRepository(this.api);

  final ApiClient api;

  static const _cacheKey = 'home_hero_images_v1';
  static const _settingsPath = '/api/v1/settings/public';

  static String settingKeyFor(HomeService service) =>
      'home.hero.${service.name}.imageUrl';

  /// Reads the cached map first so callers can paint immediately.
  Future<Map<HomeService, String>> cached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return const {};
      return _parse(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const {};
    }
  }

  /// Fetches the live values and refreshes the cache.
  ///
  /// Returns an empty map on any failure — the caller keeps whatever it already
  /// had rather than losing artwork because of one bad request.
  Future<Map<HomeService, String>> refresh() async {
    try {
      final response =
          await api.getJson(_settingsPath, authenticated: false);
      final payload = response['data'] ?? response;
      if (payload is! Map) return const {};

      final values = Map<String, dynamic>.from(payload);
      final parsed = _parse(values);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          for (final entry in parsed.entries)
            settingKeyFor(entry.key): entry.value,
        }),
      );
      return parsed;
    } catch (_) {
      return const {};
    }
  }

  Map<HomeService, String> _parse(Map<String, dynamic> values) {
    final result = <HomeService, String>{};
    for (final service in HomeService.values) {
      final raw = values[settingKeyFor(service)];
      final url = raw is String ? raw.trim() : '';
      // Only absolute URLs are accepted; a relative or malformed value would
      // just produce a broken image, so we fall back to the illustration.
      if (url.startsWith('http://') || url.startsWith('https://')) {
        result[service] = url;
      }
    }
    return result;
  }
}
