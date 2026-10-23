using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>Website → "Become a partner": send a request, see its status, reply.</summary>
[ApiController]
[Authorize]
[RejectMarkup]
[EnableRateLimiting("web-book")]
[Route("api/v1/web/partner")]
public sealed class PartnerRequestController(PartnerRequestService service) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Submit(SubmitPartnerRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SubmitAsync(User.GetRequiredUserId(), request, ct));

    [HttpGet("mine")]
    public async Task<IActionResult> Mine(CancellationToken ct) =>
        HubResults.From(this, await service.MineAsync(User.GetRequiredUserId(), ct));

    [HttpPost("{id:guid}/reply")]
    public async Task<IActionResult> Reply(Guid id, PartnerMessageRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.ApplicantReplyAsync(User.GetRequiredUserId(), id, request, ct));
}

/// <summary>Admin portal → Partner requests.</summary>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations")]
[RejectMarkup]
[Route("api/v1/admin/partner-requests")]
public sealed class AdminPartnerRequestController(PartnerRequestService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] string? status, CancellationToken ct) =>
        HubResults.From(this, await service.AdminListAsync(status, ct));

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct) =>
        HubResults.From(this, await service.AdminGetAsync(id, ct));

    [HttpPost("{id:guid}/status")]
    public async Task<IActionResult> Status(Guid id, PartnerStatusRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.AdminStatusAsync(User.GetRequiredUserId(), id, request, ct));

    [HttpPost("{id:guid}/reply")]
    public async Task<IActionResult> Reply(Guid id, AdminPartnerReplyRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.AdminReplyAsync(User.GetRequiredUserId(), id, request, ct));
}
