namespace UDrive.Api.Models;

public sealed record HotelSearchRequest(string? Query, string? City, DateOnly? CheckIn, DateOnly? CheckOut, int Guests = 1, int Rooms = 1, int Page = 1, int PageSize = 20);
public sealed record CreateHotelRequest(string Name, string Description, string Address, string City, string District, double Latitude, double Longitude, string ContactPhone, string MainImageUrl, IReadOnlyList<string>? Amenities, bool TransportAvailable = true);
public sealed record UpdateHotelRequest(string Name, string Description, string Address, string City, string District, double Latitude, double Longitude, string ContactPhone, string MainImageUrl, IReadOnlyList<string>? Amenities, bool TransportAvailable, bool IsActive = true);
public sealed record CreateHotelRoomRequest(string RoomType, string Description, int Capacity, int TotalRooms, decimal BaseRate, string ImageUrl, IReadOnlyList<string>? Amenities);
public sealed record UpdateInventoryRequest(DateOnly FromDate, DateOnly ToDate, int AvailableRooms, decimal Rate);
public sealed record CreateHotelBookingRequest(Guid RoomId, DateOnly CheckIn, DateOnly CheckOut, int Guests, int Rooms, bool IncludeTransport, string? PickupAddress, double? PickupLatitude, double? PickupLongitude);
public sealed record ReviewHotelRequest(bool Approve, string? Reason);
