namespace UDrive.Api.Models;

/// <summary>Everything the Tour &amp; Rent home in Driver mode shows.</summary>
/// <param name="RidesVehicles">
/// How many of the driver's vehicles take city or city-to-city rides. Zero
/// means a tour/rent-only driver, whose dashboard is this home.
/// </param>
public sealed record TourRentHomeDto(
    IReadOnlyList<string> Vehicles,
    int RidesVehicles,
    decimal WalletBalance,
    int NewBookings,
    int WaitingCount,
    decimal WeekEarnings,
    IReadOnlyList<TourRentBookingDto> Bookings,
    IReadOnlyList<TourRentWaitlistDto> Waitlist,
    IReadOnlyList<TourRentDepartureDto> Departures);

/// <summary>A booking on one of the driver's tours or rent cars.</summary>
/// <param name="Kind"><c>tour</c> or <c>rent</c>.</param>
/// <param name="Title">The tour's title, or the car for a rental.</param>
/// <param name="Seats">Seats for a tour, days for a rental.</param>
/// <param name="RentalMode"><c>WithDriver</c> / <c>SelfDrive</c>; null for a tour.</param>
/// <param name="Status">
/// Tour: the booking's status. Rent: <c>Confirmed</c>, <c>HandedOver</c>, or
/// <c>PendingOwner</c> when the wallet could not cover the commission and the
/// driver still has to accept.
/// </param>
public sealed record TourRentBookingDto(
    Guid Id,
    string Kind,
    string CustomerName,
    string? CustomerPhone,
    string Title,
    string Vehicle,
    DateTimeOffset StartsAt,
    DateTimeOffset? EndsAt,
    decimal Amount,
    bool WholeVehicle,
    int Seats,
    string? RentalMode,
    string Status,
    DateTimeOffset CreatedAt);

/// <summary>A waiting-list request on one of the driver's tours or cars.</summary>
/// <param name="Free">There is room for it right now, so it can be accepted.</param>
/// <param name="Status"><c>Waiting</c>, <c>Accepted</c> or <c>Expired</c>.</param>
/// <param name="TotalSeats">Tour only: seats on the departure.</param>
/// <param name="BookedSeats">Tour only: seats already booked.</param>
public sealed record TourRentWaitlistDto(
    Guid Id,
    string Kind,
    string CustomerName,
    string? CustomerPhone,
    string Title,
    DateTimeOffset StartsAt,
    DateTimeOffset? EndsAt,
    decimal Amount,
    bool WholeVehicle,
    int Seats,
    int TotalSeats,
    int BookedSeats,
    bool Free,
    string Status,
    DateTimeOffset? AcceptExpiresAt,
    DateTimeOffset CreatedAt);

/// <summary>One upcoming departure and how full it is.</summary>
public sealed record TourRentDepartureDto(
    Guid Id,
    string Title,
    DateTimeOffset DepartureAt,
    int TotalSeats,
    int BookedSeats,
    int Bookings);

/// <summary>What happened to a waiting-list request.</summary>
public sealed record TourRentWaitlistResultDto(
    Guid Id,
    string Kind,
    string Status,
    DateTimeOffset? AcceptExpiresAt);
