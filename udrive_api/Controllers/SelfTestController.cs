using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// Runs the end-to-end self-test and reads its history.
/// </summary>
/// <remarks>
/// SuperAdmin only, and only when <c>SELFTEST_ENABLED=true</c>.
///
/// Two gates rather than one because this endpoint can mint access tokens for
/// the harness accounts. The role check is the ordinary one; the environment
/// variable is what makes the whole feature absent from a deployment nobody
/// wants it in, without needing a different build.
/// </remarks>
[ApiController]
[Authorize(Roles = "SuperAdmin")]
[Route("api/v1/admin/self-test")]
public sealed class SelfTestController(SelfTestService service) : ControllerBase
{
    [HttpGet("status")]
    public async Task<IActionResult> Status(CancellationToken ct)
    {
        // Answered even when the harness is switched off, so the admin page can
        // say "set SELFTEST_ENABLED=true" instead of showing a bare 403.
        if (!SelfTestService.Enabled)
        {
            return Ok(new
            {
                success = true,
                data = new
                {
                    enabled = false,
                    schedule = (SelfTestScheduleDto?)null,
                    message = $"The self-test is switched off. Set {SelfTestService.EnabledVariable}=true on the API service to turn it on."
                }
            });
        }

        return Ok(new
        {
            success = true,
            data = new
            {
                enabled = true,
                schedule = await service.GetScheduleAsync(ct),
                message = (string?)null
            }
        });
    }

    [HttpPost("run")]
    public async Task<IActionResult> Start(CancellationToken ct)
    {
        if (!SelfTestService.Enabled)
        {
            return Disabled();
        }

        var report = await service.RunAsync(User.GetRequiredUserId(), "Manual", ct);
        return report is null
            ? StatusCode(StatusCodes.Status409Conflict, new
            {
                success = false,
                error = "self_test_running",
                message = "A self-test is already running. Wait for it to finish."
            })
            : Ok(new { success = true, data = report });
    }

    [HttpGet("runs")]
    public async Task<IActionResult> Runs([FromQuery] int limit = 20, CancellationToken ct = default) =>
        SelfTestService.Enabled
            ? Ok(new { success = true, data = await service.GetRunsAsync(limit, ct) })
            : Disabled();

    [HttpGet("runs/{id:guid}")]
    public async Task<IActionResult> Detail(Guid id, CancellationToken ct)
    {
        if (!SelfTestService.Enabled)
        {
            return Disabled();
        }

        var report = await service.GetRunAsync(id, ct);
        return report is null
            ? NotFound(new { success = false, error = "run_not_found", message = "That self-test run does not exist." })
            : Ok(new { success = true, data = report });
    }

    [HttpPut("schedule")]
    public async Task<IActionResult> Schedule(SaveSelfTestScheduleRequest request, CancellationToken ct) =>
        SelfTestService.Enabled
            ? Ok(new { success = true, data = await service.SaveScheduleAsync(request, User.GetRequiredUserId(), ct) })
            : Disabled();

    private IActionResult Disabled() =>
        StatusCode(StatusCodes.Status409Conflict, new
        {
            success = false,
            error = "self_test_disabled",
            message = $"Set {SelfTestService.EnabledVariable}=true on the API service to use the self-test."
        });
}
