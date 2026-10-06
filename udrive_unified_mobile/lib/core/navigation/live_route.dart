import 'package:latlong2/latlong.dart';

import '../network/api_client.dart';
import '../routing/route_repository.dart';

/// One turn on a live route: what to do, and where.
class LiveRouteStep {
  const LiveRouteStep({
    required this.maneuver,
    required this.distanceMeters,
    required this.point,
  });

  /// Google's maneuver name — TURN_LEFT, ROUNDABOUT_RIGHT, DEPART and so on.
  /// [TurnGuide] turns it into an arrow, an Urdu line and a voice clip.
  final String maneuver;

  /// Length of the stretch that begins with this turn.
  final int distanceMeters;

  /// Where the turn is.
  final LatLng point;

  factory LiveRouteStep.fromJson(Map<String, dynamic> json) => LiveRouteStep(
        maneuver: '${json['maneuver'] ?? 'MANEUVER_UNSPECIFIED'}',
        distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
        point: LatLng(
          (json['latitude'] as num?)?.toDouble() ?? 0,
          (json['longitude'] as num?)?.toDouble() ?? 0,
        ),
      );
}

/// The stored road for the current leg of a live ride.
///
/// Fetched once per leg and kept on the phone, so following it — the line
/// shrinking behind the car, the distance to the next turn, the Urdu voice —
/// needs no network at all after it has arrived.
class LiveRoute {
  const LiveRoute({
    required this.id,
    required this.leg,
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
    required this.target,
  });

  /// Changes whenever the server computes a new road (a reroute), which is
  /// how the customer's screen knows to redraw.
  final String id;

  /// 'pickup' or 'destination'.
  final String leg;

  final List<LatLng> points;
  final int distanceMeters;
  final int durationSeconds;
  final List<LiveRouteStep> steps;
  final LatLng? target;

  /// Average speed the route was planned at, in metres per second. Used to
  /// turn the distance still to drive into minutes as the car moves.
  double get plannedSpeed => durationSeconds <= 0
      ? 8.0
      : (distanceMeters / durationSeconds).clamp(2.0, 30.0).toDouble();
}

/// What the server said, including why there may be no road.
class LiveRouteResult {
  const LiveRouteResult({required this.leg, this.route, this.reason});

  final String leg;
  final LiveRoute? route;

  /// no_route_yet, no_key, daily_cap, reroute_limit, cooldown, on_route,
  /// upstream_error, no_target — or null.
  final String? reason;

  /// True when Google will not be asked again today, so the screen should stop
  /// asking and say so once.
  bool get capped => reason == 'daily_cap' || reason == 'no_key';

  /// The road the caller already holds is still the current one; nothing was
  /// sent with it. Only returned to [LiveRouteRepository.current] with known.
  bool get unchanged => reason == 'unchanged';
}

/// Reads and requests the live-ride road from the UDrive API.
///
/// [current] never costs anything: it reads the row the server already holds.
/// [ensure] is the driver's, and is the only call that can make the server ask
/// Google — and the server refuses it unless the driver has really left the
/// road, has not done so too often, and the day's cap is not used up.
class LiveRouteRepository {
  const LiveRouteRepository(this.client);

  final ApiClient client;

  /// [known] is the id of the road already on screen. When it is still the
  /// current one the server answers "unchanged" without resending the road,
  /// so checking every few seconds for a reroute costs a few bytes.
  Future<LiveRouteResult> current(String bookingId, {String? known}) async {
    final query = known == null || known.isEmpty ? '' : '?known=$known';
    final response =
        await client.getJson('/api/v1/trips/$bookingId/route$query');
    return _parse(response);
  }

  /// [heading] is the way the car is moving. A reroute then continues along
  /// the road the driver has chosen instead of sending them back to the old
  /// one with a U-turn.
  Future<LiveRouteResult> ensure(
    String bookingId,
    LatLng from, {
    bool reroute = false,
    double? heading,
  }) async {
    final response = await client.postJson('/api/v1/trips/$bookingId/route', {
      'latitude': from.latitude,
      'longitude': from.longitude,
      'reroute': reroute,
      if (heading != null && heading.isFinite && heading >= 0)
        'heading': heading % 360,
    });
    return _parse(response);
  }

  static LiveRouteResult _parse(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! Map) {
      return const LiveRouteResult(leg: 'pickup', reason: 'upstream_error');
    }

    final json = Map<String, dynamic>.from(data);
    final leg = '${json['leg'] ?? 'pickup'}';
    final reason = json['reason']?.toString();
    if (reason == 'unchanged') {
      return LiveRouteResult(leg: leg, reason: reason);
    }
    final points = TripRoute.decodePolyline('${json['polyline'] ?? ''}');

    if (json['available'] != true || points.length < 2) {
      return LiveRouteResult(leg: leg, reason: reason ?? 'no_route_yet');
    }

    final targetLat = (json['targetLatitude'] as num?)?.toDouble();
    final targetLng = (json['targetLongitude'] as num?)?.toDouble();

    return LiveRouteResult(
      leg: leg,
      reason: reason,
      route: LiveRoute(
        id: '${json['routeId'] ?? ''}',
        leg: leg,
        points: points,
        distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        steps: (json['steps'] as List? ?? const [])
            .whereType<Map>()
            .map((item) =>
                LiveRouteStep.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
        target: targetLat == null || targetLng == null
            ? null
            : LatLng(targetLat, targetLng),
      ),
    );
  }
}
