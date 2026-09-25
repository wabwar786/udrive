using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// Fare zones, fuel prices and what routes are really agreed at.
/// </summary>
/// <remarks>
/// The same audience as the per-kilometre rates next door, and for the same
/// reason: each of these changes what every customer is quoted from the next
/// request onwards.
/// </remarks>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations,FinanceOfficer")]
[Route("api/v1/admin/fare")]
public sealed class AdminFareController(
    PricingZoneService zones,
    FuelPriceService fuelPrices,
    RateInsightsService insights,
    PricingSettingsService settings) : ControllerBase
{
    // ------------------------------------------------------------- zones

    [HttpGet("zones")]
    public async Task<IActionResult> ListZones(CancellationToken ct) =>
        Ok(ApiResponse<IReadOnlyList<PricingZoneDetailDto>>.Ok(await zones.ListAsync(ct)));

    [Authorize(Roles = "SuperAdmin,Admin,FinanceOfficer")]
    [HttpPost("zones")]
    public async Task<IActionResult> SaveZone(
        SavePricingZoneRequest request,
        CancellationToken ct)
    {
        if (request.Areas.Count == 0)
        {
            // A zone with no circles covers nothing, so it would sit in the
            // list looking active and price nothing. Better to refuse it than
            // to let someone spend a week wondering why their Neelum rate
            // never applies.
            return StatusCode(StatusCodes.Status400BadRequest, new
            {
                success = false,
                error = "zone_has_no_area",
                message = "Add at least one circle — a centre and a radius — before saving this zone.",
                traceId = HttpContext.TraceIdentifier,
            });
        }

        if (request.ActiveMonths is not null
            && request.ActiveMonths.Any(month => month is < 1 or > 12))
        {
            return StatusCode(StatusCodes.Status400BadRequest, new
            {
                success = false,
                error = "zone_months_invalid",
                message = "Months must be 1 (January) to 12 (December).",
                traceId = HttpContext.TraceIdentifier,
            });
        }

        var id = await zones.SaveAsync(request, ct);
        return Ok(ApiResponse<Guid>.Ok(id, "Zone saved."));
    }

    [Authorize(Roles = "SuperAdmin,Admin,FinanceOfficer")]
    [HttpDelete("zones/{id:guid}")]
    public async Task<IActionResult> DeleteZone(Guid id, CancellationToken ct)
    {
        var removed = await zones.DeleteAsync(id, ct);
        return removed
            ? Ok(ApiResponse<bool>.Ok(true, "Zone deleted."))
            : StatusCode(StatusCodes.Status404NotFound, new
            {
                success = false,
                error = "zone_not_found",
                message = "That zone no longer exists.",
                traceId = HttpContext.TraceIdentifier,
            });
    }

    // -------------------------------------------------------------- fuel

    [HttpGet("fuel-prices")]
    public async Task<IActionResult> ListFuel(
        [FromQuery] int limit,
        CancellationToken ct) =>
        Ok(ApiResponse<IReadOnlyList<FuelPriceDto>>.Ok(await fuelPrices.ListAsync(limit, ct)));

    [HttpGet("fuel-baselines")]
    public async Task<IActionResult> Baselines(CancellationToken ct) =>
        Ok(ApiResponse<FuelBaselinesDto>.Ok(await fuelPrices.GetBaselinesAsync(ct)));

    [Authorize(Roles = "SuperAdmin,Admin,FinanceOfficer")]
    [HttpPut("fuel-baselines")]
    public async Task<IActionResult> SaveBaselines(
        SaveFuelBaselinesRequest request,
        CancellationToken ct)
    {
        var saved = await fuelPrices.SaveBaselinesAsync(request, User.GetUserIdOrNull(), ct);
        settings.Invalidate();
        return Ok(ApiResponse<FuelBaselinesDto>.Ok(saved, "Baselines saved."));
    }

    [Authorize(Roles = "SuperAdmin,Admin,FinanceOfficer")]
    [HttpPost("fuel-prices")]
    public async Task<IActionResult> RecordFuel(
        SaveFuelPriceRequest request,
        CancellationToken ct)
    {
        var saved = await fuelPrices.RecordAsync(request, User.GetUserIdOrNull(), ct);

        // The fuel index is read through the settings cache, so an admin who
        // records today's price should see it in the next quote rather than up
        // to a minute later.
        settings.Invalidate();
        return Ok(ApiResponse<FuelPriceDto>.Ok(saved, "Fuel price recorded."));
    }

    // ---------------------------------------------------------- insights

    /// <summary>
    /// What routes are agreed at, against what the platform suggests.
    /// </summary>
    /// <remarks>
    /// Read-only, and deliberately so. It reports; the admin decides. Nothing
    /// on this endpoint changes a price.
    /// </remarks>
    [HttpGet("route-insights")]
    public async Task<IActionResult> RouteInsights(
        [FromQuery] int days,
        [FromQuery] int minimumSample,
        CancellationToken ct) =>
        Ok(ApiResponse<IReadOnlyList<RouteInsightDto>>.Ok(
            await insights.ListAsync(days, minimumSample, ct)));
}
