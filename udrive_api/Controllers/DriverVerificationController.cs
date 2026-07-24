using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/driver")]
public sealed class DriverVerificationController(
    DriverVerificationService driverService) : ControllerBase
{
    [HttpGet("onboarding")]
    public async Task<IActionResult> GetOnboarding(CancellationToken cancellationToken)
    {
        return ToActionResult(await driverService.GetOnboardingAsync(
            User.GetRequiredUserId(), cancellationToken));
    }

    [HttpPut("onboarding")]
    public async Task<IActionResult> SaveOnboarding(
        DriverOnboardingRequest request,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await driverService.SaveOnboardingAsync(
            User.GetRequiredUserId(), request, cancellationToken));
    }

    [HttpPost("onboarding/submit")]
    public async Task<IActionResult> SubmitOnboarding(CancellationToken cancellationToken)
    {
        return ToActionResult(await driverService.SubmitOnboardingAsync(
            User.GetRequiredUserId(), cancellationToken));
    }

    [HttpGet("documents")]
    public async Task<IActionResult> GetDocuments(CancellationToken cancellationToken)
    {
        return ToActionResult(await driverService.GetDriverDocumentsAsync(
            User.GetRequiredUserId(), cancellationToken));
    }

    [HttpPost("documents")]
    [RequestSizeLimit(10 * 1024 * 1024)]
    public async Task<IActionResult> UploadDocument(
        [FromForm] string documentType,
        [FromForm] DateOnly? expiryDate,
        [FromForm] IFormFile file,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await driverService.UploadDriverDocumentAsync(
            User.GetRequiredUserId(), documentType, expiryDate, file, cancellationToken));
    }

    [HttpGet("vehicles")]
    public async Task<IActionResult> GetVehicles(CancellationToken cancellationToken)
    {
        return ToActionResult(await driverService.GetVehiclesAsync(
            User.GetRequiredUserId(), cancellationToken));
    }

    [HttpPost("vehicles")]
    public async Task<IActionResult> CreateVehicle(
        VehicleUpsertRequest request,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await driverService.CreateVehicleAsync(
            User.GetRequiredUserId(), request, cancellationToken));
    }

    [HttpPut("vehicles/{vehicleId:guid}")]
    public async Task<IActionResult> UpdateVehicle(
        Guid vehicleId,
        VehicleUpsertRequest request,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await driverService.UpdateVehicleAsync(
            User.GetRequiredUserId(), vehicleId, request, cancellationToken));
    }

    [HttpPost("vehicles/{vehicleId:guid}/documents")]
    [RequestSizeLimit(10 * 1024 * 1024)]
    public async Task<IActionResult> UploadVehicleDocument(
        Guid vehicleId,
        [FromForm] string documentType,
        [FromForm] DateOnly? expiryDate,
        [FromForm] IFormFile file,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await driverService.UploadVehicleDocumentAsync(
            User.GetRequiredUserId(), vehicleId, documentType, expiryDate, file, cancellationToken));
    }

    [HttpPost("vehicles/{vehicleId:guid}/submit")]
    public async Task<IActionResult> SubmitVehicle(
        Guid vehicleId,
        CancellationToken cancellationToken)
    {
        return ToActionResult(await driverService.SubmitVehicleAsync(
            User.GetRequiredUserId(), vehicleId, cancellationToken));
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
