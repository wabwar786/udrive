import '../network/api_client.dart';

/// A fixed per-seat fare for a named route.
class SeatFareQuote {
  const SeatFareQuote({
    required this.originLabel,
    required this.destinationLabel,
    required this.perSeatFare,
    this.notes,
  });

  final String originLabel;
  final String destinationLabel;

  /// What one passenger pays for the whole route. Not per kilometre.
  final int perSeatFare;

  final String? notes;

  String get routeLabel => '$originLabel → $destinationLabel';

  factory SeatFareQuote.fromJson(Map<String, dynamic> json) => SeatFareQuote(
        originLabel: '${json['originLabel'] ?? ''}'.trim(),
        destinationLabel: '${json['destinationLabel'] ?? ''}'.trim(),
        perSeatFare: (json['perSeatFare'] as num?)?.round() ?? 0,
        notes: '${json['notes'] ?? ''}'.trim().isEmpty
            ? null
            : '${json['notes']}'.trim(),
      );
}

/// Looks up the fixed fare for a per-seat route.
///
/// A Coster running per seat is not a metered vehicle: it runs a known route
/// and every passenger pays the same known fare. Where the admin has listed
/// that route, the listed fare is used instead of anything worked out from the
/// distance, and the customer does not bid on it.
class SeatFaresRepository {
  SeatFaresRepository(this.api);

  final ApiClient api;

  /// Null means the route is not listed, which is the ordinary case — the
  /// caller then prices by the kilometre as before. Errors return null too: a
  /// lookup that fails must not block a booking.
  Future<SeatFareQuote?> quote({
    required String category,
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) async {
    final parameters = <String, String>{
      'category': category,
      'fromLat': '$fromLatitude',
      'fromLng': '$fromLongitude',
      'toLat': '$toLatitude',
      'toLng': '$toLongitude',
    };

    try {
      final response = await api.getJson(
        '/api/v1/catalog/seat-fare?${Uri(queryParameters: parameters).query}',
        authenticated: false,
      );

      final data = response['data'];
      if (data is! Map) return null;

      final quote = SeatFareQuote.fromJson(Map<String, dynamic>.from(data));
      return quote.perSeatFare > 0 ? quote : null;
    } catch (_) {
      return null;
    }
  }
}
