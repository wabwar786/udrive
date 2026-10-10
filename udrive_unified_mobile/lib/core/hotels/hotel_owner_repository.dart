import 'package:file_picker/file_picker.dart';

import '../network/api_client.dart';

/// Hotel mode: the owner's profile, their hotels, and the five-step wizard.
///
/// Server: `HotelOwnerController` (`/api/v1/hotels/owner/...`). A new hotel is
/// a Draft from the first step, so every step saves as it goes and the owner
/// can stop and carry on later.

class HotelOwnerProfile {
  const HotelOwnerProfile({
    required this.ownerName,
    required this.businessName,
    required this.phone,
    required this.email,
    required this.cnicFront,
    required this.cnicBack,
    required this.verificationStatus,
    required this.verificationNote,
    required this.complete,
  });

  final String ownerName;
  final String businessName;
  final String phone;
  final String email;
  final bool cnicFront;
  final bool cnicBack;

  /// NotSubmitted, Pending, Verified or Rejected.
  final String verificationStatus;
  final String? verificationNote;

  /// Name, business, number and both CNIC sides are in.
  final bool complete;

  bool get verified => verificationStatus == 'Verified';

  factory HotelOwnerProfile.fromJson(Map<String, dynamic> j) => HotelOwnerProfile(
        ownerName: _s(j['ownerName']),
        businessName: _s(j['businessName']),
        phone: _s(j['phone']),
        email: _s(j['email']),
        cnicFront: j['cnicFront'] == true,
        cnicBack: j['cnicBack'] == true,
        verificationStatus: _s(j['verificationStatus'], 'NotSubmitted'),
        verificationNote: _n(j['verificationNote']),
        complete: j['complete'] == true,
      );
}

/// One hotel on the Hotels tab.
class OwnerHotelCard {
  const OwnerHotelCard({
    required this.id,
    required this.name,
    required this.propertyType,
    required this.city,
    required this.district,
    required this.status,
    required this.rejectionReason,
    required this.isActive,
    required this.photoUrl,
    required this.photoCount,
    required this.roomTypes,
    required this.contactPhone,
  });

  final String id;
  final String name;
  final String propertyType;
  final String city;
  final String district;

  /// Draft, Pending, Approved or Rejected.
  final String status;
  final String? rejectionReason;
  final bool isActive;
  final String photoUrl;
  final int photoCount;
  final int roomTypes;
  final String contactPhone;

  factory OwnerHotelCard.fromJson(Map<String, dynamic> j) => OwnerHotelCard(
        id: _s(j['id']),
        name: _s(j['name']),
        propertyType: _s(j['propertyType'], 'Hotel'),
        city: _s(j['city']),
        district: _s(j['district']),
        status: _s(j['status'], 'Draft'),
        rejectionReason: _n(j['rejectionReason']),
        isActive: j['isActive'] != false,
        photoUrl: _s(j['photoUrl']),
        photoCount: _i(j['photoCount']),
        roomTypes: _i(j['roomTypes']),
        contactPhone: _s(j['contactPhone']),
      );
}

class HotelOwnerHome {
  const HotelOwnerHome({required this.profile, required this.hotels});

  final HotelOwnerProfile profile;
  final List<OwnerHotelCard> hotels;

  factory HotelOwnerHome.fromJson(Map<String, dynamic> j) => HotelOwnerHome(
        profile: HotelOwnerProfile.fromJson(_m(j['profile'])),
        hotels: [
          for (final item in (j['hotels'] as List? ?? const []))
            if (item is Map) OwnerHotelCard.fromJson(Map<String, dynamic>.from(item)),
        ],
      );
}

class OwnerHotelPhoto {
  const OwnerHotelPhoto({required this.id, required this.url, required this.isMain});

  final String id;
  final String url;
  final bool isMain;

  factory OwnerHotelPhoto.fromJson(Map<String, dynamic> j) => OwnerHotelPhoto(
        id: _s(j['id']),
        url: _s(j['url']),
        isMain: j['isMain'] == true,
      );
}

class OwnerHotelRoomType {
  const OwnerHotelRoomType({
    required this.id,
    required this.roomType,
    required this.description,
    required this.capacity,
    required this.totalRooms,
    required this.baseRate,
    required this.imageUrl,
  });

  final String id;
  final String roomType;
  final String description;
  final int capacity;
  final int totalRooms;
  final double baseRate;
  final String imageUrl;

  factory OwnerHotelRoomType.fromJson(Map<String, dynamic> j) => OwnerHotelRoomType(
        id: _s(j['id']),
        roomType: _s(j['roomType']),
        description: _s(j['description']),
        capacity: _i(j['capacity']),
        totalRooms: _i(j['totalRooms']),
        baseRate: _d(j['baseRate']),
        imageUrl: _s(j['imageUrl']),
      );
}

/// Everything the wizard edits.
class OwnerHotelDraft {
  const OwnerHotelDraft({
    required this.id,
    required this.name,
    required this.propertyType,
    required this.description,
    required this.address,
    required this.city,
    required this.district,
    required this.latitude,
    required this.longitude,
    required this.contactPhone,
    required this.amenities,
    required this.transportAvailable,
    required this.checkInTime,
    required this.checkOutTime,
    required this.status,
    required this.rejectionReason,
    required this.photos,
    required this.rooms,
    required this.missing,
  });

  final String id;
  final String name;
  final String propertyType;
  final String description;
  final String address;
  final String city;
  final String district;

  /// Null until the owner drops the pin.
  final double? latitude;
  final double? longitude;
  final String contactPhone;
  final List<String> amenities;
  final bool transportAvailable;

  /// "14:00", or null when not set.
  final String? checkInTime;
  final String? checkOutTime;
  final String status;
  final String? rejectionReason;
  final List<OwnerHotelPhoto> photos;
  final List<OwnerHotelRoomType> rooms;

  /// What still stops a Submit, in the server's words.
  final List<String> missing;

  bool get live => status == 'Approved';
  bool get canSubmit => status == 'Draft' || status == 'Rejected';

  factory OwnerHotelDraft.fromJson(Map<String, dynamic> j) => OwnerHotelDraft(
        id: _s(j['id']),
        name: _s(j['name']),
        propertyType: _s(j['propertyType'], 'Hotel'),
        description: _s(j['description']),
        address: _s(j['address']),
        city: _s(j['city']),
        district: _s(j['district']),
        latitude: _nd(j['latitude']),
        longitude: _nd(j['longitude']),
        contactPhone: _s(j['contactPhone']),
        amenities: [for (final a in (j['amenities'] as List? ?? const [])) '$a'],
        transportAvailable: j['transportAvailable'] != false,
        checkInTime: _n(j['checkInTime']),
        checkOutTime: _n(j['checkOutTime']),
        status: _s(j['status'], 'Draft'),
        rejectionReason: _n(j['rejectionReason']),
        photos: [
          for (final p in (j['photos'] as List? ?? const []))
            if (p is Map) OwnerHotelPhoto.fromJson(Map<String, dynamic>.from(p)),
        ],
        rooms: [
          for (final r in (j['rooms'] as List? ?? const []))
            if (r is Map) OwnerHotelRoomType.fromJson(Map<String, dynamic>.from(r)),
        ],
        missing: [for (final m in (j['missing'] as List? ?? const [])) '$m'],
      );
}

class HotelOwnerRepository {
  HotelOwnerRepository(this.api);

  final ApiClient api;

  static const _base = '/api/v1/hotels/owner';

  Future<HotelOwnerHome> home() async =>
      HotelOwnerHome.fromJson(_data(await api.getJson('$_base/home')));

  Future<HotelOwnerProfile> profile() async =>
      HotelOwnerProfile.fromJson(_data(await api.getJson('$_base/profile')));

  Future<HotelOwnerProfile> saveProfile({
    required String ownerName,
    required String businessName,
    required String phone,
    required String email,
  }) async =>
      HotelOwnerProfile.fromJson(_data(await api.putJson('$_base/profile', {
        'ownerName': ownerName,
        'businessName': businessName,
        'phone': phone,
        'email': email,
      })));

  /// [side] is `front` or `back`.
  Future<HotelOwnerProfile> uploadCnic(String side, PlatformFile file) async =>
      HotelOwnerProfile.fromJson(_data(await api.uploadFile(
        '$_base/profile/cnic/$side',
        fieldName: 'file',
        file: file,
        fields: const {},
      )));

  Future<OwnerHotelDraft> hotel(String id) async =>
      OwnerHotelDraft.fromJson(_data(await api.getJson('$_base/hotels/$id')));

  /// Step 1 of a new hotel.
  Future<OwnerHotelDraft> create(Map<String, dynamic> values) async =>
      OwnerHotelDraft.fromJson(_data(await api.postJson('$_base/hotels', values)));

  /// Sends only the keys given; the server leaves the rest as they are.
  Future<OwnerHotelDraft> update(String id, Map<String, dynamic> values) async =>
      OwnerHotelDraft.fromJson(_data(await api.putJson('$_base/hotels/$id', values)));

  Future<OwnerHotelDraft> submit(String id) async =>
      OwnerHotelDraft.fromJson(_data(await api.postJson('$_base/hotels/$id/submit', const {})));

  Future<OwnerHotelDraft> addPhoto(String id, PlatformFile file) async =>
      OwnerHotelDraft.fromJson(_data(await api.uploadFile(
        '$_base/hotels/$id/photos',
        fieldName: 'file',
        file: file,
        fields: const {},
      )));

  Future<OwnerHotelDraft> removePhoto(String id, String photoId) async =>
      OwnerHotelDraft.fromJson(_data(
          await api.postJson('$_base/hotels/$id/photos/$photoId/remove', const {})));

  Future<OwnerHotelDraft> mainPhoto(String id, String photoId) async =>
      OwnerHotelDraft.fromJson(_data(
          await api.postJson('$_base/hotels/$id/photos/$photoId/main', const {})));

  /// [roomId] null adds a new room type.
  Future<OwnerHotelDraft> saveRoom(
    String id, {
    String? roomId,
    required String roomType,
    required int capacity,
    required int totalRooms,
    required double baseRate,
  }) async {
    final body = {
      'roomType': roomType,
      'capacity': capacity,
      'totalRooms': totalRooms,
      'baseRate': baseRate,
      'description': '',
    };
    final response = roomId == null
        ? await api.postJson('$_base/hotels/$id/rooms', body)
        : await api.putJson('$_base/hotels/$id/rooms/$roomId', body);
    return OwnerHotelDraft.fromJson(_data(response));
  }

  Future<OwnerHotelDraft> removeRoom(String id, String roomId) async =>
      OwnerHotelDraft.fromJson(_data(
          await api.postJson('$_base/hotels/$id/rooms/$roomId/remove', const {})));

  Future<OwnerHotelDraft> roomPhoto(String id, String roomId, PlatformFile file) async =>
      OwnerHotelDraft.fromJson(_data(await api.uploadFile(
        '$_base/hotels/$id/rooms/$roomId/photo',
        fieldName: 'file',
        file: file,
        fields: const {},
      )));
}

Map<String, dynamic> _data(Map<String, dynamic> response) => _m(response['data']);

Map<String, dynamic> _m(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

String _s(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = '$value'.trim();
  return text.isEmpty ? fallback : text;
}

String? _n(Object? value) {
  final text = _s(value);
  return text.isEmpty ? null : text;
}

int _i(Object? value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

double _d(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}') ?? 0;

double? _nd(Object? value) =>
    value == null ? null : (value is num ? value.toDouble() : double.tryParse('$value'));
