import '../../models/business_models.dart';
import '../network/api_client.dart';

/// Data access for the Near Me module.
///
/// Mirrors the shape of [HotelRepository]: a customer-facing search, plus the
/// owner-facing CRUD a business uses to list itself. The endpoints below are
/// the agreed contract; until the API ships them these calls surface an empty
/// result rather than an error screen, so Near Me degrades to a clean empty
/// state instead of breaking.
class BusinessRepository {
  BusinessRepository(this.api);

  final ApiClient api;

  dynamic _data(Map<String, dynamic> json) => json['data'] ?? json;

  List<BusinessListing> _parseList(Map<String, dynamic> response) {
    final payload = _data(response);
    final rawItems = payload is Map
        ? (payload['items'] as List? ?? const [])
        : payload is List
            ? payload
            : const [];
    return rawItems
        .whereType<Map>()
        .map((item) =>
            BusinessListing.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  // ------------------------------------------------------------- customer

  /// GET /api/v1/businesses/nearby
  Future<List<BusinessListing>> nearby({
    required double latitude,
    required double longitude,
    double radiusKm = 3,
    BusinessCategory? category,
    String query = '',
    String sort = 'distance',
  }) async {
    final parameters = <String, String>{
      'lat': '$latitude',
      'lng': '$longitude',
      'radiusKm': '$radiusKm',
      'sort': sort,
      if (category != null) 'category': category.apiValue,
      if (query.trim().isNotEmpty) 'q': query.trim(),
    };

    try {
      final response = await api.getJson(
        '/api/v1/businesses/nearby?${Uri(queryParameters: parameters).query}',
        authenticated: false,
      );
      return _parseList(response);
    } catch (_) {
      // The endpoint is not deployed yet in every environment. An empty list
      // renders the "no listings here" state, which is the honest answer.
      return const [];
    }
  }

  /// GET /api/v1/businesses/{id}
  Future<BusinessListing?> details(String id) async {
    try {
      final response =
          await api.getJson('/api/v1/businesses/$id', authenticated: false);
      final payload = _data(response);
      if (payload is Map) {
        return BusinessListing.fromJson(Map<String, dynamic>.from(payload));
      }
    } catch (_) {
      // fall through
    }
    return null;
  }

  // ---------------------------------------------------------------- owner

  /// GET /api/v1/businesses/mine
  Future<List<BusinessListing>> myBusinesses() async {
    final response = await api.getJson('/api/v1/businesses/mine');
    return _parseList(response);
  }

  /// POST /api/v1/businesses — submits for admin approval.
  Future<void> create(Map<String, dynamic> values) async {
    await api.postJson('/api/v1/businesses', values);
  }

  /// PUT /api/v1/businesses/{id}
  Future<void> update(String id, Map<String, dynamic> values) async {
    await api.putJson('/api/v1/businesses/$id', values);
  }
}
