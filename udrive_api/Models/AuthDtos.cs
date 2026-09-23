using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

public sealed record RequestOtpRequest(
    [Required, StringLength(24)] string PhoneNumber,
    [StringLength(32)] string Purpose = "login");

public sealed record RequestOtpDto(
    Guid ChallengeId,
    DateTimeOffset ExpiresAt,
    int RetryAfterSeconds,
    string DeliveryChannel,
    string? DevelopmentCode = null);

public sealed record VerifyOtpRequest(
    [Required, StringLength(24)] string PhoneNumber,
    [Required, StringLength(8, MinimumLength = 4)] string Code,
    [StringLength(160)] string? FullName,
    [StringLength(8)] string Language = "en",
    [StringLength(120)] string? DeviceId = null,
    [StringLength(160)] string? DeviceName = null);

public sealed record RefreshTokenRequest(
    [Required] string RefreshToken,
    [StringLength(120)] string? DeviceId = null,
    [StringLength(160)] string? DeviceName = null);

/// <summary>Body for POST /api/v1/auth/account/delete. Confirmation must be "DELETE".</summary>
public sealed record DeleteAccountRequest(
    [Required, StringLength(16)] string Confirmation,
    [StringLength(500)] string? Reason = null);

/// <summary>Admin handling an emailed deletion request (public /account-deletion page).</summary>
public sealed record AdminDeleteAccountRequest(
    [Required, StringLength(24)] string PhoneNumber,
    [StringLength(500)] string? Reason = null);

public sealed record LogoutRequest(
    string? RefreshToken,
    bool RevokeAllDevices = false);

public sealed record CurrentUserDto(
    Guid Id,
    string PhoneNumber,
    string FullName,
    string? Email,
    string PreferredLanguage,
    string AccountStatus,
    IReadOnlyList<string> Roles,
    Guid? DriverProfileId,
    string? DriverVerificationStatus,
    bool DriverModeAvailable);

public sealed record AuthTokensDto(
    string AccessToken,
    DateTimeOffset AccessTokenExpiresAt,
    string RefreshToken,
    DateTimeOffset RefreshTokenExpiresAt,
    CurrentUserDto User);
