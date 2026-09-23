import '../network/api_client.dart';
import 'nearby_vehicle.dart';

/// Reads the vehicles that are online around the customer.
class NearbyVehicleRepository {
  NearbyVehicleRepository(this.api);

  final ApiClient api;

  /// GET /api/v1/catalog/vehicles/nearby
  ///
  /// Returns an empty list rather than throwing when the endpoint is missing or
  /// unreachable: the home map should show "no vehicles nearby" instead of an
  /// error, and a failed poll must never disturb a screen in use.
  Future<List<NearbyVehicle>> nearby({
    required double latitude,
    required double longitude,
    double radiusKm = 5,
    String? category,
    bool tourOnly = false,
  }) async {
    final parameters = <String, String>{
      'lat': '$latitude',
      'lng': '$longitude',
      'radiusKm': '$radiusKm',
      if (category != null && category.isNotEmpty) 'category': category,
      if (tourOnly) 'tourOnly': 'true',
    };

    try {
      final response = await api.getJson(
        '/api/v1/catalog/vehicles/nearby'
        '?${Uri(queryParameters: parameters).query}',
        authenticated: false,
      );

      final payload = response['data'] ?? response;
      final rawItems = payload is Map
          ? (payload['items'] as List? ?? const [])
          : payload is List
              ? payload
              : const [];

      return rawItems
          .whereType<Map>()
          .map((item) => NearbyVehicle.fromJson(Map<String, dynamic>.from(item)))
          .where((vehicle) => vehicle.latitude != 0 || vehicle.longitude != 0)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
