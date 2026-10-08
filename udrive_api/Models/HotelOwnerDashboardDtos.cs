namespace UDrive.Api.Models;

/// <summary>The hotel owner's home screen.</summary>
/// <param name="FreeRoomsToday">Rooms of every type free tonight.</param>
/// <param name="Bookings">Confirmed bookings from today on, earliest first.</param>
public sealed record HotelOwnerDashboardDto(
    IReadOnlyList<HotelOwnerHotelDto> Hotels,
    Guid? HotelId,
    int NewBookings,
    int FreeRoomsToday,
    int TotalRooms,
    decimal MonthAmount,
    IReadOnlyList<HotelOwnerBookingDto> Bookings,
    IReadOnlyList<HotelOwnerBookingDto> CheckInsToday,
    IReadOnlyList<HotelOwnerBookingDto> CheckOutsToday,
    IReadOnlyList<HotelOwnerRoomDto> Rooms,
    DateOnly Today);

public sealed record HotelOwnerHotelDto(
    Guid Id,
    string Name,
    string City,
    string ApprovalStatus,
    string? PhotoUrl,
    int RoomTypes,
    int TotalRooms);

public sealed record HotelOwnerBookingDto(
    Guid Id,
    string Reference,
    string GuestName,
    string? GuestPhone,
    string RoomType,
    int Rooms,
    int Guests,
    DateOnly CheckIn,
    DateOnly CheckOut,
    decimal Amount,
    string Status,
    string? ArrivalTime,
    bool Transport,
    DateTimeOffset CreatedAt);

/// <param name="FreePerDay">Rooms of this type free on each of the next seven nights, today first.</param>
public sealed record HotelOwnerRoomDto(
    Guid Id,
    string RoomType,
    decimal Rate,
    int[] FreePerDay);
