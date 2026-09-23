using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>Serves the vehicle category photographs.</summary>
/// <remarks>
/// Anonymous, and that is the point. `SaveAsync` returns a path under
/// `/api/v1/admin/verification/files/...`, which is correct for a CNIC and
/// wrong for this: an uploaded vehicle picture came back on an **admin-only**
/// route, so the portal's own preview could not load it — an `img` tag cannot
/// send a bearer token — and the customer app certainly could not.
///
/// The upload worked and the picture was on disk. Nothing could read it.
///
/// Deliberately narrow. It serves one folder, `vehicle-images`, and rejects any
/// path that tries to leave it. This is the one category of upload that is
/// meant to be public; driver documents stay behind the authenticated route,
/// and nothing here opens them.
/// </remarks>
[ApiController]
[AllowAnonymous]
[Route("api/v1/vehicle-images")]
public sealed class PublicVehicleImageController(
    LocalFileStorageService fileStorage) : ControllerBase
{
    [HttpGet("{owner}/{fileName}")]
    [ResponseCache(Duration = 86400, Location = ResponseCacheLocation.Any)]
    public IActionResult Get(string owner, string fileName)
    {
        var file = fileStorage.ResolveProtectedFile(
            "vehicle-images", owner, fileName);

        return file is null
            ? NotFound()
            : PhysicalFile(file.Path, file.ContentType);
    }
}
