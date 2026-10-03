using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>The admin portal's view of renting.</summary>
/// <remarks>
/// Read-only apart from cancelling and the settings. An Admin editing somebody
/// else's rental — its dates, its rate, its deposit — would be rewriting an
/// agreement between two other people after they made it, and neither of them
/// would be told.
/// </remarks>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations")]
[Route("api/v1/admin/rentals")]
public sealed class AdminRentalController(AdminRentalService service) : ControllerBase
{
    [HttpGet("summary")]
    public async Task<IActionResult> Summary(CancellationToken ct) =>
        Result(await service.SummaryAsync(ct));

    [HttpGet]
    public async Task<IActionResult> List(
        [FromQuery] string? scope,
        [FromQuery] string? search,
        [FromQuery] DateOnly? from,
        [FromQuery] DateOnly? to,
        CancellationToken ct) =>
        Result(await service.ListAsync(scope, search, from, to, ct));

    [HttpGet("{bookingId:guid}")]
    public async Task<IActionResult> Detail(Guid bookingId, CancellationToken ct) =>
        Result(await service.DetailAsync(bookingId, ct));

    /// <summary>Every vehicle an owner has put up for rent, listed or not.</summary>
    [HttpGet("fleet")]
    public async Task<IActionResult> Fleet(CancellationToken ct) =>
        Result(await service.FleetAsync(ct));

    /// <summary>Calls a booking off on behalf of neither side. Needs a reason.</summary>
    [Authorize(Roles = "SuperAdmin,Admin,Manager")]
    [HttpPost("{bookingId:guid}/cancel")]
    public async Task<IActionResult> Cancel(
        Guid bookingId,
        AdminCancelRentalRequest request,
        CancellationToken ct) =>
        Result(await service.CancelAsync(
            User.GetRequiredUserId(), bookingId, request.Reason, ct));

    [HttpGet("settings")]
    public async Task<IActionResult> Settings(CancellationToken ct) =>
        Result(await service.SettingsAsync(ct));

    [Authorize(Roles = "SuperAdmin,Admin")]
    [HttpPut("settings")]
    public async Task<IActionResult> SaveSettings(
        AdminRentalSettingsRequest request,
        CancellationToken ct) =>
        Result(await service.SaveSettingsAsync(request, ct));

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
