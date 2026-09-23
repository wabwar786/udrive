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
    DriverVerificationService driverService,
    VerificationFileLookupService fileLookup) : ControllerBase
{
    /// <summary>Lets a Driver look at a document they uploaded.</summary>
    /// <remarks>
    /// Until now only Admins could open these files, so a Driver could upload a
    /// photograph of their licence and never see what had actually arrived —
    /// they found out it was blurred or upside down when it came back rejected,
    /// days later.
    ///
    /// The ownership check is inside the query, not a test afterwards. A
    /// document id in a URL must never be enough to read another Driver's CNIC.
    /// </remarks>
    [HttpGet("documents/{documentId:guid}/file")]
    public async Task<IActionResult> DownloadOwnDocument(
        Guid documentId,
        CancellationToken cancellationToken)
    {
        return ServeOwn(await fileLookup.FindOwnDriverDocumentAsync(
            documentId, User.GetRequiredUserId(), cancellationToken));
    }

    /// <summary>The same, for a document attached to the Driver's vehicle.</summary>
    [HttpGet("vehicle-documents/{documentId:guid}/file")]
    public async Task<IActionResult> DownloadOwnVehicleDocument(
        Guid documentId,
        CancellationToken cancellationToken)
    {
        return ServeOwn(await fileLookup.FindOwnVehicleDocumentAsync(
            documentId, User.GetRequiredUserId(), cancellationToken));
    }

    /// <summary>
    /// Sends the file back, or says plainly which of the two things went wrong.
    /// </summary>
    /// <remarks>
    /// A missing record and a missing file are different faults with different
    /// fixes — one means the upload never completed, the other means storage
    /// lost it — and collapsing both into "not found" sends the Driver to
    /// support for something they could have re-uploaded themselves.
    /// </remarks>
    private IActionResult ServeOwn(VerificationFileLookupResult lookup)
    {
        if (!lookup.MetadataFound)
        {
            return NotFound(new
            {
                success = false,
                error = "attachment_not_found",
                message = "That document is not on your account.",
            });
        }

        if (lookup.File is null)
        {
            return NotFound(new
            {
                success = false,
                error = "attachment_file_missing",
                message = "The file did not finish uploading. Please upload it again.",
            });
        }

        return PhysicalFile(
            lookup.File.Path,
            lookup.File.ContentType,
            lookup.File.DownloadName);
    }

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
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(10 * 1024 * 1024)]
    public async Task<IActionResult> UploadDocument(
        [FromForm] string documentType,
        [FromForm] DateOnly? expiryDate,
        IFormFile file,
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
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(10 * 1024 * 1024)]
    public async Task<IActionResult> UploadVehicleDocument(
        Guid vehicleId,
        [FromForm] string documentType,
        [FromForm] DateOnly? expiryDate,
        IFormFile file,
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
