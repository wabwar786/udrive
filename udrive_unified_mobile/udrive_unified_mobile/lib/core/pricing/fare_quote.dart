/// A fare the server worked out, and the proof it worked it out.
///
/// The app used to price trips itself, in two screens, differently. It now
/// asks, and what comes back is both the band the customer may offer within
/// and a signed token that the booking endpoint checks before it will accept
/// an offer at all.
///
/// The client still knows how to price a trip on its own — see
/// `VehicleOptionsRepository` — and still does so while a quote is in flight,
/// so the vehicle pills are never blank. That local figure is a placeholder,
/// never an authority: the customer cannot send a ride request against it.
class FareQuote {
  const FareQuote({
    required this.quoteId,
    required this.token,
    required this.expiresAt,
    required this.minimum,
    required this.recommended,
    required this.maximum,
    required this.surge,
    required this.negotiable,
    required this.currency,
    this.fixedRouteLabel,
    this.breakdown,
  });

  final String quoteId;
  final String token;
  final DateTime expiresAt;

  /// The lowest the customer may offer. The driver is held to the same figure.
  final int minimum;

  /// What the fare box opens at.
  final int recommended;

  /// A guard against a mistyped amount, not a limit on generosity.
  final int maximum;

  /// 1.0 unless the pickup area is short of drivers.
  final double surge;

  /// False for a published fixed-route fare, which is not bid on.
  final bool negotiable;

  final String currency;

  /// Set when a published route fare applies, e.g. "Muzaffarabad → Keran".
  final String? fixedRouteLabel;

  final FareBreakdown? breakdown;

  bool get hasSurge => surge > 1.0;

  /// Quotes expire so a stale one cannot be spent after a rate change. A
  /// minute of headroom keeps a quote that is about to lapse from being
  /// offered to the customer only to be refused on the next screen.
  bool get isUsable => DateTime.now().isBefore(
        expiresAt.subtract(const Duration(minutes: 1)),
      );

  factory FareQuote.fromJson(Map<String, dynamic> json) => FareQuote(
        quoteId: '${json['quoteId'] ?? ''}',
        token: '${json['quoteToken'] ?? ''}',
        expiresAt: DateTime.tryParse('${json['expiresAt'] ?? ''}')?.toLocal() ??
            DateTime.now().add(const Duration(minutes: 15)),
        minimum: (json['minimum'] as num?)?.round() ?? 0,
        recommended: (json['recommended'] as num?)?.round() ?? 0,
        // Falls back to the recommendation rather than zero: a band whose
        // ceiling is below its floor makes clamp() throw, and a truncated
        // payload should not be able to crash a button.
        maximum: (json['maximum'] as num?)?.round() ??
            (json['recommended'] as num?)?.round() ??
            0,
        surge: (json['surge'] as num?)?.toDouble() ?? 1.0,
        negotiable: json['negotiable'] as bool? ?? true,
        currency: '${json['currency'] ?? 'PKR'}',
        fixedRouteLabel: _trimmedOrNull(json['fixedRouteLabel']),
        breakdown: json['breakdown'] is Map
            ? FareBreakdown.fromJson(
                Map<String, dynamic>.from(json['breakdown'] as Map))
            : null,
      );
}

/// Every number that went into the fare, in the order applied.
///
/// Shown to the customer behind a tap and to the driver on the request card.
/// A price a driver cannot have explained to him is one he stops trusting, and
/// "why is this so low" deserves an answer with figures in it.
class FareBreakdown {
  const FareBreakdown({
    required this.baseFare,
    required this.perKmRate,
    required this.perMinuteRate,
    required this.distanceKm,
    required this.durationMinutes,
    required this.distanceCost,
    required this.timeCost,
    required this.fuelFactor,
    required this.fuelType,
    required this.zoneFactor,
    required this.originZone,
    required this.destinationZone,
    required this.returnShare,
    required this.returnCost,
    required this.surge,
    this.fuelPricePerLitre,
    this.surgeReason,
    this.seatCapacity,
    this.perSeatFare,
  });

  final int baseFare;
  final int perKmRate;
  final int perMinuteRate;
  final double distanceKm;
  final double durationMinutes;
  final int distanceCost;
  final int timeCost;
  final double fuelFactor;
  final String fuelType;
  final double? fuelPricePerLitre;
  final double zoneFactor;
  final String originZone;
  final String destinationZone;
  final double returnShare;
  final int returnCost;
  final double surge;
  final String? surgeReason;
  final int? seatCapacity;
  final int? perSeatFare;

  bool get hasTerrain => zoneFactor > 1.0;
  bool get hasReturn => returnCost > 0;
  bool get hasFuelAdjustment => (fuelFactor - 1.0).abs() > 0.001;

  factory FareBreakdown.fromJson(Map<String, dynamic> json) => FareBreakdown(
        baseFare: (json['baseFare'] as num?)?.round() ?? 0,
        perKmRate: (json['perKmRate'] as num?)?.round() ?? 0,
        perMinuteRate: (json['perMinuteRate'] as num?)?.round() ?? 0,
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
        durationMinutes: (json['durationMinutes'] as num?)?.toDouble() ?? 0,
        distanceCost: (json['distanceCost'] as num?)?.round() ?? 0,
        timeCost: (json['timeCost'] as num?)?.round() ?? 0,
        fuelFactor: (json['fuelFactor'] as num?)?.toDouble() ?? 1.0,
        fuelType: '${json['fuelType'] ?? 'Petrol'}',
        fuelPricePerLitre: (json['fuelPricePerLitre'] as num?)?.toDouble(),
        zoneFactor: (json['zoneFactor'] as num?)?.toDouble() ?? 1.0,
        originZone: '${json['originZone'] ?? ''}',
        destinationZone: '${json['destinationZone'] ?? ''}',
        returnShare: (json['returnShare'] as num?)?.toDouble() ?? 0,
        returnCost: (json['returnCost'] as num?)?.round() ?? 0,
        surge: (json['surge'] as num?)?.toDouble() ?? 1.0,
        surgeReason: _trimmedOrNull(json['surgeReason']),
        seatCapacity: (json['seatCapacity'] as num?)?.round(),
        perSeatFare: (json['perSeatFare'] as num?)?.round(),
      );
}

String? _trimmedOrNull(Object? value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? null : text;
}
