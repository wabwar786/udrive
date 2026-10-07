using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>The Tour &amp; Rent home in Driver mode.</summary>
[ApiController]
[Authorize]
[Route("api/v1/driver/tour-rent")]
public sealed class DriverTourRentController(
    TourRentDriverService service,
    BookingService bookings,
    RentalService rentals) : ControllerBase
{
    [HttpGet("home")]
    public async Task<IActionResult> Home(CancellationToken ct) =>
        Result(await service.HomeAsync(User.GetRequiredUserId(), ct));

    /// <summary>Gives a freed place to a waiting customer. Kind: tour | rent.</summary>
    [HttpPost("waitlist/{kind}/{id:guid}/accept")]
    public async Task<IActionResult> Accept(string kind, Guid id, CancellationToken ct) =>
        Result(await service.AcceptAsync(User.GetRequiredUserId(), kind.Trim().ToLowerInvariant(), id, ct));

    [HttpPost("waitlist/{kind}/{id:guid}/decline")]
    public async Task<IActionResult> Decline(string kind, Guid id, CancellationToken ct) =>
        Result(await service.DeclineAsync(User.GetRequiredUserId(), kind.Trim().ToLowerInvariant(), id, ct));

    /// <summary>
    /// The booked customer did not come. Frees the seats or the car so a
    /// waiting-list request can be accepted.
    /// </summary>
    [HttpPost("bookings/{kind}/{id:guid}/no-show")]
    public async Task<IActionResult> NoShow(string kind, Guid id, CancellationToken ct)
    {
        var userId = User.GetRequiredUserId();
        return kind.Trim().ToLowerInvariant() switch
        {
            "tour" => Result(await bookings.CancelBookingAsync(
                userId, id, new CancelBookingRequest("Customer nahi aaya (no-show) — driver ne mark kiya."), ct)),
            "rent" => Result(await rentals.SetStatusAsync(userId, id, "NoShow", ct)),
            _ => BadRequest(new { success = false, error = "kind_invalid", message = "Kind must be tour or rent." }),
        };
    }

    private IActionResult Result<T>(ServiceResult<T> result) =>
        result.Success
            ? StatusCode(result.StatusCode, ApiResponse<T>.Ok(result.Data!, result.Message))
            : StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
            });
}
