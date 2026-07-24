using NetTopologySuite.Geometries;
using UDrive.Api.Domain.Enums;

namespace UDrive.Api.Domain.Entities;

public sealed class RideRequest : BaseEntity
{
    public Guid CustomerUserId { get; set; }
    public Point PickupLocation { get; set; } = default!;
    public Point DestinationLocation { get; set; } = default!;
    public string PickupLabel { get; set; } = string.Empty;
    public string DestinationLabel { get; set; } = string.Empty;
    public DateTimeOffset PickupAt { get; set; }
    public BookingType BookingType { get; set; }
    public int SeatsRequested { get; set; }
    public int Adults { get; set; }
    public int Children { get; set; }
    public int LuggageCount { get; set; }
    public decimal CustomerOffer { get; set; }
    public string VehicleCategory { get; set; } = string.Empty;
    public bool FamilyOnly { get; set; }
    public RideRequestStatus Status { get; set; } = RideRequestStatus.Open;
}

public sealed class DriverOffer : BaseEntity
{
    public Guid RideRequestId { get; set; }
    public Guid DriverProfileId { get; set; }
    public Guid VehicleId { get; set; }
    public decimal Amount { get; set; }
    public int EstimatedArrivalMinutes { get; set; }
    public string? Message { get; set; }
    public OfferStatus Status { get; set; } = OfferStatus.Pending;
    public DateTimeOffset ExpiresAt { get; set; }
}

public sealed class Booking : BaseEntity
{
    public Guid CustomerUserId { get; set; }
    public Guid? DriverProfileId { get; set; }
    public Guid? VehicleId { get; set; }
    public Guid? RideRequestId { get; set; }
    public Guid? TourPackageId { get; set; }
    public BookingType BookingType { get; set; }
    public BookingStatus Status { get; set; } = BookingStatus.Pending;
    public int SeatsBooked { get; set; }
    public decimal TotalAmount { get; set; }
    public decimal AdvanceAmount { get; set; }
    public decimal RemainingAmount { get; set; }
    public DateTimeOffset PickupAt { get; set; }
    public string TripOtpHash { get; set; } = string.Empty;
}

public sealed class PackageBooking : BaseEntity
{
    public Guid TourPackageId { get; set; }
    public Guid CustomerUserId { get; set; }
    public BookingType BookingType { get; set; }
    public int SeatsBooked { get; set; }
    public decimal TotalAmount { get; set; }
    public BookingStatus Status { get; set; } = BookingStatus.Pending;
}

public sealed class LiveLocation : BaseEntity
{
    public Guid BookingId { get; set; }
    public Guid UserId { get; set; }
    public string ActorType { get; set; } = string.Empty;
    public Point Location { get; set; } = default!;
    public double? Heading { get; set; }
    public double? SpeedKph { get; set; }
    public double? AccuracyMeters { get; set; }
    public DateTimeOffset RecordedAt { get; set; }
}
