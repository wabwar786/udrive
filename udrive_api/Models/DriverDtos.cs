using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

public sealed record DriverOnboardingRequest(
    [Required, StringLength(160)] string FullName,
    [Required, StringLength(32)] string CnicNumber,
    [Required, StringLength(64)] string DrivingLicenceNumber,
    DateOnly? DateOfBirth,
    [Required, StringLength(600)] string Address,
    [Required, StringLength(120)] string EmergencyContactName,
    [Required, StringLength(24)] string EmergencyContactPhone,
    [StringLength(120)] string? BankAccountTitle,
    [StringLength(40)] string? PayoutMethod,
    [StringLength(80)] string? PayoutAccount,
    string[]? Languages,
    string[]? ServiceAreas);

public sealed record DriverOnboardingDto(
    Guid DriverProfileId,
    string VerificationStatus,
    string? CnicMasked,
    string? DrivingLicenceMasked,
    DateOnly? DateOfBirth,
    string? Address,
    string? EmergencyContactName,
    string? EmergencyContactPhone,
    string? BankAccountTitle,
    string? PayoutMethod,
    string? PayoutAccountMasked,
    IReadOnlyList<string> Languages,
    IReadOnlyList<string> ServiceAreas,
    DateTimeOffset? SubmittedAt,
    DateTimeOffset? ReviewedAt,
    string? ReviewNotes);

public sealed record DriverDocumentDto(
    Guid Id,
    string DocumentType,
    string FileUrl,
    DateOnly? ExpiryDate,
    string Status,
    string? ReviewNotes);

public sealed record VehicleUpsertRequest(
    [Required, StringLength(48)] string Category,
    [Required, StringLength(64)] string Make,
    [Required, StringLength(64)] string Model,
    [Range(1980, 2100)] int Year,
    [Required, StringLength(40)] string RegistrationNumber,
    [Required, StringLength(40)] string Colour,
    [Range(1, 60)] int PassengerCapacity,
    [Range(0, 100)] int LuggageCapacity,
    bool HasAirConditioning,
    bool HasHeating,
    bool IsFourByFour,
    bool HasFirstAidKit,
    bool HasFireExtinguisher,
    bool HasSpareTyre,
    bool HasSnowChains,
    bool HasChildSeat);

public sealed record VehicleDto(
    Guid Id,
    string Category,
    string Make,
    string Model,
    int Year,
    string RegistrationNumber,
    string Colour,
    int PassengerCapacity,
    int LuggageCapacity,
    bool HasAirConditioning,
    bool HasHeating,
    bool IsFourByFour,
    bool HasFirstAidKit,
    bool HasFireExtinguisher,
    bool HasSpareTyre,
    bool HasSnowChains,
    bool HasChildSeat,
    int MountainReadinessScore,
    string Status,
    IReadOnlyList<VehicleDocumentDto> Documents);

public sealed record VehicleDocumentDto(
    Guid Id,
    string DocumentType,
    string FileUrl,
    DateOnly? ExpiryDate,
    string Status,
    string? ReviewNotes);

public sealed record VerificationReviewRequest(
    [Required, StringLength(32)] string Decision,
    [StringLength(1000)] string? Notes);

public sealed record DriverReviewListItemDto(
    Guid DriverProfileId,
    Guid UserId,
    string FullName,
    string PhoneNumber,
    string VerificationStatus,
    string? CnicMasked,
    string? DrivingLicenceMasked,
    DateTimeOffset? SubmittedAt,
    int DocumentCount,
    int VehicleCount);

public sealed record VehicleReviewListItemDto(
    Guid VehicleId,
    Guid DriverProfileId,
    string DriverName,
    string RegistrationNumber,
    string Vehicle,
    string Status,
    int MountainReadinessScore,
    int DocumentCount);

public sealed record DriverReviewDetailDto(
    DriverReviewListItemDto Driver,
    DriverOnboardingDto Profile,
    IReadOnlyList<DriverDocumentDto> Documents,
    IReadOnlyList<VehicleReviewListItemDto> Vehicles);

public sealed record VehicleReviewDetailDto(
    VehicleReviewListItemDto Vehicle,
    IReadOnlyList<VehicleDocumentDto> Documents);

