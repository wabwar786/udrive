using System.ComponentModel.DataAnnotations;

namespace UDrive.Api.Models;

/// <summary>A pricing rule as the admin portal sees it.</summary>
/// <param name="DaysOfWeek">
/// ISO days, 1 = Monday … 7 = Sunday. Empty means every day.
/// </param>
/// <param name="AreaRadiusKm">
/// Null together with the coordinates means the rule applies everywhere.
/// </param>
public sealed record PricingRuleDto(
    Guid Id,
    string Name,
    string ServiceType,
    string VehicleCategory,
    decimal PerKmRate,
    decimal MinimumFare,
    decimal PerMinuteRate,
    IReadOnlyList<int> DaysOfWeek,
    string? AreaLabel,
    double? AreaLatitude,
    double? AreaLongitude,
    double? AreaRadiusKm,
    int Priority,
    bool IsActive,
    DateTimeOffset UpdatedAt);

/// <summary>Create or update a pricing rule.</summary>
public sealed record UpsertPricingRuleRequest(
    [Required, StringLength(120, MinimumLength = 2)] string Name,
    [Required, StringLength(40)] string ServiceType,
    [Required, StringLength(40)] string VehicleCategory,
    [Range(0.01, 100000)] decimal PerKmRate,
    [Range(0, 1000000)] decimal MinimumFare,
    [Range(0, 10000)] decimal PerMinuteRate,
    IReadOnlyList<int>? DaysOfWeek,
    [StringLength(160)] string? AreaLabel,
    [Range(-90, 90)] double? AreaLatitude,
    [Range(-180, 180)] double? AreaLongitude,
    [Range(0.1, 500)] double? AreaRadiusKm,
    [Range(-1000, 1000)] int Priority = 0,
    bool IsActive = true);

/// <summary>
/// What a rule would charge for a given trip, so the admin can check a change
/// before saving it rather than by booking a ride.
/// </summary>
public sealed record PricingPreviewDto(
    string VehicleCategory,
    string? MatchedRuleName,
    decimal PerKmRate,
    decimal MinimumFare,
    decimal PerMinuteRate,
    decimal Fare);
