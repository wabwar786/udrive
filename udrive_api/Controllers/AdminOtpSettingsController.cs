using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// WhatsApp OTP (WA Engine) settings for the admin portal. SuperAdmin only:
/// whoever controls these controls every sign-in.
/// </summary>
[ApiController]
[Authorize(Roles = "SuperAdmin")]
[Route("api/v1/admin/otp-settings")]
public sealed class AdminOtpSettingsController(OtpDeliveryService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken ct) =>
        Ok(ApiResponse<OtpSettingsDto>.Ok(await service.GetAsync(ct)));

    [HttpPut]
    public async Task<IActionResult> Update(UpdateOtpSettingsRequest request, CancellationToken ct) =>
        Result(await service.UpdateAsync(User.GetRequiredUserId(), request, ct));

    /// <summary>WA Engine session check (GET /api/status on the configured base URL).</summary>
    [HttpGet("status")]
    public async Task<IActionResult> Status(CancellationToken ct) => Result(await service.StatusAsync(ct));

    [HttpPost("test")]
    public async Task<IActionResult> Test(OtpTestRequest request, CancellationToken ct) =>
        Result(await service.TestAsync(User.GetRequiredUserId(), request.PhoneNumber, ct));

    private IActionResult Result<T>(ServiceResult<T> result)
    {
        if (!result.Success)
        {
            return StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
                traceId = HttpContext.TraceIdentifier
            });
        }
        return Ok(ApiResponse<T>.Ok(result.Data!, result.Message));
    }
}
