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
    [HttpGet("/api/v1/settings/tracking")]
    public async Task<IActionResult> Tracking(CancellationToken ct) =>
        Ok(ApiResponse<object>.Ok(new
        {
            pingSeconds = await service.TrackingIntervalSecondsAsync(ct),
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
