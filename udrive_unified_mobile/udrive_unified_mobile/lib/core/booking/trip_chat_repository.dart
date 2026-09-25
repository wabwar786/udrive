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

/// The driver's own headline figures, for their dashboard.
class DriverDashboard {
  const DriverDashboard({
    required this.fullName,
    required this.verificationStatus,
    required this.ratingCount,
    required this.completedTrips,
    required this.earnedToday,
    required this.earnedThisMonth,
    required this.tripsToday,
    required this.recentReviews,
    this.rating,
  });

  final String fullName;
  final String verificationStatus;

  /// Null until a customer has rated this driver.
  final double? rating;

  final int ratingCount;
  final int completedTrips;

  /// Counted in Pakistan time. A driver finishing at 2am wants that fare in
  /// today, and a UTC boundary would move it five hours early.
  final double earnedToday;
  final double earnedThisMonth;
  final int tripsToday;

  final List<DriverReview> recentReviews;

  factory DriverDashboard.fromJson(Map<String, dynamic> json) => DriverDashboard(
        fullName: '${json['fullName'] ?? ''}',
        verificationStatus: '${json['verificationStatus'] ?? 'Draft'}',
        rating: (json['rating'] as num?)?.toDouble(),
        ratingCount: (json['ratingCount'] as num?)?.toInt() ?? 0,
        completedTrips: (json['completedTrips'] as num?)?.toInt() ?? 0,
        earnedToday: (json['earnedToday'] as num?)?.toDouble() ?? 0,
        earnedThisMonth: (json['earnedThisMonth'] as num?)?.toDouble() ?? 0,
        tripsToday: (json['tripsToday'] as num?)?.toInt() ?? 0,
        recentReviews: (json['recentReviews'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => DriverReview.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
      );
}

/// A document an admin has asked the driver to send again.
class PendingDocument {
  const PendingDocument({
    required this.documentType,
    required this.scope,
    required this.ridesRemaining,
    this.reason,
  });

  /// The API's own type string, e.g. `CNIC_FRONT` or `VEHICLE_FRONT`.
  final String documentType;

  /// 'Driver' or 'Vehicle'.
  final String scope;

  /// How many more rides may be taken before requests stop. Zero means stopped.
  final int ridesRemaining;

  final String? reason;

  /// The type as a person would say it: `CNIC_FRONT` → `Cnic front`.
  String get label {
    final words = documentType.toLowerCase().replaceAll('_', ' ').trim();
    if (words.isEmpty) return 'Document';
    return words[0].toUpperCase() + words.substring(1);
  }

  factory PendingDocument.fromJson(Map<String, dynamic> json) => PendingDocument(
        documentType: '${json['documentType'] ?? ''}',
        scope: '${json['scope'] ?? 'Driver'}',
        ridesRemaining: (json['ridesRemaining'] as num?)?.toInt() ?? 0,
        reason: '${json['reason'] ?? ''}'.trim().isEmpty
            ? null
            : '${json['reason']}'.trim(),
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

  /// Documents the driver has been asked to send again.
  ///
  /// Empty on failure. A dashboard that loses this strip is still usable; one
  /// that refuses to load because of it is not.
  Future<List<PendingDocument>> pendingDocuments() async {
    try {
      final response = await api.getJson('/api/v1/driver/pending-documents');
      final data = response['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((item) => PendingDocument.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// The signed-in driver's own dashboard figures.
  ///
  /// Returns null rather than throwing: a dashboard that loses its stats strip
  /// is still a working dashboard, and a driver waiting for a ride should not
  /// be shown an error screen because one figure failed to load.
  Future<DriverDashboard?> driverDashboard() async {
    try {
      final response = await api.getJson('/api/v1/driver/dashboard');
      final data = response['data'];
      if (data is! Map) return null;
      return DriverDashboard.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
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
