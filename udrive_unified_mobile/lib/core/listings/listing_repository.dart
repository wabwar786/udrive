import 'package:file_picker/file_picker.dart';

import '../../models/auth_models.dart';
import '../network/api_client.dart';

/// "Earn with your vehicle": owners list cars for rent and tours, invite the
/// drivers who will drive customers, post daily tour departures and block
/// days on the rent calendar.
///
/// Every route lives under `/api/v1/listings` except the rental actions,
/// which sit beside the existing owner rental routes. A refusal from the
/// server arrives as [ListingRefused] carrying the server's own sentence.

class ListingRefused implements Exception {
  const ListingRefused(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

String? _text(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int _int(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? fallback;

DateTime? _date(Object? value) {
  final text = _text(value);
  return text == null ? null : DateTime.tryParse(text);
}

String _ymd(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Tour equipment, as the readiness score counts it.
class ListingKit {
  const ListingKit({
    this.fourByFour = false,
    this.firstAidKit = false,
    this.spareTyre = false,
    this.fireExtinguisher = false,
    this.snowChains = false,
    this.heating = false,
    this.airConditioning = false,
  });

  final bool fourByFour;
  final bool firstAidKit;
  final bool spareTyre;
  final bool fireExtinguisher;
  final bool snowChains;
  final bool heating;
  final bool airConditioning;

  /// Key → label, in the order the readiness score weighs them.
  static const labels = <String, String>{
    'fourByFour': '4x4',
    'firstAidKit': 'First-aid kit',
    'spareTyre': 'Spare tyre',
    'fireExtinguisher': 'Fire extinguisher',
    'snowChains': 'Snow chains',
    'heating': 'Heating',
    'airConditioning': 'AC',
  };

  bool operator [](String key) => toJson()[key] == true;

  ListingKit toggled(String key) {
    final map = toJson()..[key] = !(this[key]);
    return ListingKit.fromJson(map);
  }

  Map<String, dynamic> toJson() => {
        'fourByFour': fourByFour,
        'firstAidKit': firstAidKit,
        'spareTyre': spareTyre,
        'fireExtinguisher': fireExtinguisher,
        'snowChains': snowChains,
        'heating': heating,
        'airConditioning': airConditioning,
      };

  factory ListingKit.fromJson(Map<String, dynamic>? json) => ListingKit(
        fourByFour: json?['fourByFour'] == true,
        firstAidKit: json?['firstAidKit'] == true,
        spareTyre: json?['spareTyre'] == true,
        fireExtinguisher: json?['fireExtinguisher'] == true,
        snowChains: json?['snowChains'] == true,
        heating: json?['heating'] == true,
        airConditioning: json?['airConditioning'] == true,
      );
}

class ListingOwner {
  const ListingOwner({
    required this.hasProfile,
    required this.drivesSelf,
    required this.cnicFront,
    required this.cnicBack,
    required this.selfie,
    required this.licenceFront,
    required this.licenceBack,
    required this.licenceNumber,
    required this.licenceExpiry,
    required this.agreementAccepted,
    required this.agreementVersion,
  });

  final bool hasProfile;
  final bool drivesSelf;
  final bool cnicFront;
  final bool cnicBack;
  final bool selfie;
  final bool licenceFront;
  final bool licenceBack;
  final String? licenceNumber;
  final DateTime? licenceExpiry;
  final bool agreementAccepted;
  final int agreementVersion;

  /// CNIC both sides and a selfie — asked once, for every vehicle after.
  bool get identityDone => cnicFront && cnicBack && selfie;

  factory ListingOwner.fromJson(Map<String, dynamic> json) => ListingOwner(
        hasProfile: json['hasProfile'] == true,
        drivesSelf: json['drivesSelf'] == true,
        cnicFront: json['cnicFront'] == true,
        cnicBack: json['cnicBack'] == true,
        selfie: json['selfie'] == true,
        licenceFront: json['licenceFront'] == true,
        licenceBack: json['licenceBack'] == true,
        licenceNumber: _text(json['licenceNumber']),
        licenceExpiry: _date(json['licenceExpiry']),
        agreementAccepted: json['agreementAccepted'] == true,
        agreementVersion: _int(json['agreementVersion'], 1),
      );
}

/// Where one use (rent or tour) of a vehicle stands with UDrive.
class PurposeReview {
  const PurposeReview({this.status = 'None', this.note});

  /// "None", "Pending", "Approved", "Rejected" or "Info".
  final String status;
  final String? note;

  factory PurposeReview.fromJson(Object? json) {
    if (json is! Map) return const PurposeReview();
    final status = _text(json['status']);
    return PurposeReview(status: status ?? 'None', note: _text(json['note']));
  }
}

class ListingVehicle {
  const ListingVehicle({
    required this.id,
    required this.name,
    required this.make,
    required this.model,
    required this.year,
    required this.category,
    required this.isFourByFour,
    required this.registrationNumber,
    required this.seats,
    required this.photoUrl,
    required this.status,
    required this.reviewNote,
    required this.wantsRent,
    required this.wantsTour,
    required this.availableForRent,
    required this.availableForTour,
    required this.withDriverDaily,
    required this.selfDriveDaily,
    required this.pickupPoint,
    required this.readinessScore,
    required this.readinessRequired,
    required this.kit,
    required this.docFront,
    required this.docRegistrationFront,
    required this.docRegistrationBack,
    required this.pendingRentals,
    this.tehsilId,
    this.tehsilName,
    this.districtName,
    this.rentReview = const PurposeReview(),
    this.tourReview = const PurposeReview(),
  });

  final String id;
  final String name;
  final String make;
  final String model;
  final int year;

  /// "Car", "Hiace" or "Coster". A jeep is a Car with [isFourByFour].
  final String category;
  final bool isFourByFour;
  final String registrationNumber;
  final int seats;
  final String? photoUrl;

  /// "Draft", "PendingReview", "Verified" or "Rejected".
  final String status;
  final String? reviewNote;
  final bool wantsRent;
  final bool wantsTour;
  final bool availableForRent;
  final bool availableForTour;
  final double? withDriverDaily;
  final double? selfDriveDaily;
  final String? pickupPoint;
  final int readinessScore;
  final int readinessRequired;
  final ListingKit kit;
  final bool docFront;
  final bool docRegistrationFront;
  final bool docRegistrationBack;
  final int pendingRentals;
  final String? tehsilId;
  final String? tehsilName;
  final String? districtName;
  final PurposeReview rentReview;
  final PurposeReview tourReview;

  bool get hasLocation => tehsilId != null;

  /// "District · Tehsil", or null when no area is set.
  String? get locationLabel {
    if (tehsilId == null) return null;
    final parts = [districtName, tehsilName]
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  bool get isLive => status == 'Verified';
  bool get inReview => status == 'PendingReview';
  bool get photosDone => docFront && docRegistrationFront && docRegistrationBack;

  /// The category the wizard shows: "Jeep" for a four-by-four car.
  String get pickerCategory =>
      category == 'Car' && isFourByFour ? 'Jeep' : category;

  factory ListingVehicle.fromJson(Map<String, dynamic> json) {
    final docs = json['docs'] is Map
        ? Map<String, dynamic>.from(json['docs'] as Map)
        : const <String, dynamic>{};
    return ListingVehicle(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}'.trim(),
      make: '${json['make'] ?? ''}',
      model: '${json['model'] ?? ''}',
      year: _int(json['year']),
      category: '${json['category'] ?? 'Car'}',
      isFourByFour: json['isFourByFour'] == true,
      registrationNumber: '${json['registrationNumber'] ?? ''}',
      seats: _int(json['seats'], 4),
      photoUrl: _text(json['photoUrl']),
      status: '${json['status'] ?? 'Draft'}',
      reviewNote: _text(json['reviewNote']),
      wantsRent: json['wantsRent'] == true,
      wantsTour: json['wantsTour'] == true,
      availableForRent: json['availableForRent'] == true,
      availableForTour: json['availableForTour'] == true,
      withDriverDaily: _number(json['withDriverDaily']),
      selfDriveDaily: _number(json['selfDriveDaily']),
      pickupPoint: _text(json['pickupPoint']),
      readinessScore: _int(json['readinessScore']),
      readinessRequired: _int(json['readinessRequired'], 60),
      kit: ListingKit.fromJson(json['kit'] is Map
          ? Map<String, dynamic>.from(json['kit'] as Map)
          : null),
      docFront: docs['front'] == true,
      docRegistrationFront: docs['registrationFront'] == true,
      docRegistrationBack: docs['registrationBack'] == true,
      pendingRentals: _int(json['pendingRentals']),
      tehsilId: _text(json['tehsilId']),
      tehsilName: _text(json['tehsilName']),
      districtName: _text(json['districtName']),
      rentReview: PurposeReview.fromJson(json['rentReview']),
      tourReview: PurposeReview.fromJson(json['tourReview']),
    );
  }
}

class FleetDriver {
  const FleetDriver({
    required this.id,
    required this.name,
    required this.phone,
    required this.isOwner,
    required this.status,
    required this.licenceExpiry,
    required this.licenceValid,
    required this.expiresInDays,
    required this.reviewNote,
  });

  final String id;
  final String name;
  final String phone;
  final bool isOwner;

  /// "Invited", "Submitted", "Approved" or "Rejected".
  final String status;
  final DateTime? licenceExpiry;

  /// Approved and the licence has not expired: can be given a booking.
  final bool licenceValid;
  final int? expiresInDays;
  final String? reviewNote;

  factory FleetDriver.fromJson(Map<String, dynamic> json) => FleetDriver(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        phone: '${json['phone'] ?? ''}',
        isOwner: json['isOwner'] == true,
        status: '${json['status'] ?? 'Invited'}',
        licenceExpiry: _date(json['licenceExpiry']),
        licenceValid: json['licenceValid'] == true,
        expiresInDays: (json['expiresInDays'] as num?)?.toInt(),
        reviewNote: _text(json['reviewNote']),
      );
}

class ListingHome {
  const ListingHome({
    required this.owner,
    required this.vehicles,
    required this.drivers,
    required this.invites,
  });

  final ListingOwner owner;
  final List<ListingVehicle> vehicles;
  final List<FleetDriver> drivers;

  /// Open driver invites addressed to this account's own phone.
  final int invites;

  factory ListingHome.fromJson(Map<String, dynamic> json) => ListingHome(
        owner: ListingOwner.fromJson(json['owner'] is Map
            ? Map<String, dynamic>.from(json['owner'] as Map)
            : const {}),
        vehicles: ((json['vehicles'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ListingVehicle.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
        drivers: ((json['drivers'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => FleetDriver.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
        invites: _int(json['invites']),
      );
}

/// A driver invite, as the invited person sees it on their own phone.
class DriverInvite {
  const DriverInvite({
    required this.id,
    required this.ownerName,
    required this.vehicles,
    required this.status,
    required this.cnicFront,
    required this.cnicBack,
    required this.selfie,
    required this.licenceFront,
    required this.licenceBack,
    required this.licenceNumber,
    required this.licenceExpiry,
    required this.agreementVersion,
    required this.reviewNote,
  });

  final String id;
  final String ownerName;
  final String vehicles;
  final String status;
  final bool cnicFront;
  final bool cnicBack;
  final bool selfie;
  final bool licenceFront;
  final bool licenceBack;
  final String? licenceNumber;
  final DateTime? licenceExpiry;
  final int agreementVersion;
  final String? reviewNote;

  bool get photosDone =>
      cnicFront && cnicBack && selfie && licenceFront && licenceBack;

  factory DriverInvite.fromJson(Map<String, dynamic> json) => DriverInvite(
        id: '${json['id'] ?? ''}',
        ownerName: '${json['ownerName'] ?? 'Owner'}',
        vehicles: '${json['vehicles'] ?? ''}',
        status: '${json['status'] ?? 'Invited'}',
        cnicFront: json['cnicFront'] == true,
        cnicBack: json['cnicBack'] == true,
        selfie: json['selfie'] == true,
        licenceFront: json['licenceFront'] == true,
        licenceBack: json['licenceBack'] == true,
        licenceNumber: _text(json['licenceNumber']),
        licenceExpiry: _date(json['licenceExpiry']),
        agreementVersion: _int(json['agreementVersion'], 1),
        reviewNote: _text(json['reviewNote']),
      );
}

/// One day on the owner's rent calendar.
class RentCalendarDay {
  const RentCalendarDay({required this.date, required this.state});

  final DateTime date;

  /// "free", "pending", "booked", "blocked", "tour" or "past".
  final String state;

  factory RentCalendarDay.fromJson(Map<String, dynamic> json) =>
      RentCalendarDay(
        date: DateTime.parse('${json['date']}'),
        state: '${json['state'] ?? 'free'}',
      );
}

/// One day's tour departure for one vehicle.
class DepartureDay {
  const DepartureDay({
    required this.date,
    required this.packageId,
    required this.from,
    required this.destinationId,
    required this.destination,
    required this.time,
    required this.durationDays,
    required this.seatsSold,
    required this.totalSeats,
    required this.pricePerSeat,
    required this.wholeVehiclePrice,
    required this.pickupPoint,
    required this.fleetDriverId,
    required this.driverName,
  });

  /// Null on a template.
  final DateTime? date;
  final String? packageId;
  final String from;
  final String destinationId;
  final String destination;

  /// "HH:mm", Pakistan time.
  final String time;
  final int durationDays;
  final int seatsSold;
  final int totalSeats;
  final double pricePerSeat;
  final double wholeVehiclePrice;
  final String pickupPoint;
  final String? fleetDriverId;
  final String? driverName;

  factory DepartureDay.fromJson(Map<String, dynamic> json) => DepartureDay(
        date: _date(json['date']),
        packageId: _text(json['packageId']),
        from: '${json['from'] ?? ''}',
        destinationId: '${json['destinationId'] ?? ''}',
        destination: '${json['destination'] ?? ''}',
        time: '${json['time'] ?? '06:00'}',
        durationDays: _int(json['durationDays'], 1),
        seatsSold: _int(json['seatsSold']),
        totalSeats: _int(json['totalSeats']),
        pricePerSeat: _number(json['pricePerSeat']) ?? 0,
        wholeVehiclePrice: _number(json['wholeVehiclePrice']) ?? 0,
        pickupPoint: '${json['pickupPoint'] ?? ''}',
        fleetDriverId: _text(json['fleetDriverId']),
        driverName: _text(json['driverName']),
      );
}

class DepartureMonth {
  const DepartureMonth({
    required this.days,
    required this.template,
    required this.totalSeats,
    required this.perSeatAllowed,
  });

  final List<DepartureDay> days;
  final DepartureDay? template;
  final int totalSeats;

  /// False for vehicles of five seats or fewer: sold whole only.
  final bool perSeatAllowed;

  factory DepartureMonth.fromJson(Map<String, dynamic> json) => DepartureMonth(
        days: ((json['days'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => DepartureDay.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
        template: json['template'] is Map
            ? DepartureDay.fromJson(
                Map<String, dynamic>.from(json['template'] as Map))
            : null,
        totalSeats: _int(json['totalSeats']),
        perSeatAllowed: json['perSeatAllowed'] == true,
      );
}

class ListingRepository {
  ListingRepository(this.api);

  final ApiClient api;

  dynamic _data(Map<String, dynamic> response) => response['data'] ?? response;

  Map<String, dynamic> _map(Map<String, dynamic> response) {
    final data = _data(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ListingRefused(
        'unexpected_response', 'The server sent something unexpected.');
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> response) {
    final data = _data(response);
    return (data is List ? data : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiException catch (error) {
      throw ListingRefused(error.code ?? '', error.message);
    }
  }

  // ─────────────────────────────────────────────────────────── owner

  Future<ListingHome> home() => _guard(() async =>
      ListingHome.fromJson(_map(await api.getJson('/api/v1/listings/me'))));

  Future<ListingVehicle> saveVehicle({
    String? vehicleId,
    required String category,
    required String make,
    required String model,
    required int year,
    required String registrationNumber,
    required int seats,
    required bool wantsRent,
    required bool wantsTour,
    required String drivers,
    double? withDriverDaily,
    double? selfDriveDaily,
    String? pickupPoint,
    required ListingKit kit,
    String? tehsilId,
  }) =>
      _guard(() async {
        final body = <String, dynamic>{
          'category': category,
          'make': make.trim(),
          'model': model.trim(),
          'year': year,
          'registrationNumber': registrationNumber.trim(),
          'seats': seats,
          'wantsRent': wantsRent,
          'wantsTour': wantsTour,
          'drivers': drivers,
          'withDriverDaily': withDriverDaily,
          'selfDriveDaily': selfDriveDaily,
          'pickupPoint': pickupPoint?.trim(),
          'kit': kit.toJson(),
          'tehsilId': tehsilId,
        };
        final response = vehicleId == null
            ? await api.postJson('/api/v1/listings/vehicles', body)
            : await api.putJson('/api/v1/listings/vehicles/$vehicleId', body);
        return ListingVehicle.fromJson(_map(response));
      });

  /// Moves a vehicle to another tehsil; allowed live or not.
  Future<ListingVehicle> setLocation(String vehicleId, String tehsilId) =>
      _guard(() async => ListingVehicle.fromJson(_map(await api.putJson(
            '/api/v1/listings/vehicles/$vehicleId/location',
            {'tehsilId': tehsilId},
          ))));

  /// purpose: `rent` or `tour`. Sends that use for review again, or adds it
  /// to a vehicle that is already live.
  Future<ListingVehicle> submitPurpose(String vehicleId, String purpose) =>
      _guard(() async => ListingVehicle.fromJson(_map(await api.postJson(
            '/api/v1/listings/vehicles/$vehicleId/purposes/$purpose/submit',
            const {},
          ))));

  /// kind: `front`, `registration-front` or `registration-back`.
  Future<ListingVehicle> uploadVehiclePhoto(
          String vehicleId, String kind, PlatformFile file) =>
      _guard(() async => ListingVehicle.fromJson(_map(await api.uploadFile(
            '/api/v1/listings/vehicles/$vehicleId/photos/$kind',
            fieldName: 'file',
            file: file,
            fields: const {},
          ))));

  /// kind: `cnic-front`, `cnic-back`, `selfie`, `licence-front`, `licence-back`.
  Future<ListingOwner> uploadOwnerDocument(String kind, PlatformFile file) =>
      _guard(() async => ListingOwner.fromJson(_map(await api.uploadFile(
            '/api/v1/listings/owner/documents/$kind',
            fieldName: 'file',
            file: file,
            fields: const {},
          ))));

  Future<ListingVehicle> submit(
    String vehicleId, {
    String? licenceNumber,
    DateTime? licenceExpiry,
    required bool acceptAgreement,
    required int agreementVersion,
  }) =>
      _guard(() async => ListingVehicle.fromJson(_map(await api.postJson(
            '/api/v1/listings/vehicles/$vehicleId/submit',
            {
              'licenceNumber': licenceNumber?.trim(),
              'licenceExpiry':
                  licenceExpiry == null ? null : _ymd(licenceExpiry),
              'acceptAgreement': acceptAgreement,
              'agreementVersion': agreementVersion,
            },
          ))));

  // ─────────────────────────────────────────────────────────── drivers

  Future<FleetDriver> inviteDriver({
    required String name,
    required String phone,
  }) =>
      _guard(() async => FleetDriver.fromJson(_map(await api.postJson(
            '/api/v1/listings/drivers',
            {'name': name.trim(), 'phone': phone.trim()},
          ))));

  Future<void> removeDriver(String id) => _guard(() async {
        await api.postJson('/api/v1/listings/drivers/$id/remove', const {});
      });

  // ─────────────────────────────────────────────────────────── invites

  Future<List<DriverInvite>> invites() => _guard(() async =>
      _list(await api.getJson('/api/v1/listings/invites'))
          .map(DriverInvite.fromJson)
          .toList(growable: false));

  Future<DriverInvite> uploadInviteDocument(
          String inviteId, String kind, PlatformFile file) =>
      _guard(() async => DriverInvite.fromJson(_map(await api.uploadFile(
            '/api/v1/listings/invites/$inviteId/documents/$kind',
            fieldName: 'file',
            file: file,
            fields: const {},
          ))));

  Future<DriverInvite> submitInvite(
    String inviteId, {
    required String licenceNumber,
    required DateTime licenceExpiry,
    required bool acceptAgreement,
    required int agreementVersion,
  }) =>
      _guard(() async => DriverInvite.fromJson(_map(await api.postJson(
            '/api/v1/listings/invites/$inviteId/submit',
            {
              'licenceNumber': licenceNumber.trim(),
              'licenceExpiry': _ymd(licenceExpiry),
              'acceptAgreement': acceptAgreement,
              'agreementVersion': agreementVersion,
            },
          ))));

  Future<void> declineInvite(String inviteId) => _guard(() async {
        await api.postJson(
            '/api/v1/listings/invites/$inviteId/decline', const {});
      });

  // ─────────────────────────────────────────────────────────── rent calendar

  Future<List<RentCalendarDay>> calendar(String vehicleId, DateTime from,
          {int days = 42}) =>
      _guard(() async => _list(await api.getJson(
                  '/api/v1/listings/vehicles/$vehicleId/calendar'
                  '?from=${_ymd(from)}&days=$days'))
              .map(RentCalendarDay.fromJson)
              .toList(growable: false));

  Future<List<RentCalendarDay>> setBlockedDays(
    String vehicleId, {
    required List<DateTime> block,
    required List<DateTime> unblock,
  }) =>
      _guard(() async => _list(await api.putJson(
                  '/api/v1/listings/vehicles/$vehicleId/blocked-days', {
                'block': block.map(_ymd).toList(),
                'unblock': unblock.map(_ymd).toList(),
              }))
              .map(RentCalendarDay.fromJson)
              .toList(growable: false));

  // ─────────────────────────────────────────────────────────── departures

  Future<DepartureMonth> departures(String vehicleId, DateTime month) =>
      _guard(() async => DepartureMonth.fromJson(_map(await api.getJson(
          '/api/v1/listings/vehicles/$vehicleId/departures'
          '?month=${month.year.toString().padLeft(4, '0')}-'
          '${month.month.toString().padLeft(2, '0')}'))));

  Future<DepartureDay> saveDeparture(
    String vehicleId,
    DateTime date, {
    required String from,
    required String destinationId,
    required String time,
    required int durationDays,
    required double pricePerSeat,
    required double wholeVehiclePrice,
    required String pickupPoint,
    String? fleetDriverId,
  }) =>
      _guard(() async => DepartureDay.fromJson(_map(await api.putJson(
            '/api/v1/listings/vehicles/$vehicleId/departures/${_ymd(date)}',
            {
              'from': from.trim(),
              'destinationId': destinationId,
              'time': time,
              'durationDays': durationDays,
              'pricePerSeat': pricePerSeat,
              'wholeVehiclePrice': wholeVehiclePrice,
              'pickupPoint': pickupPoint.trim(),
              'fleetDriverId': fleetDriverId,
            },
          ))));

  Future<void> cancelDeparture(String vehicleId, DateTime date) =>
      _guard(() async {
        await api.postJson(
          '/api/v1/listings/vehicles/$vehicleId/departures/${_ymd(date)}/cancel',
          const {},
        );
      });
}
