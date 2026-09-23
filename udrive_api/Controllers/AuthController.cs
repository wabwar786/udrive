using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Route("api/v1/auth")]
public sealed class AuthController(AuthService authService, AccountDeletionService accountDeletion) : ControllerBase
{
    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    [HttpPost("otp/request")]
    public async Task<IActionResult> RequestOtp(
        RequestOtpRequest request,
        CancellationToken cancellationToken)
    {
        var result = await authService.RequestOtpAsync(
            request,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            cancellationToken);
        return ToActionResult(result);
    }

    [AllowAnonymous]
    [EnableRateLimiting("otp")]
    [HttpPost("otp/verify")]
    public async Task<IActionResult> VerifyOtp(
        VerifyOtpRequest request,
        CancellationToken cancellationToken)
    {
        var result = await authService.VerifyOtpAsync(
            request,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            Request.Headers["User-Agent"].ToString(),
            cancellationToken);
        return ToActionResult(result);
    }

    [AllowAnonymous]
    [HttpPost("refresh")]
    public async Task<IActionResult> Refresh(
        RefreshTokenRequest request,
        CancellationToken cancellationToken)
    {
        var result = await authService.RefreshAsync(
            request,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            Request.Headers["User-Agent"].ToString(),
            cancellationToken);
        return ToActionResult(result);
    }

    [Authorize]
    [HttpGet("me")]
    public async Task<IActionResult> Me(CancellationToken cancellationToken)
    {
        var result = await authService.GetCurrentUserAsync(
            User.GetRequiredUserId(),
            cancellationToken);
        return ToActionResult(result);
    }

    [Authorize]
    [HttpPost("logout")]
    public async Task<IActionResult> Logout(
        LogoutRequest request,
        CancellationToken cancellationToken)
    {
        var result = await authService.LogoutAsync(
            User.GetRequiredUserId(),
            request,
            cancellationToken);
        return ToActionResult(result);
    }

    /// <summary>
    /// Permanently deletes the signed-in user's account (Google Play policy).
    /// The client must send { "confirmation": "DELETE" } so a stray call cannot
    /// wipe an account.
    /// </summary>
    [Authorize]
    [EnableRateLimiting("otp")]
    [HttpPost("account/delete")]
    public async Task<IActionResult> DeleteAccount(
        DeleteAccountRequest request,
        CancellationToken cancellationToken)
    {
        if (!string.Equals(request.Confirmation?.Trim(), "DELETE", StringComparison.Ordinal))
        {
            return BadRequest(new
            {
                success = false,
                error = "confirmation_required",
                message = "Type DELETE to confirm account deletion.",
                traceId = HttpContext.TraceIdentifier
            });
        }

        var userId = User.GetRequiredUserId();
        var result = await accountDeletion.DeleteAsync(
            userId,
            userId,
            request.Reason,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            cancellationToken);
        return ToActionResult(result);
    }

    private IActionResult ToActionResult<T>(ServiceResult<T> result)
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

        var response = ApiResponse<T>.Ok(result.Data!, result.Message);
        return result.StatusCode == StatusCodes.Status201Created
            ? StatusCode(StatusCodes.Status201Created, response)
            : Ok(response);
    }
}
