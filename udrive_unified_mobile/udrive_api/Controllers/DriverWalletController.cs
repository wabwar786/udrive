using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// The Driver's prepaid commission balance.
/// </summary>
[ApiController]
[Authorize]
[Route("api/v1/driver/wallet")]
public sealed class DriverWalletController(DriverWalletService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Summary(CancellationToken ct) =>
        Result(await service.SummaryAsync(User.GetRequiredUserId(), ct));

    /// <summary>Where to send a top-up.</summary>
    /// <remarks>
    /// From settings rather than printed in the app. The number changes —
    /// accounts get closed, ownership moves — and one baked into a release
    /// means money sent somewhere nobody is watching until the next deploy.
    /// </remarks>
    [HttpGet("topup-account")]
    public async Task<IActionResult> TopupAccount(
        [FromServices] ServiceAvailabilityService settings,
        CancellationToken ct)
    {
        var (number, name) = await settings.TopupAccountAsync(ct);
        return Ok(ApiResponse<object>.Ok(new
        {
            easypaisaNumber = number,
            accountName = name,
        }));
    }

    /// <summary>Every commission charge, newest first.</summary>
    /// <remarks>
    /// A balance alone invites the question a Driver cannot answer: where did
    /// it go? This is the ledger behind it — one line per ride, with the fare,
    /// the rate applied and the amount taken.
    ///
    /// The rate is stored per entry rather than read from settings at display
    /// time, so a Driver looking back at last month sees what they were
    /// actually charged, not what the rate happens to be today.
    /// </remarks>
    [HttpGet("commission")]
    public async Task<IActionResult> Commission(
        [FromQuery] int take = 50,
        CancellationToken ct = default) =>
        Result(await service.CommissionHistoryAsync(
            User.GetRequiredUserId(), Math.Clamp(take, 1, 200), ct));

    /// <summary>Records a payment the Driver says they have sent.</summary>
    /// <remarks>
    /// Nothing is credited here. A screenshot is a claim, not a receipt, and
    /// crediting on upload would make the balance forgeable with an image
    /// editor. The balance moves when an Admin has seen the money arrive.
    /// </remarks>
    [HttpPost("topups")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(10 * 1024 * 1024)]
    public async Task<IActionResult> SubmitTopup(
        [FromForm] decimal amount,
        [FromForm] string? senderReference,
        IFormFile? file,
        CancellationToken ct) =>
        Result(await service.SubmitTopupAsync(
            User.GetRequiredUserId(), amount, senderReference, file, ct));

    private IActionResult Result<T>(ServiceResult<T> result)
    {
        if (!result.Success)
        {
            return StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
            });
        }

        var body = ApiResponse<T>.Ok(result.Data!, result.Message);
        return result.StatusCode == StatusCodes.Status201Created
            ? StatusCode(201, body)
            : Ok(body);
    }
}

/// <summary>
/// Confirming that Driver top-up money actually arrived.
/// </summary>
/// <remarks>
/// Narrow roles on purpose. Approving a top-up creates credit out of nothing if
/// the money is not really there, so it sits with the people who can see the
/// company's own statement.
/// </remarks>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,FinanceOfficer")]
[Route("api/v1/admin/wallet-topups")]
public sealed class AdminWalletTopupsController(DriverWalletService service) : ControllerBase
{
    [HttpGet("pending")]
    public async Task<IActionResult> Pending(CancellationToken ct) =>
        Result(await service.PendingAsync(ct));

    [HttpPost("{topupId:guid}/review")]
    public async Task<IActionResult> Review(
        Guid topupId,
        ReviewTopupRequest request,
        CancellationToken ct) =>
        Result(await service.ReviewTopupAsync(
            User.GetRequiredUserId(), topupId, request.Approve, request.Notes, ct));

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
