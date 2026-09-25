using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

// PerMinuteRate is pricing_rules.per_minute_rate, which the admin edits and the
// server's own preview honours. It was missing from this contract, so both the
// mobile app and the admin portal's inline estimate substituted a literal 2 and
// an operator changing the value saw no effect anywhere a customer looks.
// Defaulted so older callers constructing this record still compile.
/// <param name="BaseFare">
/// Flagfall, charged once before distance and time. Defaults to 0, which is
/// the arithmetic the platform had before a base fare existed.
/// </param>
/// <param name="FuelType">Which pump price indexes this vehicle's rates.</param>
/// <param name="SeatCapacity">
/// Seats this category sells. The per-seat price is the whole-vehicle price
/// shared across it, so a wrong capacity is a wrong seat price.
/// </param>
public sealed record ServiceVehicleRateDto(string ServiceType,string VehicleCategory,decimal PerSeatRate,decimal WholeVehicleRate,decimal PerKmRate,string Currency,decimal PerMinuteRate = 2m,decimal BaseFare = 0m,string FuelType = "Petrol",int SeatCapacity = 4);
public sealed record AmbulanceServiceDto(Guid Id,string Name,string City,string PhoneNumber,decimal PerKmFare,string Currency,string? ImageUrl);
/// <param name="Heading">
/// Compass bearing in degrees, 0 = north. Nullable because a stationary phone
/// reports no heading and an older Driver build sends none at all; the map then
/// draws the vehicle unrotated rather than pointing it somewhere invented.
/// </param>
public sealed record DriverPresenceUpdateRequest([Range(-90,90)] double Latitude,[Range(-180,180)] double Longitude,[Range(0,10000)] double? Accuracy,DateTimeOffset DeviceTimestamp,[Range(0,360)] double? Heading = null);
