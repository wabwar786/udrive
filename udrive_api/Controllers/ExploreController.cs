using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>Explore Kashmir — the extra facts behind one place.</summary>
[ApiController]
[AllowAnonymous]
[Route("api/v1/catalog/destinations")]
public sealed class ExploreController(ExploreService service) : ControllerBase
{
    [HttpGet("{id:guid}/explore")]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct)
    {
        var result = await service.GetAsync(id, ct);
        return result.Success
            ? Ok(new { success = true, data = result.Data })
            : StatusCode(result.StatusCode, new { success = false, error = result.ErrorCode, message = result.Message });
    }
}
