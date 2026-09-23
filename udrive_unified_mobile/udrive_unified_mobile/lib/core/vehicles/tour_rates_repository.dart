import '../network/api_client.dart';

/// What tour vehicles of one category are asking per day.
///
/// A range rather than a single figure, because there is no single answer —
/// every number in it was set by a driver about their own vehicle.
class TourRateGuide {
  const TourRateGuide({
    required this.category,
    required this.vehicleCount,
    required this.lowestPerDay,
    required this.typicalPerDay,
    required this.highestPerDay,
  });

  final String category;
  final int vehicleCount;
  final double lowestPerDay;
  final double typicalPerDay;
  final double highestPerDay;

  factory TourRateGuide.fromJson(Map<String, dynamic> json) => TourRateGuide(
        category: '${json['category'] ?? ''}'.trim(),
        vehicleCount: (json['vehicleCount'] as num?)?.toInt() ?? 0,
        lowestPerDay: _toDouble(json['lowestPerDay']) ?? 0,
        typicalPerDay: _toDouble(json['typicalPerDay']) ?? 0,
        highestPerDay: _toDouble(json['highestPerDay']) ?? 0,
      );

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

/// Reads the tour prices drivers have published.
///
/// Tourism is priced by the driver, not by the admin's per-kilometre rules, so
/// there is no recommended fare to compute here. What the customer gets instead
/// is what drivers actually charge — enough to name an offer with, without the
/// app pretending to set a price it does not set.
class TourRatesRepository {
  TourRatesRepository(this.api);

  final ApiClient api;

  /// Returns an empty list rather than throwing. A missing guide costs the
  /// customer a hint; an error would cost them the booking screen.
  Future<List<TourRateGuide>> guide({
    double? latitude,
    double? longitude,
    double radiusKm = 150,
  }) async {
    final parameters = <String, String>{
      'radiusKm': '$radiusKm',
      if (latitude != null) 'lat': '$latitude',
      if (longitude != null) 'lng': '$longitude',
    };

    try {
      final response = await api.getJson(
        '/api/v1/catalog/tour-rates?${Uri(queryParameters: parameters).query}',
        authenticated: false,
      );

      final payload = response['data'] ?? response;
      if (payload is! List) return const [];

      return payload
          .whereType<Map>()
          .map((item) => TourRateGuide.fromJson(Map<String, dynamic>.from(item)))
          .where((guide) => guide.vehicleCount > 0 && guide.typicalPerDay > 0)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
