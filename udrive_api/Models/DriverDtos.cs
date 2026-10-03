using System.ComponentModel.DataAnnotations;
using UDrive.Api.Domain;

namespace UDrive.Api.Models;

public sealed record DriverOnboardingRequest(
    [Required, StringLength(160)] string FullName,
    [Required, StringLength(32)] string CnicNumber,
    [Required, StringLength(64)] string DrivingLicenceNumber,
    /// <summary>When the licence runs out.</summary>
    /// <remarks>
    /// Collected because a driver whose licence has expired should stop
    /// receiving work, and until this was stored nothing could tell.
    /// </remarks>
    DateOnly? DrivingLicenceExpiry,
    DateOnly? DateOfBirth,
    /// <summary>Home address, and who to call if something happens.</summary>
    /// <remarks>
    /// Optional, and that is a change. They were `[Required]`, which meant the
    /// four-step sign-up — which does not ask for them — could not submit at
    /// all: sending empty strings fails `[Required]` just as null does.
    ///
    /// Making them optional is the honest fix rather than inventing values to
    /// satisfy the attribute. The columns were always nullable; only the
    /// request insisted. They are collected in profile settings, and a driver
    /// cannot be approved without a reviewer seeing the profile anyway.
    /// </remarks>
    [StringLength(600)] string? Address,
    [StringLength(120)] string? EmergencyContactName,
    [StringLength(24)] string? EmergencyContactPhone,
    [StringLength(120)] string? BankAccountTitle,
    [StringLength(40)] string? PayoutMethod,
    [StringLength(80)] string? PayoutAccount,
    string[]? Languages,
    string[]? ServiceAreas);

public sealed record DriverOnboardingDto(
    Guid DriverProfileId,
    string VerificationStatus,
    string? CnicMasked,
    string? DrivingLicenceMasked,
    DateOnly? DateOfBirth,
    string? Address,
    string? EmergencyContactName,
    string? EmergencyContactPhone,
    string? BankAccountTitle,
    string? PayoutMethod,
    string? PayoutAccountMasked,
    IReadOnlyList<string> Languages,
    IReadOnlyList<string> ServiceAreas,
    DateTimeOffset? SubmittedAt,
    DateTimeOffset? ReviewedAt,
    string? ReviewNotes);

public sealed record DriverDocumentDto(
    Guid Id,
    string DocumentType,
    string FileUrl,
    DateOnly? ExpiryDate,
    string Status,
    string? ReviewNotes);

public sealed record VehicleUpsertRequest(
    [Required, StringLength(48)] string Category,
    [Required, StringLength(64)] string Make,
    [Required, StringLength(64)] string Model,
    [Range(1980, 2100)] int Year,
    [Required, StringLength(40)] string RegistrationNumber,
    [Required, StringLength(40)] string Colour,
    [Range(1, 60)] int PassengerCapacity,
    [Range(0, 100)] int LuggageCapacity,
    bool HasAirConditioning,
    bool HasHeating,
    bool IsFourByFour,
    bool HasFirstAidKit,
    bool HasFireExtinguisher,
    bool HasSpareTyre,
    bool HasSnowChains,
    bool HasChildSeat);

public sealed record VehicleDto(
    Guid Id,
    string Category,
    string Make,
    string Model,
    int Year,
    string RegistrationNumber,
    string Colour,
    int PassengerCapacity,
    int LuggageCapacity,
    bool HasAirConditioning,
    bool HasHeating,
    bool IsFourByFour,
    bool HasFirstAidKit,
    bool HasFireExtinguisher,
    bool HasSpareTyre,
    bool HasSnowChains,
    bool HasChildSeat,
    int MountainReadinessScore,
    string Status,
    string? ImageUrl,
    IReadOnlyList<VehicleDocumentDto> Documents,

    /// <summary>The score this vehicle must reach to carry a tour package.</summary>
    /// <remarks>
    /// Sent with the vehicle so the Driver's screen can show "45 / 60" without
    /// the app carrying a copy of the number. It is an Admin setting, so a copy
    /// in the app would be wrong the day it changed.
    /// </remarks>
    int TourReadinessRequired = TourReadiness.DefaultMinimum,

    /// <summary>The second gate: the Driver's own switch for this vehicle.</summary>
    /// <remarks>
    /// Score and switch are separate, and both must pass. A Driver whose
    /// vehicle scored 82 and still could not be picked for a package had hit
    /// this one, with nothing on screen mentioning it existed.
    /// </remarks>
    bool AvailableForTour = false,

    /// <summary>
    /// Every item that counts towards the score, whether this vehicle has it,
    /// and what it is worth.
    /// </summary>
    /// <remarks>
    /// Sent rather than computed in the app, so the weights live in one place.
    /// An app that scored vehicles itself would disagree with the server the
    /// first time a weight changed, and the Driver would be told they qualify
    /// by one screen and refused by the next.
    /// </remarks>
    IReadOnlyList<TourReadinessItemDto>? TourReadinessItems = null,

    /// <summary>
    /// The cheapest missing items that would reach the bar — empty when the
    /// vehicle already does.
    /// </summary>
    IReadOnlyList<TourReadinessItemDto>? TourReadinessMissing = null);

/// <param name="Points">What it adds to the score.</param>
/// <param name="Present">Whether this vehicle has it.</param>
public sealed record TourReadinessItemDto(
    string Key,
    string Label,
    int Points,
    bool Present);

public sealed record VehicleDocumentDto(
    Guid Id,
    string DocumentType,
    string FileUrl,
    DateOnly? ExpiryDate,
    string Status,
    string? ReviewNotes);

/// <param name="LaunchCityId">
/// Which launch city this driver belongs to, set when they are approved.
/// <para>
/// Nothing in the API ever wrote driver_profiles.launch_city_id, so every
/// driver had none — and the whole rewards engine reaches a driver only
/// through their city: no city, no campaigns loaded, no progress measured,
/// nothing ever paid. Founding numbers are per city too, so those could not be
/// granted either. The entire Driver Growth system was inert for want of this
/// one column.
/// </para>
/// <para>
/// Optional. Left out, the city is inferred — from the driver's own service
/// area if it names an active city, otherwise from the single active city if
/// the business is only running one. Sent explicitly, it wins, which is how an
/// admin says "I am opening Rawalakot, approve this driver into Rawalakot".
/// </para>
/// </param>
public sealed record VerificationReviewRequest(
    [Required, StringLength(32)] string Decision,
    [StringLength(1000)] string? Notes,
    bool DeleteAttachments = false,
    Guid? LaunchCityId = null);

public sealed record DeleteVerificationEntityRequest(
    [Required, StringLength(1000, MinimumLength = 3)] string Reason);

public sealed record DriverReviewListItemDto(
    Guid DriverProfileId,
    Guid UserId,
    string FullName,
    string PhoneNumber,
    string VerificationStatus,
    string? CnicMasked,
    string? DrivingLicenceMasked,
    DateTimeOffset? SubmittedAt,
    int DocumentCount,
    int VehicleCount);

public sealed record VehicleReviewListItemDto(
    Guid VehicleId,
    Guid DriverProfileId,
    string DriverName,
    string RegistrationNumber,
    string Vehicle,
    string Status,
    int MountainReadinessScore,
    int DocumentCount);

public sealed record DriverReviewDetailDto(
    DriverReviewListItemDto Driver,
    DriverOnboardingDto Profile,
    IReadOnlyList<DriverDocumentDto> Documents,
    IReadOnlyList<VehicleReviewListItemDto> Vehicles);

public sealed record VehicleReviewDetailDto(
    VehicleReviewListItemDto Vehicle,
    IReadOnlyList<VehicleDocumentDto> Documents);


// ─────────────────────────────────────────────── what a vehicle is used for

/// <summary>One approved vehicle and the three things it may be used for.</summary>
/// <remarks>
/// This is not registration. The vehicle already exists and an Admin has
/// already verified it; there is one way onto the platform and it has not
/// changed. What this carries is the step after that — city rides, tours,
/// rent — together with everything a Driver needs on screen to understand why
/// a switch will or will not move.
/// </remarks>
/// <param name="LivePackageCount">
/// Active packages departing in the future. Tour needs at least one, and the
/// count is sent so the screen can say "no package yet" instead of leaving the
/// Driver to find out at save time.
/// </param>
public sealed record VehicleUsageDto(
    Guid VehicleId,
    string Name,
    string RegistrationNumber,
    string Status,

    /// <summary>Takes ordinary city ride requests.</summary>
    /// <remarks>
    /// On for every vehicle that exists today, because that is what a verified
    /// vehicle has always done. Turning rent on turns this off; the two cannot
    /// both be true, and the database says so as well.
    /// </remarks>
    bool AvailableForCity,

    /// <summary>Carries tour packages.</summary>
    /// <remarks>
    /// Needs readiness *and* a package, and it stays in the city pool: a tour
    /// vehicle is still a vehicle on the road between departures.
    /// </remarks>
    bool AvailableForTour,

    /// <summary>Goes out on rent, by the day.</summary>
    /// <remarks>
    /// Needs a rate. Costs the vehicle its city requests, because a car on rent
    /// is with somebody else and cannot pick anyone up.
    /// </remarks>
    bool AvailableForRent,

    int TourReadinessScore,
    int TourReadinessRequired,

    /// <summary>The cheapest missing equipment that would reach the bar.</summary>
    IReadOnlyList<TourReadinessItemDto> TourReadinessMissing,

    int LivePackageCount,

    decimal? RentWithDriverDaily,
    decimal? RentSelfDriveDaily,
    decimal? RentSecurityDeposit,
    int RentMinimumDays,
    int? RentKmPerDay,
    bool RentFuelIncluded,
    string? RentPickupPoint,

    /// <summary>The owner's own photograph of this vehicle, if there is one.</summary>
    /// <remarks>
    /// Required before renting can be switched on. A rental listing is a
    /// decision about one specific car, and a list of names and prices is a
    /// list nobody books from — while the only picture the platform could
    /// otherwise show is a stock photograph of the model, which is a different
    /// car in a different colour.
    /// </remarks>
    string? PhotoUrl = null)
{
    /// <summary>Whether tour could be switched on right now.</summary>
    public bool CanCarryTour =>
        TourReadinessScore >= TourReadinessRequired && LivePackageCount > 0;

    /// <summary>Whether rent could be switched on right now.</summary>
    public bool CanBeRented =>
        (RentWithDriverDaily is > 0 || RentSelfDriveDaily is > 0)
        && !string.IsNullOrWhiteSpace(PhotoUrl);
}

/// <summary>A switch the Driver moved. Null means "leave this one alone".</summary>
/// <remarks>
/// Every field is nullable so the app can send one switch rather than the
/// whole set. Sending all three would make two screens race: the Driver turns
/// rent on from one, and a stale copy of the other turns it back off.
/// </remarks>
public sealed record VehicleUsageRequest(
    bool? AvailableForCity = null,
    bool? AvailableForTour = null,
    bool? AvailableForRent = null);

/// <summary>What renting this vehicle costs and requires.</summary>
/// <param name="WithDriverDaily">
/// Per day with the owner's own driver. No customer documents are needed on
/// this path — nobody hands the car over.
/// </param>
/// <param name="SelfDriveDaily">
/// Per day with the customer driving. At least one of the two rates must be
/// set; leaving one empty means that option is not offered.
/// </param>
public sealed record VehicleRentSettingsRequest(
    decimal? WithDriverDaily,
    decimal? SelfDriveDaily,
    decimal? SecurityDeposit = null,
    int MinimumDays = 1,
    int? KmPerDay = null,
    bool FuelIncluded = false,
    [StringLength(200)] string? PickupPoint = null);

/// <summary>The equipment a vehicle carries, which is what the score counts.</summary>
/// <remarks>
/// The whole set is sent every time rather than one item at a time: the score is
/// computed from all eight together, and a partial update would have to guess at
/// the rest.
/// </remarks>
public sealed record VehicleEquipmentRequest(
    bool FourByFour = false,
    bool FirstAidKit = false,
    bool SpareTyre = false,
    bool FireExtinguisher = false,
    bool SnowChains = false,
    bool Heating = false,
    bool AirConditioning = false,
    bool ChildSeat = false);
