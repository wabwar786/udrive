import '../../models/hotel_models.dart';
import '../network/api_client.dart';

class HotelRepository {
  HotelRepository(this.api);

  final ApiClient api;

  // _demoHotels / _filterDemoHotels / _demoDetails were here: three invented
  // businesses — "Neelum Riverside Lodge", "Muzaffarabad Grand Stay",
  // "Rawalakot Pine View Hotel" — with invented addresses in real towns, real
  // GPS coordinates, ratings, nightly rates and hotlinked stock photographs.
  //
  // They were not a debug aid. search() returned them whenever the API threw
  // AND whenever it returned an empty list, so they were the default result
  // for every customer, three taps from Home. The rooms carried fixed ids the
  // server has never issued, so "Book" posted to /api/v1/hotels/{id}/bookings
  // for a hotel that does not exist and failed silently.
  //
  // Presenting named accommodation businesses that we have no relationship
  // with, at prices we invented, is not something a fallback path may do.

  dynamic _data(Map<String, dynamic> json) => json['data'] ?? json;

  Future<List<HotelSummary>> search({
    String query = '',
    DateTime? checkIn,
    DateTime? checkOut,
    int guests = 1,
    int rooms = 1,
    int page = 1,
  }) async {
    final parameters = <String, String>{
      'query': query,
      'guests': '$guests',
      'rooms': '$rooms',
      'page': '$page',
      'pageSize': '20',
    };
    if (checkIn != null) {
      parameters['checkIn'] = checkIn.toIso8601String().substring(0, 10);
    }
    if (checkOut != null) {
      parameters['checkOut'] = checkOut.toIso8601String().substring(0, 10);
    }

    try {
      final response = await api.getJson(
        '/api/v1/hotels?${Uri(queryParameters: parameters).query}',
        authenticated: false,
      );
      final payload = Map<String, dynamic>.from(_data(response) as Map);
      final items = ((payload['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => HotelSummary.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false);
      // An empty list is a real answer — no approved hotel matched — and the
      // caller shows its empty state for it. It is not a reason to substitute
      // anything.
      return items;
    } catch (_) {
      rethrow;
    }
  }

  Future<HotelDetails> details(
    String id, {
    DateTime? checkIn,
    DateTime? checkOut,
  }) async {
    final parameters = <String, String>{};
    if (checkIn != null) {
      parameters['checkIn'] = checkIn.toIso8601String().substring(0, 10);
    }
    if (checkOut != null) {
      parameters['checkOut'] = checkOut.toIso8601String().substring(0, 10);
    }

    try {
      final suffix = parameters.isEmpty
          ? ''
          : '?${Uri(queryParameters: parameters).query}';
      final response = await api.getJson(
        '/api/v1/hotels/$id$suffix',
        authenticated: false,
      );
      final payload = Map<String, dynamic>.from(_data(response) as Map);
      final hotelJson = Map<String, dynamic>.from(payload['hotel'] as Map);
      return HotelDetails(
        hotel: HotelSummary.fromJson(hotelJson),
        rooms: ((payload['rooms'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => HotelRoom.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(growable: false),
        description: '${hotelJson['description'] ?? ''}',
        amenities: ((hotelJson['amenities'] as List?) ?? const [])
            .map((item) => '$item')
            .toList(growable: false),
      );
    } catch (_) {
      rethrow;
    }
  }

  Future<List<HotelSummary>> myHotels() async {
    final response = await api.getJson('/api/v1/hotels/owner/my');
    return (_data(response) as List)
        .whereType<Map>()
        .map((item) => HotelSummary.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> ownerBookings({String? hotelId}) async {
    final response = await api.getJson(
      '/api/v1/hotels/owner/bookings${hotelId == null ? '' : '?hotelId=$hotelId'}',
    );
    return (_data(response) as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> createHotel(Map<String, dynamic> values) async {
    await api.postJson('/api/v1/hotels/owner', values);
  }

  Future<void> addRoom(String id, Map<String, dynamic> values) async {
    await api.postJson('/api/v1/hotels/owner/$id/rooms', values);
  }

  Future<Map<String, dynamic>> book(
    String hotelId,
    Map<String, dynamic> values,
  ) async {
    return Map<String, dynamic>.from(
      _data(await api.postJson('/api/v1/hotels/$hotelId/bookings', values)),
    );
  }

}
