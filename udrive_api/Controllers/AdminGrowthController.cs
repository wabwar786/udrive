using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// The admin side of the driver growth system.
/// </summary>
/// <remarks>
/// Narrower than most admin sections. Everything behind these routes either
/// spends money or decides which city is live, so it sits with the roles that
/// carry those decisions rather than with everyone who can open the portal —
/// the same reasoning as the pricing section.
/// </remarks>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations,FinanceOfficer")]
[Route("api/v1/admin/growth")]
public sealed class AdminGrowthController(AdminGrowthService service) : ControllerBase
{
    // ───────────────────────────────────────────────────────────────  cities

    [HttpGet("cities")]
    public async Task<IActionResult> Cities(CancellationToken ct) =>
        Result(await service.CitiesAsync(ct));

    [HttpPost("cities")]
    public async Task<IActionResult> CreateCity(
        LaunchCityRequest request,
        CancellationToken ct) =>
        Result(await service.SaveCityAsync(null, request, ct));

    [HttpPut("cities/{id:guid}")]
    public async Task<IActionResult> UpdateCity(
        Guid id,
        LaunchCityRequest request,
        CancellationToken ct) =>
        Result(await service.SaveCityAsync(id, request, ct));

    // ────────────────────────────────────────────────────────────  campaigns

    [HttpGet("campaigns")]
    public async Task<IActionResult> Campaigns(
        [FromQuery] Guid? cityId,
        CancellationToken ct) =>
        Result(await service.CampaignsAsync(cityId, ct));

    [HttpPost("campaigns")]
    public async Task<IActionResult> CreateCampaign(
        GrowthCampaignRequest request,
        CancellationToken ct) =>
        Result(await service.SaveCampaignAsync(
            null, request, User.GetUserIdOrNull(), ct));

    [HttpPut("campaigns/{id:guid}")]
    public async Task<IActionResult> UpdateCampaign(
        Guid id,
        GrowthCampaignRequest request,
        CancellationToken ct) =>
        Result(await service.SaveCampaignAsync(
            id, request, User.GetUserIdOrNull(), ct));

    /// <summary>
    /// Stops or restarts a campaign without deleting what it has paid.
    /// </summary>
    [HttpPost("campaigns/{id:guid}/active")]
    public async Task<IActionResult> SetActive(
        Guid id,
        SetActiveRequest request,
        CancellationToken ct) =>
        Result(await service.SetCampaignActiveAsync(id, request.Active, ct));

    /// <summary>Who this campaign has paid, and who is still working on it.</summary>
    [HttpGet("campaigns/{id:guid}/awards")]
    public async Task<IActionResult> Awards(Guid id, CancellationToken ct) =>
        Result(await service.AwardsAsync(id, ct));

    // ──────────────────────────────────────────────────────── demand windows

    [HttpGet("demand-windows")]
    public async Task<IActionResult> DemandWindows(CancellationToken ct) =>
        Result(await service.DemandWindowsAsync(ct));

    [HttpPost("demand-windows")]
    public async Task<IActionResult> CreateDemandWindow(
        ExpectedDemandRequest request,
        CancellationToken ct) =>
        Result(await service.SaveDemandWindowAsync(
            null, request, User.GetUserIdOrNull(), ct));

    [HttpPut("demand-windows/{id:guid}")]
    public async Task<IActionResult> UpdateDemandWindow(
        Guid id,
        ExpectedDemandRequest request,
        CancellationToken ct) =>
        Result(await service.SaveDemandWindowAsync(
            id, request, User.GetUserIdOrNull(), ct));

    [HttpDelete("demand-windows/{id:guid}")]
    public async Task<IActionResult> DeleteDemandWindow(
        Guid id,
        CancellationToken ct) =>
        Result(await service.DeleteDemandWindowAsync(id, ct));

    // ──────────────────────────────────────────────────────────────  updates

    [HttpGet("updates")]
    public async Task<IActionResult> ListUpdates(CancellationToken ct) =>
        Result(await service.ListUpdatesAsync(ct));

    [HttpDelete("updates/{id:guid}")]
    public async Task<IActionResult> DeleteUpdate(Guid id, CancellationToken ct) =>
        Result(await service.DeleteUpdateAsync(id, ct));

    [HttpPost("updates")]
    public async Task<IActionResult> CreateUpdate(
        DriverUpdateRequest request,
        CancellationToken ct) =>
        Result(await service.SaveUpdateAsync(
            null, request, User.GetUserIdOrNull(), ct));

    [HttpPut("updates/{id:guid}")]
    public async Task<IActionResult> UpdateUpdate(
        Guid id,
        DriverUpdateRequest request,
        CancellationToken ct) =>
        Result(await service.SaveUpdateAsync(
            id, request, User.GetUserIdOrNull(), ct));

    // ─────────────────────────────────────────────────────────── fraud review

    [HttpGet("fraud-flags")]
    public async Task<IActionResult> FraudFlags(
        [FromQuery] string? status,
        CancellationToken ct) =>
        Result(await service.FraudFlagsAsync(status, ct));

    [HttpPost("fraud-flags/{id:guid}/review")]
    public async Task<IActionResult> ReviewFlag(
        Guid id,
        FraudReviewRequest request,
        CancellationToken ct) =>
        Result(await service.ReviewFraudFlagAsync(
            id, request, User.GetUserIdOrNull(), ct));

    // ───────────────────────────────────────────────────────────────  founding

    [HttpPost("founding/{driverProfileId:guid}")]
    public async Task<IActionResult> GrantFounding(
        Guid driverProfileId,
        CancellationToken ct) =>
        Result(await service.GrantFoundingAsync(driverProfileId, ct));

    private IActionResult Result<T>(ServiceResult<T> result) =>
        result.Success
            ? Ok(ApiResponse<T>.Ok(result.Data!, result.Message))
            : StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
            });
}

public sealed record SetActiveRequest(bool Active);
