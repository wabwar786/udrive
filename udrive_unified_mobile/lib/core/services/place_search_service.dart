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
/// Every lookup goes through the UDrive API proxy
/// (`/api/v1/places/...`). The server decides whether to answer from Google
/// Places or from OpenStreetMap, so the Google key never reaches the client and
/// an admin can rotate it without a new build.
///
/// This client used to call Nominatim directly and that silently failed on
/// web: Nominatim wants a `User-Agent`, browsers forbid setting one, and the
/// request died in CORS preflight. Proxying fixed the header problem and the
/// cross-origin problem at once.
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
    try {
      return await _searchViaProxy(trimmed, bias);
    } catch (_) {
      return const [];
    }
  }

  /// Calls the UDrive proxy.
  ///
  /// The proxy talks to Google when an admin has configured a key and falls
  /// back to OpenStreetMap when they have not, so this client never needs to
  /// know which one answered.
  ///
  /// Client-side calls to Nominatim were removed deliberately: Nominatim
  /// requires a `User-Agent`, and browsers forbid that header, so a direct call
  /// fails CORS preflight on web every time. Going through our own origin also
  /// removes the CORS question entirely.
  Future<List<PlaceSuggestion>> _searchViaProxy(
    String query,
    LatLng? bias,
  ) async {
    final uri = ApiConfig.uri(AppConfig.placesProxyPath, {
      'q': query,
      'country': 'pk',
      if (bias != null) 'lat': bias.latitude,
      if (bias != null) 'lng': bias.longitude,
    });

    final response = await _client.get(uri).timeout(AppConfig.networkTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final decoded = jsonDecode(response.body);
    final payload = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
    final items = payload is Map
        ? (payload['results'] as List? ?? const [])
        : payload is List
            ? payload
            : const [];

    return items
        .whereType<Map>()
        .map((raw) {
          final map = Map<String, dynamic>.from(raw);
          final lat = _toDouble(map['latitude']);
          final lng = _toDouble(map['longitude']);
          if (lat == null || lng == null) return null;
          return PlaceSuggestion(
            title: '${map['title'] ?? ''}'.trim(),
            subtitle: '${map['subtitle'] ?? ''}'.trim(),
            latitude: lat,
            longitude: lng,
          );
        })
        .whereType<PlaceSuggestion>()
        .where((item) => item.title.isNotEmpty)
        .toList(growable: false);
  }

  /// Human-readable address for a coordinate, via the same proxy.
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
        final payload = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
        if (payload is Map) {
          final label = '${payload['address'] ?? ''}'.trim();
          if (label.isNotEmpty) return label;
        }
      }
    } catch (_) {
      // An empty label makes the caller show coordinates instead, which is
      // still usable — better than blocking on a failed lookup.
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
