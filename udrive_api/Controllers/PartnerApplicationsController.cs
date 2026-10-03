using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// "Become a partner", from the customer app.
/// </summary>
/// <remarks>
/// Any signed-in customer, with no role attached. That is the point: a partner is
/// somebody who already uses UDrive in their own town, and the queue the admin
/// works through is built from these requests rather than from names an admin
/// types in.
///
/// <para>Nothing here returns another partner's terms. The territory list says
/// whether a place is taken and who holds it — a partner is a public role in a
/// town, and somebody deciding whether to apply has to know the job is open. It
/// does not say what anybody was paid, deposited, or committed to.</para>
/// </remarks>
[ApiController]
[Authorize]
[Route("api/v1/partners")]
public sealed class PartnerApplicationsController(
    PartnerDirectoryService service) : ControllerBase
{
    /// <summary>The tiers, the territory tree, and where the caller stands.</summary>
    [HttpGet("openings")]
    public async Task<IActionResult> Openings(CancellationToken ct) =>
        Result(await service.OpeningsAsync(User.GetRequiredUserId(), ct));

    [HttpGet("me")]
    public async Task<IActionResult> Mine(CancellationToken ct) =>
        Result(await service.MineAsync(User.GetRequiredUserId(), ct));

    [HttpPost("applications")]
    public async Task<IActionResult> Apply(
        PartnerApplicationRequest request,
        CancellationToken ct) =>
        Result(await service.ApplyAsync(User.GetRequiredUserId(), request, ct));

    [HttpPost("applications/{id:guid}/withdraw")]
    public async Task<IActionResult> Withdraw(Guid id, CancellationToken ct) =>
        Result(await service.WithdrawAsync(User.GetRequiredUserId(), id, ct));

    private IActionResult Result<T>(ServiceResult<T> result) =>
        result.Success
            ? Ok(ApiResponse<T>.Ok(result.Data!, result.Message))
            : StatusCode(
                result.StatusCode,
                new
                {
                    success = false,
                    error = result.ErrorCode,
                    message = result.Message,
                    traceId = HttpContext.TraceIdentifier,
                });
}

/// <summary>
/// Which city the customer is in, and whether UDrive runs there.
/// </summary>
/// <remarks>
/// <b>Anonymous on purpose.</b> The city gate is the first thing the app asks
/// about, often before anybody has signed in, and a city list behind a token
/// means a brand-new user in Rawalakot is shown a working home screen in a city
/// with no drivers.
///
/// <para>Joining the waiting list does need an account — the whole value of the
/// list is being able to tell those people the day the city opens.</para>
/// </remarks>
[ApiController]
[Route("api/v1/cities")]
public sealed class CityStatusController(PartnerDirectoryService service) : ControllerBase
{
    [HttpGet("status")]
    [AllowAnonymous]
    public async Task<IActionResult> Status(
        [FromQuery] double? lat,
        [FromQuery] double? lng,
        CancellationToken ct) =>
        Result(await service.CityStatusAsync(lat, lng, User.GetUserIdOrNull(), ct));

    [HttpPost("waitlist")]
    [Authorize]
    public async Task<IActionResult> Join(WaitlistJoinRequest request, CancellationToken ct) =>
        Result(await service.JoinWaitlistAsync(User.GetRequiredUserId(), request, ct));

    [HttpDelete("waitlist/{cityId:guid}")]
    [Authorize]
    public async Task<IActionResult> Leave(Guid cityId, CancellationToken ct) =>
        Result(await service.LeaveWaitlistAsync(User.GetRequiredUserId(), cityId, ct));

    private IActionResult Result<T>(ServiceResult<T> result) =>
        result.Success
            ? Ok(ApiResponse<T>.Ok(result.Data!, result.Message))
            : StatusCode(
                result.StatusCode,
                new
                {
                    success = false,
                    error = result.ErrorCode,
                    message = result.Message,
                    traceId = HttpContext.TraceIdentifier,
                });
}
