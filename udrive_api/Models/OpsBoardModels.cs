namespace UDrive.Api.Models;

// Ops board ("Aaj ke kaam"). Everything here is read-only output except the
// request records at the bottom.

public sealed record OpsKpiDto(string Key, string Label, string Value, string? Note, string Trend);

public sealed record OpsCardButtonDto(string Kind, string Label, IReadOnlyDictionary<string, string> Args);

public sealed record OpsCardDto(
    string Key,
    string Kind,
    string Severity,
    string Title,
    string Body,
    string Why,
    string Since,
    IReadOnlyList<OpsCardButtonDto> Buttons);

public sealed record OpsAreaRowDto(
    Guid TerritoryId,
    string Tehsil,
    string District,
    int Requests30,
    int DriversOnline,
    int NoOffer,
    string OfferGap,
    string State);

public sealed record OpsLiveRideDto(
    Guid BookingId,
    string Reference,
    string Vehicle,
    string Route,
    string Status,
    string Flag,
    string FlagTone);

public sealed record OpsAccountsDto(
    int NewCustomers,
    int NewDrivers,
    int NewOwners,
    int NewHotelOwners,
    int Deleted,
    IReadOnlyList<string> DeleteReasons,
    int ActiveUsers,
    IReadOnlyList<string> Versions);

public sealed record OpsHourDto(int Hour, int Today, double Usual);

public sealed record OpsWeatherDayDto(string Date, int Code, double Max, double Min, double Rain, double Snow, double Wind);

public sealed record OpsWeatherRowDto(
    string PlaceKey,
    string Name,
    double? NowTemp,
    int? NowCode,
    IReadOnlyList<OpsWeatherDayDto> Days,
    string Risk,
    string RiskTone,
    string? Affects);

public sealed record OpsLogDto(string At, string Card, string Decision, string Actor, string Detail);

public sealed record OpsFareAdjustmentDto(Guid Id, string Tehsil, string VehicleClass, decimal Percent, string Until, string Reason);

public sealed record OpsRoadReportDto(Guid Id, string Tehsil, string Kind, string Note, double Latitude, double Longitude, string Ago, string Driver);

public sealed record OpsBoardDto(
    string UpdatedAt,
    IReadOnlyList<OpsKpiDto> Kpis,
    IReadOnlyList<OpsCardDto> Cards,
    IReadOnlyList<OpsAreaRowDto> Areas,
    IReadOnlyList<OpsLiveRideDto> LiveRides,
    OpsAccountsDto Accounts,
    IReadOnlyList<OpsHourDto> Hours,
    IReadOnlyList<OpsWeatherRowDto> Weather,
    string? WeatherFetchedAt,
    IReadOnlyList<OpsFareAdjustmentDto> FareAdjustments,
    IReadOnlyList<OpsRoadReportDto> RoadReports,
    IReadOnlyList<OpsLogDto> Log);

public sealed record OpsFareAdjustmentRequest(Guid TerritoryId, string VehicleClass, decimal Percent, string? CardKey, string? Reason);

public sealed record OpsDecisionRequest(string CardKey, string CardKind, string? Title, string Decision, string? Detail);

public sealed record OpsRoadReviewRequest(bool Valid);

/// <summary>Who a board WhatsApp goes to. The server works out the list itself.</summary>
public sealed record OpsAudienceRequest(string Audience, Guid? TerritoryId, string? VehicleClass, string? CardKey, string? Body);

public sealed record OpsRecipientDto(string Name, string Phone);

public sealed record OpsMessagePreviewDto(string Audience, string AudienceLabel, string Body, int Count, IReadOnlyList<OpsRecipientDto> Recipients);

public sealed record OpsAdvisoryRequest(string Title, string? Details, int Hours, string? CardKey);

public sealed record RoadReportRequest(double Latitude, double Longitude, string? Kind, string? Note);
