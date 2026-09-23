using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

public sealed record CreatePortalUserRequest(
    [Required, StringLength(160, MinimumLength = 2)] string FullName,
    [Required, StringLength(24)] string PhoneNumber,
    [EmailAddress, StringLength(320)] string? Email,
    [Required, StringLength(32)] string Role,
    [StringLength(8)] string? PreferredLanguage);

public sealed record UpdatePortalRoleRequest(
    [StringLength(32)] string? Role);

public sealed record CreatedPortalUserDto(
    Guid Id,
    string FullName,
    string PhoneNumber,
    string? Email,
    string Role,
    string Status);
