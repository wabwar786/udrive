using System.ComponentModel.DataAnnotations;
using UDrive.Api.Domain.Enums;

namespace UDrive.Api.Models;

public sealed record CreateRideRequestRequest(
    [Required, StringLength(240)] string PickupLabel,
    [Required, StringLength(240)] string DestinationLabel,
    [Range(-90, 90)] double PickupLatitude,
    [Range(-180, 180)] double PickupLongitude,
    [Range(-90, 90)] double DestinationLatitude,
    [Range(-180, 180)] double DestinationLongitude,
    DateTimeOffset PickupAt,
    DateTimeOffset? ReturnAt,
    BookingType BookingType,
    [Range(1, 60)] int SeatsRequested,
    [Range(1, 60)] int Adults,
    [Range(0, 40)] int Children,
    [Range(0, 100)] int LuggageCount,
    [Range(1, 10000000)] decimal CustomerOffer,
    [Required, StringLength(80)] string VehicleCategory,
    [Required, StringLength(32)] string PartyType,
    bool FamilyOnly,
    bool WomenOnly,
    [StringLength(1000)] string? Notes,
    bool InstantRide = false);

public sealed record RideRequestDto(
    Guid Id,
    string PickupLabel,
    string DestinationLabel,
    double PickupLatitude,
    double PickupLongitude,
    double DestinationLatitude,
    double DestinationLongitude,
    DateTimeOffset PickupAt,
    DateTimeOffset? ReturnAt,
    string BookingType,
    int SeatsRequested,
    int Adults,
    int Children,
    int LuggageCount,
    decimal CustomerOffer,
    string VehicleCategory,
    string PartyType,
    bool FamilyOnly,
    bool WomenOnly,
    string Status,
    int OffersCount,
    Guid? SelectedOfferId,
    DateTimeOffset? ExpiresAt,
    DateTimeOffset CreatedAt,
    string CustomerName);

public sealed record DriverRideOfferStatusDto(
    Guid OfferId,
    Guid RideRequestId,
    Guid VehicleId,
    string Vehicle,
    string RegistrationNumber,
    decimal DriverAmount,
    string OfferStatus,
    bool SelectedByCustomer,
    Guid? BookingId,
    string? BookingStatus,
    string PickupLabel,
    string DestinationLabel,
    double PickupLatitude,
    double PickupLongitude,
    double DestinationLatitude,
    double DestinationLongitude,
    string BookingType,
    int SeatsRequested,
    decimal CustomerOffer,
    string VehicleCategory,
    string CustomerName,
    DateTimeOffset CreatedAt,
    DateTimeOffset ExpiresAt);

public sealed record RejectRideRequestRequest(
    [StringLength(500)] string? Reason);

public sealed record DriverRideRequestDecisionDto(
    Guid RideRequestId,
    string Decision,
    DateTimeOffset CreatedAt);

public sealed record SubmitDriverOfferRequest(
    Guid VehicleId,
    [Range(1, 10000000)] decimal Amount,
    [Range(1, 600)] int EstimatedArrivalMinutes,
    [StringLength(500)] string? Message);

public sealed record DriverOfferDto(
    Guid Id,
    Guid RideRequestId,
    Guid DriverProfileId,
    Guid VehicleId,
    string DriverName,
    decimal DriverRating,
    int CompletedTrips,
    int SafetyScore,
    string Vehicle,
    string RegistrationNumber,
    string VehicleCategory,
    decimal Amount,
    decimal? CounterAmount,
    int EstimatedArrivalMinutes,
    string? Message,
    string Status,
    DateTimeOffset ExpiresAt,
    DateTimeOffset CreatedAt);

public sealed record SelectDriverOfferRequest(
    [Range(0, 10000000)] decimal AdvanceAmount = 0);

public sealed record BookingDto(
    Guid Id,
    string BookingReference,
    string BookingType,
    string Status,
    int SeatsBooked,
    decimal TotalAmount,
    decimal AdvanceAmount,
    decimal RemainingAmount,
    DateTimeOffset PickupAt,
    DateTimeOffset? ReturnAt,
    string PickupLabel,
    string DestinationLabel,
    string PartyType,
    string? DriverName,
    string? DriverPhone,
    string? Vehicle,
    string? RegistrationNumber,
    Guid? RideRequestId,
    Guid? TourPackageId,
    Guid? PackageBookingId,
    string? TripOtp,
    DateTimeOffset CreatedAt);

public sealed record CancelBookingRequest(
    [Required, StringLength(1000)] string Reason);

public sealed record RescheduleBookingRequest(
    DateTimeOffset PickupAt,
    DateTimeOffset? ReturnAt,
    [StringLength(1000)] string? Reason);

public sealed record BookingStatusHistoryDto(
    Guid Id,
    string EntityType,
    Guid EntityId,
    string? BookingReference,
    string? FromStatus,
    string ToStatus,
    string? Reason,
    DateTimeOffset CreatedAt);

public sealed record PassengerRequest(
    [Required, StringLength(160)] string FullName,
    [StringLength(24)] string? Gender,
    [Required, StringLength(24)] string AgeGroup,
    [StringLength(32)] string? PhoneNumber,
    bool EmergencyContact = false);

public sealed record CreateTourPackageRequest(
    Guid VehicleId,
    Guid DestinationId,
    [Required, StringLength(200)] string Title,
    [Required, StringLength(120)] string StartingCity,
    [Required, StringLength(200)] string PickupPoint,
    DateTimeOffset DepartureAt,
    DateTimeOffset? ReturnAt,
    [Range(1, 60)] int TotalSeats,
    [Range(1, 10000000)] decimal PricePerSeat,
    [Range(1, 10000000)] decimal WholeVehiclePrice,
    bool FamilyOnly,
    bool WomenOnly,
    bool CustomerOffersAllowed,
    [StringLength(4000)] string? Description,
    [StringLength(2000)] string? CancellationPolicy,
    [StringLength(160)] string? PassengerPolicy,
    [StringLength(200)] string? LuggageAllowance,
    string[]? RouteStops,
    string[]? Inclusions,
    string[]? Exclusions,
    string[]? Itinerary,
    bool FuelIncluded,
    bool TollIncluded,
    bool HotelIncluded,
    bool MealsIncluded,
    bool GuideIncluded,
    bool JeepTransferIncluded,
    bool DriverAccommodationIncluded,
    [StringLength(1000)] string? CoverImageUrl);

public sealed record TourPackageLiveDto(
    Guid Id,
    Guid DriverProfileId,
    Guid VehicleId,
    Guid DestinationId,
    string Title,
    string StartingCity,
    string PickupPoint,
    string Destination,
    DateTimeOffset DepartureAt,
    DateTimeOffset? ReturnAt,
    int TotalSeats,
    int AvailableSeats,
    int HeldSeats,
    decimal PricePerSeat,
    decimal WholeVehiclePrice,
    bool FamilyOnly,
    bool WomenOnly,
    bool CustomerOffersAllowed,
    string Status,
    string? Description,
    string? CancellationPolicy,
    string PassengerPolicy,
    string? LuggageAllowance,
    IReadOnlyList<string> RouteStops,
    IReadOnlyList<string> Inclusions,
    IReadOnlyList<string> Exclusions,
    IReadOnlyList<string> Itinerary,
    string DriverName,
    decimal DriverRating,
    int DriverSafetyScore,
    string Vehicle,
    string RegistrationNumber,
    int MountainReadinessScore,
    string? CoverImageUrl,
    string? ReviewNotes,
    DateTimeOffset CreatedAt);

public sealed record PackageAvailabilityDto(
    Guid TourPackageId,
    int TotalSeats,
    int ConfirmedAvailableSeats,
    int TemporarilyHeldSeats,
    int BookableSeats,
    bool WholeVehicleAvailable,
    DateTimeOffset CalculatedAt);

public sealed record AcquirePackageHoldRequest(
    BookingType BookingType,
    [Range(1, 60)] int Seats);

public sealed record PackageSeatHoldDto(
    Guid HoldId,
    Guid TourPackageId,
    string BookingType,
    int SeatsHeld,
    decimal QuotedAmount,
    DateTimeOffset ExpiresAt,
    int RemainingSeconds);

public sealed record ConfirmPackageBookingRequest(
    Guid HoldId,
    [Range(0, 10000000)] decimal AdvanceAmount,
    IReadOnlyList<PassengerRequest>? Passengers);

public sealed record CreatePackageOfferRequest(
    BookingType BookingType,
    [Range(1, 60)] int Seats,
    [Range(1, 10000000)] decimal OfferedAmount,
    [StringLength(500)] string? Message);

public sealed record ReviewPackageOfferRequest(
    [Required, StringLength(32)] string Decision,
    [Range(1, 10000000)] decimal? CounterAmount,
    [StringLength(500)] string? Message);

public sealed record PackageOfferDto(
    Guid Id,
    Guid TourPackageId,
    string PackageTitle,
    Guid CustomerUserId,
    string CustomerName,
    string BookingType,
    int SeatsRequested,
    decimal OfferedAmount,
    decimal? CounterAmount,
    string? Message,
    string? DriverMessage,
    string Status,
    DateTimeOffset ExpiresAt,
    DateTimeOffset CreatedAt);

public sealed record AdminPackageReviewRequest(
    [Required, StringLength(32)] string Decision,
    [StringLength(1000)] string? Notes);

public sealed record CreateTourInterestRequest(
    Guid DestinationId,
    DateOnly PreferredStartDate,
    DateOnly? PreferredEndDate,
    [Range(1, 60)] int Persons,
    [Required, StringLength(40)] string GroupPreference,
    [Range(0, 10000000)] decimal? BudgetPerSeat,
    [Required, StringLength(120)] string PickupCity);

public sealed record TourInterestDto(
    Guid Id,
    Guid DestinationId,
    string Destination,
    DateOnly PreferredStartDate,
    DateOnly? PreferredEndDate,
    int Persons,
    string GroupPreference,
    decimal? BudgetPerSeat,
    string PickupCity,
    bool IsActive,
    DateTimeOffset CreatedAt);

public sealed record TourMatchDto(
    Guid TourInterestId,
    Guid TourPackageId,
    string PackageTitle,
    string Destination,
    DateTimeOffset DepartureAt,
    int AvailableSeats,
    decimal PricePerSeat,
    decimal WholeVehiclePrice,
    int MatchPercent,
    string DriverName,
    decimal DriverRating,
    int SafetyScore);

public sealed record JoinPackageWaitlistRequest(
    BookingType BookingType,
    [Range(1, 60)] int Seats,
    [StringLength(500)] string? Notes);

public sealed record PackageWaitlistDto(
    Guid Id,
    Guid TourPackageId,
    string PackageTitle,
    string Destination,
    DateTimeOffset DepartureAt,
    string BookingType,
    int SeatsRequested,
    string Status,
    string CustomerName,
    string? Notes,
    DateTimeOffset CreatedAt);

public sealed record PassengerManifestItemDto(
    Guid Id,
    string FullName,
    string? Gender,
    string AgeGroup,
    string? PhoneNumberMasked,
    bool IdentityVerified,
    bool EmergencyContact);

public sealed record PassengerManifestDto(
    Guid BookingId,
    string BookingReference,
    int SeatsBooked,
    IReadOnlyList<PassengerManifestItemDto> Passengers);

public sealed record PackageVehicleLocationDto(
    Guid TourPackageId,
    Guid VehicleId,
    string Vehicle,
    string RegistrationNumber,
    string StartingCity,
    string PickupPoint,
    string Destination,
    double? Latitude,
    double? Longitude,
    DateTimeOffset? LastUpdatedAt,
    bool IsLive,
    bool IsStale,
    double? DestinationLatitude,
    double? DestinationLongitude);

