import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../network/api_config.dart';

/// A single autocomplete suggestion, renderer-agnostic.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
  });

  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;

  LatLng get point => LatLng(latitude, longitude);

  @override
  bool operator ==(Object other) =>
      other is PlaceSuggestion &&
      other.title == title &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(title, latitude, longitude);
}

/// Address autocomplete and reverse geocoding for the whole app.
///
/// Resolution order, by design:
///
///  1. **UDrive API proxy** (`/api/v1/places/autocomplete`). The Google Places
///     key lives on the server, so an admin can add or rotate it without
///     shipping a new build, and the key is never exposed in the APK.
///  2. **OpenStreetMap Nominatim**, which needs no key. This keeps search
///     working today, before the Google key exists, and acts as a safety net
///     if the proxy is ever down or over quota.
///
/// Callers get the same [PlaceSuggestion] list either way and never need to
/// know which source answered.
class PlaceSearchService {
  PlaceSearchService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  Timer? _debounce;
  int _requestToken = 0;

  /// Debounced search. Later calls cancel earlier in-flight ones, so a fast
  /// typist never sees results for a prefix they have already moved past.
  void searchDebounced(
    String query, {
    required void Function(List<PlaceSuggestion> results) onResults,
    void Function(Object error)? onError,
    LatLng? bias,
  }) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      onResults(const []);
      return;
    }
    _debounce = Timer(AppConfig.searchDebounce, () async {
      final token = ++_requestToken;
      try {
        final results = await search(trimmed, bias: bias);
        if (token != _requestToken) return; // superseded
        onResults(results);
      } catch (error) {
        if (token != _requestToken) return;
        onError?.call(error);
        onResults(const []);
      }
    });
  }

  Future<List<PlaceSuggestion>> search(String query, {LatLng? bias}) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    final viaProxy = await _searchViaProxy(trimmed, bias);
    if (viaProxy != null && viaProxy.isNotEmpty) return viaProxy;

    return _searchViaNominatim(trimmed);
  }

  /// Returns null when the proxy is unreachable or not yet deployed, so the
  /// caller can fall through to Nominatim. Returns an empty list only when the
  /// proxy genuinely found nothing.
  Future<List<PlaceSuggestion>?> _searchViaProxy(
    String query,
    LatLng? bias,
  ) async {
    try {
      final uri = ApiConfig.uri(AppConfig.placesProxyPath, {
        'q': query,
        'country': 'pk',
        if (bias != null) 'lat': bias.latitude,
        if (bias != null) 'lng': bias.longitude,
      });
      final response =
          await _client.get(uri).timeout(AppConfig.networkTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final decoded = jsonDecode(response.body);
      final items = decoded is List
          ? decoded
          : decoded is Map && decoded['results'] is List
              ? decoded['results'] as List
              : const [];

      return items
          .whereType<Map>()
          .map((raw) {
            final map = Map<String, dynamic>.from(raw);
            final lat = _toDouble(map['latitude'] ?? map['lat']);
            final lng = _toDouble(map['longitude'] ?? map['lng']);
            if (lat == null || lng == null) return null;
            return PlaceSuggestion(
              title: '${map['title'] ?? map['name'] ?? ''}'.trim(),
              subtitle: '${map['subtitle'] ?? map['address'] ?? ''}'.trim(),
              latitude: lat,
              longitude: lng,
            );
          })
          .whereType<PlaceSuggestion>()
          .where((item) => item.title.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<List<PlaceSuggestion>> _searchViaNominatim(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'jsonv2',
      'limit': '8',
      'countrycodes': 'pk',
      'addressdetails': '1',
    });

    final response = await _client.get(uri, headers: const {
      'User-Agent': 'UDrive-Mobile/1.0',
      'Accept-Language': 'en',
    }).timeout(AppConfig.networkTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map((raw) {
          final map = Map<String, dynamic>.from(raw);
          final lat = double.tryParse('${map['lat']}');
          final lng = double.tryParse('${map['lon']}');
          if (lat == null || lng == null) return null;

          final display = '${map['display_name'] ?? ''}';
          final parts = display.split(',').map((e) => e.trim()).toList();
          final title = '${map['name'] ?? ''}'.trim().isNotEmpty
              ? '${map['name']}'.trim()
              : (parts.isNotEmpty ? parts.first : display);
          final subtitle =
              parts.length > 1 ? parts.skip(1).take(3).join(', ') : '';

          return PlaceSuggestion(
            title: title,
            subtitle: subtitle,
            latitude: lat,
            longitude: lng,
          );
        })
        .whereType<PlaceSuggestion>()
        .where((item) => item.title.isNotEmpty)
        .toList(growable: false);
  }

  /// Human-readable address for a coordinate. Proxy first, Nominatim second.
  Future<String> reverseGeocode(double latitude, double longitude) async {
    try {
      final uri = ApiConfig.uri(AppConfig.geocodeProxyPath, {
        'lat': latitude,
        'lng': longitude,
      });
      final response =
          await _client.get(uri).timeout(AppConfig.networkTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final label = '${decoded['address'] ?? decoded['title'] ?? ''}'.trim();
          if (label.isNotEmpty) return label;
        }
      }
    } catch (_) {
      // fall through
    }

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': '$latitude',
        'lon': '$longitude',
        'format': 'jsonv2',
        'zoom': '16',
      });
      final response = await _client.get(uri, headers: const {
        'User-Agent': 'UDrive-Mobile/1.0',
        'Accept-Language': 'en',
      }).timeout(AppConfig.networkTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final display = '${decoded['display_name'] ?? ''}'.trim();
          if (display.isNotEmpty) {
            return display.split(',').take(3).map((e) => e.trim()).join(', ');
          }
        }
      }
    } catch (_) {
      // fall through
    }

    return '';
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  void dispose() {
    _debounce?.cancel();
    _requestToken++;
    _client.close();
  }
}
