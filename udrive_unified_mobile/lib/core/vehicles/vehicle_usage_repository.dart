import 'package:file_picker/file_picker.dart';

import '../../models/auth_models.dart';
import '../network/api_client.dart';

/// One missing piece of tour equipment, and what it is worth.
class UsageReadinessItem {
  const UsageReadinessItem({
    required this.key,
    required this.label,
    required this.points,
  });

  final String key;
  final String label;
  final int points;

  factory UsageReadinessItem.fromJson(Map<String, dynamic> json) =>
      UsageReadinessItem(
        key: '${json['key'] ?? ''}',
        label: '${json['label'] ?? ''}',
        points: (json['points'] as num?)?.toInt() ?? 0,
      );
}

/// What one approved vehicle is used for, and what each usage still needs.
///
/// Every rule a switch depends on arrives with the vehicle. The screen never
/// works a rule out for itself: a copy of "sixty" in the app would be wrong the
/// day an Admin changed it, and the Driver would be told they qualify by one
/// screen and refused by the next.
class VehicleUsage {
  const VehicleUsage({
    required this.vehicleId,
    required this.name,
    required this.registrationNumber,
    required this.status,
    required this.availableForCity,
    required this.availableForTour,
    required this.availableForRent,
    required this.tourReadinessScore,
    required this.tourReadinessRequired,
    required this.tourReadinessMissing,
    required this.livePackageCount,
    required this.rentWithDriverDaily,
    required this.rentSelfDriveDaily,
    required this.rentSecurityDeposit,
    required this.rentMinimumDays,
    required this.rentKmPerDay,
    required this.rentFuelIncluded,
    required this.rentPickupPoint,
    required this.photoUrl,
  });

  final String vehicleId;
  final String name;
  final String registrationNumber;
  final String status;

  final bool availableForCity;
  final bool availableForTour;
  final bool availableForRent;

  final int tourReadinessScore;
  final int tourReadinessRequired;
  final List<UsageReadinessItem> tourReadinessMissing;
  final int livePackageCount;

  final double? rentWithDriverDaily;
  final double? rentSelfDriveDaily;
  final double? rentSecurityDeposit;
  final int rentMinimumDays;
  final int? rentKmPerDay;
  final bool rentFuelIncluded;
  final String? rentPickupPoint;

  /// The owner's own photograph. Renting needs one.
  final String? photoUrl;

  /// An Admin has verified it, so the usages can be chosen.
  bool get isVerified =>
      status.toLowerCase() == 'verified' || status.toLowerCase() == 'approved';

  bool get meetsReadiness => tourReadinessScore >= tourReadinessRequired;

  /// Tour needs both gates: the score, and somewhere to go.
  bool get canCarryTour => meetsReadiness && livePackageCount > 0;

  bool get hasRentRate =>
      (rentWithDriverDaily ?? 0) > 0 || (rentSelfDriveDaily ?? 0) > 0;

  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;

  /// Both gates for renting: a rate, and a picture of the actual car.
  bool get canBeRented => hasRentRate && hasPhoto;

  factory VehicleUsage.fromJson(Map<String, dynamic> json) => VehicleUsage(
        vehicleId: '${json['vehicleId'] ?? ''}',
        name: '${json['name'] ?? ''}'.trim(),
        registrationNumber: '${json['registrationNumber'] ?? ''}',
        status: '${json['status'] ?? ''}',
        availableForCity: json['availableForCity'] == true,
        availableForTour: json['availableForTour'] == true,
        availableForRent: json['availableForRent'] == true,
        tourReadinessScore: (json['tourReadinessScore'] as num?)?.toInt() ?? 0,
        tourReadinessRequired:
            (json['tourReadinessRequired'] as num?)?.toInt() ?? 60,
        tourReadinessMissing: _items(json['tourReadinessMissing']),
        livePackageCount: (json['livePackageCount'] as num?)?.toInt() ?? 0,
        rentWithDriverDaily: _toDouble(json['rentWithDriverDaily']),
        rentSelfDriveDaily: _toDouble(json['rentSelfDriveDaily']),
        rentSecurityDeposit: _toDouble(json['rentSecurityDeposit']),
        rentMinimumDays: (json['rentMinimumDays'] as num?)?.toInt() ?? 1,
        rentKmPerDay: (json['rentKmPerDay'] as num?)?.toInt(),
        rentFuelIncluded: json['rentFuelIncluded'] == true,
        rentPickupPoint: _trimmedOrNull(json['rentPickupPoint']),
        photoUrl: _trimmedOrNull(json['photoUrl']),
      );

  static List<UsageReadinessItem> _items(Object? value) {
    if (value is! List) return const [];
    final list = <UsageReadinessItem>[];
    for (final item in value) {
      if (item is Map) {
        list.add(UsageReadinessItem.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return list;
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String? _trimmedOrNull(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }
}

/// Raised when the server refuses a switch, carrying the reason it gave.
///
/// The app shows every rule up front, so a refusal here should be rare — but
/// two screens open at once, or a package that expired a minute ago, can still
/// produce one, and the Driver is told what the server actually said rather
/// than "something went wrong".
class VehicleUsageRefused implements Exception {
  const VehicleUsageRefused(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Reads and writes what each vehicle is used for.
class VehicleUsageRepository {
  VehicleUsageRepository(this.api);

  final ApiClient api;

  Future<List<VehicleUsage>> list() async {
    final response = await api.getJson('/api/v1/driver/vehicles/usage');
    final payload = response['data'] ?? response;
    if (payload is! List) return const [];
    final list = <VehicleUsage>[];
    for (final item in payload) {
      if (item is Map) {
        list.add(VehicleUsage.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return list;
  }

  /// Moves one switch. The others are left out so two open screens cannot
  /// undo each other's change.
  Future<VehicleUsage> setUsage(
    String vehicleId, {
    bool? city,
    bool? tour,
    bool? rent,
  }) =>
      _write('/api/v1/driver/vehicles/$vehicleId/usage', {
        if (city != null) 'availableForCity': city,
        if (tour != null) 'availableForTour': tour,
        if (rent != null) 'availableForRent': rent,
      });

  /// Sends the owner's own photograph of this vehicle.
  ///
  /// One picture, replacing whatever was there, public the moment it lands.
  /// Required before the vehicle can be put out on rent — a rental listing of
  /// names and prices is a listing nobody books from.
  Future<VehicleUsage> uploadPhoto(String vehicleId, PlatformFile file) async {
    final Map<String, dynamic> response;
    try {
      response = await api.uploadFile(
        '/api/v1/driver/vehicles/$vehicleId/photo',
        fieldName: 'file',
        file: file,
        fields: const {},
      );
    } on ApiException catch (error) {
      throw VehicleUsageRefused(error.code ?? '', error.message);
    }

    final payload = response['data'] ?? response;
    if (payload is Map) {
      return VehicleUsage.fromJson(Map<String, dynamic>.from(payload));
    }
    throw const VehicleUsageRefused(
        'unexpected_response', 'The server did not return the vehicle.');
  }

  /// Records what the vehicle carries, and rescores its tour readiness.
  ///
  /// The whole set goes every time, because the score is computed from all
  /// eight together. This is the only part of a verified vehicle a Driver may
  /// change: the vehicle edit refuses once an Admin has verified it, which left
  /// a Driver told "readiness 45, you need 60" with no way to record that they
  /// had bought the missing kit.
  Future<VehicleUsage> setEquipment(
    String vehicleId, {
    required bool fourByFour,
    required bool firstAidKit,
    required bool spareTyre,
    required bool fireExtinguisher,
    required bool snowChains,
    required bool heating,
    required bool airConditioning,
    required bool childSeat,
  }) =>
      _write('/api/v1/driver/vehicles/$vehicleId/equipment', {
        'fourByFour': fourByFour,
        'firstAidKit': firstAidKit,
        'spareTyre': spareTyre,
        'fireExtinguisher': fireExtinguisher,
        'snowChains': snowChains,
        'heating': heating,
        'airConditioning': airConditioning,
        'childSeat': childSeat,
      });

  /// Saves the rent terms. This does not switch renting on by itself.
  Future<VehicleUsage> setRentSettings(
    String vehicleId, {
    double? withDriverDaily,
    double? selfDriveDaily,
    double? securityDeposit,
    required int minimumDays,
    int? kmPerDay,
    required bool fuelIncluded,
    String? pickupPoint,
  }) =>
      _write('/api/v1/driver/vehicles/$vehicleId/rent-settings', {
        'withDriverDaily': withDriverDaily,
        'selfDriveDaily': selfDriveDaily,
        'securityDeposit': securityDeposit,
        'minimumDays': minimumDays,
        'kmPerDay': kmPerDay,
        'fuelIncluded': fuelIncluded,
        'pickupPoint': pickupPoint,
      });

  Future<VehicleUsage> _write(String path, Map<String, dynamic> body) async {
    final Map<String, dynamic> response;
    try {
      response = await api.putJson(path, body);
    } on ApiException catch (error) {
      throw VehicleUsageRefused(error.code ?? '', error.message);
    }

    final payload = response['data'] ?? response;
    if (payload is Map) {
      return VehicleUsage.fromJson(Map<String, dynamic>.from(payload));
    }
    throw const VehicleUsageRefused(
        'unexpected_response', 'The server did not return the vehicle.');
  }
}
