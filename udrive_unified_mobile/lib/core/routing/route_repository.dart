import 'dart:convert';

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
  /// Implemented here rather than pulling in a package: it is about twenty
  /// lines, and the algorithm has not changed in fifteen years.
  ///
  /// Values are stored as differences from the previous point, each split into
  /// 5-bit chunks with the high bit marking "more chunks follow", then offset
  /// by 63 to keep them printable.
  static List<LatLng> decodePolyline(String encoded) {
    if (encoded.isEmpty) return const [];

    final points = <LatLng>[];
    var index = 0;
    var latitude = 0;
    var longitude = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int byte;

      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);
      // The low bit is a sign flag, inverted for negatives.
      latitude += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);
      longitude += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(latitude / 1e5, longitude / 1e5));
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
  const TripRouteResult({this.routes = const [], this.failure});

  final List<TripRoute> routes;
  final RouteFailure? failure;

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
        return const TripRouteResult(failure: RouteFailure.unavailable);
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

      if (routes.isNotEmpty) return TripRouteResult(routes: routes);

      return TripRouteResult(
        failure: switch (reason) {
          'no_key' => RouteFailure.noKey,
          'ZERO_RESULTS' => RouteFailure.notFound,
          _ => RouteFailure.unavailable,
        },
      );
    } catch (_) {
      return const TripRouteResult(failure: RouteFailure.unavailable);
    }
  }

  void dispose() => _client.close();
}
