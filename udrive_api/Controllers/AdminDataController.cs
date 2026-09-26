using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Route("api/v1/admin/data")]
[Authorize(Roles = "Admin,SuperAdmin")]
public sealed class AdminDataController(AdminDataService service) : ControllerBase
{
    [HttpGet("status")]
    public async Task<IActionResult> Status(CancellationToken cancellationToken) =>
        Ok(new { success = true, data = await service.GetStatusAsync(cancellationToken) });

    [HttpPost("demo")]
    public async Task<IActionResult> AddDemoData(CancellationToken cancellationToken) =>
        Ok(new
        {
            success = true,
            data = await service.AddDemoDataAsync(User.GetRequiredUserId(), cancellationToken)
        });

    /// <summary>Removes the seeded demo hotels and their owner accounts.</summary>
    /// <remarks>
    /// No typed confirmation, unlike the reset below. This one is scoped to the
    /// seeded demo accounts, it cannot reach a real customer's records, and
    /// anything it removes comes back by pressing the restore button — so the
    /// ordinary confirm dialog in the portal is the right amount of friction.
    /// Making it feel as dangerous as the reset would teach an operator to type
    /// past warnings.
    /// </remarks>
    [HttpPost("demo/remove")]
    public async Task<IActionResult> RemoveDemoData(CancellationToken cancellationToken) =>
        Ok(new
        {
            success = true,
            data = await service.RemoveDemoDataAsync(User.GetRequiredUserId(), cancellationToken)
        });

    [HttpPost("reset")]
    public async Task<IActionResult> Reset(
        ResetApplicationDataRequest request,
        CancellationToken cancellationToken)
    {
        if (!string.Equals(request.Confirmation?.Trim(), "DELETE ALL DATA", StringComparison.Ordinal))
        {
            return BadRequest(new
            {
                success = false,
                error = "confirmation_required",
                message = "Type DELETE ALL DATA exactly to confirm the reset."
            });
        }

        return Ok(new
        {
            success = true,
            data = await service.ResetAsync(User.GetRequiredUserId(), cancellationToken)
        });
    }
}
