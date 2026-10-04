namespace UDrive.Api.Models;

public sealed record HotelSearchRequest(string? Query, string? City, DateOnly? CheckIn, DateOnly? CheckOut, int Guests = 1, int Rooms = 1, int Page = 1, int PageSize = 20);
public sealed record CreateHotelRequest(string Name, string Description, string Address, string City, string District, double Latitude, double Longitude, string ContactPhone, string MainImageUrl, IReadOnlyList<string>? Amenities, bool TransportAvailable = true);
public sealed record UpdateHotelRequest(string Name, string Description, string Address, string City, string District, double Latitude, double Longitude, string ContactPhone, string MainImageUrl, IReadOnlyList<string>? Amenities, bool TransportAvailable, bool IsActive = true);
public sealed record CreateHotelRoomRequest(string RoomType, string Description, int Capacity, int TotalRooms, decimal BaseRate, string ImageUrl, IReadOnlyList<string>? Amenities);
public sealed record UpdateInventoryRequest(DateOnly FromDate, DateOnly ToDate, int AvailableRooms, decimal Rate);
public sealed record CreateHotelBookingRequest(Guid RoomId, DateOnly CheckIn, DateOnly CheckOut, int Guests, int Rooms, bool IncludeTransport, string? PickupAddress, double? PickupLatitude, double? PickupLongitude, string? ArrivalTime = null, string? ArrivalMode = null, string? CarNumber = null, string? GuestName = null, string? GuestPhone = null);

/// <summary>What the customer's app gets back after booking a room.</summary>
/// <remarks>
/// <c>bookingId</c> and <c>amount</c> keep the names the self-test and the
/// earlier app read. <c>OwnerNotified</c> is false when the hotel's WhatsApp
/// could not be reached; the booking itself stands either way.
/// </remarks>
public sealed record HotelBookingCreatedDto(Guid BookingId, string Reference, decimal Amount, bool IncludeTransport, object TransportDestination, int Nights, bool OwnerNotified);

/// <summary>The WhatsApp message for the hotel, and where it goes.</summary>
public sealed record HotelOwnerNotice(string To, string Message);
public sealed record ReviewHotelRequest(bool Approve, string? Reason);
public sealed record SetHotelActiveRequest(bool IsActive);
