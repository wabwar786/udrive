using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>Admin → Storage: how full the upload volume is, and making room.</summary>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin")]
[Route("api/v1/admin/storage")]
public sealed class StorageController(StorageService service) : ControllerBase
{
    [HttpGet]
    public IActionResult Summary() => HubResults.From(this, service.Summary());

    /// <summary>Shrinks up to <paramref name="limit"/> big old photos; call again while Remaining &gt; 0.</summary>
    [HttpPost("shrink")]
    public async Task<IActionResult> Shrink([FromQuery] int limit = 40, CancellationToken ct = default) =>
        HubResults.From(this, await service.ShrinkAsync(limit, ct));

    /// <summary>Files no record points at. Nothing is moved.</summary>
    [HttpGet("orphans")]
    public async Task<IActionResult> Orphans(CancellationToken ct) =>
        HubResults.From(this, await service.OrphansAsync(move: false, ct));

    /// <summary>Moves those files to the trash (emptied after 30 days).</summary>
    [HttpPost("orphans/move")]
    public async Task<IActionResult> MoveOrphans(CancellationToken ct) =>
        HubResults.From(this, await service.OrphansAsync(move: true, ct));
}
