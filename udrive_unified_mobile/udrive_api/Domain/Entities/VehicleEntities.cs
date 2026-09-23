using UDrive.Api.Domain.Enums;

namespace UDrive.Api.Domain.Entities;

public sealed class Vehicle : BaseEntity
{
    public Guid DriverProfileId { get; set; }
    public string Category { get; set; } = string.Empty;
    public string Make { get; set; } = string.Empty;
    public string Model { get; set; } = string.Empty;
    public int Year { get; set; }
    public string RegistrationNumber { get; set; } = string.Empty;
    public string Colour { get; set; } = string.Empty;
    public int PassengerCapacity { get; set; }
    public int LuggageCapacity { get; set; }
    public bool HasAirConditioning { get; set; }
    public bool HasHeating { get; set; }
    public bool IsFourByFour { get; set; }
    public bool HasFirstAidKit { get; set; }
    public bool HasFireExtinguisher { get; set; }
    public bool HasSpareTyre { get; set; }
    public bool HasSnowChains { get; set; }
    public bool HasChildSeat { get; set; }
    public int MountainReadinessScore { get; set; }
    public VehicleStatus Status { get; set; } = VehicleStatus.Draft;
}

public sealed class VehicleDocument : BaseEntity
{
    public Guid VehicleId { get; set; }
    public string DocumentType { get; set; } = string.Empty;
    public string FileUrl { get; set; } = string.Empty;
    public DateOnly? ExpiryDate { get; set; }
    public VehicleStatus Status { get; set; } = VehicleStatus.PendingReview;
    public string? ReviewNotes { get; set; }
}
