using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// Chat and passenger context for one booking.
/// </summary>
/// <remarks>
/// Every route is scoped to a booking the caller is part of. There is no
/// general inbox and no way to reach someone you are not currently travelling
/// with — which is the point, not a limitation: a Driver must not be able to
/// keep messaging a Customer after the ride has ended.
/// </remarks>
[ApiController]
[Authorize]
[Route("api/v1/trips/{bookingId:guid}")]
public sealed class TripChatController(TripChatService service) : ControllerBase
{
    /// <summary>The signed-in Driver's own dashboard figures.</summary>
    /// <remarks>
    /// Not booking-scoped, so it sits on its own route outside this
    /// controller's prefix rather than pretending to belong to a trip.
    /// </remarks>
    [HttpGet("/api/v1/driver/dashboard")]
    public async Task<IActionResult> DriverDashboard(CancellationToken ct) =>
        Result(await service.DriverDashboardAsync(User.GetRequiredUserId(), ct));

    [HttpGet("messages")]
    public async Task<IActionResult> Messages(
        Guid bookingId,
        [FromQuery] DateTimeOffset? after,
        CancellationToken ct) =>
        Result(await service.MessagesAsync(
            User.GetRequiredUserId(), bookingId, after, ct));

    [HttpPost("messages")]
    public async Task<IActionResult> Send(
        Guid bookingId,
        SendTripMessageRequest request,
        CancellationToken ct) =>
        Result(await service.SendAsync(
            User.GetRequiredUserId(), bookingId, request, ct));

    /// <summary>Driver only: the passenger's history on this platform.</summary>
    [HttpGet("passenger")]
    public async Task<IActionResult> Passenger(Guid bookingId, CancellationToken ct) =>
        Result(await service.PassengerStandingAsync(
            User.GetRequiredUserId(), bookingId, ct));

    /// <summary>Customer only: the Driver's rating and recent reviews.</summary>
    [HttpGet("driver")]
    public async Task<IActionResult> Driver(Guid bookingId, CancellationToken ct) =>
        Result(await service.DriverReputationAsync(
            User.GetRequiredUserId(), bookingId, ct));

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
