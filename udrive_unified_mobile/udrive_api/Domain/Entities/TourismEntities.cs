using NetTopologySuite.Geometries;
using UDrive.Api.Domain.Enums;

namespace UDrive.Api.Domain.Entities;

public sealed class Destination : BaseEntity
{
    public string Slug { get; set; } = string.Empty;
    public string NameEn { get; set; } = string.Empty;
    public string NameUr { get; set; } = string.Empty;
    public string SummaryEn { get; set; } = string.Empty;
    public string SummaryUr { get; set; } = string.Empty;
    public Point Location { get; set; } = default!;
    public string District { get; set; } = string.Empty;
    public string BestSeason { get; set; } = string.Empty;
    public string RecommendedVehicle { get; set; } = string.Empty;
    public string NetworkStatus { get; set; } = string.Empty;
    public int FamilySuitabilityScore { get; set; }
    public int RouteSafetyScore { get; set; }
    public string? CoverImageUrl { get; set; }
    public bool IsActive { get; set; } = true;
}

public sealed class TourismRoute : BaseEntity
{
    public string Name { get; set; } = string.Empty;
    public Guid? OriginDestinationId { get; set; }
    public Guid? DestinationId { get; set; }
    public Point OriginLocation { get; set; } = default!;
    public Point DestinationLocation { get; set; } = default!;
    public LineString? RoutePath { get; set; }
    public decimal DistanceKm { get; set; }
    public int EstimatedMinutes { get; set; }
    public string RecommendedVehicle { get; set; } = string.Empty;
    public bool FourByFourRequired { get; set; }
    public bool DaylightOnly { get; set; }
    public int SafetyScore { get; set; }
    public bool IsActive { get; set; } = true;
}

public sealed class RouteAdvisory : BaseEntity
{
    public Guid? RouteId { get; set; }
    public IncidentSeverity Severity { get; set; }
    public string TitleEn { get; set; } = string.Empty;
    public string TitleUr { get; set; } = string.Empty;
    public string DetailsEn { get; set; } = string.Empty;
    public string DetailsUr { get; set; } = string.Empty;
    public string SourceName { get; set; } = string.Empty;
    public DateTimeOffset StartsAt { get; set; }
    public DateTimeOffset? EndsAt { get; set; }
    public bool IsActive { get; set; } = true;
}

public sealed class TourInterest : BaseEntity
{
    public Guid UserId { get; set; }
    public Guid DestinationId { get; set; }
    public DateOnly PreferredStartDate { get; set; }
    public DateOnly? PreferredEndDate { get; set; }
    public int Persons { get; set; }
    public string GroupPreference { get; set; } = "family";
    public decimal? BudgetPerSeat { get; set; }
    public string PickupCity { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;
}

public sealed class TourPackage : BaseEntity
{
    public Guid DriverProfileId { get; set; }
    public Guid VehicleId { get; set; }
    public Guid DestinationId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string StartingCity { get; set; } = string.Empty;
    public string PickupPoint { get; set; } = string.Empty;
    public DateTimeOffset DepartureAt { get; set; }
    public DateTimeOffset? ReturnAt { get; set; }
    public int TotalSeats { get; set; }
    public int AvailableSeats { get; set; }
    public decimal PricePerSeat { get; set; }
    public decimal WholeVehiclePrice { get; set; }
    public bool FamilyOnly { get; set; }
    public bool WomenOnly { get; set; }
    public bool CustomerOffersAllowed { get; set; }
    public PackageStatus Status { get; set; } = PackageStatus.Draft;
    public string[] Inclusions { get; set; } = [];
    public string[] Exclusions { get; set; } = [];
    public string ItineraryJson { get; set; } = "[]";
    public string? CoverImageUrl { get; set; }
}
