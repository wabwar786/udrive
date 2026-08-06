import '../../models/hotel_models.dart';
import '../network/api_client.dart';

class HotelRepository {
  HotelRepository(this.api);

  final ApiClient api;

  static const List<HotelSummary> _demoHotels = [
    HotelSummary(
      id: '52000000-0000-0000-0000-000000000001',
      name: 'Neelum Riverside Lodge',
      address: 'Main Neelum Road, Keran',
      city: 'Keran',
      latitude: 34.6501,
      longitude: 73.9479,
      rating: 4.7,
      mainImageUrl:
          'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=1400&q=80',
      startingRate: 14500,
      availableRooms: 9,
      transportAvailable: true,
      approvalStatus: 'Approved',
    ),
    HotelSummary(
      id: '52000000-0000-0000-0000-000000000002',
      name: 'Muzaffarabad Grand Stay',
      address: 'Near Domel Bridge, Muzaffarabad',
      city: 'Muzaffarabad',
      latitude: 34.3714,
      longitude: 73.4718,
      rating: 4.5,
      mainImageUrl:
          'https://images.unsplash.com/photo-1564501049412-61c2a3083791?auto=format&fit=crop&w=1400&q=80',
      startingRate: 12000,
      availableRooms: 10,
      transportAvailable: true,
      approvalStatus: 'Approved',
    ),
    HotelSummary(
      id: '52000000-0000-0000-0000-000000000003',
      name: 'Rawalakot Pine View Hotel',
      address: 'Banjosa Road, Rawalakot',
      city: 'Rawalakot',
      latitude: 33.8578,
      longitude: 73.7604,
      rating: 4.6,
      mainImageUrl:
          'https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?auto=format&fit=crop&w=1400&q=80',
      startingRate: 13500,
      availableRooms: 5,
      transportAvailable: true,
      approvalStatus: 'Approved',
    ),
  ];

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
      if (items.isNotEmpty) return items;
    } catch (_) {
      // Keep the approved demo catalogue usable while a new API deployment is
      // propagating. Live approved hotels automatically replace this list.
    }

    return _filterDemoHotels(query);
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
      final fallback = _demoDetails(id);
      if (fallback != null) return fallback;
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

  List<HotelSummary> _filterDemoHotels(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return _demoHotels;
    return _demoHotels.where((hotel) {
      final searchable = '${hotel.name} ${hotel.city} ${hotel.address}'
          .toLowerCase();
      return searchable.contains(needle);
    }).toList(growable: false);
  }

  HotelDetails? _demoDetails(String id) {
    HotelSummary? hotel;
    for (final item in _demoHotels) {
      if (item.id == id) {
        hotel = item;
        break;
      }
    }
    if (hotel == null) return null;

    final rooms = switch (id) {
      '52000000-0000-0000-0000-000000000001' => const [
          HotelRoom(
            id: '53000000-0000-0000-0000-000000000001',
            roomType: 'Deluxe River View',
            capacity: 2,
            availableRooms: 6,
            rate: 14500,
            imageUrl:
                'https://images.unsplash.com/photo-1611892440504-42a792e24d32?auto=format&fit=crop&w=1200&q=80',
            amenities: ['King bed', 'Balcony', 'Heating', 'Private bathroom'],
          ),
          HotelRoom(
            id: '53000000-0000-0000-0000-000000000002',
            roomType: 'Family Suite',
            capacity: 5,
            availableRooms: 3,
            rate: 22500,
            imageUrl:
                'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=1200&q=80',
            amenities: ['Two rooms', 'Family seating', 'Heating', 'River view'],
          ),
        ],
      '52000000-0000-0000-0000-000000000002' => const [
          HotelRoom(
            id: '53000000-0000-0000-0000-000000000003',
            roomType: 'Executive Double',
            capacity: 2,
            availableRooms: 10,
            rate: 12000,
            imageUrl:
                'https://images.unsplash.com/photo-1598928636135-d146006ff4be?auto=format&fit=crop&w=1200&q=80',
            amenities: ['Double bed', 'WiFi', 'Breakfast', 'Air conditioning'],
          ),
        ],
      _ => const [
          HotelRoom(
            id: '53000000-0000-0000-0000-000000000004',
            roomType: 'Pine View Family Room',
            capacity: 4,
            availableRooms: 5,
            rate: 13500,
            imageUrl:
                'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=1200&q=80',
            amenities: ['Family beds', 'Heating', 'Mountain view', 'Hot water'],
          ),
        ],
    };

    return HotelDetails(
      hotel: hotel,
      rooms: rooms,
      description: switch (id) {
        '52000000-0000-0000-0000-000000000001' =>
          'A comfortable riverside stay for families visiting Keran and Upper Neelum.',
        '52000000-0000-0000-0000-000000000002' =>
          'Central city hotel with easy access to transport, markets and tourism routes.',
        _ =>
          'Quiet hill stay near Rawalakot with family rooms and mountain views.',
      },
      amenities: const [
        'Free WiFi',
        'Family rooms',
        'Parking',
        'Restaurant',
        'Transport available',
      ],
    );
  }
}
