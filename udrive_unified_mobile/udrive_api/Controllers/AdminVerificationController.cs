using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations,VerificationOfficer")]
[Route("api/v1/admin/verification")]
public sealed class AdminVerificationController(
    AdminVerificationService adminService) : ControllerBase
{
    [HttpGet("drivers")]
    public async Task<IActionResult> GetDrivers(
        [FromQuery] string? status,
        CancellationToken cancellationToken) =>
        ToActionResult(await adminService.GetDriversAsync(status, cancellationToken));

    [HttpGet("drivers/{driverProfileId:guid}")]
    public async Task<IActionResult> GetDriver(
        Guid driverProfileId,
        CancellationToken cancellationToken) =>
        ToActionResult(await adminService.GetDriverDetailAsync(driverProfileId, cancellationToken));

    [HttpPut("drivers/{driverProfileId:guid}")]
    public async Task<IActionResult> ReviewDriver(
        Guid driverProfileId,
        VerificationReviewRequest request,
        CancellationToken cancellationToken)
    {
        if (request.DeleteAttachments && !User.IsInRole("SuperAdmin"))
        {
            return StatusCode(StatusCodes.Status403Forbidden, new
            {
                success = false,
                error = "super_admin_required",
                message = "Only SuperAdmin can permanently delete verification attachments."
            });
        }

        return ToActionResult(await adminService.ReviewDriverAsync(
            User.GetRequiredUserId(),
            driverProfileId,
            request,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            cancellationToken));
    }

    [Authorize(Roles = "SuperAdmin")]
    [HttpDelete("drivers/{driverProfileId:guid}")]
    public async Task<IActionResult> DeleteDriver(
        Guid driverProfileId,
        DeleteVerificationEntityRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await adminService.DeleteDriverAsync(
            User.GetRequiredUserId(),
            driverProfileId,
            request.Reason,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            cancellationToken));

    // Admin as well as SuperAdmin.
    //
    // Deleting a document is destructive, but the people reviewing verification
    // all day are Admins, and a reviewer who can see that a file is corrupt or
    // is the wrong document but cannot remove it has to find a SuperAdmin to
    // press one button. That queue is where applications sit for days.
    /// <summary>Asks the Driver to send this one document again.</summary>
    [Authorize(Roles = "SuperAdmin,Admin,VerificationOfficer")]
    [HttpPost("drivers/{driverProfileId:guid}/documents/{documentId:guid}/request-reupload")]
    public async Task<IActionResult> RequestDriverDocumentReupload(
        Guid driverProfileId,
        Guid documentId,
        RequestReuploadRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await adminService.RequestDocumentReuploadAsync(
            User.GetRequiredUserId(), false, driverProfileId, documentId,
            request.Reason, cancellationToken));

    /// <summary>The same, for a vehicle photograph or paper.</summary>
    [Authorize(Roles = "SuperAdmin,Admin,VerificationOfficer")]
    [HttpPost("vehicles/{vehicleId:guid}/documents/{documentId:guid}/request-reupload")]
    public async Task<IActionResult> RequestVehicleDocumentReupload(
        Guid vehicleId,
        Guid documentId,
        RequestReuploadRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await adminService.RequestDocumentReuploadAsync(
            User.GetRequiredUserId(), true, vehicleId, documentId,
            request.Reason, cancellationToken));

    [Authorize(Roles = "SuperAdmin,Admin")]
    [HttpDelete("drivers/{driverProfileId:guid}/documents/{documentId:guid}")]
    public async Task<IActionResult> DeleteDriverDocument(
        Guid driverProfileId,
        Guid documentId,
        CancellationToken cancellationToken) =>
        ToActionResult(await adminService.DeleteDriverDocumentAsync(
            User.GetRequiredUserId(),
            driverProfileId,
            documentId,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            cancellationToken));

    [HttpGet("vehicles")]
    public async Task<IActionResult> GetVehicles(
        [FromQuery] string? status,
        CancellationToken cancellationToken) =>
        ToActionResult(await adminService.GetVehiclesAsync(status, cancellationToken));

    [HttpGet("vehicles/{vehicleId:guid}")]
    public async Task<IActionResult> GetVehicle(
        Guid vehicleId,
        CancellationToken cancellationToken) =>
        ToActionResult(await adminService.GetVehicleDetailAsync(vehicleId, cancellationToken));

    [HttpPut("vehicles/{vehicleId:guid}")]
    public async Task<IActionResult> ReviewVehicle(
        Guid vehicleId,
        VerificationReviewRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await adminService.ReviewVehicleAsync(
            User.GetRequiredUserId(),
            vehicleId,
            request,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            cancellationToken));

    [Authorize(Roles = "SuperAdmin,Admin")]
    [HttpDelete("vehicles/{vehicleId:guid}")]
    public async Task<IActionResult> DeleteVehicle(
        Guid vehicleId,
        DeleteVerificationEntityRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await adminService.DeleteVehicleAsync(
            User.GetRequiredUserId(),
            vehicleId,
            request.Reason,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            cancellationToken));

    [Authorize(Roles = "SuperAdmin")]
    [HttpDelete("vehicles/{vehicleId:guid}/documents/{documentId:guid}")]
    public async Task<IActionResult> DeleteVehicleDocument(
        Guid vehicleId,
        Guid documentId,
        CancellationToken cancellationToken) =>
        ToActionResult(await adminService.DeleteVehicleDocumentAsync(
            User.GetRequiredUserId(),
            vehicleId,
            documentId,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            cancellationToken));

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
