namespace UDrive.Api.Models;

// The admin Pricing page ("Pricing — aasan"): one row per vehicle, the
// switches that sit on top of the meter, suggestions, and the fare check.
// Every number is the admin's. Suggestions are shown, never applied.

/// <summary>What the system would suggest for one vehicle, and why.</summary>
public sealed record PricingVehicleSuggestionDto(
    decimal BaseFare,
    decimal PerKmRate,
    decimal PerMinuteRate,
    decimal MinimumFare,
    string Basis,
    decimal? FuelCostPerKm,
    decimal? MarketPerKm,
    int MarketTrips);

/// <summary>One vehicle's everyday rate (City, every day, everywhere).</summary>
public sealed record PricingVehicleRowDto(
    string Category,
    Guid? RuleId,
    decimal BaseFare,
    decimal PerKmRate,
    decimal PerMinuteRate,
    decimal MinimumFare,
    PricingVehicleSuggestionDto Suggestion);

/// <summary>The settings that sit on top of the meter.</summary>
public sealed record PricingSwitchesDto(
    decimal RoundingStep,
    bool ZonesEnabled,
    bool FuelEnabled,
    bool SurgeEnabled,
    decimal OfferCeiling);

public sealed record PricingSwitchSuggestionDto(string Key, string Value, string Reason);

/// <summary>What is actually running behind the switches right now.</summary>
public sealed record PricingStatusDto(
    int ActiveZones,
    decimal PetrolBaseline,
    decimal DieselBaseline,
    decimal? PetrolPrice,
    decimal? DieselPrice,
    int SurgeSteps,
    int SpecialRules,
    IReadOnlyList<string> OpsAdjustments);

public sealed record PricingSetupDto(
    IReadOnlyList<PricingVehicleRowDto> Vehicles,
    PricingSwitchesDto Switches,
    IReadOnlyList<PricingSwitchSuggestionDto> SwitchSuggestions,
    PricingStatusDto Status,
    IReadOnlyList<Guid> StandardRuleIds);

public sealed record SavePricingRateRequest(
    string Category,
    decimal BaseFare,
    decimal PerKmRate,
    decimal PerMinuteRate,
    decimal MinimumFare);

public sealed record SavePricingRatesRequest(IReadOnlyList<SavePricingRateRequest> Rates);

public sealed record SavePricingSwitchesRequest(
    decimal RoundingStep,
    bool ZonesEnabled,
    bool FuelEnabled,
    bool SurgeEnabled,
    decimal OfferCeiling);

public sealed record PricingCheckRequest(
    string Category,
    double PickupLatitude,
    double PickupLongitude,
    double? DestinationLatitude,
    double? DestinationLongitude,
    double DistanceKm,
    double Minutes);

public sealed record PricingCheckLineDto(string Label, string Value, bool Dim);

public sealed record PricingCheckDto(
    string RuleName,
    IReadOnlyList<PricingCheckLineDto> Lines,
    decimal Recommended,
    decimal Minimum,
    decimal Maximum,
    bool Negotiable,
    decimal AppListEstimate);
