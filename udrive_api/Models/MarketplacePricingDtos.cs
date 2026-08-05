using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

public sealed record ServiceVehicleRateDto(string ServiceType,string VehicleCategory,decimal PerSeatRate,decimal WholeVehicleRate,string Currency);
public sealed record DriverPresenceUpdateRequest([Range(-90,90)] double Latitude,[Range(-180,180)] double Longitude,[Range(0,10000)] double? Accuracy,DateTimeOffset DeviceTimestamp);
