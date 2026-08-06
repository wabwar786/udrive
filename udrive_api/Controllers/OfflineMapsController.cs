using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Route("api/v1/offline-maps")]
public sealed class OfflineMapsController(OfflineMapManifestService service) : ControllerBase
{
    [AllowAnonymous]
    [HttpGet("manifest")]
    public async Task<IActionResult> Manifest(CancellationToken ct)
    {
        var result = await service.ListAsync(includeInactive: true, ct);
        return Ok(ApiResponse<IReadOnlyList<OfflineMapPackDto>>.Ok(result.Data!, "Offline map manifest loaded."));
    }

    [Authorize(Roles = "SuperAdmin,Admin,Manager,Operations")]
    [HttpGet("admin")]
    public async Task<IActionResult> AdminList(CancellationToken ct)
    {
        var result = await service.ListAsync(includeInactive: true, ct);
        return Ok(ApiResponse<IReadOnlyList<OfflineMapPackDto>>.Ok(result.Data!, "Offline map packs loaded."));
    }

    [Authorize(Roles = "SuperAdmin,Admin")]
    [HttpPut("admin/{id}")]
    public async Task<IActionResult> Upsert(string id, UpsertOfflineMapPackRequest request, CancellationToken ct)
    {
        var result = await service.UpsertAsync(id, request, ct);
        return result.Success
            ? Ok(ApiResponse<OfflineMapPackDto>.Ok(result.Data!, result.Message))
            : StatusCode(result.StatusCode, new { success = false, error = result.ErrorCode, message = result.Message, traceId = HttpContext.TraceIdentifier });
    }
}
