using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>The public website's API ("UDrive – Travel &amp; Tour").</summary>
/// <remarks>
/// Read-only and anonymous, except the tour booking and the "registered from
/// the website" mark, which need a customer signed in with the WhatsApp OTP
/// (the same /api/v1/auth/otp endpoints the app uses). Every route is rate
/// limited per caller; CORS allows only the origins in ALLOWED_ORIGINS.
/// </remarks>
[ApiController]
[EnableRateLimiting("web")]
[Route("api/v1/web")]
public sealed class WebsiteController(WebsiteService service) : ControllerBase
{
    [AllowAnonymous]
    [HttpGet("home")]
    public async Task<IActionResult> Home(CancellationToken ct) => HubResults.From(this, await service.HomeAsync(ct));

    [AllowAnonymous]
    [HttpGet("tours")]
    public async Task<IActionResult> Tours(
        [FromQuery] string? destination, [FromQuery] string? days, [FromQuery] string? mode,
        [FromQuery] DateOnly? date, [FromQuery] int page = 1, CancellationToken ct = default) =>
        HubResults.From(this, await service.ToursAsync(destination, days, mode, date, page, ct));

    [AllowAnonymous]
    [HttpGet("tours/{id:guid}")]
    public async Task<IActionResult> Tour(Guid id, CancellationToken ct) => HubResults.From(this, await service.TourAsync(id, ct));

    [AllowAnonymous]
    [HttpGet("destinations")]
    public async Task<IActionResult> Destinations(CancellationToken ct) => HubResults.From(this, await service.DestinationsAsync(ct));

    [AllowAnonymous]
    [HttpGet("hotels")]
    public async Task<IActionResult> Hotels([FromQuery] string? city, [FromQuery] int page = 1, CancellationToken ct = default) =>
        HubResults.From(this, await service.HotelsPageAsync(city, page, ct));

    [AllowAnonymous]
    [HttpGet("hotels/{id:guid}")]
    public async Task<IActionResult> Hotel(Guid id, CancellationToken ct) => HubResults.From(this, await service.HotelAsync(id, ct));

    [AllowAnonymous]
    [HttpGet("hotels/by-slug/{slug}")]
    public async Task<IActionResult> HotelBySlug(string slug, CancellationToken ct) =>
        HubResults.From(this, await service.HotelBySlugAsync(slug, ct));

    [AllowAnonymous]
    [HttpGet("ads/{slot}")]
    public async Task<IActionResult> Ads(string slot, CancellationToken ct) =>
        HubResults.From(this, await service.AdsForSlotAsync((slot ?? "").ToLowerInvariant(), ct));

    [AllowAnonymous]
    [HttpPost("ads/{id:guid}/click")]
    public async Task<IActionResult> AdClick(Guid id, CancellationToken ct) => HubResults.From(this, await service.AdClickAsync(id, ct));

    /// <summary>Destinations and hotels for the website's build and sitemap.xml.</summary>
    [AllowAnonymous]
    [HttpGet("sitemap")]
    public async Task<IActionResult> Sitemap(CancellationToken ct) => HubResults.From(this, await service.SitemapAsync(ct));

    /// <summary>Books seats (or the whole vehicle) on a tour. Signed-in customer only.</summary>
    [Authorize]
    [EnableRateLimiting("web-book")]
    [HttpPost("tours/{id:guid}/book")]
    public async Task<IActionResult> Book(Guid id, WebTourBookingRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.BookTourAsync(User.GetRequiredUserId(), id, request, ct));

    /// <summary>Marks a hotel the signed-in owner just created on the website.</summary>
    [Authorize]
    [EnableRateLimiting("web-book")]
    [HttpPost("hotels/{id:guid}/from-web")]
    public async Task<IActionResult> FromWeb(Guid id, CancellationToken ct) =>
        HubResults.From(this, await service.MarkHotelFromWebAsync(User.GetRequiredUserId(), id, ct));
}

/// <summary>Admin portal → Website: ad places and what came in from the website.</summary>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations")]
[Route("api/v1/admin/web")]
public sealed class AdminWebsiteController(WebsiteAdminService service, LocalFileStorageService files) : ControllerBase
{
    [HttpGet("ads")]
    public async Task<IActionResult> Ads(CancellationToken ct) => HubResults.From(this, await service.AdsAsync(ct));

    [HttpPost("ads")]
    public async Task<IActionResult> Create(SaveWebAdRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SaveAdAsync(User.GetRequiredUserId(), null, request, ct));

    [HttpPut("ads/{id:guid}")]
    public async Task<IActionResult> Update(Guid id, SaveWebAdRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SaveAdAsync(User.GetRequiredUserId(), id, request, ct));

    [HttpPost("ads/{id:guid}/remove")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct) => HubResults.From(this, await service.DeleteAdAsync(id, ct));

    /// <summary>Uploads an ad picture (JPG, PNG or WebP). Returns its public URL.</summary>
    [HttpPost("ads/image")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(10 * 1024 * 1024)]
    public async Task<IActionResult> Image(IFormFile? file, CancellationToken ct)
    {
        if (file is null || file.Length == 0)
        {
            return BadRequest(new { success = false, error = "empty_file", message = "Tasveer chunein." });
        }

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (ext is not (".jpg" or ".jpeg" or ".png" or ".webp"))
        {
            return BadRequest(new { success = false, error = "file_type", message = "Sirf JPG, PNG ya WebP tasveer." });
        }

        var stored = await files.SaveAsync(file, "web-ads", Guid.Empty, ct);
        var parts = stored.RelativeUrl.Split('/');
        var url = $"/api/v1/web-images/{parts[^2]}/{parts[^1]}";
        return Ok(Common.ApiResponse<object>.Ok(new { url }));
    }

    [HttpGet("activity")]
    public async Task<IActionResult> Activity(CancellationToken ct) => HubResults.From(this, await service.ActivityAsync(ct));
}

/// <summary>Serves ad pictures to the website.</summary>
[ApiController]
[AllowAnonymous]
[Route("api/v1/web-images")]
public sealed class PublicWebImageController(LocalFileStorageService files) : ControllerBase
{
    [HttpGet("{owner}/{fileName}")]
    [ResponseCache(Duration = 86400, Location = ResponseCacheLocation.Any)]
    public IActionResult Get(string owner, string fileName)
    {
        // Exact path only (no legacy search), and never a PDF.
        var file = files.ResolveProtectedFile("web-ads", owner, fileName, allowLegacyFallback: false);
        if (file is null || file.ContentType == "application/pdf") return NotFound();
        Response.Headers["Cross-Origin-Resource-Policy"] = "cross-origin";
        return PhysicalFile(file.Path, file.ContentType);
    }
}
