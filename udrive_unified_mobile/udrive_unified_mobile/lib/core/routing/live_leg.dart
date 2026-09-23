import 'package:latlong2/latlong.dart';

import 'route_repository.dart';

/// The road between where a Driver is now and where they are heading.
///
/// Both live screens used to draw a straight line from the Driver to the pickup
/// and estimate arrival from that distance over an assumed speed. In Azad
/// Kashmir that is not an approximation, it is a different number: a road
/// through the mountains is routinely two or three times the crow-flight
/// distance, so a Customer told "4 minutes" waited twenty and a Driver planning
/// their next hour planned it wrong.
///
/// This asks the routing service for the real road, and re-asks only when the
/// Driver has actually moved. Requests cost money and quota; a car sitting at a
/// junction does not need its route recomputed every ten seconds.
class LiveLeg {
  LiveLeg({RouteRepository? repository})
      : _repository = repository ?? RouteRepository();

  final RouteRepository _repository;

  TripRoute? _route;
  LatLng? _routedFrom;
  LatLng? _routedTo;
  bool _inFlight = false;

  /// The road geometry, or empty until the first route arrives.
  ///
  /// Callers fall back to a straight line while this is empty rather than
  /// showing nothing — an approximate line is a reasonable thing to look at for
  /// two seconds, and it is replaced as soon as the real one lands.
  List<LatLng> get points => _route?.points ?? const [];

  /// Road distance in kilometres, or null before the first route arrives.
  double? get distanceKm => _route?.distanceKm;

  /// Minutes to arrival by road, or null before the first route arrives.
  int? get etaMinutes {
    final route = _route;
    if (route == null) return null;
    final minutes = (route.durationSeconds / 60).ceil();
    return minutes < 1 ? 1 : minutes;
  }

  /// How far the origin must move before the route is worth recomputing.
  ///
  /// A hundred and fifty metres is roughly a street. Below that the road ahead
  /// is unchanged and the redraw would be indistinguishable, so it would be
  /// spending a paid request to move a line by a few pixels.
  static const double _resendAfterMetres = 150;

  /// Recomputes the route if the Driver has moved far enough, or the target
  /// has changed — which happens once per trip, when they pick the Customer up
  /// and start heading for the destination instead.
  ///
  /// Returns true when new geometry arrived, so the caller knows to repaint.
  Future<bool> update({required LatLng from, required LatLng to}) async {
    if (_inFlight) return false;

    final targetChanged = _routedTo == null ||
        const Distance().as(LengthUnit.Meter, _routedTo!, to) > 40;
    final movedFar = _routedFrom == null ||
        const Distance().as(LengthUnit.Meter, _routedFrom!, from) >
            _resendAfterMetres;

    if (!targetChanged && !movedFar) return false;

    _inFlight = true;
    try {
      final result = await _repository.route(origin: from, destination: to);
      if (!result.hasRoute) return false;

      _route = result.routes.first;
      _routedFrom = from;
      _routedTo = to;
      return true;
    } catch (_) {
      // A failed lookup leaves the previous route in place. Clearing it would
      // blank the map over one bad request on a mountain road.
      return false;
    } finally {
      _inFlight = false;
    }
  }

  /// Drops the cached route, so the next [update] always fetches.
  void reset() {
    _route = null;
    _routedFrom = null;
    _routedTo = null;
  }
}
