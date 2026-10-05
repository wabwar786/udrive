import 'dart:math' as math;

import '../network/api_client.dart';

/// Place names an owner can type into a tour's From / To: destinations,
/// tehsils and the main cities, as the server publishes them. Used for
/// typing suggestions and a gentle spelling fix only — any other name is
/// still saved exactly as typed.

class PlaceName {
  const PlaceName({
    required this.name,
    required this.kind,
    required this.detail,
    this.latitude,
    this.longitude,
  });

  final String name;

  /// "Tehsil", "Destination" or "City".
  final String kind;

  /// "Bagh district", "Punjab"… shown small under the name.
  final String detail;
  final double? latitude;
  final double? longitude;

  factory PlaceName.fromJson(Map<String, dynamic> j) => PlaceName(
        name: '${j['name'] ?? ''}'.trim(),
        kind: '${j['kind'] ?? ''}'.trim(),
        detail: '${j['detail'] ?? ''}'.trim(),
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
      );
}

class PlaceRepository {
  PlaceRepository(this.api);

  final ApiClient api;

  /// Most suggestions shown under a field.
  static const int maxSuggestions = 6;

  static List<PlaceName>? _cache;

  /// The public list, kept for the life of the app once loaded.
  Future<List<PlaceName>> names() async {
    final cached = _cache;
    if (cached != null) return cached;
    final response = await api.getJson('/api/v1/catalog/place-names',
        authenticated: false);
    final list = ((response['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => PlaceName.fromJson(Map<String, dynamic>.from(e)))
        .where((p) => p.name.isNotEmpty)
        .toList(growable: false);
    _cache = list;
    return list;
  }

  /// Lower case, without spaces or dots: "D.I. Khan" → "dikhan".
  static String _key(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s.]+'), '');

  /// Up to [maxSuggestions] names for [typed]: those starting with it first,
  /// then those containing it.
  static List<PlaceName> suggest(List<PlaceName> places, String typed) {
    final needle = _key(typed);
    if (needle.isEmpty) return const [];
    final starts = <PlaceName>[];
    final contains = <PlaceName>[];
    for (final place in places) {
      final key = _key(place.name);
      if (key.startsWith(needle)) {
        starts.add(place);
      } else if (key.contains(needle)) {
        contains.add(place);
      }
    }
    return [...starts, ...contains].take(maxSuggestions).toList(growable: false);
  }

  /// The closest known name when [typed] looks like a misspelling of it, or
  /// null when it already matches a name or nothing is close.
  static String? closest(List<PlaceName> places, String typed) {
    final text = typed.trim().toLowerCase();
    final textKey = _key(typed);
    if (textKey.length < 3) return null;
    for (final place in places) {
      if (place.name.toLowerCase() == text) return null;
    }

    String? best;
    var bestDistance = 1 << 30;
    for (final place in places) {
      final name = place.name.toLowerCase();
      final nameKey = _key(place.name);
      final allowed = nameKey.length <= 8 ? 2 : 3;
      final distance = math.min(
        _levenshtein(text, name),
        _levenshtein(textKey, nameKey),
      );
      if (distance <= allowed && distance < bestDistance) {
        bestDistance = distance;
        best = place.name;
      }
    }
    return best;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    var current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        current[j] = math.min(
          math.min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + cost,
        );
      }
      final swap = previous;
      previous = current;
      current = swap;
    }
    return previous[b.length];
  }
}
