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
    this.isDemo = false,
    this.bookedOnDates = false,
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

  /// A sample car added from the admin portal. It is shown with a Demo label
  /// and the server refuses to book it.
  final bool isDemo;

  /// Another customer has this car on some of the chosen dates. It is shown
  /// anyway, so a waiting-list request can be sent.
  final bool bookedOnDates;

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
        isDemo: json['isDemo'] == true,
        bookedOnDates: json['bookedOnDates'] == true,
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

/// The four condition photos taken at one end of a rental.
class RentalConditionPhotos {
  const RentalConditionPhotos({this.front, this.back, this.left, this.right});

  final String? front;
  final String? back;
  final String? left;
  final String? right;

  static const sides = ['front', 'back', 'left', 'right'];

  String? operator [](String side) => switch (side) {
        'front' => front,
        'back' => back,
        'left' => left,
        'right' => right,
        _ => null,
      };

  bool get complete =>
      front != null && back != null && left != null && right != null;

  RentalConditionPhotos withSide(String side, String? url) =>
      RentalConditionPhotos(
        front: side == 'front' ? url : front,
        back: side == 'back' ? url : back,
        left: side == 'left' ? url : left,
        right: side == 'right' ? url : right,
      );

  static const empty = RentalConditionPhotos();

  factory RentalConditionPhotos.fromJson(Object? json) {
    if (json is! Map) return empty;
    return RentalConditionPhotos(
      front: _text(json['front']),
      back: _text(json['back']),
      left: _text(json['left']),
      right: _text(json['right']),
    );
  }
}

/// The meter and the tank, at handover or at return.
class RentalMeterReading {
  const RentalMeterReading({
    required this.odometerKm,
    required this.fuel,
    required this.at,
  });

  final int odometerKm;

  /// "Quarter", "Half", "ThreeQuarters" or "Full".
  final String fuel;
  final DateTime? at;

  String get fuelLabel => rentalFuelLabel(fuel);

  static RentalMeterReading? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = _text(json['at']);
    return RentalMeterReading(
      odometerKm: (json['odometerKm'] as num?)?.toInt() ?? 0,
      fuel: '${json['fuel'] ?? ''}',
      at: at == null ? null : DateTime.tryParse(at)?.toLocal(),
    );
  }
}

/// "¼", "½", "¾" or "Full" for the server's fuel words.
String rentalFuelLabel(String fuel) => switch (fuel) {
      'Quarter' => '¼',
      'Half' => '½',
      'ThreeQuarters' => '¾',
      'Full' => 'Full',
      _ => fuel,
    };

/// How a rental status reads to a person, and which tone it gets.
///
/// One place for every status the server sends, so a new one — PendingOwner,
/// Declined, Expired — reads the same on every screen.
String rentalStatusLabel(String status) => switch (status) {
      'PendingOwner' => 'Waiting for owner',
      'Confirmed' => 'Confirmed',
      'HandedOver' => 'Car out',
      'Returned' => 'Returned',
      'Cancelled' => 'Cancelled',
      'NoShow' => 'No-show',
      'Declined' => 'Owner declined — advance refunded',
      'Expired' => 'Expired — advance refunded',
      _ => status,
    };

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
    this.vehicleId = '',
    this.ownerRespondBy,
    this.driverName,
    this.driverPhone,
    this.handoverPhotos = RentalConditionPhotos.empty,
    this.returnPhotos = RentalConditionPhotos.empty,
    this.handover,
    this.returned,
    this.customerDocumentsVerified = false,
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

  final String vehicleId;

  /// The owner's answer deadline. Only set while [isPendingOwner].
  final DateTime? ownerRespondBy;

  /// The driver the owner assigned (with-driver rentals), once confirmed.
  final String? driverName;
  final String? driverPhone;

  final RentalConditionPhotos handoverPhotos;
  final RentalConditionPhotos returnPhotos;
  final RentalMeterReading? handover;
  final RentalMeterReading? returned;

  /// Self-drive: all four of the customer's documents are on file.
  final bool customerDocumentsVerified;

  bool get isSelfDrive => rentalMode == 'SelfDrive';
  bool get isPendingOwner => status == 'PendingOwner';

  /// Ended with the advance going back: the owner said no or never answered.
  bool get isRefusedByOwner => status == 'Declined' || status == 'Expired';

  /// Still open: waiting for the owner, confirmed, or out on the road.
  bool get isLive =>
      status == 'PendingOwner' ||
      status == 'Confirmed' ||
      status == 'HandedOver';

  String get statusLabel => rentalStatusLabel(status);

  factory RentalBooking.fromJson(Map<String, dynamic> json) => RentalBooking(
        id: '${json['id'] ?? ''}',
        reference: '${json['bookingReference'] ?? ''}',
        vehicleName: '${json['vehicleName'] ?? ''}',
        registrationNumber: '${json['registrationNumber'] ?? ''}',
        photoUrl: _text(json['vehiclePhotoUrl']) ?? _text(json['photoUrl']),
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
        advanceRefundableNow: json['advanceRefundableNow'] == true ||
            json['refundableNow'] == true,
        vehicleId: '${json['vehicleId'] ?? ''}',
        ownerRespondBy: _timestamp(json['ownerRespondBy']),
        driverName: _text(json['driverName']),
        driverPhone: _text(json['driverPhone']),
        handoverPhotos: RentalConditionPhotos.fromJson(json['handoverPhotos']),
        returnPhotos: RentalConditionPhotos.fromJson(json['returnPhotos']),
        handover: RentalMeterReading.fromJson(json['handover']),
        returned: RentalMeterReading.fromJson(json['returned']),
        customerDocumentsVerified: json['customerDocumentsVerified'] == true,
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

/// The rental terms, as the admin currently has them worded.
///
/// Fetched rather than compiled in. The wording used to live inside the app,
/// which made changing a single sentence a release: a new build, a Play Store
/// review and a wait, for a line of text a lawyer may want altered the same
/// afternoon. Worse, the version was already stored on every booking — the
/// database was carefully recording which text a Customer agreed to while the
/// text itself lived where the database could not see it.
class RentalTerms {
  const RentalTerms({
    required this.version,
    required this.textEn,
    required this.textUr,
  });

  final int version;
  final String textEn;
  final String textUr;

  String text(String languageCode) =>
      languageCode == 'ur' && textUr.isNotEmpty ? textUr : textEn;

  /// What the app shows if the settings call fails.
  ///
  /// Version 0, deliberately: the server refuses a booking whose accepted
  /// version is not the current one, so a Customer can read this but cannot
  /// book against it. Agreeing to wording the platform cannot identify later
  /// is worth nothing to either side.
  static const fallback = RentalTerms(
    version: 0,
    textEn: 'The car goes out in your care. UDrive introduces you to the owner '
        'and nothing more: we do not inspect the car, we do not check its '
        'papers, and we are not responsible for a fine, a crash, theft or '
        'damage.',
    textUr: '',
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

  /// Asks for a car that is booked on these dates. Nothing is paid; if the
  /// owner accepts, the customer is told and books as usual.
  Future<void> joinWaitlist({
    required String vehicleId,
    required DateTime from,
    required DateTime to,
    required String mode,
  }) async {
    try {
      await api.postJson('/api/v1/rentals/waitlist', {
        'vehicleId': vehicleId,
        'startDate': _day(from),
        'endDate': _day(to),
        'rentalMode': mode,
      });
    } on ApiException catch (error) {
      throw RentalRefused(error.code ?? '', error.message);
    }
  }

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

  /// Every rental of the owner's vehicles, newest states included.
  Future<List<RentalBooking>> ownerRentals() => driverBookings();

  /// The owner's answer to a new booking.
  ///
  /// A with-driver rental needs [fleetDriverId] on accept: an approved driver
  /// whose licence is still valid. A refusal refunds the customer's advance.
  Future<RentalBooking> respond(
    String bookingId, {
    required bool accept,
    String? fleetDriverId,
    String? reason,
  }) async =>
      _one(
        () => api.postJson('/api/v1/driver/rentals/$bookingId/respond', {
          'accept': accept,
          'fleetDriverId': fleetDriverId,
          'reason': (reason == null || reason.trim().isEmpty)
              ? null
              : reason.trim(),
        }),
        RentalBooking.fromJson,
      );

  /// One condition photo. [phase] is `handover` or `return`; [side] is
  /// `front`, `back`, `left` or `right`. Returns the stored photo's url.
  Future<String> uploadConditionPhoto(
    String bookingId,
    String phase,
    String side,
    PlatformFile file,
  ) async {
    final Map<String, dynamic> response;
    try {
      response = await api.uploadFile(
        '/api/v1/driver/rentals/$bookingId/photos/$phase/$side',
        fieldName: 'file',
        file: file,
        fields: const {},
      );
    } on ApiException catch (error) {
      throw RentalRefused(error.code ?? '', error.message);
    }
    final payload = response['data'] ?? response;
    final url = payload is Map ? _text(payload['url']) : null;
    if (url == null) {
      throw const RentalRefused(
          'unexpected_response', 'The photo was not saved. Please try again.');
    }
    return url;
  }

  /// The car goes out. Needs all four handover photos on the server first.
  Future<RentalBooking> handOver(
    String bookingId, {
    required int odometerKm,
    required String fuel,
    required bool identityChecked,
    required bool licenceSeen,
    required bool depositReceived,
  }) async =>
      _one(
        () => api.postJson('/api/v1/driver/rentals/$bookingId/handover', {
          'odometerKm': odometerKm,
          'fuel': fuel,
          'identityChecked': identityChecked,
          'licenceSeen': licenceSeen,
          'depositReceived': depositReceived,
        }),
        RentalBooking.fromJson,
      );

  /// The car is back. Needs all four return photos on the server first.
  Future<RentalBooking> markReturned(
    String bookingId, {
    required int odometerKm,
    required String fuel,
  }) async =>
      _one(
        () => api.postJson('/api/v1/driver/rentals/$bookingId/return', {
          'odometerKm': odometerKm,
          'fuel': fuel,
        }),
        RentalBooking.fromJson,
      );

  /// The current terms text and its version.
  ///
  /// Read from the public settings route the app already uses, so there is no
  /// new plumbing and no token needed — the terms are meant to be readable
  /// before anybody signs in.
  Future<RentalTerms> terms() async {
    try {
      final response =
          await api.getJson('/api/v1/settings/public', authenticated: false);
      final payload = response['data'] ?? response;
      if (payload is! Map) return RentalTerms.fallback;

      final version = payload['rental.disclaimer_version'];
      final english = '${payload['rental.disclaimer_text_en'] ?? ''}'.trim();
      if (english.isEmpty) return RentalTerms.fallback;

      return RentalTerms(
        version: version is num ? version.toInt() : 1,
        textEn: english,
        textUr: '${payload['rental.disclaimer_text_ur'] ?? ''}'.trim(),
      );
    } catch (_) {
      return RentalTerms.fallback;
    }
  }

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

}

/// Top-level, not members of [RentalRepository].
///
/// These were `static` on the repository while every caller was in a different
/// class in this file — `RentalVehicle.fromJson`, `RentalQuote.fromJson`,
/// `RentalBooking.fromJson`. Dart will not resolve another class's private
/// static without qualifying it, so the file did not compile. As top-level
/// privates they are visible to the whole library, which is what the calls
/// already assumed.
double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

String? _text(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

DateTime? _timestamp(Object? value) {
  final text = _text(value);
  return text == null ? null : DateTime.tryParse(text)?.toLocal();
}
