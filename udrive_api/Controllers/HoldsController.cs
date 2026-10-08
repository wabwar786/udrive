using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// The Approved page: everything live or suspended, per tab, with Review
/// again, Suspend, Unsuspend and the answer to an owner's re-claim.
/// </summary>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations,VerificationOfficer")]
[Route("api/v1/admin/verify")]
public sealed class AdminApprovedController(HoldService service) : ControllerBase
{
    [HttpGet("approved-summary")]
    public async Task<IActionResult> Summary([FromQuery] string? area, CancellationToken ct) =>
        HubResults.From(this, await service.SummaryAsync(area, ct, TeamAccess.AllowedAreas(HttpContext)));

    /// <param name="state">Live, Suspended or All.</param>
    [HttpGet("{tab}/approved")]
    public async Task<IActionResult> List(
        string tab, [FromQuery] string? state, [FromQuery] string? area, [FromQuery] string? q, CancellationToken ct) =>
        HubResults.From(this, await service.ListAsync(tab.ToLowerInvariant(), state, area, q, ct, TeamAccess.AllowedAreas(HttpContext)));

    [HttpGet("{tab}/{id:guid}/approved")]
    public async Task<IActionResult> Detail(string tab, Guid id, CancellationToken ct) =>
        HubResults.From(this, await service.DetailAsync(tab.ToLowerInvariant(), id, ct));

    [HttpPost("{tab}/{id:guid}/review-again")]
    public async Task<IActionResult> ReviewAgain(string tab, Guid id, HoldReviewRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.ReviewAgainAsync(User.GetRequiredUserId(), tab.ToLowerInvariant(), id, request, ct));

    [HttpPost("{tab}/{id:guid}/suspend")]
    public async Task<IActionResult> Suspend(string tab, Guid id, HoldNoteRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SuspendAsync(User.GetRequiredUserId(), tab.ToLowerInvariant(), id, request, ct));

    [HttpPost("{tab}/{id:guid}/unsuspend")]
    public async Task<IActionResult> Unsuspend(string tab, Guid id, HoldNoteRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.UnsuspendAsync(User.GetRequiredUserId(), tab.ToLowerInvariant(), id, request, ct));

    [HttpPost("{tab}/{id:guid}/claim-reject")]
    public async Task<IActionResult> RejectClaim(string tab, Guid id, HoldNoteRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.RejectClaimAsync(User.GetRequiredUserId(), tab.ToLowerInvariant(), id, request, ct));
}

/// <summary>The owner's side: the dashboard banner, documents asked for again, and the re-claim.</summary>
[ApiController]
[Authorize]
[Route("api/v1/me/holds")]
public sealed class MyHoldsController(HoldService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Mine(CancellationToken ct) =>
        HubResults.From(this, await service.MineAsync(User.GetRequiredUserId(), ct));

    [HttpPost("{id:guid}/documents/{type}")]
    [RequestSizeLimit(11 * 1024 * 1024)]
    public async Task<IActionResult> Upload(Guid id, string type, IFormFile file, CancellationToken ct) =>
        HubResults.From(this, await service.UploadAsync(User.GetRequiredUserId(), id, type, file, ct));

    [HttpPost("{id:guid}/submit")]
    public async Task<IActionResult> Submit(Guid id, CancellationToken ct) =>
        HubResults.From(this, await service.SubmitAsync(User.GetRequiredUserId(), id, ct));

    /// <summary>Multipart: type (WrongReason | Fixed), message, photos (up to 3).</summary>
    [HttpPost("{id:guid}/claim")]
    [RequestSizeLimit(32 * 1024 * 1024)]
    public async Task<IActionResult> Claim(
        Guid id, [FromForm] string? type, [FromForm] string? message, [FromForm] List<IFormFile>? photos, CancellationToken ct) =>
        HubResults.From(this, await service.ClaimAsync(User.GetRequiredUserId(), id, type, message, photos ?? [], ct));
}
