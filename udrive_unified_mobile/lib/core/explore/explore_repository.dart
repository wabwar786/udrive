import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';

/// One place in the Explore catalogue, as the admin portal lists it.
class ExplorePlace {
  const ExplorePlace({
    required this.id,
    required this.name,
    required this.summary,
    required this.latitude,
    required this.longitude,
    required this.district,
    required this.bestSeason,
    required this.recommendedVehicle,
    required this.networkStatus,
    required this.familyScore,
    required this.safetyScore,
    required this.coverImageUrl,
  });

  final String id;
  final String name;
  final String summary;
  final double latitude;
  final double longitude;
  final String district;

  /// As written in the portal: "May to September", "All year".
  final String bestSeason;
  final String recommendedVehicle;
  final String networkStatus;
  final int familyScore;
  final int safetyScore;
  final String? coverImageUrl;

  bool get needsFourByFour {
    final v = recommendedVehicle.toLowerCase();
    return v.contains('4x4') || v.contains('4×4') || v.contains('jeep');
  }

  bool get weakSignal {
    final n = networkStatus.toLowerCase();
    return n.contains('weak') || n.contains('no ') || n.contains('none') ||
        n.contains('limited') || n.contains('poor');
  }

  /// "May – Sep", short enough for a chip.
  String get seasonShort {
    final range = _seasonMonths;
    if (range == null) return bestSeason;
    if (range.$1 == 1 && range.$2 == 12) return 'All year';
    return '${_short[range.$1 - 1]} – ${_short[range.$2 - 1]}';
  }

  /// Whether [month] (1–12) falls in the best season. Unreadable seasons
  /// count as in season — better to show a place than hide it on a typo.
  bool inSeason(int month) {
    final range = _seasonMonths;
    if (range == null) return true;
    final (from, to) = range;
    return from <= to
        ? month >= from && month <= to
        : month >= from || month <= to;
  }

  static const _short = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  (int, int)? get _seasonMonths {
    final text = bestSeason.toLowerCase();
    if (text.contains('all year') || text.contains('year round')) {
      return (1, 12);
    }
    final found = <int>[];
    for (final word in RegExp(r'[a-z]+').allMatches(text)) {
      final w = word.group(0)!;
      if (w.length < 3) continue;
      final month = _months[w.substring(0, 3)];
      if (month != null) found.add(month);
    }
    if (found.length < 2) return null;
    return (found.first, found[1]);
  }

  factory ExplorePlace.fromJson(Map<String, dynamic> j) => ExplorePlace(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}'.trim(),
        summary: '${j['summary'] ?? ''}'.trim(),
        latitude: (j['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (j['longitude'] as num?)?.toDouble() ?? 0,
        district: '${j['district'] ?? ''}'.trim(),
        bestSeason: '${j['bestSeason'] ?? ''}'.trim(),
        recommendedVehicle: '${j['recommendedVehicle'] ?? ''}'.trim(),
        networkStatus: '${j['networkStatus'] ?? ''}'.trim(),
        familyScore: (j['familySuitabilityScore'] as num?)?.toInt() ?? 0,
        safetyScore: (j['routeSafetyScore'] as num?)?.toInt() ?? 0,
        coverImageUrl: j['coverImageUrl']?.toString(),
      );
}

class ExploreRoute {
  const ExploreRoute({
    required this.name,
    required this.fromName,
    required this.distanceKm,
    required this.minutes,
    required this.fourByFour,
    required this.daylightOnly,
  });

  final String name;
  final String? fromName;
  final double distanceKm;
  final int minutes;
  final bool fourByFour;
  final bool daylightOnly;

  factory ExploreRoute.fromJson(Map<String, dynamic> j) => ExploreRoute(
        name: '${j['name'] ?? ''}',
        fromName: j['fromName']?.toString(),
        distanceKm: (j['distanceKm'] as num?)?.toDouble() ?? 0,
        minutes: (j['estimatedMinutes'] as num?)?.toInt() ?? 0,
        fourByFour: j['fourByFourRequired'] == true,
        daylightOnly: j['daylightOnly'] == true,
      );
}

class ExploreNearby {
  const ExploreNearby({
    required this.id,
    required this.name,
    required this.district,
    required this.distanceKm,
    required this.coverImageUrl,
  });

  final String id;
  final String name;
  final String district;
  final double distanceKm;
  final String? coverImageUrl;

  factory ExploreNearby.fromJson(Map<String, dynamic> j) => ExploreNearby(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        district: '${j['district'] ?? ''}',
        distanceKm: (j['distanceKm'] as num?)?.toDouble() ?? 0,
        coverImageUrl: j['coverImageUrl']?.toString(),
      );
}

/// The extra facts behind one place: Urdu name, the way in, what is on sale.
class ExploreDetails {
  const ExploreDetails({
    required this.nameUr,
    required this.route,
    required this.toursCount,
    required this.nextDeparture,
    required this.hotelsNearby,
    required this.nearby,
  });

  final String nameUr;
  final ExploreRoute? route;
  final int toursCount;
  final DateTime? nextDeparture;
  final int hotelsNearby;
  final List<ExploreNearby> nearby;

  factory ExploreDetails.fromJson(Map<String, dynamic> j) => ExploreDetails(
        nameUr: '${j['nameUr'] ?? ''}',
        route: j['route'] is Map
            ? ExploreRoute.fromJson(Map<String, dynamic>.from(j['route'] as Map))
            : null,
        toursCount: (j['toursCount'] as num?)?.toInt() ?? 0,
        nextDeparture: j['nextDeparture'] == null
            ? null
            : DateTime.tryParse('${j['nextDeparture']}')?.toLocal(),
        hotelsNearby: (j['hotelsNearby'] as num?)?.toInt() ?? 0,
        nearby: ((j['nearby'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ExploreNearby.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
      );
}

class ExploreRepository {
  ExploreRepository(this.api);

  final ApiClient api;

  static const _savedKey = 'explore_saved_places_v1';

  Future<List<ExplorePlace>> places({String language = 'en'}) async {
    final response = await api.getJson(
      '/api/v1/catalog/destinations?language=$language',
      authenticated: false,
    );
    return ((response['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ExplorePlace.fromJson(Map<String, dynamic>.from(e)))
        .where((p) => p.id.isNotEmpty && p.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<ExploreDetails> details(String id) async {
    final response = await api.getJson(
      '/api/v1/catalog/destinations/$id/explore',
      authenticated: false,
    );
    final data = response['data'] ?? response;
    return ExploreDetails.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Saved places live on the phone; nothing about them needs the server.
  static Future<Set<String>> saved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_savedKey) ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<Set<String>> toggleSaved(String id) async {
    final current = await saved();
    if (!current.remove(id)) current.add(id);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_savedKey, current.toList());
    } catch (_) {}
    return current;
  }
}
