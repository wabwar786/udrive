using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize(Roles = "Admin,Operations")]
[Route("api/v1/admin/verification")]
public sealed class AdminVerificationController(
    AdminVerificationService adminService) : ControllerBase
{
    [HttpGet("drivers")]
    public async Task<IActionResult> GetDrivers(
        [FromQuery] string? status,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await adminService.GetDriversAsync(status, cancellationToken));
    }

    [HttpGet("drivers/{driverProfileId:guid}")]
    public async Task<IActionResult> GetDriver(
        Guid driverProfileId,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await adminService.GetDriverDetailAsync(
            driverProfileId,
            cancellationToken));
    }

    [HttpPut("drivers/{driverProfileId:guid}")]
    public async Task<IActionResult> ReviewDriver(
        Guid driverProfileId,
        VerificationReviewRequest request,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await adminService.ReviewDriverAsync(
            User.GetRequiredUserId(),
            driverProfileId,
            request,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            cancellationToken));
    }

    [HttpGet("vehicles")]
    public async Task<IActionResult> GetVehicles(
        [FromQuery] string? status,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await adminService.GetVehiclesAsync(status, cancellationToken));
    }

    [HttpGet("vehicles/{vehicleId:guid}")]
    public async Task<IActionResult> GetVehicle(
        Guid vehicleId,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await adminService.GetVehicleDetailAsync(
            vehicleId,
            cancellationToken));
    }

    [HttpPut("vehicles/{vehicleId:guid}")]
    public async Task<IActionResult> ReviewVehicle(
        Guid vehicleId,
        VerificationReviewRequest request,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await adminService.ReviewVehicleAsync(
            User.GetRequiredUserId(),
            vehicleId,
            request,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            cancellationToken));
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

        return Ok(ApiResponse<T>.Ok(result.Data!, result.Message));
    }
}
