import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Where the car is relative to the road it is meant to be on.
class RouteFix {
  const RouteFix({
    required this.snapped,
    required this.offRouteMeters,
    required this.alongMeters,
    required this.remainingMeters,
    required this.segmentIndex,
    required this.bearing,
  });

  /// The nearest point on the road. The car is drawn here while it is close
  /// enough, so GPS wobble does not show it driving through houses.
  final LatLng snapped;

  /// How far the GPS fix is from the road.
  final double offRouteMeters;

  /// Distance already driven along the road.
  final double alongMeters;

  /// Distance still to drive along the road.
  final double remainingMeters;

  /// Index of the road segment the car is on.
  final int segmentIndex;

  /// Compass bearing of that segment — steadier than the GPS heading, which
  /// swings at low speed and is undefined when standing still.
  final double bearing;
}

/// Follows one route as the car moves along it. Pure arithmetic, no network.
///
/// The search looks near the last known segment first, because a car does not
/// teleport, and only scans the whole line when that fails — after a tunnel,
/// a wrong turn or a GPS jump. On a 5,000-point mountain route that keeps each
/// update to a few dozen segment checks.
class RouteTracker {
  RouteTracker(this.points)
      : _cumulative = _cumulativeDistances(points),
        assert(points.length >= 2, 'A route needs at least two points.');

  final List<LatLng> points;
  final List<double> _cumulative;
  int _lastSegment = 0;

  /// Total road length in metres.
  double get totalMeters => _cumulative.last;

  static const double _metresPerDegree = 111320;

  static List<double> _cumulativeDistances(List<LatLng> points) {
    final result = List<double>.filled(points.length, 0);
    for (var i = 1; i < points.length; i++) {
      result[i] = result[i - 1] + _flatDistance(points[i - 1], points[i]);
    }
    return result;
  }

  static double _flatDistance(LatLng a, LatLng b) {
    final cos = math.cos((a.latitude + b.latitude) / 2 * math.pi / 180);
    final dx = (b.longitude - a.longitude) * _metresPerDegree * cos;
    final dy = (b.latitude - a.latitude) * _metresPerDegree;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Compass bearing from [a] to [b], 0 = north, clockwise.
  static double bearingBetween(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final degrees = math.atan2(y, x) * 180 / math.pi;
    return (degrees + 360) % 360;
  }

  /// Distance along the route of the vertex nearest to [point]. Used once per
  /// turn when a route arrives, to know where each turn sits on the line.
  double alongOf(LatLng point) {
    final probe = _project(point, 0, points.length - 2);
    return probe.along;
  }

  /// Places [position] on the route.
  RouteFix locate(LatLng position) {
    final last = points.length - 2;
    final from = math.max(0, _lastSegment - 3);
    final to = math.min(last, _lastSegment + 40);

    var best = _project(position, from, to);
    // Near the last segment and still far from the road: look everywhere
    // before deciding the car has left it.
    if (best.distance > 30) {
      final everywhere = _project(position, 0, last);
      if (everywhere.distance < best.distance) best = everywhere;
    }

    _lastSegment = best.segment;
    return RouteFix(
      snapped: best.point,
      offRouteMeters: best.distance,
      alongMeters: best.along,
      remainingMeters: math.max(0, totalMeters - best.along),
      segmentIndex: best.segment,
      bearing: bearingBetween(points[best.segment], points[best.segment + 1]),
    );
  }

  /// The part of the road still ahead, starting at [fix].
  List<LatLng> remaining(RouteFix fix) {
    final start = math.min(fix.segmentIndex + 1, points.length - 1);
    return <LatLng>[fix.snapped, ...points.sublist(start)];
  }

  ({LatLng point, double distance, double along, int segment}) _project(
    LatLng p,
    int from,
    int to,
  ) {
    final cos = math.cos(p.latitude * math.pi / 180);
    var bestDistance = double.infinity;
    var bestSegment = from;
    var bestT = 0.0;

    for (var i = from; i <= to; i++) {
      final a = points[i];
      final b = points[i + 1];
      final ax = (a.longitude - p.longitude) * _metresPerDegree * cos;
      final ay = (a.latitude - p.latitude) * _metresPerDegree;
      final bx = (b.longitude - p.longitude) * _metresPerDegree * cos;
      final by = (b.latitude - p.latitude) * _metresPerDegree;
      final dx = bx - ax;
      final dy = by - ay;
      final lengthSquared = dx * dx + dy * dy;
      final t = lengthSquared == 0
          ? 0.0
          : (-(ax * dx + ay * dy) / lengthSquared).clamp(0.0, 1.0).toDouble();
      final px = ax + t * dx;
      final py = ay + t * dy;
      final distance = math.sqrt(px * px + py * py);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestSegment = i;
        bestT = t;
      }
    }

    final a = points[bestSegment];
    final b = points[bestSegment + 1];
    final point = LatLng(
      a.latitude + (b.latitude - a.latitude) * bestT,
      a.longitude + (b.longitude - a.longitude) * bestT,
    );
    final segmentLength = _cumulative[bestSegment + 1] - _cumulative[bestSegment];
    return (
      point: point,
      distance: bestDistance,
      along: _cumulative[bestSegment] + segmentLength * bestT,
      segment: bestSegment,
    );
  }
}
