import 'dart:math' as math;

import '../network/api_client.dart';

/// Districts and their tehsils, as the admin portal publishes them.
///
/// Owners and city-ride drivers pick one tehsil so customers nearby see them
/// first and the area's team checks them. The list is public and changes
/// rarely, so the first good answer is kept for the life of the app.

class AreaTehsil {
  const AreaTehsil({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final double? latitude;
  final double? longitude;

  bool get hasPin => latitude != null && longitude != null;

  factory AreaTehsil.fromJson(Map<String, dynamic> j) => AreaTehsil(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}'.trim(),
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
      );
}

class AreaDistrict {
  const AreaDistrict({
    required this.id,
    required this.name,
    required this.tehsils,
  });

  final String id;
  final String name;
  final List<AreaTehsil> tehsils;

  factory AreaDistrict.fromJson(Map<String, dynamic> j) => AreaDistrict(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}'.trim(),
        tehsils: ((j['tehsils'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) => e['isActive'] != false)
            .map(AreaTehsil.fromJson)
            .where((t) => t.id.isNotEmpty && t.name.isNotEmpty)
            .toList(growable: false),
      );
}

/// One chosen tehsil, with the names needed to show it.
class AreaSelection {
  const AreaSelection({
    required this.districtId,
    required this.districtName,
    required this.tehsilId,
    required this.tehsilName,
  });

  final String districtId;
  final String districtName;
  final String tehsilId;
  final String tehsilName;

  /// "Muzaffarabad · Naseerabad".
  String get label => '$districtName · $tehsilName';
}

class AreaRepository {
  AreaRepository(this.api);

  final ApiClient api;

  /// How far a tehsil centre may be for GPS to suggest it.
  static const double maxSuggestKm = 80;

  static List<AreaDistrict>? _cache;

  Future<List<AreaDistrict>> districts() async {
    final cached = _cache;
    if (cached != null) return cached;
    final response =
        await api.getJson('/api/v1/catalog/areas', authenticated: false);
    final list = ((response['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => e['isActive'] != false)
        .map(AreaDistrict.fromJson)
        .where((d) => d.id.isNotEmpty && d.name.isNotEmpty)
        .toList(growable: false);
    _cache = list;
    return list;
  }

  /// The selection for [tehsilId] in [districts], or null when not found.
  static AreaSelection? find(List<AreaDistrict> districts, String? tehsilId) {
    if (tehsilId == null || tehsilId.isEmpty) return null;
    for (final district in districts) {
      for (final tehsil in district.tehsils) {
        if (tehsil.id == tehsilId) {
          return AreaSelection(
            districtId: district.id,
            districtName: district.name,
            tehsilId: tehsil.id,
            tehsilName: tehsil.name,
          );
        }
      }
    }
    return null;
  }

  /// The nearest tehsil centre to a GPS fix, if one is within
  /// [maxSuggestKm]. Equirectangular distance — plenty at this scale.
  AreaSelection? nearest(
      List<AreaDistrict> districts, double lat, double lng) {
    AreaSelection? best;
    var bestKm = double.infinity;
    for (final district in districts) {
      for (final tehsil in district.tehsils) {
        final tLat = tehsil.latitude;
        final tLng = tehsil.longitude;
        if (tLat == null || tLng == null) continue;
        final dLat = tLat - lat;
        final dLng = (tLng - lng) * math.cos(lat * math.pi / 180);
        final km = 111.32 * math.sqrt(dLat * dLat + dLng * dLng);
        if (km < bestKm) {
          bestKm = km;
          best = AreaSelection(
            districtId: district.id,
            districtName: district.name,
            tehsilId: tehsil.id,
            tehsilName: tehsil.name,
          );
        }
      }
    }
    return bestKm <= maxSuggestKm ? best : null;
  }
}
