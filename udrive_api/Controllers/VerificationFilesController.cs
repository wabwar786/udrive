using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize(Roles = "Admin,Operations")]
[Route("api/v1/admin/verification/files")]
public sealed class VerificationFilesController(
    LocalFileStorageService fileStorage) : ControllerBase
{
    [HttpGet("{category}/{owner}/{fileName}")]
    public IActionResult Download(string category, string owner, string fileName)
    {
        var file = fileStorage.ResolveProtectedFile(category, owner, fileName);
        if (file is null)
        {
            return NotFound(new
            {
                success = false,
                error = "file_not_found",
                message = "The verification file was not found."
            });
        }

        Response.Headers.CacheControl = "private,no-store";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        return new PhysicalFileResult(file.Value.Path, file.Value.ContentType) { EnableRangeProcessing = true };
    }
}
