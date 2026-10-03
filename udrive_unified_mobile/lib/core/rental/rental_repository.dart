import 'package:file_picker/file_picker.dart';

import '../../models/auth_models.dart';
import '../network/api_client.dart';

/// One car on offer, as the rental list shows it.
class RentalVehicle {
  const RentalVehicle({
    required this.vehicleId,
    required this.name,
    required this.category,
    required this.registrationNumber,
    required this.colour,
    required this.year,
    required this.passengerCapacity,
    required this.luggageCapacity,
    required this.photoUrl,
    required this.withDriverDaily,
    required this.selfDriveDaily,
    required this.securityDeposit,
    required this.minimumDays,
    required this.kmPerDay,
    required this.fuelIncluded,
    required this.pickupPoint,
    required this.ownerName,
    required this.ownerRating,
    required this.hasAirConditioning,
    required this.isFourByFour,
  });

  final String vehicleId;
  final String name;
  final String category;
  final String registrationNumber;
  final String colour;
  final int year;
  final int passengerCapacity;
  final int luggageCapacity;

  /// The owner's own photograph. Never a stock picture of the model — a rental
  /// is a decision about this one car.
  final String? photoUrl;

  final double? withDriverDaily;
  final double? selfDriveDaily;
  final double securityDeposit;
  final int minimumDays;
  final int? kmPerDay;
  final bool fuelIncluded;
  final String? pickupPoint;
  final String ownerName;
  final double ownerRating;
  final bool hasAirConditioning;
  final bool isFourByFour;

  bool get offersWithDriver => (withDriverDaily ?? 0) > 0;
  bool get offersSelfDrive => (selfDriveDaily ?? 0) > 0;

  /// The lower of the two, which is what a list should lead with.
  double get fromDaily {
    final rates = <double>[
      if (offersWithDriver) withDriverDaily!,
      if (offersSelfDrive) selfDriveDaily!,
    ];
    if (rates.isEmpty) return 0;
    return rates.reduce((a, b) => a < b ? a : b);
  }

  factory RentalVehicle.fromJson(Map<String, dynamic> json) => RentalVehicle(
        vehicleId: '${json['vehicleId'] ?? ''}',
        name: '${json['name'] ?? ''}'.trim(),
        category: '${json['category'] ?? ''}',
        registrationNumber: '${json['registrationNumber'] ?? ''}',
        colour: '${json['colour'] ?? ''}',
        year: (json['year'] as num?)?.toInt() ?? 0,
        passengerCapacity: (json['passengerCapacity'] as num?)?.toInt() ?? 0,
        luggageCapacity: (json['luggageCapacity'] as num?)?.toInt() ?? 0,
        photoUrl: _text(json['photoUrl']),
        withDriverDaily: _number(json['withDriverDaily']),
        selfDriveDaily: _number(json['selfDriveDaily']),
        securityDeposit: _number(json['securityDeposit']) ?? 0,
        minimumDays: (json['minimumDays'] as num?)?.toInt() ?? 1,
        kmPerDay: (json['kmPerDay'] as num?)?.toInt(),
        fuelIncluded: json['fuelIncluded'] == true,
        pickupPoint: _text(json['pickupPoint']),
        ownerName: '${json['ownerName'] ?? 'Owner'}',
        ownerRating: _number(json['ownerRating']) ?? 0,
        hasAirConditioning: json['hasAirConditioning'] == true,
        isFourByFour: json['isFourByFour'] == true,
      );
}

/// A day the car cannot be taken, and what has it.
class RentalBlockedDay {
  const RentalBlockedDay({required this.date, required this.reason});

  final DateTime date;

  /// `rented`, `turnaround`, `tour` or `trip`.
  final String reason;

  factory RentalBlockedDay.fromJson(Map<String, dynamic> json) =>
      RentalBlockedDay(
        date: DateTime.parse('${json['date']}'),
        reason: '${json['reason'] ?? ''}',
      );
}

/// What a set of dates costs, worked out by the server.
class RentalQuote {
  const RentalQuote({
    required this.days,
    required this.dailyRate,
    required this.subtotal,
    required this.securityDeposit,
    required this.advanceAmount,
    required this.balanceDue,
    required this.kmIncluded,
    required this.fuelIncluded,
    required this.disclaimerVersion,
    required this.requiresCustomerDocuments,
    required this.customerDocumentsOnFile,
  });

  final int days;
  final double dailyRate;
  final double subtotal;
  final double securityDeposit;

  /// Paid through the app now. The rest and the deposit are cash to the owner.
  final double advanceAmount;
  final double balanceDue;

  final int? kmIncluded;
  final bool fuelIncluded;
  final int disclaimerVersion;
  final bool requiresCustomerDocuments;
  final bool customerDocumentsOnFile;

  bool get documentsMissing =>
      requiresCustomerDocuments && !customerDocumentsOnFile;

  factory RentalQuote.fromJson(Map<String, dynamic> json) => RentalQuote(
        days: (json['days'] as num?)?.toInt() ?? 0,
        dailyRate: _number(json['dailyRate']) ?? 0,
        subtotal: _number(json['subtotal']) ?? 0,
        securityDeposit: _number(json['securityDeposit']) ?? 0,
        advanceAmount: _number(json['advanceAmount']) ?? 0,
        balanceDue: _number(json['balanceDue']) ?? 0,
        kmIncluded: (json['kmIncluded'] as num?)?.toInt(),
        fuelIncluded: json['fuelIncluded'] == true,
        disclaimerVersion: (json['disclaimerVersion'] as num?)?.toInt() ?? 1,
        requiresCustomerDocuments: json['requiresCustomerDocuments'] == true,
        customerDocumentsOnFile: json['customerDocumentsOnFile'] == true,
      );
}

class RentalBooking {
  const RentalBooking({
    required this.id,
    required this.reference,
    required this.vehicleName,
    required this.registrationNumber,
    required this.photoUrl,
    required this.startDate,
    required this.endDate,
    required this.rentalMode,
    required this.days,
    required this.subtotal,
    required this.securityDeposit,
    required this.advanceAmount,
    required this.balanceDue,
    required this.pickupPoint,
    required this.status,
    required this.counterpartName,
    required this.counterpartPhone,
    required this.advanceRefundableNow,
  });

  final String id;
  final String reference;
  final String vehicleName;
  final String registrationNumber;
  final String? photoUrl;
  final DateTime startDate;
  final DateTime endDate;
  final String rentalMode;
  final int days;
  final double subtotal;
  final double securityDeposit;
  final double advanceAmount;
  final double balanceDue;
  final String? pickupPoint;
  final String status;

  /// Whoever the reader is not: the customer sees the owner, and the reverse.
  final String counterpartName;
  final String? counterpartPhone;

  /// Whether cancelling right now still returns the advance. Decided by the
  /// server so the app never has to work the rule out for itself.
  final bool advanceRefundableNow;

  bool get isSelfDrive => rentalMode == 'SelfDrive';
  bool get isLive => status == 'Confirmed' || status == 'HandedOver';

  factory RentalBooking.fromJson(Map<String, dynamic> json) => RentalBooking(
        id: '${json['id'] ?? ''}',
        reference: '${json['bookingReference'] ?? ''}',
        vehicleName: '${json['vehicleName'] ?? ''}',
        registrationNumber: '${json['registrationNumber'] ?? ''}',
        photoUrl: _text(json['photoUrl']),
        startDate: DateTime.parse('${json['startDate']}'),
        endDate: DateTime.parse('${json['endDate']}'),
        rentalMode: '${json['rentalMode'] ?? ''}',
        days: (json['days'] as num?)?.toInt() ?? 0,
        subtotal: _number(json['subtotal']) ?? 0,
        securityDeposit: _number(json['securityDeposit']) ?? 0,
        advanceAmount: _number(json['advanceAmount']) ?? 0,
        balanceDue: _number(json['balanceDue']) ?? 0,
        pickupPoint: _text(json['pickupPoint']),
        status: '${json['status'] ?? ''}',
        counterpartName: '${json['counterpartName'] ?? ''}',
        counterpartPhone: _text(json['counterpartPhone']),
        advanceRefundableNow: json['advanceRefundableNow'] == true,
      );
}

/// Which of the four identity documents are on file.
class CustomerDocuments {
  const CustomerDocuments({
    required this.cnicFront,
    required this.cnicBack,
    required this.drivingLicence,
    required this.selfie,
    required this.complete,
  });

  final bool cnicFront;
  final bool cnicBack;
  final bool drivingLicence;
  final bool selfie;
  final bool complete;

  factory CustomerDocuments.fromJson(Map<String, dynamic> json) =>
      CustomerDocuments(
        cnicFront: json['cnicFront'] == true,
        cnicBack: json['cnicBack'] == true,
        drivingLicence: json['drivingLicence'] == true,
        selfie: json['selfie'] == true,
        complete: json['complete'] == true,
      );

  static const empty = CustomerDocuments(
    cnicFront: false,
    cnicBack: false,
    drivingLicence: false,
    selfie: false,
    complete: false,
  );
}

/// Raised when the server refuses, carrying the reason it gave.
class RentalRefused implements Exception {
  const RentalRefused(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

class RentalRepository {
  RentalRepository(this.api);

  final ApiClient api;

  Future<List<RentalVehicle>> search({
    DateTime? from,
    DateTime? to,
    String? mode,
    String? category,
  }) async {
    final query = <String, String>{
      if (from != null) 'from': _day(from),
      if (to != null) 'to': _day(to),
      if (mode != null && mode.isNotEmpty) 'mode': mode,
      if (category != null && category.isNotEmpty) 'category': category,
    };

    final response = await api.getJson(
      '/api/v1/rentals/vehicles'
      '${query.isEmpty ? '' : '?${Uri(queryParameters: query).query}'}',
      authenticated: false,
    );
    return _list(response, RentalVehicle.fromJson);
  }

  Future<List<RentalBlockedDay>> blockedDays(String vehicleId,
      {DateTime? from}) async {
    final query = from == null ? '' : '?from=${_day(from)}';
    final response = await api.getJson(
      '/api/v1/rentals/vehicles/$vehicleId/blocked-days$query',
      authenticated: false,
    );
    return _list(response, RentalBlockedDay.fromJson);
  }

  /// The price, worked out server-side.
  ///
  /// Never computed in the app. Days × rate looks like arithmetic anyone can
  /// do, but the advance percentage, the minimum-days rule and whether those
  /// dates are even free are all server decisions, and an app that guessed any
  /// of them would quote a figure the booking then refuses.
  Future<RentalQuote> quote(
    String vehicleId, {
    required DateTime from,
    required DateTime to,
    required String mode,
  }) async =>
      _one(
        () => api.postJson(
          '/api/v1/rentals/vehicles/$vehicleId/quote',
          {
            'startDate': _day(from),
            'endDate': _day(to),
            'rentalMode': mode,
          },
        ),
        RentalQuote.fromJson,
      );

  Future<RentalBooking> book({
    required String vehicleId,
    required DateTime from,
    required DateTime to,
    required String mode,
    required int disclaimerVersion,
  }) async =>
      _one(
        () => api.postJson('/api/v1/rentals/bookings', {
          'vehicleId': vehicleId,
          'startDate': _day(from),
          'endDate': _day(to),
          'rentalMode': mode,
          'acceptedDisclaimerVersion': disclaimerVersion,
        }),
        RentalBooking.fromJson,
      );

  Future<List<RentalBooking>> myBookings() async {
    final response = await api.getJson('/api/v1/rentals/bookings');
    return _list(response, RentalBooking.fromJson);
  }

  Future<RentalBooking> cancel(String bookingId, {String? reason}) async => _one(
        () => api.postJson('/api/v1/rentals/bookings/$bookingId/cancel', {
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        }),
        RentalBooking.fromJson,
      );

  // ── the owner's side ──────────────────────────────────────────────────────

  Future<List<RentalBooking>> driverBookings() async {
    final response = await api.getJson('/api/v1/driver/rentals');
    return _list(response, RentalBooking.fromJson);
  }

  Future<RentalBooking> setStatus(String bookingId, String status) async => _one(
        () => api.postJson('/api/v1/driver/rentals/$bookingId/status/$status',
            const {}),
        RentalBooking.fromJson,
      );

  // ── the customer's own documents ──────────────────────────────────────────

  Future<CustomerDocuments> documents() async {
    try {
      final response = await api.getJson('/api/v1/customer/documents');
      final payload = response['data'] ?? response;
      return payload is Map
          ? CustomerDocuments.fromJson(Map<String, dynamic>.from(payload))
          : CustomerDocuments.empty;
    } catch (_) {
      return CustomerDocuments.empty;
    }
  }

  /// Uploads one of `cnic-front`, `cnic-back`, `driving-licence`, `selfie`.
  Future<CustomerDocuments> uploadDocument(
      String kind, PlatformFile file) async {
    final response = await api.uploadFile(
      '/api/v1/customer/documents/$kind',
      fieldName: 'file',
      file: file,
      fields: const {},
    );
    final payload = response['data'] ?? response;
    return payload is Map
        ? CustomerDocuments.fromJson(Map<String, dynamic>.from(payload))
        : CustomerDocuments.empty;
  }

  // ── plumbing ──────────────────────────────────────────────────────────────

  static List<T> _list<T>(
      Map<String, dynamic> response, T Function(Map<String, dynamic>) read) {
    final payload = response['data'] ?? response;
    if (payload is! List) return const [];
    final list = <T>[];
    for (final item in payload) {
      if (item is Map) list.add(read(Map<String, dynamic>.from(item)));
    }
    return list;
  }

  static Future<T> _one<T>(
    Future<Map<String, dynamic>> Function() call,
    T Function(Map<String, dynamic>) read,
  ) async {
    final Map<String, dynamic> response;
    try {
      response = await call();
    } on ApiException catch (error) {
      throw RentalRefused(error.code ?? '', error.message);
    }

    final payload = response['data'] ?? response;
    if (payload is Map) return read(Map<String, dynamic>.from(payload));
    throw const RentalRefused(
        'unexpected_response', 'The server sent something unexpected.');
  }

  static String _day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }
}
