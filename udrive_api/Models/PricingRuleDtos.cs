using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

/// <summary>A pricing rule as the admin portal sees it.</summary>
/// <param name="DaysOfWeek">
/// ISO days, 1 = Monday … 7 = Sunday. Empty means every day.
/// </param>
/// <param name="AreaRadiusKm">
/// Null together with the coordinates means the rule applies everywhere.
/// </param>
public sealed record PricingRuleDto(
    Guid Id,
    string Name,
    string ServiceType,
    string VehicleCategory,
    decimal PerKmRate,
    decimal MinimumFare,
    decimal PerMinuteRate,
    IReadOnlyList<int> DaysOfWeek,
    string? AreaLabel,
    double? AreaLatitude,
    double? AreaLongitude,
    double? AreaRadiusKm,
    int Priority,
    bool IsActive,
    DateTimeOffset UpdatedAt);

/// <summary>Create or update a pricing rule.</summary>
public sealed record UpsertPricingRuleRequest(
    [Required, StringLength(120, MinimumLength = 2)] string Name,
    [Required, StringLength(40)] string ServiceType,
    [Required, StringLength(40)] string VehicleCategory,
    [Range(0.01, 100000)] decimal PerKmRate,
    [Range(0, 1000000)] decimal MinimumFare,
    [Range(0, 10000)] decimal PerMinuteRate,
    IReadOnlyList<int>? DaysOfWeek,
    [StringLength(160)] string? AreaLabel,
    [Range(-90, 90)] double? AreaLatitude,
    [Range(-180, 180)] double? AreaLongitude,
    [Range(0.1, 500)] double? AreaRadiusKm,
    [Range(-1000, 1000)] int Priority = 0,
    bool IsActive = true);

/// <summary>
/// What a rule would charge for a given trip, so the admin can check a change
/// before saving it rather than by booking a ride.
/// </summary>
public sealed record PricingPreviewDto(
    string VehicleCategory,
    string? MatchedRuleName,
    decimal PerKmRate,
    decimal MinimumFare,
    decimal PerMinuteRate,
    decimal Fare);

/// <summary>A driver's own asking price for touring, per vehicle.</summary>
/// <remarks>
/// Separate from <c>VehicleUpsertRequest</c> on purpose. That request is locked
/// once a vehicle is verified, because changing a registration number or seat
/// count after approval would invalidate the approval. A price is commercial,
/// not compliance — a driver has to be able to change it on a Tuesday without
/// asking anyone.
/// </remarks>
public sealed record TourRateDto(
    Guid VehicleId,
    string Category,
    string Label,
    bool AvailableForTour,
    decimal? PerDayRate,
    decimal? PerKmRate,
    decimal? MinimumFare,
    string? Notes);

public sealed record UpsertTourRateRequest(
    [Range(0, 1000000)] decimal? PerDayRate,
    [Range(0, 100000)] decimal? PerKmRate,
    [Range(0, 1000000)] decimal? MinimumFare,
    [StringLength(400)] string? Notes,
    bool AvailableForTour = true);

/// <summary>
/// What tour vehicles around a customer are asking, by category.
/// </summary>
/// <remarks>
/// A range rather than one number, because there is no single right answer —
/// each driver sets their own. It exists so a customer naming an offer has some
/// idea what drivers actually charge, instead of guessing into silence.
/// </remarks>
public sealed record TourRateGuideDto(
    string Category,
    int VehicleCount,
    decimal LowestPerDay,
    decimal TypicalPerDay,
    decimal HighestPerDay);

/// <summary>A fixed per-seat fare for one route.</summary>
public sealed record SeatFareDto(
    Guid Id,
    string VehicleCategory,
    string OriginLabel,
    double OriginLatitude,
    double OriginLongitude,
    double OriginRadiusKm,
    string DestinationLabel,
    double DestinationLatitude,
    double DestinationLongitude,
    double DestinationRadiusKm,
    decimal PerSeatFare,
    bool AppliesBothWays,
    string? Notes,
    bool IsActive,
    DateTimeOffset UpdatedAt);

public sealed record UpsertSeatFareRequest(
    [Required, StringLength(40)] string VehicleCategory,
    [Required, StringLength(160)] string OriginLabel,
    [Range(-90, 90)] double OriginLatitude,
    [Range(-180, 180)] double OriginLongitude,
    [Range(0.5, 200)] double OriginRadiusKm,
    [Required, StringLength(160)] string DestinationLabel,
    [Range(-90, 90)] double DestinationLatitude,
    [Range(-180, 180)] double DestinationLongitude,
    [Range(0.5, 200)] double DestinationRadiusKm,
    [Range(1, 1000000)] decimal PerSeatFare,
    bool AppliesBothWays = true,
    [StringLength(400)] string? Notes = null,
    bool IsActive = true);

/// <summary>
/// The fixed fare that applies to a trip, when one does.
/// </summary>
/// <param name="Reversed">
/// True when the match was the return leg of a both-ways route. Shown to the
/// customer so the named route reads the way they are actually travelling.
/// </param>
public sealed record SeatFareQuoteDto(
    Guid Id,
    string VehicleCategory,
    string OriginLabel,
    string DestinationLabel,
    decimal PerSeatFare,
    bool Reversed,
    string? Notes);

/// <summary>One message on a booking.</summary>
public sealed record TripMessageDto(
    Guid Id,
    Guid SenderUserId,
    string SenderRole,
    string SenderName,
    string Body,
    DateTimeOffset? ReadAt,
    DateTimeOffset CreatedAt);

public sealed record SendTripMessageRequest(
    [Required, StringLength(1000, MinimumLength = 1)] string Body);

/// <summary>
/// What a Driver can know about the passenger before they meet.
/// </summary>
/// <param name="Rating">
/// Null when no Driver has ever rated this Customer. Deliberately not defaulted
/// to five — a reassurance nobody earned is worse than no reassurance.
/// </param>
/// <param name="Standing">One of New, Regular, Trusted or Mixed.</param>
public sealed record PassengerStandingDto(
    string FullName,
    DateTimeOffset MemberSince,
    int CompletedTrips,
    int CancelledTrips,
    decimal? Rating,
    int RatingCount,
    string Standing);

/// <summary>A raised fare for a request that is still searching.</summary>
public sealed record RaiseFareRequest([Range(1, 1000000)] decimal CustomerOffer);

/// <summary>One published review of a Driver, written by a Customer.</summary>
public sealed record DriverReviewDto(
    int Rating,
    string? Text,
    string ReviewerFirstName,
    DateTimeOffset CreatedAt);

/// <summary>
/// What the Customer waiting for this Driver can see about them.
/// </summary>
/// <param name="Rating">
/// Null when no Customer has rated this Driver. Not defaulted to five: a score
/// nobody gave is worse than an honest blank.
/// </param>
public sealed record DriverReputationDto(
    string DriverName,
    decimal? Rating,
    int RatingCount,
    int CompletedTrips,
    IReadOnlyList<DriverReviewDto> RecentReviews);

/// <summary>
/// Everything a Driver's own dashboard shows about them.
/// </summary>
/// <remarks>
/// One call, because it is one screen. Four round trips for four numbers on the
/// first screen a Driver opens is four chances to show a half-loaded dashboard.
/// </remarks>
public sealed record DriverDashboardDto(
    string FullName,
    string VerificationStatus,
    decimal? Rating,
    int RatingCount,
    int CompletedTrips,
    decimal EarnedToday,
    decimal EarnedThisMonth,
    int TripsToday,
    IReadOnlyList<DriverReviewDto> RecentReviews);

/// <summary>A payment a Driver says they have sent the company.</summary>
/// <param name="DriverName">Only filled for the Admin queue.</param>
public sealed record WalletTopupDto(
    Guid Id,
    string? DriverName,
    decimal Amount,
    string Method,
    string? SenderReference,
    string Status,
    string? AdminNotes,
    DateTimeOffset CreatedAt,
    DateTimeOffset? ReviewedAt);

/// <summary>One commission charge against the prepaid balance.</summary>
public sealed record WalletChargeDto(
    decimal Amount,
    string Description,
    DateTimeOffset CreatedAt);

/// <summary>
/// The Driver's prepaid commission balance.
/// </summary>
/// <param name="CanReceiveRides">
/// False once the balance is at or below the platform minimum. Computed here so
/// the app never has to reimplement the rule and get a different answer.
/// </param>
public sealed record DriverCommissionWalletDto(
    decimal Balance,
    decimal MinimumBalance,
    decimal CommissionPercentage,
    bool CanReceiveRides,
    IReadOnlyList<WalletTopupDto> Topups,
    IReadOnlyList<WalletChargeDto> RecentCharges);

public sealed record SubmitTopupRequest(
    [Range(1, 1000000)] decimal Amount,
    [StringLength(120)] string? SenderReference);

public sealed record ReviewTopupRequest(
    bool Approve,
    [StringLength(400)] string? Notes);

/// <summary>Asks a Driver to send one document again.</summary>
public sealed record RequestReuploadRequest([StringLength(300)] string? Reason);

/// <summary>A document an Admin has asked the Driver to send again.</summary>
/// <param name="Scope">'Driver' or 'Vehicle'.</param>
/// <param name="RidesSince">Rides completed since the request was made.</param>
/// <param name="RidesRemaining">
/// How many more rides they may take before requests stop. Zero means stopped.
/// </param>
public sealed record PendingDocumentDto(
    string DocumentType,
    string? Reason,
    string Scope,
    int RidesSince,
    int RidesRemaining);
