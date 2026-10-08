using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>The hotel owner's home screen and guest arrival / departure.</summary>
[ApiController]
[Authorize]
[Route("api/v1/hotels/owner")]
public sealed class HotelOwnerDashboardController(HotelOwnerDashboardService service) : ControllerBase
{
    [HttpGet("dashboard")]
    public async Task<IActionResult> Dashboard([FromQuery] Guid? hotelId, CancellationToken ct) =>
        HubResults.From(this, await service.DashboardAsync(User.GetRequiredUserId(), hotelId, ct));

    /// <summary>Status: CheckedIn (guest arrived) or CheckedOut (guest left).</summary>
    [HttpPost("bookings/{bookingId:guid}/status/{status}")]
    public async Task<IActionResult> SetStatus(Guid bookingId, string status, CancellationToken ct) =>
        HubResults.From(this, await service.SetStatusAsync(User.GetRequiredUserId(), bookingId, status, ct));
}
