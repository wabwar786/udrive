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
    int PendingRentals);

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
    ListingKitDto? Kit);

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
    Guid? FleetDriverId);

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
