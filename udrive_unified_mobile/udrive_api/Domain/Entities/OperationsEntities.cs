using UDrive.Api.Domain.Enums;

namespace UDrive.Api.Domain.Entities;

public sealed class SafetyIncident : BaseEntity
{
    public Guid? BookingId { get; set; }
    public Guid ReportedByUserId { get; set; }
    public IncidentSeverity Severity { get; set; }
    public string IncidentType { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string Status { get; set; } = "open";
    public Guid? AssignedAdminUserId { get; set; }
    public DateTimeOffset? ResolvedAt { get; set; }
}

public sealed class Notification : BaseEntity
{
    public Guid UserId { get; set; }
    public string Type { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public string DataJson { get; set; } = "{}";
    public DateTimeOffset? ReadAt { get; set; }
}

public sealed class Payment : BaseEntity
{
    public Guid BookingId { get; set; }
    public string Method { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public string Currency { get; set; } = "PKR";
    public PaymentStatus Status { get; set; } = PaymentStatus.Pending;
    public string? ProviderReference { get; set; }
}

public sealed class AuditLog : BaseEntity
{
    public Guid? ActorUserId { get; set; }
    public string Action { get; set; } = string.Empty;
    public string EntityType { get; set; } = string.Empty;
    public string EntityId { get; set; } = string.Empty;
    public string? IpAddress { get; set; }
    public string ChangesJson { get; set; } = "{}";
}
