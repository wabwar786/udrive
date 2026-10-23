using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

// "Become a partner" on the website: the request, the messages both ways,
// and the admin's view.

public sealed record SubmitPartnerRequest(
    [Required, StringLength(80)] string FullName,
    [StringLength(160)] string? Email,
    [Required, StringLength(60)] string CurrentCity,
    [Required, StringLength(60)] string TargetCity,
    [StringLength(120)] string? Work,
    [Required, StringLength(8)] string Budget,
    [StringLength(1000)] string? Message);

public sealed record PartnerMessageRequest([Required, StringLength(1000)] string Body);

public sealed record PartnerMessageDto(Guid Id, string Author, string Body, bool WhatsAppSent, DateTimeOffset CreatedAt);

/// <summary>What the applicant sees (no internal notes).</summary>
public sealed record PartnerRequestDto(
    Guid Id,
    string Reference,
    string FullName,
    string CurrentCity,
    string TargetCity,
    string Budget,
    string Status,
    DateTimeOffset CreatedAt,
    IReadOnlyList<PartnerMessageDto> Messages);

public sealed record AdminPartnerRowDto(
    Guid Id,
    string Reference,
    string FullName,
    string Phone,
    string TargetCity,
    string Budget,
    string Status,
    int Unread,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record AdminPartnerDetailDto(
    Guid Id,
    string Reference,
    string FullName,
    string Phone,
    string? Email,
    string CurrentCity,
    string TargetCity,
    string? Work,
    string Budget,
    string Status,
    DateTimeOffset CreatedAt,
    IReadOnlyList<PartnerMessageDto> Messages);

public sealed record AdminPartnerListDto(IReadOnlyList<AdminPartnerRowDto> Items, IReadOnlyDictionary<string, int> Counts);

public sealed record PartnerRequestStatusRequest([Required, StringLength(16)] string Status);

public sealed record AdminPartnerReplyRequest([Required, StringLength(1000)] string Body, bool SendWhatsApp, bool InternalNote);

// ───────────────────────────── website: rent a car, hotel special dates

public sealed record WebRentCarDto(
    Guid Id,
    string Name,
    string Category,
    int Year,
    int Seats,
    string? PhotoUrl,
    decimal? WithDriverDaily,
    decimal? SelfDriveDaily,
    decimal SecurityDeposit,
    int MinimumDays,
    int? KmPerDay,
    bool FuelIncluded,
    string? PickupPoint,
    string OwnerName,
    decimal OwnerRating,
    bool AirConditioning,
    bool FourByFour);

public sealed record SaveSpecialRateRequest(
    Guid? RoomId,
    DateOnly StartsOn,
    DateOnly EndsOn,
    decimal? Rate,
    int? Percent,
    int? RoomsOpen);

public sealed record SpecialRateDto(
    Guid Id,
    Guid? RoomId,
    string RoomName,
    DateOnly StartsOn,
    DateOnly EndsOn,
    decimal? Rate,
    int? Percent,
    int? RoomsOpen);
