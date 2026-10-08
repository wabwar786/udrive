import '../network/api_client.dart';

/// One booking on the driver's tour or rent car, with the customer to call.
class TourRentBooking {
  const TourRentBooking({
    required this.id,
    required this.kind,
    required this.customerName,
    required this.customerPhone,
    required this.title,
    required this.vehicle,
    required this.startsAt,
    required this.endsAt,
    required this.amount,
    required this.wholeVehicle,
    required this.seats,
    required this.rentalMode,
    required this.status,
    required this.createdAt,
  });

  final String id;

  /// `tour` or `rent`.
  final String kind;
  final String customerName;
  final String? customerPhone;
  final String title;
  final String vehicle;
  final DateTime startsAt;
  final DateTime? endsAt;
  final double amount;
  final bool wholeVehicle;

  /// Seats for a tour, days for a rental.
  final int seats;
  final String? rentalMode;

  /// A rental still `PendingOwner` could not be confirmed on its own (the
  /// wallet was short) and waits for the driver in the rentals screen.
  final String status;

  /// When the customer booked — "Nayi bookings" counts the last seven days.
  final DateTime createdAt;

  bool get isTour => kind == 'tour';
  bool get needsAccept => status == 'PendingOwner';

  factory TourRentBooking.fromJson(Map<String, dynamic> json) => TourRentBooking(
        id: '${json['id']}',
        kind: '${json['kind'] ?? 'tour'}',
        customerName: '${json['customerName'] ?? 'Customer'}',
        customerPhone: _text(json['customerPhone']),
        title: '${json['title'] ?? ''}',
        vehicle: '${json['vehicle'] ?? ''}',
        startsAt: _time(json['startsAt']) ?? DateTime.now(),
        endsAt: _time(json['endsAt']),
        amount: _number(json['amount']),
        wholeVehicle: json['wholeVehicle'] == true,
        seats: (json['seats'] as num?)?.toInt() ?? 0,
        rentalMode: _text(json['rentalMode']),
        status: '${json['status'] ?? ''}',
        createdAt: _time(json['createdAt']) ?? DateTime.now(),
      );
}

/// A waiting-list request: the vehicle or seats were taken when it came in.
class TourRentRequest {
  const TourRentRequest({
    required this.id,
    required this.kind,
    required this.customerName,
    required this.customerPhone,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.amount,
    required this.wholeVehicle,
    required this.seats,
    required this.totalSeats,
    required this.bookedSeats,
    required this.free,
    required this.status,
    required this.acceptExpiresAt,
  });

  final String id;
  final String kind;
  final String customerName;
  final String? customerPhone;
  final String title;
  final DateTime startsAt;
  final DateTime? endsAt;
  final double amount;
  final bool wholeVehicle;
  final int seats;
  final int totalSeats;
  final int bookedSeats;

  /// There is room for it now, so the driver can accept it.
  final bool free;

  /// `Waiting`, `Accepted` or `Expired`.
  final String status;
  final DateTime? acceptExpiresAt;

  bool get isTour => kind == 'tour';
  bool get accepted => status == 'Accepted';

  factory TourRentRequest.fromJson(Map<String, dynamic> json) => TourRentRequest(
        id: '${json['id']}',
        kind: '${json['kind'] ?? 'tour'}',
        customerName: '${json['customerName'] ?? 'Customer'}',
        customerPhone: _text(json['customerPhone']),
        title: '${json['title'] ?? ''}',
        startsAt: _time(json['startsAt']) ?? DateTime.now(),
        endsAt: _time(json['endsAt']),
        amount: _number(json['amount']),
        wholeVehicle: json['wholeVehicle'] == true,
        seats: (json['seats'] as num?)?.toInt() ?? 0,
        totalSeats: (json['totalSeats'] as num?)?.toInt() ?? 0,
        bookedSeats: (json['bookedSeats'] as num?)?.toInt() ?? 0,
        free: json['free'] == true,
        status: '${json['status'] ?? 'Waiting'}',
        acceptExpiresAt: _time(json['acceptExpiresAt']),
      );
}

/// An upcoming departure and how full it is.
class TourRentDeparture {
  const TourRentDeparture({
    required this.id,
    required this.vehicleId,
    required this.title,
    required this.departureAt,
    required this.totalSeats,
    required this.bookedSeats,
    required this.bookings,
  });

  final String id;
  final String vehicleId;
  final String title;
  final DateTime departureAt;
  final int totalSeats;
  final int bookedSeats;
  final int bookings;

  bool get full => totalSeats > 0 && bookedSeats >= totalSeats;

  factory TourRentDeparture.fromJson(Map<String, dynamic> json) =>
      TourRentDeparture(
        id: '${json['id']}',
        vehicleId: '${json['vehicleId'] ?? ''}',
        title: '${json['title'] ?? ''}',
        departureAt: _time(json['departureAt']) ?? DateTime.now(),
        totalSeats: (json['totalSeats'] as num?)?.toInt() ?? 0,
        bookedSeats: (json['bookedSeats'] as num?)?.toInt() ?? 0,
        bookings: (json['bookings'] as num?)?.toInt() ?? 0,
      );
}

/// Everything on the Tour & Rent home.
class TourRentHome {
  const TourRentHome({
    required this.vehicles,
    required this.ridesVehicles,
    required this.walletBalance,
    required this.newBookings,
    required this.waitingCount,
    required this.weekEarnings,
    required this.weekTour,
    required this.weekRent,
    required this.bookings,
    required this.waitlist,
    required this.departures,
  });

  final List<String> vehicles;

  /// Vehicles that take city or city-to-city rides. Zero: a tour/rent-only
  /// driver, whose dashboard is this home.
  final int ridesVehicles;
  final double walletBalance;
  final int newBookings;
  final int waitingCount;
  final double weekEarnings;
  final double weekTour;
  final double weekRent;
  final List<TourRentBooking> bookings;
  final List<TourRentRequest> waitlist;
  final List<TourRentDeparture> departures;

  bool get tourRentOnly => ridesVehicles == 0 && vehicles.isNotEmpty;

  factory TourRentHome.fromJson(Map<String, dynamic> json) => TourRentHome(
        vehicles: [
          for (final item in (json['vehicles'] as List? ?? const []))
            '$item',
        ],
        ridesVehicles: (json['ridesVehicles'] as num?)?.toInt() ?? 0,
        walletBalance: _number(json['walletBalance']),
        newBookings: (json['newBookings'] as num?)?.toInt() ?? 0,
        waitingCount: (json['waitingCount'] as num?)?.toInt() ?? 0,
        weekEarnings: _number(json['weekEarnings']),
        weekTour: _number(json['weekTour']),
        weekRent: _number(json['weekRent']),
        bookings: _list(json['bookings'], TourRentBooking.fromJson),
        waitlist: _list(json['waitlist'], TourRentRequest.fromJson),
        departures: _list(json['departures'], TourRentDeparture.fromJson),
      );
}

/// The Tour & Rent home's server calls.
class TourRentRepository {
  TourRentRepository(this.api);

  final ApiClient api;

  Future<TourRentHome> home() async {
    final response = await api.getJson('/api/v1/driver/tour-rent/home');
    final data = response['data'];
    return TourRentHome.fromJson(
        data is Map ? Map<String, dynamic>.from(data) : const {});
  }

  /// Gives a freed place to the waiting customer. Returns the server's
  /// message for the snackbar.
  Future<String> accept(TourRentRequest request) => _post(
      '/api/v1/driver/tour-rent/waitlist/${request.kind}/${request.id}/accept');

  Future<String> decline(TourRentRequest request) => _post(
      '/api/v1/driver/tour-rent/waitlist/${request.kind}/${request.id}/decline');

  /// The booked customer did not come; frees the seats or the car.
  Future<String> noShow(TourRentBooking booking) => _post(
      '/api/v1/driver/tour-rent/bookings/${booking.kind}/${booking.id}/no-show');

  Future<String> _post(String path) async {
    final response = await api.postJson(path, const {});
    return '${response['message'] ?? 'Ho gaya.'}';
  }
}

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) read) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) read(Map<String, dynamic>.from(item)),
  ];
}

double _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

DateTime? _time(Object? value) {
  final text = _text(value);
  return text == null ? null : DateTime.tryParse(text)?.toLocal();
}
