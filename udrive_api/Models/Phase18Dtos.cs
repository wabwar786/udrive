using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

public sealed record TourItineraryDayRequest(
    [Range(1, 60)] int DayNumber,
    [Required, StringLength(180)] string Title,
    [Required, StringLength(200)] string Location,
    [Required, StringLength(3000)] string Activity,
    TimeOnly? StartTime,
    TimeOnly? EndTime,
    [StringLength(1500)] string? Notes);

public sealed record TourImageRequest(
    [Required, StringLength(1200)] string ImageUrl,
    [StringLength(240)] string? Caption,
    int SortOrder,
    bool IsCover);

public sealed record TourCancellationRuleRequest(
    [Range(0, 8760)] int HoursBeforeDeparture,
    [Range(0, 100)] decimal RefundPercent,
    [StringLength(300)] string? Description);

public sealed record UpdateTourPackageContentRequest(
    IReadOnlyList<TourItineraryDayRequest>? Itinerary,
    IReadOnlyList<TourImageRequest>? Images,
    IReadOnlyList<TourCancellationRuleRequest>? CancellationRules,
    [Range(1, 60)] int MinimumPassengers = 1);

public sealed record TourItineraryDayDto(Guid Id, int DayNumber, string Title, string Location, string Activity, TimeOnly? StartTime, TimeOnly? EndTime, string? Notes);
public sealed record TourImageDto(Guid Id, string ImageUrl, string? Caption, int SortOrder, bool IsCover);
public sealed record TourCancellationRuleDto(Guid Id, int HoursBeforeDeparture, decimal RefundPercent, string? Description);

public sealed record TourPackageContentDto(
    Guid TourPackageId,
    IReadOnlyList<TourItineraryDayDto> Itinerary,
    IReadOnlyList<TourImageDto> Images,
    IReadOnlyList<TourCancellationRuleDto> CancellationRules,
    int MinimumPassengers);

public sealed record TourOperationDto(
    Guid Id,
    Guid TourPackageId,
    string PackageTitle,
    Guid? DepartureId,
    DateTimeOffset DepartureAt,
    DateTimeOffset? ReturnAt,
    string Status,
    int ConfirmedBookings,
    int SeatsBooked,
    int CheckedInPassengers,
    int BoardedPassengers,
    string Vehicle,
    string RegistrationNumber,
    int Version);

public sealed record UpdateTourStatusRequest(
    [Required, StringLength(32)] string Status,
    [StringLength(1000)] string? Notes,
    int ExpectedVersion);

public sealed record CheckInPassengerRequest(
    Guid BookingId,
    Guid? PassengerId,
    [Required, StringLength(32)] string Status,
    [StringLength(500)] string? Notes);

public sealed record TourCheckInDto(Guid Id, Guid BookingId, Guid? PassengerId, string PassengerName, string BookingReference, string Status, DateTimeOffset? CheckedInAt, DateTimeOffset? BoardedAt);

public sealed record PackageBookingSummaryDto(Guid BookingId, string BookingReference, Guid TourPackageId, string PackageTitle, string Destination, DateTimeOffset DepartureAt, int SeatsBooked, decimal TotalAmount, decimal RemainingAmount, string Status, string TourStatus);

public sealed record AdminPackageListItemDto(Guid Id, string Title, string StartingCity, string Destination, DateTimeOffset DepartureAt, DateTimeOffset? ReturnAt, string Status, int TotalSeats, int AvailableSeats, decimal PricePerSeat, decimal WholeVehiclePrice, string DriverName, string Vehicle, string RegistrationNumber, int BookingCount, int SeatsBooked, decimal GrossRevenue);
