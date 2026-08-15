using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

public sealed record ServiceVehicleRateDto(string ServiceType,string VehicleCategory,decimal PerSeatRate,decimal WholeVehicleRate,decimal PerKmRate,string Currency);
public sealed record AmbulanceServiceDto(Guid Id,string Name,string City,string PhoneNumber,decimal PerKmFare,string Currency,string? ImageUrl);
public sealed record DriverPresenceUpdateRequest([Range(-90,90)] double Latitude,[Range(-180,180)] double Longitude,[Range(0,10000)] double? Accuracy,DateTimeOffset DeviceTimestamp);
