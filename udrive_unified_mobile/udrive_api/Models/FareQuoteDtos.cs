using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

/// <summary>Ask the server what a trip should cost.</summary>
/// <remarks>
/// Distance and duration come from the client's route lookup rather than being
/// worked out here, because the server would otherwise need its own Directions
/// call on every vehicle card — the cost and the latency of which would be paid
/// on a screen people open constantly.
///
/// That makes them client-supplied numbers, and the engine treats them as
/// claims: it checks the distance against the straight line between the two
/// points before pricing anything, then signs the band it issued so it never
/// has to trust the same numbers twice.
/// </remarks>
public sealed record FareQuoteRequest(
    [Required, StringLength(40)] string ServiceType,
    [Required, StringLength(80)] string VehicleCategory,
    [Required, StringLength(32)] string BookingType,
    [Range(1, 60)] int Seats,
    [Range(-90, 90)] double PickupLatitude,
    [Range(-180, 180)] double PickupLongitude,
    [Range(-90, 90)] double DestinationLatitude,
    [Range(-180, 180)] double DestinationLongitude,
    [Range(0.01, 5000)] double DistanceKm,
    [Range(0, 6000)] double DurationMinutes);

/// <summary>Every number that went into the fare, in the order applied.</summary>
/// <remarks>
/// Returned to the app and shown to the customer and the driver on request.
/// A price a driver cannot have explained to him is a price he stops trusting,
/// and the platform's own defence against "why is this so low" is being able
/// to answer it.
/// </remarks>
public sealed record FareBreakdownDto(
    decimal BaseFare,
    decimal PerKmRate,
    decimal PerMinuteRate,
    double DistanceKm,
    double DurationMinutes,
    decimal DistanceCost,
    decimal TimeCost,
    decimal FuelFactor,
    string FuelType,
    decimal? FuelPricePerLitre,
    decimal ZoneFactor,
    string OriginZone,
    string DestinationZone,
    decimal ReturnShare,
    decimal ReturnCost,
    decimal Metered,
    decimal Floor,
    decimal Surge,
    string? SurgeReason,
    int? SeatCapacity,
    decimal? PerSeatFare);

/// <summary>What the customer may offer, and the proof the server said so.</summary>
public sealed record FareQuoteDto(
    Guid QuoteId,
    string QuoteToken,
    DateTimeOffset ExpiresAt,
    decimal Minimum,
    decimal Recommended,
    decimal Maximum,
    decimal Surge,
    bool Negotiable,
    string? FixedRouteLabel,
    string Currency,
    FareBreakdownDto Breakdown);

// ---------------------------------------------------------------- fuel

public sealed record FuelPriceDto(
    Guid Id,
    string FuelType,
    decimal PricePerLitre,
    DateOnly EffectiveFrom,
    string? Source,
    DateTimeOffset CreatedAt);

/// <summary>
/// The pump prices the current rate card was set against.
/// </summary>
/// <remarks>
/// Zero means fuel indexing is off for that fuel, which is how the platform
/// ships. Setting a baseline is the act that switches it on — from then on
/// every fare moves with the difference between it and today's price.
/// </remarks>
/// <param name="FactorMin">Floor on the index, from pricing.fuel.factor.min.</param>
/// <param name="FactorMax">Ceiling on the index, from pricing.fuel.factor.max.</param>
public sealed record FuelBaselinesDto(
    decimal Petrol,
    decimal Diesel,
    decimal FactorMin = 0.85m,
    decimal FactorMax = 1.25m);

public sealed record SaveFuelBaselinesRequest(
    [Range(0, 10000)] decimal Petrol,
    [Range(0, 10000)] decimal Diesel);

public sealed record SaveFuelPriceRequest(
    [Required, RegularExpression("^(Petrol|Diesel)$")] string FuelType,
    [Range(1, 10000)] decimal PricePerLitre,
    [Required] DateOnly EffectiveFrom,
    [StringLength(200)] string? Source);

// ---------------------------------------------------------------- zones

public sealed record PricingZoneDto(
    Guid? Id,
    string Name,
    decimal DifficultyFactor,
    decimal ReturnShare,
    bool SurgeEnabled);

public sealed record PricingZoneAreaDto(
    Guid? Id,
    string? Label,
    double Latitude,
    double Longitude,
    decimal RadiusKm);

public sealed record PricingZoneDetailDto(
    Guid Id,
    string Name,
    decimal DifficultyFactor,
    decimal ReturnShare,
    bool SurgeEnabled,
    IReadOnlyList<int>? ActiveMonths,
    int Priority,
    bool IsActive,
    string? Notes,
    IReadOnlyList<PricingZoneAreaDto> Areas);

public sealed record SaveZoneAreaRequest(
    [StringLength(120)] string? Label,
    [Range(-90, 90)] double Latitude,
    [Range(-180, 180)] double Longitude,
    [Range(0.1, 200)] decimal RadiusKm);

public sealed record SavePricingZoneRequest(
    Guid? Id,
    [Required, StringLength(120, MinimumLength = 2)] string Name,
    [Range(0.5, 4.0)] decimal DifficultyFactor,
    [Range(0.0, 1.0)] decimal ReturnShare,
    bool SurgeEnabled,
    IReadOnlyList<int>? ActiveMonths,
    [Range(-1000, 1000)] int Priority,
    bool IsActive,
    [StringLength(2000)] string? Notes,
    IReadOnlyList<SaveZoneAreaRequest> Areas);

// -------------------------------------------------------------- insights

/// <summary>
/// What a route is actually agreed at, against what the platform suggests.
/// </summary>
/// <remarks>
/// The whole learning loop, and it is a median and two counts — no model and
/// nothing to explain to a driver beyond the numbers themselves.
///
/// <paramref name="NoOfferRate"/> is the tell. A route where the suggested
/// fare is close to the agreed one but half the requests attract no offer at
/// all is a route priced below what a driver will get out of bed for.
/// </remarks>
public sealed record RouteInsightDto(
    string OriginZone,
    string DestinationZone,
    string VehicleCategory,
    int CompletedRides,
    int RequestsWithNoOffer,
    decimal NoOfferRate,
    decimal? MedianAgreedFare,
    decimal? MedianSuggestedFare,
    decimal? MedianFirstOfferSeconds,
    decimal? SuggestedChangePercent);
