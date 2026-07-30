using System.ComponentModel.DataAnnotations;
using System.Text.Json;

namespace UDrive.Api.Models;

public sealed record AdminMetricDto(string Label, decimal Value, decimal ChangePercent, string Tone);
public sealed record AdminRecentActivityDto(string Type, string Title, string Subtitle, DateTimeOffset OccurredAt, string Status);
public sealed record AdminDashboardDto(
    IReadOnlyList<AdminMetricDto> Metrics,
    IReadOnlyList<AdminRecentActivityDto> RecentActivity,
    IReadOnlyDictionary<string, int> BookingStatuses,
    IReadOnlyDictionary<string, int> VerificationQueues);

public sealed record AdminBookingListItemDto(
    Guid Id, string BookingReference, string CustomerName, string CustomerPhone,
    string? DriverName, string? Vehicle, string BookingType, string Status,
    int SeatsBooked, decimal TotalAmount, decimal AdvanceAmount, decimal RemainingAmount,
    string? PickupLabel, string? DestinationLabel, DateTimeOffset PickupAt, DateTimeOffset CreatedAt);
public sealed record AdminBookingDetailDto(
    AdminBookingListItemDto Booking,
    IReadOnlyList<AdminPassengerDto> Passengers,
    IReadOnlyList<AdminStatusHistoryDto> StatusHistory,
    IReadOnlyList<AdminPaymentDto> Payments);
public sealed record AdminPassengerDto(Guid Id, string FullName, string? Gender, string AgeGroup, string? PhoneNumberMasked, bool IdentityVerified, bool EmergencyContact);
public sealed record AdminStatusHistoryDto(string? FromStatus, string ToStatus, string? Reason, DateTimeOffset CreatedAt, string? ChangedBy);
public sealed record UpdateBookingStatusRequest([Required, StringLength(32)] string Status, [StringLength(1000)] string? Reason);

public sealed record AdminRideRequestDto(Guid Id, string CustomerName, string PickupLabel, string DestinationLabel, DateTimeOffset PickupAt, string BookingType, int SeatsRequested, decimal CustomerOffer, string VehicleCategory, string Status, int OfferCount, DateTimeOffset CreatedAt);
public sealed record AdminUserDto(Guid Id, string FullName, string PhoneNumber, string? Email, string Status, string PreferredLanguage, IReadOnlyList<string> Roles, DateTimeOffset? LastLoginAt, DateTimeOffset CreatedAt);
public sealed record UpdateUserStatusRequest([Required, StringLength(32)] string Status, [StringLength(500)] string? Reason);
public sealed record UpdateUserRolesRequest([Required, MinLength(1)] string[] Roles);
public sealed record AdminDriverDto(Guid DriverProfileId, Guid UserId, string FullName, string PhoneNumber, string VerificationStatus, decimal AverageRating, int CompletedTrips, int SafetyScore, bool IsOnline, int VehicleCount, DateTimeOffset UpdatedAt);
public sealed record AdminVehicleDto(Guid Id, string DriverName, string RegistrationNumber, string Vehicle, string Category, int PassengerCapacity, bool IsFourByFour, int MountainReadinessScore, string Status, DateTimeOffset UpdatedAt);

public sealed record AdminDestinationDto(Guid Id, string Slug, string NameEn, string NameUr, string SummaryEn, string SummaryUr, string District, string BestSeason, string RecommendedVehicle, string NetworkStatus, int FamilySuitabilityScore, int RouteSafetyScore, double Latitude, double Longitude, bool IsActive, string? CoverImageUrl);
public sealed record UpsertDestinationRequest(
    [Required, StringLength(120)] string Slug, [Required, StringLength(160)] string NameEn,
    [Required, StringLength(200)] string NameUr, [Required] string SummaryEn, [Required] string SummaryUr,
    [Range(-90,90)] double Latitude, [Range(-180,180)] double Longitude,
    [Required, StringLength(100)] string District, [Required, StringLength(100)] string BestSeason,
    [Required, StringLength(80)] string RecommendedVehicle, [Required, StringLength(80)] string NetworkStatus,
    [Range(0,100)] int FamilySuitabilityScore, [Range(0,100)] int RouteSafetyScore,
    string? CoverImageUrl, bool IsActive = true);

public sealed record AdminRouteDto(Guid Id, string Name, string? Origin, string? Destination, decimal DistanceKm, int EstimatedMinutes, string RecommendedVehicle, bool FourByFourRequired, bool DaylightOnly, int SafetyScore, bool IsActive);
public sealed record UpsertRouteRequest(
    [Required, StringLength(200)] string Name, Guid? OriginDestinationId, Guid? DestinationId,
    [Range(-90,90)] double OriginLatitude, [Range(-180,180)] double OriginLongitude,
    [Range(-90,90)] double DestinationLatitude, [Range(-180,180)] double DestinationLongitude,
    [Range(0.1,10000)] decimal DistanceKm, [Range(1,100000)] int EstimatedMinutes,
    [Required, StringLength(80)] string RecommendedVehicle, bool FourByFourRequired, bool DaylightOnly,
    [Range(0,100)] int SafetyScore, bool IsActive = true);

public sealed record AdminAdvisoryDto(Guid Id, Guid? RouteId, string? RouteName, string Severity, string TitleEn, string TitleUr, string DetailsEn, string DetailsUr, string SourceName, DateTimeOffset StartsAt, DateTimeOffset? EndsAt, bool IsActive);
public sealed record UpsertAdvisoryRequest(Guid? RouteId, [Required, StringLength(32)] string Severity,
    [Required, StringLength(200)] string TitleEn, [Required, StringLength(240)] string TitleUr,
    [Required] string DetailsEn, [Required] string DetailsUr, [Required, StringLength(160)] string SourceName,
    DateTimeOffset StartsAt, DateTimeOffset? EndsAt, bool IsActive = true);

public sealed record AdminSafetyIncidentDto(Guid Id, string? BookingReference, string Reporter, string Severity, string IncidentType, string Description, string Status, string? AssignedTo, string? ResolutionNotes, DateTimeOffset CreatedAt, DateTimeOffset? ResolvedAt);
public sealed record UpdateSafetyIncidentRequest([Required, StringLength(32)] string Status, Guid? AssignedAdminUserId, [StringLength(2000)] string? ResolutionNotes);
public sealed record AdminPaymentDto(Guid Id, string BookingReference, string CustomerName, string Method, decimal Amount, string Currency, string Status, string? ProviderReference, decimal RefundAmount, string? ReviewNotes, DateTimeOffset CreatedAt);
public sealed record UpdatePaymentRequest([Required, StringLength(32)] string Status, [Range(0,100000000)] decimal RefundAmount, [StringLength(1000)] string? ReviewNotes);

public sealed record AdminSupportTicketDto(Guid Id, string Reference, string? CustomerName, string? BookingReference, string Category, string Priority, string Subject, string Description, string Status, string? AssignedTo, string? ResolutionNotes, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt);
public sealed record CreateSupportTicketRequest(Guid? CustomerUserId, Guid? BookingId, [Required, StringLength(64)] string Category, [Required, StringLength(32)] string Priority, [Required, StringLength(200)] string Subject, [Required, StringLength(4000)] string Description);
public sealed record UpdateSupportTicketRequest([Required, StringLength(32)] string Status, Guid? AssignedAdminUserId, [StringLength(2000)] string? ResolutionNotes);
public sealed record BroadcastNotificationRequest([Required, StringLength(80)] string Type, [Required, StringLength(200)] string Title, [Required, StringLength(2000)] string Body, string? AudienceRole, JsonElement? Data);
public sealed record AdminAuditLogDto(Guid Id, string? ActorName, string Action, string EntityType, string EntityId, string? IpAddress, string ChangesJson, DateTimeOffset CreatedAt);
public sealed record AdminSettingDto(string Key, string ValueJson, string? Description, bool IsPublic, DateTimeOffset UpdatedAt);
public sealed record UpdateSettingsRequest([Required] IReadOnlyDictionary<string, JsonElement> Values);
