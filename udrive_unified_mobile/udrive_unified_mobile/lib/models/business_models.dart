/// Categories a local business can list itself under.
///
/// Kept as a closed enum on the client so filter chips, icons and the owner
/// registration form stay in sync; the API exchanges the [apiValue] string.
enum BusinessCategory {
  restaurant,
  grocery,
  medicalStore,
  hospital,
  bank,
  fuel,
  mosque,
}

extension BusinessCategoryInfo on BusinessCategory {
  String get apiValue => switch (this) {
        BusinessCategory.restaurant => 'Restaurant',
        BusinessCategory.grocery => 'Grocery',
        BusinessCategory.medicalStore => 'MedicalStore',
        BusinessCategory.hospital => 'Hospital',
        BusinessCategory.bank => 'Bank',
        BusinessCategory.fuel => 'Fuel',
        BusinessCategory.mosque => 'Mosque',
      };

  String get label => switch (this) {
        BusinessCategory.restaurant => 'Restaurants',
        BusinessCategory.grocery => 'Grocery',
        BusinessCategory.medicalStore => 'Medical store',
        BusinessCategory.hospital => 'Hospital',
        BusinessCategory.bank => 'ATM / Bank',
        BusinessCategory.fuel => 'Fuel',
        BusinessCategory.mosque => 'Mosque',
      };

  static BusinessCategory? fromApi(String? value) {
    if (value == null) return null;
    final needle = value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    for (final category in BusinessCategory.values) {
      if (category.apiValue.toLowerCase() == needle) return category;
    }
    return null;
  }
}

/// Approval state controlled by UDrive admins, mirroring how hotels work.
enum BusinessStatus { draft, pending, approved, rejected, suspended }

extension BusinessStatusInfo on BusinessStatus {
  String get label => switch (this) {
        BusinessStatus.draft => 'Draft',
        BusinessStatus.pending => 'Pending review',
        BusinessStatus.approved => 'Live',
        BusinessStatus.rejected => 'Rejected',
        BusinessStatus.suspended => 'Suspended',
      };

  static BusinessStatus fromApi(String? value) {
    final needle = (value ?? '').toLowerCase();
    if (needle.contains('approve') || needle.contains('live')) {
      return BusinessStatus.approved;
    }
    if (needle.contains('reject')) return BusinessStatus.rejected;
    if (needle.contains('suspend')) return BusinessStatus.suspended;
    if (needle.contains('draft')) return BusinessStatus.draft;
    return BusinessStatus.pending;
  }
}

class BusinessListing {
  const BusinessListing({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.status,
    this.phone,
    this.photos = const [],
    this.openNow,
    this.rating,
    this.reviewCount,
    this.distanceKm,
    this.verified = false,
    this.description,
    this.hours,
  });

  final String id;
  final String name;
  final BusinessCategory? category;
  final double latitude;
  final double longitude;
  final String address;
  final BusinessStatus status;
  final String? phone;
  final List<String> photos;

  /// Null when the business has not published opening hours.
  final bool? openNow;
  final double? rating;
  final int? reviewCount;

  /// Straight-line distance from the customer, supplied by the API.
  final double? distanceKm;
  final bool verified;
  final String? description;
  final Map<String, String>? hours;

  factory BusinessListing.fromJson(Map<String, dynamic> json) {
    return BusinessListing(
      id: '${json['id']}',
      name: '${json['name'] ?? ''}'.trim(),
      category: BusinessCategoryInfo.fromApi(json['category']?.toString()),
      latitude: _toDouble(json['latitude']) ?? 0,
      longitude: _toDouble(json['longitude']) ?? 0,
      address: '${json['address'] ?? ''}'.trim(),
      status: BusinessStatusInfo.fromApi(json['status']?.toString()),
      phone: json['phone']?.toString(),
      photos: (json['photos'] as List? ?? const [])
          .map((value) => '$value')
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      openNow: json['openNow'] is bool ? json['openNow'] as bool : null,
      rating: _toDouble(json['rating']),
      reviewCount: (json['reviewCount'] as num?)?.toInt(),
      distanceKm: _toDouble(json['distanceKm']),
      verified: json['verified'] == true,
      description: json['description']?.toString(),
      hours: json['hours'] is Map
          ? (json['hours'] as Map)
              .map((key, value) => MapEntry('$key', '$value'))
          : null,
    );
  }

  Map<String, dynamic> toCreateJson() => {
        'name': name,
        'category': category?.apiValue,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        if (phone != null) 'phone': phone,
        if (description != null) 'description': description,
        if (hours != null) 'hours': hours,
      };

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
