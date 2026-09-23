import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../network/api_config.dart';

/// One driving route between pickup and destination.
class TripRoute {
  const TripRoute({
    required this.summary,
    required this.distanceMetres,
    required this.durationSeconds,
    required this.points,
  });

  /// The road Google names for this route, e.g. "Neelum Road".
  final String summary;

  final int distanceMetres;
  final int durationSeconds;

  /// Decoded geometry, ready to draw.
  final List<LatLng> points;

  double get distanceKm => distanceMetres / 1000;

  /// "1 hr 25 min", "45 min". Rounded to the minute — second-level precision
  /// would imply an accuracy traffic estimates do not have.
  String get durationLabel {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours hr' : '$hours hr $rest min';
  }

  String get distanceLabel {
    final km = distanceKm;
    return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
  }

  factory TripRoute.fromJson(Map<String, dynamic> json) => TripRoute(
        summary: '${json['summary'] ?? ''}'.trim(),
        distanceMetres: (json['distanceMetres'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        points: decodePolyline('${json['polyline'] ?? ''}'),
      );

  /// Decodes Google's encoded polyline format.
  ///
  /// Written with arithmetic rather than bitwise operators, deliberately.
  ///
  /// On the web, Dart ints compile to JavaScript numbers and `<<`, `&` and `~`
  /// operate on 32 bits. The textbook implementation shifts a 5-bit chunk left
  /// by up to 30 places, and `31 << 30` evaluates to -1073741824 in a browser
  /// instead of 33285996544. Long polylines therefore decoded into enormous
  /// coordinates — a camera centred at latitude 8353745 was this bug — while
  /// the identical code was correct on Android, where ints are 64-bit.
  ///
  /// Multiplication and division carry full precision on both, so the same
  /// source now produces the same result everywhere.
  ///
  /// The format itself: each value is a difference from the previous point,
  /// split into 5-bit chunks with the high bit marking "more chunks follow",
  /// then offset by 63 to stay printable. The low bit of the assembled value is
  /// a sign flag.
  static List<LatLng> decodePolyline(String encoded) {
    if (encoded.isEmpty) return const [];

    final points = <LatLng>[];
    var index = 0;
    var latitude = 0.0;
    var longitude = 0.0;

    double readValue() {
      var result = 0.0;
      var factor = 1.0;

      while (index < encoded.length) {
        final byte = encoded.codeUnitAt(index) - 63;
        index++;
        // (byte & 0x1f) without the bitwise and.
        result += (byte % 32) * factor;
        factor *= 32;
        if (byte < 0x20) break;
      }

      // Odd means negative, and the magnitude is the value shifted right once.
      final negative = result % 2 == 1;
      final magnitude = (result - (negative ? 1 : 0)) / 2;
      return negative ? -magnitude - 1 : magnitude;
    }

    while (index < encoded.length) {
      latitude += readValue();
      if (index > encoded.length) break;
      longitude += readValue();

      final lat = latitude / 1e5;
      final lng = longitude / 1e5;

      // A coordinate outside these ranges means the stream has gone out of
      // step, and every point after it is meaningless. Stopping here keeps
      // whatever was decoded correctly and prevents a corrupt tail reaching
      // the map — a route centred at latitude 8353745 came from letting one
      // bad value through.
      if (lat.isNaN || lng.isNaN || lat.abs() > 90 || lng.abs() > 180) {
        break;
      }

      points.add(LatLng(lat, lng));
    }

    return points;
  }
}

/// Why no route came back, so the UI can say something useful.
enum RouteFailure {
  /// No Google key configured in the admin portal.
  noKey,

  /// Google found no drivable route between the two points.
  notFound,

  /// Network or upstream problem.
  unavailable,
}

class TripRouteResult {
  const TripRouteResult({
    this.routes = const [],
    this.failure,
    this.detail,
  });

  final List<TripRoute> routes;
  final RouteFailure? failure;

  /// Google's own error text, passed through by the proxy. Shown to the user
  /// because a real message ("API not enabled", "referer restriction") points
  /// straight at the fix, whereas a generic one wastes an afternoon.
  final String? detail;

  bool get hasRoute => routes.isNotEmpty;
  TripRoute? get best => routes.isEmpty ? null : routes.first;
}

/// Fetches driving routes through the UDrive proxy.
///
/// The proxy calls Google's Routes API. Directions and Distance Matrix went
/// legacy in March 2025 and cannot be enabled on new Cloud projects, so Routes
/// is the only option available to this project.
class RouteRepository {
  RouteRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Returns routes ordered fastest first.
  ///
  /// Never invents a fallback. A straight line through Kashmir's mountains can
  /// be a third of the real road distance, so a made-up figure would mislead
  /// the customer about both the fare and when they would arrive.
  Future<TripRouteResult> route({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final uri = ApiConfig.uri('/api/v1/places/directions', {
        'originLat': origin.latitude,
        'originLng': origin.longitude,
        'destinationLat': destination.latitude,
        'destinationLng': destination.longitude,
        'alternatives': 'true',
      });

      final response =
          await _client.get(uri).timeout(AppConfig.networkTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return TripRouteResult(
          failure: RouteFailure.unavailable,
          detail: 'HTTP ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      final payload = decoded is Map ? (decoded['data'] ?? decoded) : decoded;
      if (payload is! Map) {
        return const TripRouteResult(failure: RouteFailure.unavailable);
      }

      final reason = '${payload['reason'] ?? ''}';
      final routes = (payload['routes'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => TripRoute.fromJson(Map<String, dynamic>.from(item)))
          .where((route) => route.points.isNotEmpty)
          .toList()
        ..sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));

      if (routes.isNotEmpty) {
        for (var i = 0; i < routes.length; i++) {
          final route = routes[i];
          final lats = route.points.map((p) => p.latitude);
          final lngs = route.points.map((p) => p.longitude);
          developer.log(
            'route $i: ${route.points.length} pts  '
            'lat ${lats.reduce((a, b) => a < b ? a : b).toStringAsFixed(4)}'
            '..${lats.reduce((a, b) => a > b ? a : b).toStringAsFixed(4)}  '
            'lng ${lngs.reduce((a, b) => a < b ? a : b).toStringAsFixed(4)}'
            '..${lngs.reduce((a, b) => a > b ? a : b).toStringAsFixed(4)}  '
            '${route.distanceLabel} ${route.durationLabel}',
            name: 'UDrive.route',
          );
        }
        return TripRouteResult(routes: routes);
      }

      final detail = payload['detail']?.toString();
      return TripRouteResult(
        failure: switch (reason) {
          'no_key' => RouteFailure.noKey,
          'ZERO_RESULTS' => RouteFailure.notFound,
          _ => RouteFailure.unavailable,
        },
        detail: detail == null || detail.isEmpty ? reason : detail,
      );
    } catch (error) {
      return TripRouteResult(
        failure: RouteFailure.unavailable,
        detail: '$error',
      );
    }
  }

  void dispose() => _client.close();
}
