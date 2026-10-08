import '../network/api_client.dart';

/// One hotel of this owner, for the "Hotel badlein" list.
class OwnerHotel {
  const OwnerHotel({
    required this.id,
    required this.name,
    required this.city,
    required this.approvalStatus,
    required this.photoUrl,
    required this.roomTypes,
    required this.totalRooms,
  });

  final String id;
  final String name;
  final String city;
  final String approvalStatus;
  final String? photoUrl;
  final int roomTypes;
  final int totalRooms;

  factory OwnerHotel.fromJson(Map<String, dynamic> j) => OwnerHotel(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        city: '${j['city'] ?? ''}',
        approvalStatus: '${j['approvalStatus'] ?? 'Pending'}',
        photoUrl: _text(j['photoUrl']),
        roomTypes: _int(j['roomTypes']),
        totalRooms: _int(j['totalRooms']),
      );
}

/// A guest's booking, as the hotel sees it.
class OwnerHotelBooking {
  const OwnerHotelBooking({
    required this.id,
    required this.reference,
    required this.guestName,
    required this.guestPhone,
    required this.roomType,
    required this.rooms,
    required this.guests,
    required this.checkIn,
    required this.checkOut,
    required this.amount,
    required this.status,
    required this.arrivalTime,
    required this.transport,
  });

  final String id;
  final String reference;
  final String guestName;
  final String? guestPhone;
  final String roomType;
  final int rooms;
  final int guests;
  final DateTime checkIn;
  final DateTime checkOut;
  final double amount;
  final String status;
  final String? arrivalTime;
  final bool transport;

  int get nights => checkOut.difference(checkIn).inDays;

  factory OwnerHotelBooking.fromJson(Map<String, dynamic> j) => OwnerHotelBooking(
        id: '${j['id']}',
        reference: '${j['reference'] ?? ''}',
        guestName: '${j['guestName'] ?? 'Guest'}',
        guestPhone: _text(j['guestPhone']),
        roomType: '${j['roomType'] ?? ''}',
        rooms: _int(j['rooms']),
        guests: _int(j['guests']),
        checkIn: DateTime.parse('${j['checkIn']}'),
        checkOut: DateTime.parse('${j['checkOut']}'),
        amount: _double(j['amount']),
        status: '${j['status'] ?? ''}',
        arrivalTime: _text(j['arrivalTime']),
        transport: j['transport'] == true,
      );
}

/// One room type and how many are free each of the next seven nights.
class OwnerHotelRoom {
  const OwnerHotelRoom({
    required this.roomType,
    required this.rate,
    required this.freePerDay,
  });

  final String roomType;
  final double rate;
  final List<int> freePerDay;

  factory OwnerHotelRoom.fromJson(Map<String, dynamic> j) => OwnerHotelRoom(
        roomType: '${j['roomType'] ?? ''}',
        rate: _double(j['rate']),
        freePerDay: [
          for (final v in (j['freePerDay'] as List? ?? const [])) _int(v),
        ],
      );
}

class OwnerHotelDashboard {
  const OwnerHotelDashboard({
    required this.hotels,
    required this.hotelId,
    required this.newBookings,
    required this.freeRoomsToday,
    required this.totalRooms,
    required this.monthAmount,
    required this.bookings,
    required this.checkInsToday,
    required this.checkOutsToday,
    required this.rooms,
    required this.today,
  });

  final List<OwnerHotel> hotels;
  final String? hotelId;
  final int newBookings;
  final int freeRoomsToday;
  final int totalRooms;
  final double monthAmount;
  final List<OwnerHotelBooking> bookings;
  final List<OwnerHotelBooking> checkInsToday;
  final List<OwnerHotelBooking> checkOutsToday;
  final List<OwnerHotelRoom> rooms;
  final DateTime today;

  OwnerHotel? get hotel {
    for (final h in hotels) {
      if (h.id == hotelId) return h;
    }
    return null;
  }

  factory OwnerHotelDashboard.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) read) => [
          for (final item in (j[key] as List? ?? const []))
            if (item is Map) read(Map<String, dynamic>.from(item)),
        ];
    return OwnerHotelDashboard(
      hotels: list('hotels', OwnerHotel.fromJson),
      hotelId: _text(j['hotelId']),
      newBookings: _int(j['newBookings']),
      freeRoomsToday: _int(j['freeRoomsToday']),
      totalRooms: _int(j['totalRooms']),
      monthAmount: _double(j['monthAmount']),
      bookings: list('bookings', OwnerHotelBooking.fromJson),
      checkInsToday: list('checkInsToday', OwnerHotelBooking.fromJson),
      checkOutsToday: list('checkOutsToday', OwnerHotelBooking.fromJson),
      rooms: list('rooms', OwnerHotelRoom.fromJson),
      today: DateTime.tryParse('${j['today']}') ?? DateTime.now(),
    );
  }
}

/// The hotel owner's home screen and guest arrival / departure.
class HotelOwnerDashboardRepository {
  HotelOwnerDashboardRepository(this.api);

  final ApiClient api;

  Future<OwnerHotelDashboard> load({String? hotelId}) async {
    final response = await api.getJson(
        '/api/v1/hotels/owner/dashboard${hotelId == null ? '' : '?hotelId=$hotelId'}');
    final data = response['data'];
    return OwnerHotelDashboard.fromJson(
        data is Map ? Map<String, dynamic>.from(data) : const {});
  }

  /// [status] is `CheckedIn` or `CheckedOut`. Returns the server's message.
  Future<String> setStatus(String bookingId, String status) async {
    final response = await api.postJson(
        '/api/v1/hotels/owner/bookings/$bookingId/status/$status', const {});
    return '${response['message'] ?? 'Ho gaya.'}';
  }
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

double _double(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

String? _text(Object? v) {
  if (v == null) return null;
  final t = '$v'.trim();
  return t.isEmpty || t == 'null' ? null : t;
}
