using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>Uploading the photograph shown for a vehicle category.</summary>
/// <remarks>
/// The portal previously only accepted a URL, which put the pictures on
/// somebody else's server. Those links rot: an image host changes a path, a
/// search-engine thumbnail expires, a site blocks hotlinking — and the app
/// quietly shows nothing, with no way to tell from the admin screen because the
/// preview there is fetched by the browser, not by the phone.
///
/// Uploading stores the file on the platform's own volume, so the picture a
/// reviewer chose is the picture a customer sees, for as long as it is there.
///
/// URLs still work. Somebody who has a good permanent link should not be forced
/// to download and re-upload it.
/// </remarks>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin")]
[Route("api/v1/admin/vehicle-images")]
public sealed class VehicleImageUploadController(
    LocalFileStorageService fileStorage,
    ServiceAvailabilityService settings) : ControllerBase
{
    /// <summary>Category keys the app knows how to display.</summary>
    /// <remarks>
    /// Fixed, because each maps to a setting the app reads by name. An upload
    /// against a category nobody renders is a file taking up space for nothing.
    /// </remarks>
    private static readonly HashSet<string> Categories =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "bike", "car", "ac_car", "hiace", "coaster",
        };

    [HttpPost("{category}")]
    [RequestSizeLimit(10 * 1024 * 1024)]
    public async Task<IActionResult> Upload(
        string category,
        IFormFile file,
        CancellationToken cancellationToken)
    {
        if (!Categories.Contains(category))
        {
            return BadRequest(new
            {
                success = false,
                error = "unknown_category",
                message = $"'{category}' is not a vehicle category the app shows.",
            });
        }

        if (file is null || file.Length == 0)
        {
            return BadRequest(new
            {
                success = false,
                error = "empty_file",
                message = "Choose a picture to upload.",
            });
        }

        var stored = await fileStorage.SaveAsync(
            file, "vehicle-images", Guid.Empty, cancellationToken);

        // Rewritten onto the public route.
        //
        // `SaveAsync` returns a path under the admin verification files
        // endpoint, which is right for a CNIC and wrong for this: the portal's
        // own preview could not load it — an `img` tag cannot send a bearer
        // token — and the customer app certainly could not. The upload worked
        // and the file was on disk; nothing could read it.
        //
        // A path rather than a full URL: the API's host differs between
        // environments, and a path resolves against whatever base the client is
        // already talking to.
        var stem = stored.RelativeUrl.Split('/');
        var url = $"/api/v1/vehicle-images/{stem[^2]}/{stem[^1]}";

        await settings.SetVehicleImageAsync(
            User.GetRequiredUserId(),
            category.ToLowerInvariant(),
            url,
            cancellationToken);

        return Ok(ApiResponse<object>.Ok(new { url }));
    }
}
