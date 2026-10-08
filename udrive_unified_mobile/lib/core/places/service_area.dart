import 'package:latlong2/latlong.dart';

/// Where a pickup or destination may be.
///
/// A place with no coordinates used to travel through the app as (0, 0) — a
/// point in the sea off West Africa. The map then framed half the world, the
/// distance came out as thousands of kilometres and the fare as PKR 500,000.
/// Every point is checked here before it is used for a route or a fare.
class ServiceArea {
  const ServiceArea._();

  // Pakistan with a margin. Tight enough to catch (0, 0) and swapped
  // latitude / longitude, loose enough for any real trip.
  static const double _south = 23.0;
  static const double _north = 37.5;
  static const double _west = 60.5;
  static const double _east = 78.0;

  static bool isUsable(LatLng? point) =>
      point != null &&
      point.latitude.isFinite &&
      point.longitude.isFinite &&
      point.latitude >= _south &&
      point.latitude <= _north &&
      point.longitude >= _west &&
      point.longitude <= _east;

  /// The point, or null when it cannot be a real place.
  static LatLng? orNull(LatLng? point) => isUsable(point) ? point : null;
}
