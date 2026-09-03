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
