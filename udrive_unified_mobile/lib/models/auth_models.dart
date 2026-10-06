import 'dart:convert';

class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.phoneNumber,
    required this.fullName,
    required this.preferredLanguage,
    required this.accountStatus,
    required this.roles,
    required this.driverModeAvailable,
    this.email,
    this.driverProfileId,
    this.driverVerificationStatus,
  });

  final String id;
  final String phoneNumber;
  final String fullName;
  final String? email;
  final String preferredLanguage;
  final String accountStatus;
  final List<String> roles;
  final String? driverProfileId;
  final String? driverVerificationStatus;
  final bool driverModeAvailable;

  factory CurrentUser.fromJson(Map<String, dynamic> json) => CurrentUser(
        id: json['id']?.toString() ?? '',
        phoneNumber: json['phoneNumber']?.toString() ?? '',
        fullName: json['fullName']?.toString() ?? 'Udrive User',
        email: json['email']?.toString(),
        preferredLanguage: json['preferredLanguage']?.toString() ?? 'en',
        accountStatus: json['accountStatus']?.toString() ?? 'Approved',
        roles: (json['roles'] as List? ?? const []).map((e) => e.toString()).toList(),
        driverProfileId: json['driverProfileId']?.toString(),
        driverVerificationStatus: json['driverVerificationStatus']?.toString(),
        driverModeAvailable: json['driverModeAvailable'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'phoneNumber': phoneNumber,
        'fullName': fullName,
        'email': email,
        'preferredLanguage': preferredLanguage,
        'accountStatus': accountStatus,
        'roles': roles,
        'driverProfileId': driverProfileId,
        'driverVerificationStatus': driverVerificationStatus,
        'driverModeAvailable': driverModeAvailable,
      };

  String encode() => jsonEncode(toJson());
  static CurrentUser? decode(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return CurrentUser.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.refreshToken,
    required this.refreshTokenExpiresAt,
    required this.user,
  });

  final String accessToken;
  final DateTime accessTokenExpiresAt;
  final String refreshToken;
  final DateTime refreshTokenExpiresAt;
  final CurrentUser user;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: json['accessToken']?.toString() ?? '',
        accessTokenExpiresAt: DateTime.parse(json['accessTokenExpiresAt'].toString()),
        refreshToken: json['refreshToken']?.toString() ?? '',
        refreshTokenExpiresAt: DateTime.parse(json['refreshTokenExpiresAt'].toString()),
        user: CurrentUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}

class OtpChallenge {
  const OtpChallenge({
    required this.challengeId,
    required this.expiresAt,
    required this.retryAfterSeconds,
    required this.deliveryChannel,
    this.developmentCode,
  });

  final String challengeId;
  final DateTime expiresAt;
  final int retryAfterSeconds;
  final String deliveryChannel;
  final String? developmentCode;

  factory OtpChallenge.fromJson(Map<String, dynamic> json) => OtpChallenge(
        challengeId: json['challengeId']?.toString() ?? '',
        expiresAt: DateTime.parse(json['expiresAt'].toString()),
        retryAfterSeconds: (json['retryAfterSeconds'] as num?)?.toInt() ?? 45,
        deliveryChannel: json['deliveryChannel']?.toString() ?? 'development',
        developmentCode: json['developmentCode']?.toString(),
      );
}

class DriverProfileLive {
  const DriverProfileLive({
    required this.driverProfileId,
    required this.verificationStatus,
    required this.languages,
    required this.serviceAreas,
    this.cnicMasked,
    this.drivingLicenceMasked,
    this.reviewNotes,
    this.tehsilId,
    this.tehsilName,
    this.districtId,
    this.districtName,
    this.hasListedVehicles = false,
  });

  final String driverProfileId;
  final String verificationStatus;
  final String? cnicMasked;
  final String? drivingLicenceMasked;
  final List<String> languages;
  final List<String> serviceAreas;
  final String? reviewNotes;
  final String? tehsilId;
  final String? tehsilName;
  final String? districtId;
  final String? districtName;

  /// Has vehicles listed the old way ("Earn with your vehicle"). Driver mode
  /// shows these owners a "Listed vehicles" entry for them.
  final bool hasListedVehicles;

  static String? _optional(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  factory DriverProfileLive.fromJson(Map<String, dynamic> json) => DriverProfileLive(
        driverProfileId: json['driverProfileId']?.toString() ?? '',
        verificationStatus: json['verificationStatus']?.toString() ?? 'Draft',
        cnicMasked: json['cnicMasked']?.toString(),
        drivingLicenceMasked: json['drivingLicenceMasked']?.toString(),
        languages: (json['languages'] as List? ?? const []).map((e) => e.toString()).toList(),
        serviceAreas: (json['serviceAreas'] as List? ?? const []).map((e) => e.toString()).toList(),
        reviewNotes: json['reviewNotes']?.toString(),
        tehsilId: _optional(json['tehsilId']),
        tehsilName: _optional(json['tehsilName']),
        districtId: _optional(json['districtId']),
        districtName: _optional(json['districtName']),
        hasListedVehicles: json['hasListedVehicles'] == true,
      );
}

class LiveVehicle {
  const LiveVehicle({
    required this.id,
    required this.category,
    required this.make,
    required this.model,
    required this.year,
    required this.registrationNumber,
    required this.colour,
    required this.passengerCapacity,
    required this.luggageCapacity,
    required this.mountainReadinessScore,
    required this.status,
    this.imageUrl,
    required this.documents,
    this.tourReadinessRequired = 60,
    this.availableForTour = false,
    this.tourReadinessItems = const [],
    this.tourReadinessMissing = const [],
  });

  final String id;
  final String category;
  final String make;
  final String model;
  final int year;
  final String registrationNumber;
  final String colour;
  final int passengerCapacity;
  final int luggageCapacity;
  final int mountainReadinessScore;
  final String status;
  final String? imageUrl;
  final List<Map<String, dynamic>> documents;

  /// The score this vehicle must reach before it can carry a tour package.
  ///
  /// From the server, because it is an Admin setting. A copy in the app would
  /// be wrong the day it changed, and the Driver would be told they qualify by
  /// one screen and refused by the next.
  final int tourReadinessRequired;

  /// The Driver's own switch. The second tour gate, and the one that used to
  /// be invisible — a vehicle scoring 82 could still be refused on this alone
  /// with nothing on screen saying the switch existed.
  final bool availableForTour;

  /// Everything that counts towards the score, with what this vehicle has.
  final List<TourReadinessItem> tourReadinessItems;

  /// The cheapest missing items that would reach the bar. Empty when it does.
  final List<TourReadinessItem> tourReadinessMissing;

  bool get meetsTourReadiness =>
      mountainReadinessScore >= tourReadinessRequired;

  /// Both gates. Either one alone is not enough to publish a package.
  bool get canCarryTour => meetsTourReadiness && availableForTour;

  factory LiveVehicle.fromJson(Map<String, dynamic> json) => LiveVehicle(
        id: json['id']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        make: json['make']?.toString() ?? '',
        model: json['model']?.toString() ?? '',
        year: (json['year'] as num?)?.toInt() ?? 0,
        registrationNumber: json['registrationNumber']?.toString() ?? '',
        colour: json['colour']?.toString() ?? '',
        passengerCapacity: (json['passengerCapacity'] as num?)?.toInt() ?? 0,
        luggageCapacity: (json['luggageCapacity'] as num?)?.toInt() ?? 0,
        mountainReadinessScore: (json['mountainReadinessScore'] as num?)?.toInt() ?? 0,
        status: json['status']?.toString() ?? 'Draft',
        imageUrl: json['imageUrl']?.toString(),
        documents: (json['documents'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        tourReadinessRequired:
            (json['tourReadinessRequired'] as num?)?.toInt() ?? 60,
        availableForTour: json['availableForTour'] == true,
        tourReadinessItems: TourReadinessItem.listFrom(json['tourReadinessItems']),
        tourReadinessMissing:
            TourReadinessItem.listFrom(json['tourReadinessMissing']),
      );
}

/// One piece of equipment that counts towards a vehicle's tour readiness.
///
/// The points come from the server rather than being written here. The weights
/// are a judgement about mountain roads that an Admin may revise, and an app
/// carrying its own copy would start disagreeing with the server the first time
/// it did.
class TourReadinessItem {
  const TourReadinessItem({
    required this.key,
    required this.label,
    required this.points,
    required this.present,
  });

  final String key;
  final String label;
  final int points;
  final bool present;

  factory TourReadinessItem.fromJson(Map<String, dynamic> json) =>
      TourReadinessItem(
        key: json['key']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        points: (json['points'] as num?)?.toInt() ?? 0,
        present: json['present'] == true,
      );

  static List<TourReadinessItem> listFrom(Object? value) => value is List
      ? value
          .whereType<Map>()
          .map((e) => TourReadinessItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false)
      : const [];
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;
  @override
  String toString() => message;
}
