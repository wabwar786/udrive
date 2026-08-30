namespace UDrive.Api.Models;

public sealed record DestinationDto(
    Guid Id,
    string Slug,
    string Name,
    string Summary,
    double Latitude,
    double Longitude,
    string District,
    string BestSeason,
    string RecommendedVehicle,
    string NetworkStatus,
    int FamilySuitabilityScore,
    int RouteSafetyScore,
    string? CoverImageUrl);

public sealed record RouteDto(
    Guid Id,
    string Name,
    decimal DistanceKm,
    int EstimatedMinutes,
    string RecommendedVehicle,
    bool FourByFourRequired,
    bool DaylightOnly,
    int SafetyScore);

public sealed record PackageDto(
    Guid Id,
    string Title,
    string StartingCity,
    string Destination,
    DateTimeOffset DepartureAt,
    int AvailableSeats,
    decimal PricePerSeat,
    decimal WholeVehiclePrice,
    bool FamilyOnly,
    bool WomenOnly,
    string Status,
    string? CoverImageUrl);

public sealed record PublicVehicleDto(
    Guid Id,
    Guid DriverProfileId,
    string DriverName,
    decimal DriverRating,
    int CompletedTrips,
    int SafetyScore,
    bool IsOnline,
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
    int MountainReadinessScore,
    string? ImageUrl,
    IReadOnlyList<string> ServiceAreas,
    bool IsDemo,
    // How this vehicle may be booked: WholeVehicle, PerSeat or Both.
    // The customer app offers only the modes the driver enabled.
    string BookingMode);
