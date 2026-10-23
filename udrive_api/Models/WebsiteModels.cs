using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

// The public website ("UDrive – Travel & Tour"). Every DTO here is shaped for
// strangers on the internet: no phone numbers, no CNIC, no registration
// numbers, no exact live locations, and only a driver's first name.

public sealed record WebDriverDto(string Name, string Initials, decimal Rating, int ToursDone);

public sealed record WebTourCardDto(
    Guid Id,
    string Title,
    string Destination,
    string DestinationSlug,
    string From,
    string? PickupPoint,
    DateTimeOffset DepartureAt,
    DateTimeOffset? ReturnAt,
    int Days,
    int TotalSeats,
    int SeatsLeft,
    decimal PricePerSeat,
    decimal WholeVehiclePrice,
    bool WholeVehicleAvailable,
    string Vehicle,
    string? ImageUrl,
    WebDriverDto Driver);

public sealed record WebItineraryDayDto(int Day, string Title, string Text);

public sealed record WebTourDetailDto(
    WebTourCardDto Tour,
    string? Description,
    IReadOnlyList<string> RouteStops,
    IReadOnlyList<string> Included,
    IReadOnlyList<string> NotIncluded,
    IReadOnlyList<WebItineraryDayDto> Plan,
    IReadOnlyList<string> Images,
    string? CancellationPolicy,
    string PassengerPolicy,
    string? Luggage,
    bool FamilyOnly,
    bool WomenOnly,
    decimal AdvancePercent);

public sealed record WebDestinationDto(
    Guid Id,
    string Slug,
    string Name,
    string District,
    string Summary,
    string BestSeason,
    string? ImageUrl,
    int UpcomingTours)
{
    public double? Latitude { get; init; }

    public double? Longitude { get; init; }

    /// <summary>lake, meadow or river (rivers &amp; towns); null = not set.</summary>
    public string? Kind { get; init; }

    /// <summary>Drive from Muzaffarabad, set by the team; null = the website estimates it.</summary>
    public decimal? DriveHours { get; init; }
}

public sealed record WebHotelCardDto(
    Guid Id,
    string Slug,
    string Name,
    string PropertyType,
    string City,
    string District,
    decimal Rating,
    decimal StartingRate,
    string? ImageUrl);

public sealed record WebHotelRoomDto(string RoomType, string Description, int Capacity, decimal Rate, string? ImageUrl);

public sealed record WebHotelDetailDto(
    WebHotelCardDto Hotel,
    string Description,
    string Address,
    double? Latitude,
    double? Longitude,
    IReadOnlyList<string> Amenities,
    string? CheckInTime,
    string? CheckOutTime,
    bool TransportAvailable,
    IReadOnlyList<string> Photos,
    IReadOnlyList<WebHotelRoomDto> Rooms);

public sealed record WebAdDto(Guid Id, string Slot, string Title, string Body, string? ImageUrl, string? LinkUrl, string CtaLabel);

public sealed record WebStatsDto(int ToursToday, int ToursThisWeek, int VerifiedDrivers, int Hotels);

public sealed record WebHomeDto(
    WebStatsDto Stats,
    IReadOnlyList<WebTourCardDto> Tours,
    IReadOnlyList<WebHotelCardDto> Hotels,
    IReadOnlyList<WebDestinationDto> Destinations,
    IReadOnlyList<WebAdDto> Ads);

public sealed record WebPageDto<T>(IReadOnlyList<T> Items, int Page, bool HasMore);

/// <summary>What a static build needs to pre-render pages and the sitemap.</summary>
public sealed record WebSitemapDto(
    IReadOnlyList<WebDestinationDto> Destinations,
    IReadOnlyList<WebHotelCardDto> Hotels,
    DateTimeOffset GeneratedAt);

public sealed record WebTourBookingRequest(
    [Required, StringLength(16)] string Mode,
    [Range(1, 60)] int Seats,
    [Required, StringLength(160, MinimumLength = 2)] string FullName);

public sealed record WebTourBookingDto(
    string Reference,
    string Tour,
    DateTimeOffset DepartureAt,
    string PickupPoint,
    string Mode,
    int Seats,
    decimal Total,
    decimal Advance,
    decimal PayDriverOnTheDay,
    string DriverName);

// ───────────────────────────────────────────── admin: ads and web activity

public sealed record SaveWebAdRequest(
    [Required, StringLength(16)] string Slot,
    [Required, StringLength(120, MinimumLength = 2)] string Title,
    [StringLength(300)] string? Body,
    [StringLength(500)] string? ImageUrl,
    [StringLength(500)] string? LinkUrl,
    [StringLength(40)] string? CtaLabel,
    DateOnly? StartsOn,
    DateOnly? EndsOn,
    bool IsActive,
    int SortOrder);

public sealed record AdminWebAdDto(
    Guid Id,
    string Slot,
    string Title,
    string Body,
    string? ImageUrl,
    string? LinkUrl,
    string CtaLabel,
    DateOnly? StartsOn,
    DateOnly? EndsOn,
    bool IsActive,
    int SortOrder,
    int Clicks,
    bool LiveNow,
    DateTimeOffset UpdatedAt);

public sealed record AdminWebBookingDto(
    Guid Id,
    string Reference,
    string Tour,
    DateTimeOffset DepartureAt,
    string Customer,
    string CustomerPhone,
    string Mode,
    int Seats,
    decimal Total,
    decimal Advance,
    string Status,
    string Driver,
    DateTimeOffset CreatedAt);

public sealed record AdminWebHotelDto(
    Guid Id,
    string Name,
    string City,
    string Owner,
    string OwnerPhone,
    string Status,
    DateTimeOffset CreatedAt);

public sealed record AdminWebActivityDto(
    int BookingsToday,
    int BookingsThisMonth,
    decimal ValueThisMonth,
    int HotelsThisMonth,
    IReadOnlyList<AdminWebBookingDto> Bookings,
    IReadOnlyList<AdminWebHotelDto> Hotels);

// ───────────────────────────────────────────── weather (from the hourly WeatherWorker readings)

/// <param name="Chance">Highest chance of rain or snow that day, 0–100 (null when not given).</param>
public sealed record WebWeatherDayDto(DateOnly Date, int Code, double Max, double Min, double Rain, double Snow, double WindMax, int? Chance = null);

public sealed record WebWeatherNowDto(double Temperature, int Code, double Wind);

/// <param name="Level">ok, warn or bad — the label colour.</param>
public sealed record WebWeatherAdviceDto(string Level, string Text);

public sealed record WebWeatherPlaceDto(
    string Key,
    string Name,
    string District,
    string Kind,
    WebWeatherNowDto Now,
    IReadOnlyList<WebWeatherDayDto> Days,
    WebWeatherAdviceDto Advice)
{
    public double Latitude { get; init; }

    public double Longitude { get; init; }
}

public sealed record WebRoadUpdateDto(string Title, string Details, string Severity, string? Route, string Source, DateTimeOffset StartsAt);

public sealed record WebWeatherDto(DateTimeOffset? UpdatedAt, IReadOnlyList<WebWeatherPlaceDto> Places, IReadOnlyList<WebRoadUpdateDto> RoadUpdates);

// ───────────────────────────────────────────── destination photos

public sealed record WebPhotoDto(Guid Id, string Destination, string Url, string? PageUrl, string Author, string License, string? LicenseUrl, string Season, bool Own);

public sealed record AdminWebPhotoDto(
    Guid Id, Guid DestinationId, string Destination, string Source, string Url, string? PageUrl, string Author, string License,
    string Season, int? TakenMonth, bool Hidden, DateTimeOffset CreatedAt);

public sealed record AdminWebPlaceDto(Guid Id, string Slug, string Name, string District, bool HasLocation, string? Kind, decimal? DriveHours, int Photos);

public sealed record AdminWebPhotosDto(IReadOnlyList<AdminWebPlaceDto> Places, IReadOnlyList<AdminWebPhotoDto> Photos, DateTimeOffset? LastSearch, bool Searching);

public sealed record AddWebPhotoRequest(Guid DestinationId, [Required, StringLength(300)] string Url, [StringLength(10)] string? Season);

public sealed record SaveWebPlaceRequest([StringLength(16)] string? Kind, decimal? DriveHours);
