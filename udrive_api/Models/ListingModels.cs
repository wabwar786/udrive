namespace UDrive.Api.Models;

// "Earn with your vehicle": owners listing cars for rent and tours.
// Field names here are the JSON contract the app and the portal read
// (camelCase on the wire); see the remarks in ListingService.

public sealed record ListingKitDto(
    bool FourByFour,
    bool FirstAidKit,
    bool SpareTyre,
    bool FireExtinguisher,
    bool SnowChains,
    bool Heating,
    bool AirConditioning);

public sealed record ListingOwnerDto(
    bool HasProfile,
    bool DrivesSelf,
    bool CnicFront,
    bool CnicBack,
    bool Selfie,
    bool LicenceFront,
    bool LicenceBack,
    string? LicenceNumber,
    DateOnly? LicenceExpiry,
    bool AgreementAccepted,
    int AgreementVersion);

public sealed record ListingVehicleDocsDto(bool Front, bool RegistrationFront, bool RegistrationBack);

public sealed record ListingVehicleDto(
    Guid Id,
    string Name,
    string Make,
    string Model,
    int Year,
    string Category,
    bool IsFourByFour,
    string RegistrationNumber,
    int Seats,
    string? PhotoUrl,
    string Status,
    string? ReviewNote,
    bool WantsRent,
    bool WantsTour,
    bool AvailableForRent,
    bool AvailableForTour,
    decimal? WithDriverDaily,
    decimal? SelfDriveDaily,
    string? PickupPoint,
    int ReadinessScore,
    int ReadinessRequired,
    ListingKitDto Kit,
    ListingVehicleDocsDto Docs,
    int PendingRentals)
{
    /// <summary>Where the vehicle is based; null until the owner says.</summary>
    public Guid? TehsilId { get; init; }

    public string? TehsilName { get; init; }

    public string? DistrictName { get; init; }

    /// <summary>Rent and tours are approved separately.</summary>
    public PurposeReviewDto RentReview { get; init; } = new("None", null);

    public PurposeReviewDto TourReview { get; init; } = new("None", null);
}

/// <param name="Status">None, Pending, Approved, Rejected or Info (UDrive asked for something).</param>
public sealed record PurposeReviewDto(string Status, string? Note);

public sealed record VehicleLocationRequest(Guid TehsilId);

public sealed record FleetDriverDto(
    Guid Id,
    string Name,
    string Phone,
    bool IsOwner,
    string Status,
    DateOnly? LicenceExpiry,
    bool LicenceValid,
    int? ExpiresInDays,
    string? ReviewNote);

public sealed record ListingHomeDto(
    ListingOwnerDto Owner,
    IReadOnlyList<ListingVehicleDto> Vehicles,
    IReadOnlyList<FleetDriverDto> Drivers,
    int Invites);

public sealed record SaveListingVehicleRequest(
    string Category,
    string Make,
    string Model,
    int Year,
    string RegistrationNumber,
    int Seats,
    bool WantsRent,
    bool WantsTour,
    string? Drivers,
    decimal? WithDriverDaily,
    decimal? SelfDriveDaily,
    string? PickupPoint,
    ListingKitDto? Kit,
    Guid? TehsilId = null);

public sealed record SubmitListingRequest(
    string? LicenceNumber,
    DateOnly? LicenceExpiry,
    bool AcceptAgreement,
    int AgreementVersion);

public sealed record InviteDriverRequest(string Name, string Phone);

public sealed record DriverInviteDto(
    Guid Id,
    string OwnerName,
    string Vehicles,
    string Status,
    bool CnicFront,
    bool CnicBack,
    bool Selfie,
    bool LicenceFront,
    bool LicenceBack,
    string? LicenceNumber,
    DateOnly? LicenceExpiry,
    int AgreementVersion,
    string? ReviewNote);

public sealed record SubmitInviteRequest(
    string? LicenceNumber,
    DateOnly? LicenceExpiry,
    bool AcceptAgreement,
    int AgreementVersion);

public sealed record RentCalendarDayDto(DateOnly Date, string State);

public sealed record BlockedDaysRequest(IReadOnlyList<DateOnly>? Block, IReadOnlyList<DateOnly>? Unblock);

public sealed record DepartureDayDto(
    DateOnly? Date,
    Guid? PackageId,
    string From,
    Guid DestinationId,
    string Destination,
    string Time,
    int DurationDays,
    int SeatsSold,
    int TotalSeats,
    decimal PricePerSeat,
    decimal WholeVehiclePrice,
    string PickupPoint,
    Guid? FleetDriverId,
    string? DriverName);

public sealed record DepartureMonthDto(
    IReadOnlyList<DepartureDayDto> Days,
    DepartureDayDto? Template,
    int TotalSeats,
    bool PerSeatAllowed);

public sealed record SaveDepartureRequest(
    string From,
    Guid DestinationId,
    string Time,
    int DurationDays,
    decimal PricePerSeat,
    decimal WholeVehiclePrice,
    string? PickupPoint,
    Guid? FleetDriverId,
    /// <summary>Where the trip goes, typed by hand (preferred over DestinationId).</summary>
    string? To = null);

// ─────────────────────────────────────────────── rentals: the owner's answer

public sealed record RespondRentalRequest(bool Accept, Guid? FleetDriverId, string? Reason);

public sealed record RentalHandoverRequest(
    int OdometerKm,
    string Fuel,
    bool IdentityChecked,
    bool LicenceSeen,
    bool DepositReceived);

public sealed record RentalReturnRequest(int OdometerKm, string Fuel);

public sealed record RentalConditionPhotosDto(string? Front, string? Back, string? Left, string? Right);

public sealed record RentalMeterDto(int OdometerKm, string Fuel, DateTimeOffset? At);

public sealed record RentalConditionPhotoDto(string Phase, string Side, string Url);

// ─────────────────────────────────────────────────────────────── admin

public sealed record AdminListingDocsDto(
    string? Front,
    string? RegistrationFront,
    string? RegistrationBack,
    string? CnicFront,
    string? CnicBack,
    string? Selfie,
    string? LicenceFront,
    string? LicenceBack);

public sealed record AdminListingDto(
    Guid VehicleId,
    string Name,
    int Year,
    string Category,
    string RegistrationNumber,
    int Seats,
    string? PhotoUrl,
    bool WantsRent,
    bool WantsTour,
    decimal? WithDriverDaily,
    decimal? SelfDriveDaily,
    int ReadinessScore,
    string Status,
    string? ReviewNote,
    DateTimeOffset? SubmittedAt,
    string ListedVia,
    Guid OwnerUserId,
    string OwnerName,
    string OwnerPhone,
    int OwnerVehicles,
    bool DrivesSelf,
    string? LicenceNumber,
    DateOnly? LicenceExpiry,
    AdminListingDocsDto Docs);

public sealed record AdminFleetDriverDocsDto(
    string? CnicFront,
    string? CnicBack,
    string? Selfie,
    string? LicenceFront,
    string? LicenceBack);

public sealed record AdminFleetDriverDto(
    Guid Id,
    string Name,
    string Phone,
    bool IsOwner,
    string OwnerName,
    string OwnerPhone,
    string Status,
    string? LicenceNumber,
    DateOnly? LicenceExpiry,
    bool LicenceValid,
    DateTimeOffset? SubmittedAt,
    string? ReviewNote,
    AdminFleetDriverDocsDto Docs);

public sealed record AdminReasonRequest(string? Reason, string? Note);

// ─────────────────────────────────────────────────────────────── areas

public sealed record AreaTehsilDto(Guid Id, string Name, double? Latitude, double? Longitude, bool IsActive);

public sealed record AreaDistrictDto(Guid Id, string Name, bool IsActive, IReadOnlyList<AreaTehsilDto> Tehsils);

public sealed record AdminAreaTehsilDto(
    Guid Id, string Name, double? Latitude, double? Longitude, bool IsActive, int Vehicles, int Drivers);

public sealed record AdminAreaDistrictDto(
    Guid Id, string Name, bool IsActive, int Vehicles, int Drivers, IReadOnlyList<AdminAreaTehsilDto> Tehsils);

public sealed record SaveDistrictRequest(string Name, bool IsActive = true);

public sealed record SaveTehsilRequest(Guid DistrictId, string Name, double? Latitude, double? Longitude, bool IsActive = true);

public sealed record UpdateAreaRequest(string Name, double? Latitude, double? Longitude, bool IsActive);

// ─────────────────────────────────────────────────────────── verification hub

/// <summary>Waiting counts per tab, for the tab badges.</summary>
public sealed record VerificationSummaryDto(int City, int Tour, int Rent, int Hotels, int Businesses);

/// <param name="Kind">city-driver, city-vehicle, tour, rent, hotel or business.</param>
/// <param name="Status">Waiting, Approved, Rejected or Info.</param>
public sealed record VerificationRowDto(
    string Kind,
    Guid Id,
    string Title,
    string Subtitle,
    string PersonName,
    string PersonPhone,
    Guid? TehsilId,
    string? TehsilName,
    string? DistrictName,
    DateTimeOffset? SubmittedAt,
    string Status,
    string? Note,
    int ChecksDone,
    int ChecksTotal,
    string? PhotoUrl,
    int DriversWaiting);

/// <param name="Url">A protected admin file url, or a public image url.</param>
public sealed record VerificationDocumentDto(string Label, string? Url);

public sealed record VerificationCheckDto(string Label, bool Ok);

public sealed record VerificationFactDto(string Label, string Value);

/// <param name="CanApprove">False when a rule is not met; BlockReason says which.</param>
public sealed record VerificationDetailDto(
    VerificationRowDto Row,
    IReadOnlyList<VerificationDocumentDto> Documents,
    IReadOnlyList<VerificationCheckDto> Checks,
    IReadOnlyList<VerificationFactDto> Facts,
    IReadOnlyList<AdminFleetDriverDto> Drivers,
    bool CanApprove,
    string? BlockReason,
    bool CanAskInfo);

public sealed record VerificationNoteRequest(string? Note);

// ─────────────────────────────────────────────────────── place names

/// <param name="Kind">Tehsil, Destination or City.</param>
/// <param name="Detail">e.g. "Bagh district", "UDrive destination", "Punjab".</param>
public sealed record PlaceNameDto(string Name, string Kind, string Detail, double? Latitude, double? Longitude);

public sealed record AdminPlaceNameDto(Guid Id, string Name, string Region, double? Latitude, double? Longitude, bool IsActive);

public sealed record SavePlaceNameRequest(string Name, string? Region, double? Latitude, double? Longitude, bool IsActive = true);
