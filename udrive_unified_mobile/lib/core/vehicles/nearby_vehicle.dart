import 'package:latlong2/latlong.dart';

import '../booking/vehicle_booking_mode.dart';
import '../widgets/home_service.dart';

/// A vehicle currently online near the customer, shown as a map marker.
///
/// Carries no driver identity by design — the API does not send a name, phone,
/// plate or driver id, and coordinates arrive rounded to roughly 100 m. Those
/// details are released only once a booking is confirmed.
class NearbyVehicle {
  const NearbyVehicle({
    required this.id,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.etaMinutes,
    required this.bookingMode,
    required this.rating,
    required this.passengerCapacity,
    required this.availableForTour,
  });

  final String id;
  final String category;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final int etaMinutes;
  final VehicleBookingMode bookingMode;
  final double rating;

  /// Drives the per-seat rule: 5 or fewer seats is whole-vehicle only.
  final int passengerCapacity;

  /// Set by the driver. Only these vehicles appear under the Tour service.
  final bool availableForTour;

  LatLng get point => LatLng(latitude, longitude);

  /// Which Home service this vehicle belongs under, so markers can be filtered
  /// to the service the customer selected.
  HomeService? get service {
    final value = category.toLowerCase();
    if (value.contains('coaster') ||
        value.contains('coster') ||
        value.contains('bus') ||
        value.contains('hiace') ||
        value.contains('van')) {
      return HomeService.bus;
    }
    if (value.contains('bike') ||
        value.contains('motorcycle') ||
        value.contains('motor')) {
      return HomeService.bike;
    }
    // Rickshaws are not offered on Home, so they are deliberately unmapped
    // rather than lumped in with cars.
    if (value.contains('rickshaw') || value.contains('auto')) return null;
    return HomeService.car;
  }

  factory NearbyVehicle.fromJson(Map<String, dynamic> json) => NearbyVehicle(
        id: '${json['id'] ?? ''}',
        category: '${json['category'] ?? 'Car'}'.trim(),
        latitude: _toDouble(json['latitude']) ?? 0,
        longitude: _toDouble(json['longitude']) ?? 0,
        distanceKm: _toDouble(json['distanceKm']) ?? 0,
        etaMinutes: (json['etaMinutes'] as num?)?.toInt() ?? 0,
        bookingMode:
            VehicleBookingModeInfo.fromApi(json['bookingMode']?.toString()),
        rating: _toDouble(json['rating']) ?? 0,
        passengerCapacity: (json['passengerCapacity'] as num?)?.toInt() ?? 4,
        availableForTour: json['availableForTour'] == true,
      );

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
