using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// Whether the driver is online, and for how long.
/// </summary>
/// <remarks>
/// Rate-limited with the location policy rather than the default. A heartbeat
/// every sixty seconds from every online driver in the city is the busiest
/// authenticated route the platform has, and it has the same shape as the
/// location pings that policy was written for.
/// </remarks>
[ApiController]
[Authorize]
[EnableRateLimiting("location")]
[Route("api/v1/driver/presence")]
public sealed class DriverPresenceController(DriverPresenceService service)
    : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> State(CancellationToken ct) =>
        Result(await service.StateAsync(User.GetRequiredUserId(), ct));

    [HttpPost("online")]
    public async Task<IActionResult> Online(
        DriverPresenceRequest request,
        CancellationToken ct) =>
        Result(await service.GoOnlineAsync(User.GetRequiredUserId(), request, ct));

    /// <summary>Keeps the session alive and credits the time since the last beat.</summary>
    [HttpPost("heartbeat")]
    public async Task<IActionResult> Heartbeat(
        DriverPresenceRequest request,
        CancellationToken ct) =>
        Result(await service.HeartbeatAsync(User.GetRequiredUserId(), request, ct));

    [HttpPost("offline")]
    public async Task<IActionResult> Offline(CancellationToken ct) =>
        Result(await service.GoOfflineAsync(User.GetRequiredUserId(), ct));

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

/// <summary>
/// What the driver has earned, is earning, and could earn next.
/// </summary>
[ApiController]
[Authorize]
[Route("api/v1/driver/growth")]
public sealed class DriverGrowthController(
    DriverGrowthService service,
    DriverReferralService referrals)
    : ControllerBase
{
    /// <summary>Everything the home screen needs, in one request.</summary>
    [HttpGet("home")]
    public async Task<IActionResult> Home(CancellationToken ct) =>
        Result(await service.HomeAsync(User.GetRequiredUserId(), ct));

    [HttpGet("missions")]
    public async Task<IActionResult> Missions(CancellationToken ct) =>
        Result(await service.MissionsAsync(User.GetRequiredUserId(), ct));

    [HttpGet("welcome-bonus")]
    public async Task<IActionResult> WelcomeBonus(CancellationToken ct) =>
        Result(await service.WelcomeBonusAsync(User.GetRequiredUserId(), ct));

    [HttpGet("referrals")]
    public async Task<IActionResult> Referrals(CancellationToken ct) =>
        Result(await service.ReferralAsync(User.GetRequiredUserId(), ct));

    [HttpGet("demand")]
    public async Task<IActionResult> Demand(CancellationToken ct) =>
        Result(await service.DemandAsync(User.GetRequiredUserId(), ct));

    [HttpGet("updates")]
    public async Task<IActionResult> Updates(CancellationToken ct) =>
        Result(await service.UpdatesAsync(User.GetRequiredUserId(), ct));

    /// <summary>This week's target, and what last week came to.</summary>
    [HttpGet("weekly")]
    public async Task<IActionResult> Weekly(CancellationToken ct) =>
        Result(await service.WeeklyAsync(User.GetRequiredUserId(), ct));

    /// <summary>Records who brought this Driver to the platform.</summary>
    /// <remarks>
    /// On <c>DriverGrowthController</c> rather than a controller of its own
    /// because a Driver reaches it from the referral screen, which is a growth
    /// screen. It is the first route in the codebase that writes
    /// <c>driver_referrals</c> at all.
    /// </remarks>
    [HttpPost("referrals/apply")]
    public async Task<IActionResult> ApplyReferral(
        ApplyReferralCodeRequest request,
        CancellationToken ct) =>
        Result(await referrals.ApplyCodeAsync(
            User.GetRequiredUserId(), request.Code, ct));

    /// <summary>Today, this week, this month — and every live way to earn.</summary>
    [HttpGet("earnings")]
    public async Task<IActionResult> Earnings(CancellationToken ct) =>
        Result(await service.EarningsAsync(User.GetRequiredUserId(), ct));

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
