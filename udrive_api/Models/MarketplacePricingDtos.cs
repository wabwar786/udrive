using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

public sealed record ServiceVehicleRateDto(string ServiceType,string VehicleCategory,decimal PerSeatRate,decimal WholeVehicleRate,decimal PerKmRate,string Currency);
public sealed record AmbulanceServiceDto(Guid Id,string Name,string City,string PhoneNumber,decimal PerKmFare,string Currency,string? ImageUrl);
/// <param name="Heading">
/// Compass bearing in degrees, 0 = north. Nullable because a stationary phone
/// reports no heading and an older Driver build sends none at all; the map then
/// draws the vehicle unrotated rather than pointing it somewhere invented.
/// </param>
public sealed record DriverPresenceUpdateRequest([Range(-90,90)] double Latitude,[Range(-180,180)] double Longitude,[Range(0,10000)] double? Accuracy,DateTimeOffset DeviceTimestamp,[Range(0,360)] double? Heading = null);
