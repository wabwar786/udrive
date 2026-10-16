using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>The admin Ops board ("Aaj ke kaam").</summary>
/// <remarks>
/// Under the Operations module for team users (TeamAccess). Every action is an
/// explicit admin decision; nothing here runs by itself.
/// </remarks>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations,Staff")]
[Route("api/v1/admin/ops")]
public sealed class OpsBoardController(OpsBoardService service) : ControllerBase
{
    [HttpGet("board")]
    public async Task<IActionResult> Board([FromQuery] Guid? district, CancellationToken ct) =>
        HubResults.From(this, await service.BoardAsync(district, ct));

    [HttpPost("fare-adjustments")]
    public async Task<IActionResult> Fare(OpsFareAdjustmentRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SetFareAdjustmentAsync(User.GetRequiredUserId(), request, ct));

    [HttpPost("fare-adjustments/{id:guid}/end")]
    public async Task<IActionResult> EndFare(Guid id, CancellationToken ct) =>
        HubResults.From(this, await service.EndFareAdjustmentAsync(User.GetRequiredUserId(), id, ct));

    [HttpPost("decisions")]
    public async Task<IActionResult> Decide(OpsDecisionRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.DecideAsync(User.GetRequiredUserId(), request, ct));

    [HttpPost("road-reports/review")]
    public async Task<IActionResult> Review([FromQuery] string ids, [FromQuery] bool valid, CancellationToken ct)
    {
        var list = (ids ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries)
            .Select(s => Guid.TryParse(s, out var g) ? g : Guid.Empty).Where(g => g != Guid.Empty).Take(50).ToList();
        return HubResults.From(this, await service.ReviewRoadReportsAsync(User.GetRequiredUserId(), list, valid, ct));
    }

    [HttpPost("advisories")]
    public async Task<IActionResult> Advisory(OpsAdvisoryRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.AdvisoryAsync(User.GetRequiredUserId(), request, ct));

    /// <summary>Shows the message and the people it would go to. Sends nothing.</summary>
    [HttpPost("messages/preview")]
    public async Task<IActionResult> Preview(OpsAudienceRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.PreviewAsync(request, ct));

    /// <summary>Queues the message the admin read. The list is rebuilt on the server.</summary>
    [HttpPost("messages/send")]
    public async Task<IActionResult> Send(OpsAudienceRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SendAsync(User.GetRequiredUserId(), request, ct));
}

/// <summary>"Road band hai" from the driver app.</summary>
[ApiController]
[Authorize]
[Route("api/v1/ops")]
public sealed class RoadReportController(OpsBoardService service) : ControllerBase
{
    [HttpPost("road-reports")]
    public async Task<IActionResult> Report(RoadReportRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.ReportRoadAsync(User.GetRequiredUserId(), request, ct));
}
