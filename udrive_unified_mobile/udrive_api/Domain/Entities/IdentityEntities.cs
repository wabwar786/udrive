using UDrive.Api.Domain.Enums;

namespace UDrive.Api.Domain.Entities;

public sealed class User : BaseEntity
{
    public string PhoneNumber { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string FullName { get; set; } = string.Empty;
    public UserRole Role { get; set; } = UserRole.Customer;
    public AccountStatus Status { get; set; } = AccountStatus.Approved;
    public string PreferredLanguage { get; set; } = "en";
    public bool PhoneVerified { get; set; }
    public DateTimeOffset? LastLoginAt { get; set; }
}

public sealed class CustomerProfile : BaseEntity
{
    public Guid UserId { get; set; }
    public string? ProfileImageUrl { get; set; }
    public string? EmergencyNotes { get; set; }
}

public sealed class DriverProfile : BaseEntity
{
    public Guid UserId { get; set; }
    public string? CnicNumberMasked { get; set; }
    public string? DrivingLicenceNumberMasked { get; set; }
    public AccountStatus VerificationStatus { get; set; } = AccountStatus.Draft;
    public decimal AverageRating { get; set; }
    public int CompletedTrips { get; set; }
    public int SafetyScore { get; set; } = 80;
    public string[] Languages { get; set; } = [];
    public string[] ServiceAreas { get; set; } = [];
    public bool IsOnline { get; set; }
}

public sealed class DriverDocument : BaseEntity
{
    public Guid DriverProfileId { get; set; }
    public string DocumentType { get; set; } = string.Empty;
    public string FileUrl { get; set; } = string.Empty;
    public DateOnly? ExpiryDate { get; set; }
    public AccountStatus Status { get; set; } = AccountStatus.Submitted;
    public string? ReviewNotes { get; set; }
}

public sealed class TrustedContact : BaseEntity
{
    public Guid UserId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Relationship { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public bool IsGuardian { get; set; }
    public bool EmergencyNotificationsEnabled { get; set; } = true;
}
