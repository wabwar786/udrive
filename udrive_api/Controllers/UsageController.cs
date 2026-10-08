using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>The app says it is open. Works signed in or not.</summary>
[ApiController]
[AllowAnonymous]
[Route("api/v1/telemetry")]
public sealed class TelemetryController(UsageService service) : ControllerBase
{
    [HttpPost("ping")]
    [EnableRateLimiting("telemetry")]
    public async Task<IActionResult> Ping([FromBody] UsagePingRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.PingAsync(
            request, User.GetUserIdOrNull(), HttpContext.Connection.RemoteIpAddress, ct));
}

/// <summary>Admin → App usage.</summary>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager")]
[Route("api/v1/admin/usage")]
public sealed class AdminUsageController(UsageService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Summary([FromQuery] int days = 7, [FromQuery] string? role = null, CancellationToken ct = default) =>
        HubResults.From(this, await service.SummaryAsync(days, role, ct));

    [HttpGet("devices")]
    public async Task<IActionResult> Devices(
        [FromQuery] int days = 7,
        [FromQuery] string? role = null,
        [FromQuery] string? q = null,
        [FromQuery] string? city = null,
        [FromQuery] int limit = 100,
        CancellationToken ct = default) =>
        HubResults.From(this, await service.DevicesAsync(days, role, q, city, limit, ct));

    [HttpGet("devices/{installId}")]
    public async Task<IActionResult> Device(string installId, CancellationToken ct) =>
        HubResults.From(this, await service.DeviceAsync(installId, ct));

    [Authorize(Roles = "SuperAdmin,Admin")]
    [HttpPost("geo-token")]
    public async Task<IActionResult> GeoToken([FromBody] UsageGeoTokenRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SetTokenAsync(request.Token, ct));
}
