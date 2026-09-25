import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A destination the customer has used before.
class RecentPlace {
  const RecentPlace({
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
  });

  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;

  LatLng get point => LatLng(latitude, longitude);

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'latitude': latitude,
        'longitude': longitude,
      };

  static RecentPlace? fromJson(Map<String, dynamic> json) {
    final lat = (json['latitude'] as num?)?.toDouble();
    final lng = (json['longitude'] as num?)?.toDouble();
    final title = '${json['title'] ?? ''}'.trim();
    if (lat == null || lng == null || title.isEmpty) return null;
    return RecentPlace(
      title: title,
      subtitle: '${json['subtitle'] ?? ''}'.trim(),
      latitude: lat,
      longitude: lng,
    );
  }
}

/// Recently used destinations, newest first.
///
/// Deliberately shares the storage key the route flow screen already writes to,
/// so a destination picked in either place shows up in both. Two separate
/// histories would look like the app had forgotten where the customer went.
class RecentPlacesStore {
  const RecentPlacesStore._();

  static const _key = 'udrive_recent_destination_searches';
  static const _maxEntries = 6;

  static Future<List<RecentPlace>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? const [];
      return raw
          .map((entry) {
            try {
              return RecentPlace.fromJson(
                Map<String, dynamic>.from(jsonDecode(entry) as Map),
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<RecentPlace>()
          .take(_maxEntries)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Adds a place, moving it to the front if it was already there.
  static Future<void> remember(RecentPlace place) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await load();
      final merged = <RecentPlace>[
        place,
        ...existing.where(
          (item) =>
              item.title.toLowerCase() != place.title.toLowerCase(),
        ),
      ].take(_maxEntries);

      await prefs.setStringList(
        _key,
        merged.map((item) => jsonEncode(item.toJson())).toList(growable: false),
      );
    } catch (_) {
      // History is a convenience. Losing it must never break a booking.
    }
  }
}
