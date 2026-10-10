namespace UDrive.Api.Models;

// Hotel mode: the owner profile and the step-by-step hotel wizard.

public sealed record SaveHotelOwnerProfileRequest(
    string? OwnerName,
    string? BusinessName,
    string? Phone,
    string? Email);

public sealed record HotelOwnerProfileDto(
    string OwnerName,
    string BusinessName,
    string Phone,
    string Email,
    bool CnicFront,
    bool CnicBack,
    string VerificationStatus,
    string? VerificationNote,
    bool Complete);

/// <summary>Every field is optional: each wizard step sends what it has.</summary>
public sealed record SaveOwnerHotelRequest(
    string? Name,
    string? PropertyType,
    string? Description,
    string? Address,
    string? City,
    string? District,
    double? Latitude,
    double? Longitude,
    string? ContactPhone,
    IReadOnlyList<string>? Amenities,
    bool? TransportAvailable,
    string? CheckInTime,
    string? CheckOutTime);

public sealed record SaveOwnerRoomRequest(
    string? RoomType,
    int Capacity,
    int TotalRooms,
    decimal BaseRate,
    string? Description);

public sealed record OwnerHotelPhotoDto(Guid Id, string Url, bool IsMain);

public sealed record OwnerHotelRoomDto(
    Guid Id,
    string RoomType,
    string Description,
    int Capacity,
    int TotalRooms,
    decimal BaseRate,
    string ImageUrl);

public sealed record OwnerHotelDetailDto(
    Guid Id,
    string Name,
    string PropertyType,
    string Description,
    string Address,
    string City,
    string District,
    double? Latitude,
    double? Longitude,
    string ContactPhone,
    IReadOnlyList<string> Amenities,
    bool TransportAvailable,
    string? CheckInTime,
    string? CheckOutTime,
    string Status,
    string? RejectionReason,
    bool IsActive,
    IReadOnlyList<OwnerHotelPhotoDto> Photos,
    IReadOnlyList<OwnerHotelRoomDto> Rooms,
    IReadOnlyList<string> Missing);

public sealed record OwnerHotelCardDto(
    Guid Id,
    string Name,
    string PropertyType,
    string City,
    string District,
    string Status,
    string? RejectionReason,
    bool IsActive,
    string PhotoUrl,
    int PhotoCount,
    int RoomTypes,
    string ContactPhone);

public sealed record HotelOwnerHomeDto(
    HotelOwnerProfileDto Profile,
    IReadOnlyList<OwnerHotelCardDto> Hotels);
