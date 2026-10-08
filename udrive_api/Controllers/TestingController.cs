using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// Where the automated tests report: signed in as the Google Play reviewer
/// account (Setup → WhatsApp OTP), or with the header <c>X-Test-Key</c>.
/// </summary>
[ApiController]
[AllowAnonymous]
[Route("api/v1/test-runs")]
public sealed class TestReporterController(TestingService service) : ControllerBase
{
    private async Task<IActionResult?> RefuseAsync(CancellationToken ct)
    {
        if (await service.IsTestAccountAsync(User.GetUserIdOrNull(), ct)) return null;
        var key = Request.Headers["X-Test-Key"].ToString();
        return await service.KeyMatchesAsync(key, ct)
            ? null
            : StatusCode(401, new { success = false, error = "test_account_required", message = "Test reviewer account se sign in karein (ya X-Test-Key)." });
    }

    [HttpPost]
    public async Task<IActionResult> Start([FromBody] StartTestRunRequest request, CancellationToken ct) =>
        await RefuseAsync(ct) ?? HubResults.From(this, await service.StartRunAsync(request, ct));

    /// <summary>Multipart: name, status (Running/Passed/Failed/Skipped/Info), detail, device, file (PNG, optional).</summary>
    [HttpPost("{runId:guid}/steps")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(11 * 1024 * 1024)]
    public async Task<IActionResult> Step(
        Guid runId,
        [FromForm] string name,
        [FromForm] string? status,
        [FromForm] string? detail,
        [FromForm] string? device,
        IFormFile? file,
        CancellationToken ct) =>
        await RefuseAsync(ct) ?? HubResults.From(this, await service.AddStepAsync(runId, name, status, detail, device, file, ct));

    [HttpPost("{runId:guid}/finish")]
    public async Task<IActionResult> Finish(Guid runId, [FromBody] FinishTestRunRequest? request, CancellationToken ct) =>
        await RefuseAsync(ct) ?? HubResults.From(this, await service.FinishRunAsync(runId, request ?? new FinishTestRunRequest(null), ct));
}

/// <summary>Admin → Live testing.</summary>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager")]
[Route("api/v1/admin/testing")]
public sealed class AdminTestingController(TestingService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Overview([FromQuery] int limit = 30, CancellationToken ct = default) =>
        HubResults.From(this, await service.OverviewAsync(limit, ct));

    /// <summary>Poll with <c>afterSeq</c> = the last step already shown.</summary>
    [HttpGet("runs/{runId:guid}")]
    public async Task<IActionResult> Run(Guid runId, [FromQuery] int afterSeq = 0, CancellationToken ct = default) =>
        HubResults.From(this, await service.RunAsync(runId, afterSeq, ct));

    [HttpGet("improvements")]
    public async Task<IActionResult> Improvements([FromQuery] string? status, CancellationToken ct) =>
        HubResults.From(this, await service.ImprovementsAsync(status, ct));

    [HttpPost("improvements")]
    public async Task<IActionResult> AddImprovement([FromBody] TestImprovementRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.AddImprovementAsync(User.GetRequiredUserId(), request, ct));

    [HttpPost("improvements/{id:guid}/status")]
    public async Task<IActionResult> SetStatus(Guid id, [FromBody] TestImprovementStatusRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SetImprovementStatusAsync(id, request.Status, ct));

    [HttpDelete("improvements/{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct) =>
        HubResults.From(this, await service.DeleteImprovementAsync(id, ct));

    /// <summary>A new key for the tests; shown once. SuperAdmin / Admin only.</summary>
    [Authorize(Roles = "SuperAdmin,Admin")]
    [HttpPost("key")]
    public async Task<IActionResult> Key(CancellationToken ct) =>
        HubResults.From(this, await service.GenerateKeyAsync(ct));
}
