import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import 'offer_card_fields.dart';

/// Whether one service is open to customers, and what to say when it is not.
class ServiceAvailability {
  const ServiceAvailability({
    required this.key,
    required this.isOpen,
    required this.badgeLabel,
    required this.closedMessage,
  });

  /// Matches a key the admin portal knows: `cityRides`, `carRental` and so on.
  final String key;

  final bool isOpen;

  /// Shown on the tile when closed. Short — it sits in a badge.
  final String badgeLabel;

  /// What the customer is told on tapping a closed tile.
  final String closedMessage;

  factory ServiceAvailability.fromJson(Map<String, dynamic> json) =>
      ServiceAvailability(
        key: '${json['serviceKey'] ?? ''}',
        isOpen: json['isOpen'] != false,
        badgeLabel: '${json['badgeLabel'] ?? 'SOON'}',
        closedMessage:
            '${json['closedMessage'] ?? 'This service is not open yet.'}',
      );
}

/// Which services the customer app may open.
///
/// Read from the server, cached on the phone, and — crucially — **defaulting to
/// open**. If the call fails, every service works. The alternative is a network
/// hiccup silently closing the whole app, which is a far worse failure than
/// briefly showing a service that turns out to be unavailable on the next
/// screen.
class ServiceAvailabilityRepository {
  ServiceAvailabilityRepository(this.api);

  final ApiClient api;

  static const _cacheKey = 'udrive.services.availability';

  /// The last answer the server gave, so the first frame after launch is not
  /// a screen of tiles that all change state a second later.
  static Future<Map<String, ServiceAvailability>> readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_cacheKey);
      if (raw == null) return const {};

      final result = <String, ServiceAvailability>{};
      for (final line in raw) {
        // key|isOpen|badge|message — message last, because it is the only
        // field that may contain anything.
        final parts = line.split('|');
        if (parts.length < 4) continue;
        result[parts[0]] = ServiceAvailability(
          key: parts[0],
          isOpen: parts[1] == '1',
          badgeLabel: parts[2],
          closedMessage: parts.sublist(3).join('|'),
        );
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// How often the driver should publish, and the customer poll.
  ///
  /// One number from the server so the two never drift apart. Falls back to two
  /// seconds if the call fails — the value the platform ships with, and a safe
  /// one to be wrong about for a few minutes.
  static const int defaultPingSeconds = 2;

  /// How far around themselves a customer should be shown vehicles.
  ///
  /// Cached in memory for the session after the first read, because the home
  /// screen and the offers screen both ask and the answer does not change
  /// while an app is open.
  static double _nearbyRadiusKm = defaultNearbyRadiusKm;
  static double get nearbyRadiusKm => _nearbyRadiusKm;

  static const double defaultNearbyRadiusKm = 1;

  Future<int> trackingPingSeconds() async {
    try {
      final response = await api.getJson('/api/v1/settings/operations');
      final data = response['data'];
      if (data is! Map) return defaultPingSeconds;
      // The radii come back on the same call, so they are picked up here
      // rather than costing a second round trip for two numbers.
      final radius = (data['nearbyRadiusKm'] as num?)?.toDouble();
      if (radius != null) _nearbyRadiusKm = radius.clamp(0.2, 25);

      // The offer card's fields ride along on the same call.
      final card = data['offerCard'];
      if (card is Map) {
        OfferCardFields.current =
            OfferCardFields.fromJson(Map<String, dynamic>.from(card));
      }

      final seconds = (data['pingSeconds'] as num?)?.toInt();
      if (seconds == null) return defaultPingSeconds;
      return seconds.clamp(1, 60);
    } catch (_) {
      return defaultPingSeconds;
    }
  }

  /// Fetches the current list, and caches it.
  ///
  /// Returns an empty map on failure, which the callers read as "everything is
  /// open" — see the class comment.
  Future<Map<String, ServiceAvailability>> refresh() async {
    try {
      final response = await api.getJson('/api/v1/services');
      final data = response['data'];
      if (data is! List) return const {};

      final result = <String, ServiceAvailability>{};
      for (final item in data.whereType<Map>()) {
        final entry =
            ServiceAvailability.fromJson(Map<String, dynamic>.from(item));
        if (entry.key.isNotEmpty) result[entry.key] = entry;
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
          _cacheKey,
          result.values
              .map((entry) => [
                    entry.key,
                    entry.isOpen ? '1' : '0',
                    entry.badgeLabel,
                    entry.closedMessage,
                  ].join('|'))
              .toList(),
        );
      } catch (_) {
        // A cache that cannot be written costs a flicker on next launch.
      }

      return result;
    } catch (_) {
      return const {};
    }
  }
}
