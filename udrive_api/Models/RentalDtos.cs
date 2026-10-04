using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

/// <summary>One rentable vehicle as the Customer's list shows it.</summary>
/// <param name="PhotoUrl">
/// The owner's own photograph of this car. Never a stock picture of the model:
/// renting is a decision about one specific vehicle, and a showroom photograph
/// of a different car in a different colour is not information, it is a
/// misleading advertisement.
/// </param>
/// <param name="WithDriverDaily">Null when this owner does not offer it.</param>
/// <param name="SelfDriveDaily">Null when this owner does not offer it.</param>
public sealed record RentalVehicleDto(
    Guid VehicleId,
    string Name,
    string Category,
    string RegistrationNumber,
    string Colour,
    int Year,
    int PassengerCapacity,
    int LuggageCapacity,
    string? PhotoUrl,
    decimal? WithDriverDaily,
    decimal? SelfDriveDaily,
    decimal SecurityDeposit,
    int MinimumDays,
    int? KmPerDay,
    bool FuelIncluded,
    string? PickupPoint,
    string OwnerName,
    decimal OwnerRating,
    bool HasAirConditioning,
    bool IsFourByFour,
    bool IsDemo = false);

/// <summary>A day this vehicle cannot be rented, and why.</summary>
/// <param name="Reason">
/// <c>rented</c>, <c>turnaround</c>, <c>tour</c> or <c>trip</c>. The Customer's
/// calendar only greys the day out; the Driver's own calendar shows the word,
/// because they are the one who needs to know which of their own commitments is
/// in the way.
/// </param>
public sealed record RentalBlockedDayDto(DateOnly Date, string Reason);

/// <summary>What a given set of dates would cost, before anyone commits.</summary>
/// <param name="AdvanceAmount">
/// Paid through the platform now. The rest is cash to the owner at handover,
/// together with the deposit — UDrive never holds the deposit.
/// </param>
public sealed record RentalQuoteDto(
    Guid VehicleId,
    DateOnly StartDate,
    DateOnly EndDate,
    string RentalMode,
    int Days,
    decimal DailyRate,
    decimal Subtotal,
    decimal SecurityDeposit,
    decimal AdvanceAmount,
    decimal BalanceDue,
    int? KmIncluded,
    bool FuelIncluded,
    int DisclaimerVersion,
    bool RequiresCustomerDocuments,
    bool CustomerDocumentsOnFile);

public sealed record RentalQuoteRequest(
    [Required] DateOnly StartDate,
    [Required] DateOnly EndDate,
    [Required, StringLength(16)] string RentalMode);

/// <param name="AcceptedDisclaimerVersion">
/// Which version of the disclaimer the Customer ticked. Sent back rather than
/// assumed, so a booking made against an older text in an older app build is
/// recorded as what it was.
/// </param>
public sealed record CreateRentalBookingRequest(
    [Required] Guid VehicleId,
    [Required] DateOnly StartDate,
    [Required] DateOnly EndDate,
    [Required, StringLength(16)] string RentalMode,
    [Required] int AcceptedDisclaimerVersion);

public sealed record RentalBookingDto(
    Guid Id,
    string BookingReference,
    Guid VehicleId,
    string VehicleName,
    string RegistrationNumber,
    string? PhotoUrl,
    DateOnly StartDate,
    DateOnly EndDate,
    string RentalMode,
    int Days,
    decimal DailyRate,
    decimal Subtotal,
    decimal SecurityDeposit,
    decimal AdvanceAmount,
    decimal BalanceDue,
    int? KmPerDay,
    bool FuelIncluded,
    string? PickupPoint,
    string Status,
    string CounterpartName,
    string? CounterpartPhone,
    DateTimeOffset CreatedAt,
    DateTimeOffset? CancelledAt,
    string? CancelReason,

    /// <summary>
    /// Whether cancelling right now still returns the advance.
    /// </summary>
    /// <remarks>
    /// Computed and sent rather than left to the app to work out from a
    /// settings value it would have to fetch separately and could get wrong.
    /// The Customer sees the answer, not the rule.
    /// </remarks>
    bool AdvanceRefundableNow);

public sealed record CancelRentalRequest([StringLength(500)] string? Reason);

/// <summary>The Customer's own identity documents, held once.</summary>
/// <remarks>
/// Only self-drive needs them, and nobody at UDrive reviews them. The person
/// handing over the car checks them against the person standing in front of
/// them, which is the only check that proves anything.
/// </remarks>
public sealed record CustomerDocumentsDto(
    bool CnicFront,
    bool CnicBack,
    bool DrivingLicence,
    bool Selfie,
    bool Complete,
    DateTimeOffset? UpdatedAt);

// ────────────────────────────────────────────────────── the admin's side

/// <summary>The four numbers at the top of the admin rental page.</summary>
/// <param name="AdvanceThisMonth">
/// Only the advance. The balance and the deposit never reach the platform, so
/// counting them as revenue would be a fiction an Admin might act on.
/// </param>
public sealed record AdminRentalSummaryDto(
    int CarsOutNow,
    int SelfDriveOutNow,
    int WithDriverOutNow,
    int StartingThisWeek,
    int HandoversToday,
    decimal AdvanceThisMonth,
    int CancellationsLast30Days);

public sealed record AdminRentalRowDto(
    Guid Id,
    string BookingReference,
    string RentalMode,
    string VehicleName,
    string RegistrationNumber,
    string CustomerName,
    string? CustomerPhone,
    string OwnerName,
    string? OwnerPhone,
    DateOnly StartDate,
    DateOnly EndDate,
    int Days,
    decimal AdvanceAmount,
    decimal BalanceDue,
    decimal SecurityDeposit,
    string Status,
    string? CancelledBy,
    DateTimeOffset CreatedAt);

/// <param name="CnicFront">
/// Whether it was provided — never the picture. An Admin looking at a CNIC
/// would make the platform a party to a check its own disclaimer says it does
/// not perform, and the check that matters is the owner holding the card next
/// to the face in front of them.
/// </param>
public sealed record AdminRentalDetailDto(
    Guid Id,
    string BookingReference,
    string RentalMode,
    string VehicleName,
    string RegistrationNumber,
    string CustomerName,
    string? CustomerPhone,
    string OwnerName,
    string? OwnerPhone,
    DateOnly StartDate,
    DateOnly EndDate,
    int Days,
    decimal DailyRate,
    decimal Subtotal,
    decimal AdvanceAmount,
    decimal BalanceDue,
    decimal SecurityDeposit,
    int? KmPerDay,
    bool FuelIncluded,
    string? PickupPoint,
    string Status,
    string? CancelledBy,
    DateTimeOffset? CancelledAt,
    string? CancelReason,
    int DisclaimerVersion,
    DateTimeOffset DisclaimerAcceptedAt,
    DateTimeOffset CreatedAt,
    bool CnicFront,
    bool CnicBack,
    bool DrivingLicence,
    bool Selfie);

/// <param name="HiddenReason">
/// Why this vehicle is not in the customer's rental list, in words a support
/// agent can repeat down the phone. Null when it is listed.
/// </param>
public sealed record AdminRentalVehicleDto(
    Guid VehicleId,
    string Name,
    string RegistrationNumber,
    string OwnerName,
    string? OwnerPhone,
    decimal? WithDriverDaily,
    decimal? SelfDriveDaily,
    decimal SecurityDeposit,
    int MinimumDays,
    bool HasPhoto,
    int BookingCount,
    bool Listed,
    string? HiddenReason);

public sealed record AdminRentalSettingsDto(
    int AdvancePercent,
    int FreeCancelHours,
    int MaximumDeposit,
    int DisclaimerVersion,
    string DisclaimerTextEn,
    string DisclaimerTextUr);

/// <remarks>
/// The version is not in here. It moves by itself when the text changes —
/// leaving it to the Admin means the day somebody edits the wording and forgets
/// the number, every later booking points at a version whose text no longer
/// exists, and the acceptance record becomes worthless.
/// </remarks>
public sealed record AdminRentalSettingsRequest(
    int AdvancePercent,
    int FreeCancelHours,
    int MaximumDeposit,
    string DisclaimerTextEn,
    string? DisclaimerTextUr);

public sealed record AdminCancelRentalRequest(string? Reason);
