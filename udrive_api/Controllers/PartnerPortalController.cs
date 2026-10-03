using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// The partner's own portal.
/// </summary>
/// <remarks>
/// <b>Not one route here takes a partner id.</b> Every method hands the service
/// the user id out of the token and lets it find the partner. There is no
/// identifier in any URL for somebody to change, so a partner cannot reach
/// another partner's contract, statements or evidence — the scoping is in the
/// shape of the API rather than in a check that a later route might forget.
///
/// <para>The sign-in is the same WhatsApp OTP the app uses, against the same
/// <c>users</c> row. A partner is a customer who signed a contract, so giving
/// them a second kind of account would mean a second password to lose.</para>
/// </remarks>
[ApiController]
[Authorize]
[Route("api/v1/partner")]
public sealed class PartnerPortalController(PartnerPortalService service) : ControllerBase
{
    /// <summary>Everything the dashboard shows, in one call.</summary>
    [HttpGet("me")]
    public async Task<IActionResult> Me(CancellationToken ct) =>
        Result(await service.DashboardAsync(User.GetRequiredUserId(), ct));

    /// <summary>The contract to read, with the words to read aloud.</summary>
    [HttpGet("contract")]
    public async Task<IActionResult> Contract(CancellationToken ct) =>
        Result(await service.ContractAsync(User.GetRequiredUserId(), ct));

    /// <summary>
    /// Signs it: a live photograph and a video of the words on screen.
    /// </summary>
    /// <remarks>
    /// The 30 MB limit covers a ten-megabyte photograph and a twenty-five-megabyte
    /// video with headroom; the storage service rejects anything bigger with a
    /// message naming the actual size, which is more use than a dropped
    /// connection.
    ///
    /// <para>The camera-only rule lives in the client — a server cannot tell a
    /// photograph taken now from one chosen out of a gallery. What the server does
    /// instead is record the things a client cannot forge: its own clock, the IP,
    /// the OTP-proven phone number, and the exact words the contract carried.</para>
    /// </remarks>
    [HttpPost("contract/sign")]
    [RequestSizeLimit(30 * 1024 * 1024)]
    public async Task<IActionResult> Sign(
        [FromForm] IFormFile? selfie,
        [FromForm] IFormFile? video,
        [FromForm] string? deviceInfo,
        CancellationToken ct) =>
        Result(await service.SignAsync(
            User.GetRequiredUserId(),
            selfie,
            video,
            deviceInfo,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            ct));

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
