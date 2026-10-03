import '../network/api_client.dart';
import '../../models/driver_growth_models.dart';

/// Reads the driver growth system.
///
/// Every method returns null or an empty list rather than throwing. A driver's
/// home screen must open whether or not a campaign exists, whether or not the
/// connection held, and whether or not an admin has configured anything at all
/// — the rewards are an addition to that screen, never a precondition for it.
class DriverGrowthRepository {
  const DriverGrowthRepository(this.api);

  final ApiClient api;

  /// The whole home screen in one request.
  Future<DriverGrowthHome?> home() async {
    try {
      final response = await api.getJson('/api/v1/driver/growth/home');
      final data = response['data'];
      if (data is! Map) return null;
      return DriverGrowthHome.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  Future<List<DriverMission>> missions() async {
    try {
      final response = await api.getJson('/api/v1/driver/growth/missions');
      final data = response['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((item) => DriverMission.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<WelcomeBonus?> welcomeBonus() async {
    try {
      final response = await api.getJson('/api/v1/driver/growth/welcome-bonus');
      final data = response['data'];
      if (data is! Map) return null;
      return WelcomeBonus.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  Future<List<DemandZone>> demand() async {
    try {
      final response = await api.getJson('/api/v1/driver/growth/demand');
      final data = response['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((item) => DemandZone.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Today, this week, this month — and every live way to earn.
  Future<DriverEarnings?> earnings() async {
    try {
      final response = await api.getJson('/api/v1/driver/growth/earnings');
      final data = response['data'];
      if (data is! Map) return null;
      return DriverEarnings.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  /// The Driver's own code, and everyone who has used it.
  Future<ReferralSummary?> referrals() async {
    try {
      final response = await api.getJson('/api/v1/driver/growth/referrals');
      final data = response['data'];
      if (data is! Map) return null;
      return ReferralSummary.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  /// Records who brought this Driver to the platform.
  ///
  /// Unlike the reads above this one rethrows: a code that was refused has a
  /// reason, and swallowing it would leave the Driver typing the same wrong
  /// code again.
  Future<String> applyReferralCode(String code) async {
    final response = await api.postJson(
      '/api/v1/driver/growth/referrals/apply',
      {'code': code},
    );
    final message = '${response['message'] ?? ''}'.trim();
    return message.isEmpty ? 'Added.' : message;
  }

  /// This week's target, and what last week came to.
  Future<DriverWeekly?> weekly() async {
    try {
      final response = await api.getJson('/api/v1/driver/growth/weekly');
      final data = response['data'];
      if (data is! Map) return null;
      return DriverWeekly.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  Future<List<DriverUpdate>> updates() async {
    try {
      final response = await api.getJson('/api/v1/driver/growth/updates');
      final data = response['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((item) => DriverUpdate.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
