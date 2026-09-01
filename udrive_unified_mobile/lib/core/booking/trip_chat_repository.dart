import '../network/api_client.dart';

/// One message on a booking.
class TripMessage {
  const TripMessage({
    required this.id,
    required this.senderRole,
    required this.senderName,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  final String id;

  /// 'Customer' or 'Driver'. Carried on the message so the app can lay it left
  /// or right without knowing anything else about who is looking.
  final String senderRole;

  final String senderName;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  factory TripMessage.fromJson(Map<String, dynamic> json) => TripMessage(
        id: '${json['id']}',
        senderRole: '${json['senderRole'] ?? ''}',
        senderName: '${json['senderName'] ?? ''}',
        body: '${json['body'] ?? ''}',
        createdAt:
            DateTime.parse('${json['createdAt']}').toLocal(),
        readAt: json['readAt'] == null
            ? null
            : DateTime.parse('${json['readAt']}').toLocal(),
      );
}

/// What a driver is shown about the passenger before they meet.
class PassengerStanding {
  const PassengerStanding({
    required this.fullName,
    required this.completedTrips,
    required this.cancelledTrips,
    required this.ratingCount,
    required this.standing,
    this.rating,
  });

  final String fullName;
  final int completedTrips;
  final int cancelledTrips;
  final int ratingCount;

  /// One of New, Regular, Trusted, Mixed.
  final String standing;

  /// Null when no driver has ever rated this customer. Not defaulted to five —
  /// a reassurance nobody earned is worse than none.
  final double? rating;

  factory PassengerStanding.fromJson(Map<String, dynamic> json) =>
      PassengerStanding(
        fullName: '${json['fullName'] ?? ''}',
        completedTrips: (json['completedTrips'] as num?)?.toInt() ?? 0,
        cancelledTrips: (json['cancelledTrips'] as num?)?.toInt() ?? 0,
        ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
        standing: '${json['standing'] ?? 'New'}',
        rating: (json['rating'] as num?)?.toDouble(),
      );
}

/// One published review of a driver.
class DriverReview {
  const DriverReview({
    required this.rating,
    required this.reviewerFirstName,
    required this.createdAt,
    this.text,
  });

  final int rating;
  final String? text;

  /// First name only — the reviewer did not agree to be identified to
  /// strangers, and a review is about the driver anyway.
  final String reviewerFirstName;

  final DateTime createdAt;

  factory DriverReview.fromJson(Map<String, dynamic> json) => DriverReview(
        rating: (json['rating'] as num?)?.toInt() ?? 0,
        text: '${json['text'] ?? ''}'.trim().isEmpty
            ? null
            : '${json['text']}'.trim(),
        reviewerFirstName: '${json['reviewerFirstName'] ?? 'Customer'}',
        createdAt: DateTime.parse('${json['createdAt']}').toLocal(),
      );
}

/// What a waiting customer can see about the driver coming for them.
class DriverReputation {
  const DriverReputation({
    required this.driverName,
    required this.ratingCount,
    required this.completedTrips,
    required this.recentReviews,
    this.rating,
  });

  final String driverName;

  /// Null when nobody has rated this driver yet. Not defaulted to five — a
  /// score nobody gave is worse than an honest blank.
  final double? rating;

  final int ratingCount;
  final int completedTrips;
  final List<DriverReview> recentReviews;

  factory DriverReputation.fromJson(Map<String, dynamic> json) =>
      DriverReputation(
        driverName: '${json['driverName'] ?? ''}',
        rating: (json['rating'] as num?)?.toDouble(),
        ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
        completedTrips: (json['completedTrips'] as num?)?.toInt() ?? 0,
        recentReviews: (json['recentReviews'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => DriverReview.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
      );
}

/// Chat and passenger context for one booking.
class TripChatRepository {
  TripChatRepository(this.api);

  final ApiClient api;

  /// Messages, optionally only those newer than [after].
  ///
  /// The caller passes the timestamp of the newest message it already holds, so
  /// polling costs one index lookup and usually returns an empty list.
  Future<List<TripMessage>> messages(String bookingId, {DateTime? after}) async {
    final query = after == null
        ? ''
        : '?after=${Uri.encodeQueryComponent(after.toUtc().toIso8601String())}';

    final response = await api.getJson('/api/v1/trips/$bookingId/messages$query');
    final data = response['data'];
    if (data is! List) return const [];

    return data
        .whereType<Map>()
        .map((item) => TripMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<TripMessage> send(String bookingId, String body) async {
    final response = await api.postJson(
      '/api/v1/trips/$bookingId/messages',
      {'body': body},
    );
    final data = response['data'];
    return TripMessage.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Customer only. Returns null when the server declines — a missing
  /// reputation card is a smaller problem than a screen that fails to open.
  Future<DriverReputation?> driver(String bookingId) async {
    try {
      final response = await api.getJson('/api/v1/trips/$bookingId/driver');
      final data = response['data'];
      if (data is! Map) return null;
      return DriverReputation.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  /// Driver only. Returns null when the server declines — a driver seeing no
  /// passenger card is a smaller problem than a screen that fails to open.
  Future<PassengerStanding?> passenger(String bookingId) async {
    try {
      final response = await api.getJson('/api/v1/trips/$bookingId/passenger');
      final data = response['data'];
      if (data is! Map) return null;
      return PassengerStanding.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }
}
