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
        fullName: json['fullName']?.toString() ?? 'uDrive User',
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
  });

  final String driverProfileId;
  final String verificationStatus;
  final String? cnicMasked;
  final String? drivingLicenceMasked;
  final List<String> languages;
  final List<String> serviceAreas;
  final String? reviewNotes;

  factory DriverProfileLive.fromJson(Map<String, dynamic> json) => DriverProfileLive(
        driverProfileId: json['driverProfileId']?.toString() ?? '',
        verificationStatus: json['verificationStatus']?.toString() ?? 'Draft',
        cnicMasked: json['cnicMasked']?.toString(),
        drivingLicenceMasked: json['drivingLicenceMasked']?.toString(),
        languages: (json['languages'] as List? ?? const []).map((e) => e.toString()).toList(),
        serviceAreas: (json['serviceAreas'] as List? ?? const []).map((e) => e.toString()).toList(),
        reviewNotes: json['reviewNotes']?.toString(),
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
    required this.documents,
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
  final List<Map<String, dynamic>> documents;

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
        documents: (json['documents'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;
  @override
  String toString() => message;
}
