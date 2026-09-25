using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations,VerificationOfficer")]
[Route("api/v1/admin/verification")]
public sealed class VerificationFilesController(
    LocalFileStorageService fileStorage,
    VerificationFileLookupService lookupService) : ControllerBase
{
    [HttpGet("files/{category}/{owner}/{fileName}")]
    public IActionResult DownloadLegacy(string category, string owner, string fileName)
    {
        // allowLegacyFallback: false.
        //
        // The default is true, which makes ResolveProtectedFile search EVERY
        // storage root recursively for a matching filename when the exact path
        // misses. This was the last route where a caller-supplied filename
        // still reached that search. The roles on this controller can see
        // driver documents anyway, so it was not a live leak — but "the caller
        // happens to be trusted" is the wrong reason for a path to be safe,
        // and a role added to that list later would inherit the hole silently.
        return Serve(fileStorage.ResolveProtectedFile(category, owner, fileName, allowLegacyFallback: false));
    }

    [HttpGet("driver-documents/{documentId:guid}/file")]
    public async Task<IActionResult> DownloadDriverDocument(
        Guid documentId,
        CancellationToken cancellationToken)
    {
        var lookup = await lookupService.FindDriverDocumentAsync(documentId, cancellationToken);
        return ServeLookup(lookup);
    }

    [HttpGet("vehicle-documents/{documentId:guid}/file")]
    public async Task<IActionResult> DownloadVehicleDocument(
        Guid documentId,
        CancellationToken cancellationToken)
    {
        var lookup = await lookupService.FindVehicleDocumentAsync(documentId, cancellationToken);
        return ServeLookup(lookup);
    }

    [Authorize(Roles = "SuperAdmin")]
    [HttpGet("files/storage-status")]
    public IActionResult StorageStatus()
    {
        return Ok(new { success = true, data = fileStorage.GetDiagnostics() });
    }

    private IActionResult ServeLookup(VerificationFileLookupResult lookup)
    {
        if (!lookup.MetadataFound)
        {
            return NotFound(new
            {
                success = false,
                error = "attachment_not_found",
                message = "The attachment record was not found."
            });
        }

        if (lookup.File is null)
        {
            return NotFound(new
            {
                success = false,
                error = "attachment_file_missing",
                message = "The attachment record exists, but its file is missing from API storage. Confirm the /data/uploads volume or ask the Driver to upload it again."
            });
        }

        return Serve(lookup.File);
    }

    private IActionResult Serve(ResolvedStoredFile? file)
    {
        if (file is null)
        {
            return NotFound(new
            {
                success = false,
                error = "file_not_found",
                message = "The verification file was not found in configured or legacy storage."
            });
        }

        Response.Headers.CacheControl = "private,no-store";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        Response.Headers["Cross-Origin-Resource-Policy"] = "cross-origin";
        Response.Headers["Access-Control-Expose-Headers"] =
            "Content-Type,Content-Length,Content-Disposition";
        var downloadName = file.DownloadName.Replace(
            "\"",
            string.Empty,
            StringComparison.Ordinal);
        Response.Headers.ContentDisposition =
            $"inline; filename=\"{downloadName}\"";

        return new PhysicalFileResult(file.Path, file.ContentType)
        {
            EnableRangeProcessing = true
        };
    }
}
