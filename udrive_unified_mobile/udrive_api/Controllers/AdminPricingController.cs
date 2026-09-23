using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// Per-kilometre pricing, editable from the admin portal.
/// </summary>
/// <remarks>
/// Deliberately narrower than the other admin sections. Changing a per-km rate
/// changes what every customer is quoted from the next request onwards, so it
/// sits with the people who carry that decision rather than with everyone who
/// can open the portal.
/// </remarks>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations,FinanceOfficer")]
[Route("api/v1/admin/pricing-rules")]
public sealed class AdminPricingController(
    PricingRulesService service,
    SeatFaresService seatFares) : ControllerBase
{
    // ------------------------------------------------- fixed per-seat routes

    [HttpGet("/api/v1/admin/seat-fares")]
    public async Task<IActionResult> ListSeatFares(CancellationToken ct) =>
        Result(await seatFares.ListAsync(ct));

    [Authorize(Roles = "SuperAdmin,Admin,FinanceOfficer")]
    [HttpPost("/api/v1/admin/seat-fares")]
    public async Task<IActionResult> CreateSeatFare(
        UpsertSeatFareRequest request,
        CancellationToken ct) =>
        Result(await seatFares.CreateAsync(request, ct));

    [Authorize(Roles = "SuperAdmin,Admin,FinanceOfficer")]
    [HttpPut("/api/v1/admin/seat-fares/{id:guid}")]
    public async Task<IActionResult> UpdateSeatFare(
        Guid id,
        UpsertSeatFareRequest request,
        CancellationToken ct) =>
        Result(await seatFares.UpdateAsync(id, request, ct));

    [Authorize(Roles = "SuperAdmin,Admin")]
    [HttpDelete("/api/v1/admin/seat-fares/{id:guid}")]
    public async Task<IActionResult> DeleteSeatFare(Guid id, CancellationToken ct) =>
        Result(await seatFares.DeleteAsync(id, ct));

    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct) =>
        Result(await service.ListAsync(ct));

    /// <summary>What each vehicle would cost for a sample trip, right now.</summary>
    /// <remarks>
    /// Lets a rate be checked before it is saved. Without it the only way to
    /// test a change was to book a ride, so a mistyped figure reached customers
    /// before it reached anyone who could see it was wrong.
    /// </remarks>
    [HttpGet("preview")]
    public async Task<IActionResult> Preview(
        [FromQuery] string serviceType = "City",
        [FromQuery] double distanceKm = 10,
        [FromQuery] int minutes = 20,
        [FromQuery] double? lat = null,
        [FromQuery] double? lng = null,
        CancellationToken ct = default) =>
        Result(await service.PreviewAsync(
            serviceType, distanceKm, minutes, lat, lng, ct));

    [Authorize(Roles = "SuperAdmin,Admin,FinanceOfficer")]
    [HttpPost]
    public async Task<IActionResult> Create(
        UpsertPricingRuleRequest request,
        CancellationToken ct) =>
        Result(await service.CreateAsync(request, ct));

    [Authorize(Roles = "SuperAdmin,Admin,FinanceOfficer")]
    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(
        Guid id,
        UpsertPricingRuleRequest request,
        CancellationToken ct) =>
        Result(await service.UpdateAsync(id, request, ct));

    [Authorize(Roles = "SuperAdmin,Admin")]
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct) =>
        Result(await service.DeleteAsync(id, ct));

    private IActionResult Result<T>(ServiceResult<T> result)
    {
        if (!result.Success)
        {
            return StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
                traceId = HttpContext.TraceIdentifier,
            });
        }

        var body = ApiResponse<T>.Ok(result.Data!, result.Message);
        return result.StatusCode == StatusCodes.Status201Created
            ? StatusCode(201, body)
            : Ok(body);
    }
}
