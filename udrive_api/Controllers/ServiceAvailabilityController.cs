using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>Which services the customer app may open.</summary>
/// <remarks>
/// Anonymous on purpose. The customer app reads this before anyone signs in —
/// the home screen has to know what to dim on first launch — and there is
/// nothing private here: it is the same information the tiles display.
/// </remarks>
[ApiController]
[AllowAnonymous]
[Route("api/v1/services")]
public sealed class PublicServiceAvailabilityController(
    ServiceAvailabilityService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var result = await service.ListAsync(ct);
        return Ok(ApiResponse<IReadOnlyList<ServiceAvailabilityDto>>.Ok(result.Data!));
    }

    /// <summary>How often Drivers should publish their position.</summary>
    /// <remarks>
    /// Read by both apps at launch — the Driver app to know how often to
    /// publish, the Customer app to know how often to poll. They must agree:
    /// polling slower than the Driver reports throws away fixes already paid
    /// for in battery, and polling faster returns the same point twice.
    /// </remarks>
    /// <remarks>
    /// The `tracking` path is kept as an alias because the app already calls
    /// it; `operations` is the honest name now that it carries radii too.
    /// </remarks>
    [HttpGet("/api/v1/settings/operations")]
    [HttpGet("/api/v1/settings/tracking")]
    public async Task<IActionResult> Operations(CancellationToken ct) =>
        Ok(ApiResponse<object>.Ok(new
        {
            pingSeconds = await service.TrackingIntervalSecondsAsync(ct),
            requestRadiusKm = await service.RequestRadiusKmAsync(ct),
            nearbyRadiusKm = await service.NearbyRadiusKmAsync(ct),
            commissionPercentage = await service.CommissionPercentageAsync(ct),
            welcomeBonus = await service.WelcomeBonusAsync(ct),
        }));
}

/// <summary>Opening and closing services.</summary>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin")]
[Route("api/v1/admin/services")]
public sealed class AdminServiceAvailabilityController(
    ServiceAvailabilityService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var result = await service.ListAsync(ct);
        return Ok(ApiResponse<IReadOnlyList<ServiceAvailabilityDto>>.Ok(result.Data!));
    }

    /// <summary>Sets how often Drivers publish their position.</summary>
    [HttpPut("/api/v1/admin/settings/tracking")]
    public async Task<IActionResult> SetTracking(
        SetTrackingIntervalRequest request,
        CancellationToken ct)
    {
        await service.SetTrackingIntervalAsync(
            User.GetRequiredUserId(), request.PingSeconds, ct);
        return Ok(ApiResponse<bool>.Ok(true));
    }

    /// <summary>Sets how far a request reaches, and how far customers see.</summary>
    [HttpPut("/api/v1/admin/settings/radius")]
    public async Task<IActionResult> SetRadius(
        SetRadiusRequest request,
        CancellationToken ct)
    {
        var admin = User.GetRequiredUserId();
        await service.SetRequestRadiusAsync(admin, request.RequestRadiusKm, ct);
        await service.SetNearbyRadiusAsync(admin, request.NearbyRadiusKm, ct);
        return Ok(ApiResponse<bool>.Ok(true));
    }

    /// <summary>Sets the platform's cut of each fare.</summary>
    [HttpPut("/api/v1/admin/settings/commission")]
    public async Task<IActionResult> SetCommission(
        SetCommissionRequest request,
        CancellationToken ct)
    {
        await service.SetCommissionPercentageAsync(
            User.GetRequiredUserId(), request.Percentage, ct);
        return Ok(ApiResponse<bool>.Ok(true));
    }

    /// <summary>Sets the welcome credit and the top-up account.</summary>
    [HttpPut("/api/v1/admin/settings/wallet")]
    public async Task<IActionResult> SetWallet(
        SetWalletSettingsRequest request,
        CancellationToken ct)
    {
        var admin = User.GetRequiredUserId();
        await service.SetWelcomeBonusAsync(admin, request.WelcomeBonus, ct);
        await service.SetTopupAccountAsync(
            admin,
            request.EasypaisaNumber ?? string.Empty,
            request.AccountName ?? string.Empty,
            ct);
        return Ok(ApiResponse<bool>.Ok(true));
    }

    /// <summary>The top-up account, for the admin form.</summary>
    [HttpGet("/api/v1/admin/settings/wallet")]
    public async Task<IActionResult> Wallet(CancellationToken ct)
    {
        var (number, name) = await service.TopupAccountAsync(ct);
        return Ok(ApiResponse<object>.Ok(new
        {
            welcomeBonus = await service.WelcomeBonusAsync(ct),
            easypaisaNumber = number,
            accountName = name,
        }));
    }

    [HttpPut("{serviceKey}")]
    public async Task<IActionResult> Update(
        string serviceKey,
        UpdateServiceAvailabilityRequest request,
        CancellationToken ct)
    {
        var result = await service.UpdateAsync(
            User.GetRequiredUserId(), serviceKey, request, ct);

        return result.Success
            ? Ok(ApiResponse<bool>.Ok(true))
            : StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
            });
    }
}
