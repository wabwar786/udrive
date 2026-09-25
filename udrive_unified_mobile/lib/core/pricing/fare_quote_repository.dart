import '../../models/auth_models.dart';
import '../network/api_client.dart';
import 'fare_quote.dart';

/// Asks the server what a trip costs.
///
/// Errors are not swallowed. The seat-fare lookup next door returns null on
/// failure because a missing fixed fare simply means "price it by the
/// kilometre" — but a missing quote means the app does not know what this trip
/// costs, and quietly falling back to a figure it worked out itself is how the
/// old two-formulas-that-disagree problem started. The caller shows the
/// message and offers to try again.
class FareQuoteRepository {
  FareQuoteRepository(this.api);

  final ApiClient api;

  Future<FareQuote> quote({
    required String serviceType,
    required String vehicleCategory,
    required bool perSeat,
    required int seats,
    required double pickupLatitude,
    required double pickupLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
    required double distanceKm,
    required double durationMinutes,
  }) async {
    final response = await api.postJson('/api/v1/pricing/quote', {
      'serviceType': serviceType,
      'vehicleCategory': vehicleCategory,
      'bookingType': perSeat ? 'PerSeat' : 'WholeVehicle',
      'seats': seats,
      'pickupLatitude': pickupLatitude,
      'pickupLongitude': pickupLongitude,
      'destinationLatitude': destinationLatitude,
      'destinationLongitude': destinationLongitude,
      'distanceKm': distanceKm,
      'durationMinutes': durationMinutes,
    });

    final data = response['data'];
    if (data is! Map) {
      throw const ApiException('The fare could not be read.');
    }

    return FareQuote.fromJson(Map<String, dynamic>.from(data));
  }
}
