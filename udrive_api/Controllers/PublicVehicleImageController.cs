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
        // allowLegacyFallback: false is doing real work on an anonymous route.
        // With the fallback on, a filename that does not exist under
        // vehicle-images sends the resolver searching EVERY storage root
        // recursively by name — so this endpoint, which needs no token at all,
        // would hand out a driver's CNIC to anyone who learned the filename.
        // Category imagery has no legacy layout to fall back to anyway.
        var file = fileStorage.ResolveProtectedFile(
            "vehicle-images", owner, fileName, allowLegacyFallback: false);

        if (file is null) return NotFound();

        // These pictures are meant to be embedded by other origins — the admin
        // portal previews them with a plain <img> tag, and the portal is not
        // served from the API's own site. SecurityHeadersMiddleware sets
        // Cross-Origin-Resource-Policy: same-site for everything, which made
        // the browser refuse them: the upload succeeded, the setting saved, and
        // the preview box stayed empty. CORS does not help, because a no-cors
        // <img> load is not a CORS request.
        //
        // Set here rather than relaxed globally: every other route, including
        // driver documents, keeps same-site. The middleware uses TryAdd, so the
        // value written here is the one that ships.
        Response.Headers["Cross-Origin-Resource-Policy"] = "cross-origin";

        return PhysicalFile(file.Path, file.ContentType);
    }
}
