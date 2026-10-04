namespace UDrive.Api.Models;

/// <summary>A business as Near me lists it to customers.</summary>
public sealed record BusinessDto(
    Guid Id,
    string Name,
    string Category,
    string Address,
    string Phone,
    string Description,
    double Latitude,
    double Longitude,
    IReadOnlyList<string> Photos,
    bool Open24Hours,
    string? OpensAt,
    string? ClosesAt,
    bool? OpenNow,
    double? DistanceKm,
    string Status,
    string? RejectionReason,
    bool IsActive,
    bool IsDemo);

/// <summary>What an owner sends to list or edit a business.</summary>
/// <remarks>
/// <c>OpensAt</c> / <c>ClosesAt</c> are "HH:mm" in Pakistan time; a window may
/// cross midnight (18:00 → 02:00). Leave both empty, or set
/// <c>Open24Hours</c>, when that is the truth.
/// </remarks>
public sealed record SaveBusinessRequest(
    string Name,
    string Category,
    string Address,
    string? Phone,
    string? Description,
    double Latitude,
    double Longitude,
    bool Open24Hours = false,
    string? OpensAt = null,
    string? ClosesAt = null);

/// <summary>A business in the admin portal's approval list.</summary>
public sealed record AdminBusinessDto(
    Guid Id,
    string Name,
    string Category,
    string Address,
    string Phone,
    string Description,
    double Latitude,
    double Longitude,
    bool Open24Hours,
    string? OpensAt,
    string? ClosesAt,
    string Status,
    string? RejectionReason,
    bool IsActive,
    string OwnerName,
    string OwnerPhone,
    DateTime CreatedAt,
    bool IsDemo);

public sealed record ReviewBusinessRequest(bool Approve, string? Reason);
public sealed record SetBusinessActiveRequest(bool IsActive);
