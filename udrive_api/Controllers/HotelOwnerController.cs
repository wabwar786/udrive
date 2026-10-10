using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// Hotel mode in the app: the owner profile and the step-by-step hotel wizard.
/// </summary>
/// <remarks>
/// Removal is a POST to <c>.../remove</c> rather than an HTTP DELETE: the app's
/// API client sends GET, POST, PUT and multipart, and a delete is still an
/// owner-checked state change either way.
/// </remarks>
[ApiController]
[Authorize]
[Route("api/v1/hotels/owner")]
public sealed class HotelOwnerController(HotelOwnerService service) : ControllerBase
{
    [HttpGet("home")]
    public async Task<IActionResult> Home(CancellationToken ct) =>
        HubResults.From(this, await service.HomeAsync(User.GetRequiredUserId(), ct));

    [HttpGet("profile")]
    public async Task<IActionResult> Profile(CancellationToken ct) =>
        HubResults.From(this, await service.ProfileAsync(User.GetRequiredUserId(), ct));

    [HttpPut("profile")]
    public async Task<IActionResult> SaveProfile(SaveHotelOwnerProfileRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SaveProfileAsync(User.GetRequiredUserId(), request, ct));

    /// <summary>Multipart, field <c>file</c>. Side is front or back.</summary>
    [HttpPost("profile/cnic/{side}")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(12 * 1024 * 1024)]
    public async Task<IActionResult> Cnic(string side, IFormFile? file, CancellationToken ct) =>
        HubResults.From(this, await service.UploadCnicAsync(User.GetRequiredUserId(), side, file, ct));

    [HttpPost("hotels")]
    public async Task<IActionResult> Create(SaveOwnerHotelRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.CreateAsync(User.GetRequiredUserId(), request, ct));

    [HttpGet("hotels/{id:guid}")]
    public async Task<IActionResult> Hotel(Guid id, CancellationToken ct) =>
        HubResults.From(this, await service.HotelAsync(User.GetRequiredUserId(), id, ct));

    [HttpPut("hotels/{id:guid}")]
    public async Task<IActionResult> Update(Guid id, SaveOwnerHotelRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.UpdateAsync(User.GetRequiredUserId(), id, request, ct));

    [HttpPost("hotels/{id:guid}/submit")]
    public async Task<IActionResult> Submit(Guid id, CancellationToken ct) =>
        HubResults.From(this, await service.SubmitAsync(User.GetRequiredUserId(), id, ct));

    [HttpPost("hotels/{id:guid}/photos")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(12 * 1024 * 1024)]
    public async Task<IActionResult> AddPhoto(Guid id, IFormFile? file, CancellationToken ct) =>
        HubResults.From(this, await service.AddPhotoAsync(User.GetRequiredUserId(), id, file, ct));

    [HttpPost("hotels/{id:guid}/photos/{photoId:guid}/remove")]
    public async Task<IActionResult> RemovePhoto(Guid id, Guid photoId, CancellationToken ct) =>
        HubResults.From(this, await service.RemovePhotoAsync(User.GetRequiredUserId(), id, photoId, ct));

    [HttpPost("hotels/{id:guid}/photos/{photoId:guid}/main")]
    public async Task<IActionResult> MainPhoto(Guid id, Guid photoId, CancellationToken ct) =>
        HubResults.From(this, await service.SetMainPhotoAsync(User.GetRequiredUserId(), id, photoId, ct));

    [HttpPost("hotels/{id:guid}/rooms")]
    public async Task<IActionResult> AddRoom(Guid id, SaveOwnerRoomRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SaveRoomAsync(User.GetRequiredUserId(), id, null, request, ct));

    [HttpPut("hotels/{id:guid}/rooms/{roomId:guid}")]
    public async Task<IActionResult> UpdateRoom(Guid id, Guid roomId, SaveOwnerRoomRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SaveRoomAsync(User.GetRequiredUserId(), id, roomId, request, ct));

    [HttpPost("hotels/{id:guid}/rooms/{roomId:guid}/remove")]
    public async Task<IActionResult> RemoveRoom(Guid id, Guid roomId, CancellationToken ct) =>
        HubResults.From(this, await service.RemoveRoomAsync(User.GetRequiredUserId(), id, roomId, ct));

    [HttpPost("hotels/{id:guid}/rooms/{roomId:guid}/photo")]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(12 * 1024 * 1024)]
    public async Task<IActionResult> RoomPhoto(Guid id, Guid roomId, IFormFile? file, CancellationToken ct) =>
        HubResults.From(this, await service.RoomPhotoAsync(User.GetRequiredUserId(), id, roomId, file, ct));
}

/// <summary>The admin's full view of one hotel and its owner, CNIC included.</summary>
[ApiController]
[Authorize(Roles = "Admin,SuperAdmin")]
[Route("api/v1/hotels/admin")]
public sealed class AdminHotelDetailController(HotelOwnerService service) : ControllerBase
{
    [HttpGet("{id:guid}/details")]
    public async Task<IActionResult> Details(Guid id, CancellationToken ct) =>
        HubResults.From(this, await service.AdminDetailAsync(id, ct));
}

/// <summary>Serves hotel gallery and room photos to anyone.</summary>
/// <remarks>
/// Same rules as PublicVehicleImageController: one folder only
/// (<c>hotel-images</c>), no legacy filename search — with it on, an anonymous
/// caller could reach any stored file by name, the owners' CNICs included.
/// </remarks>
[ApiController]
[AllowAnonymous]
[Route("api/v1/hotel-images")]
public sealed class PublicHotelImageController(LocalFileStorageService fileStorage) : ControllerBase
{
    [HttpGet("{owner}/{fileName}")]
    [ResponseCache(Duration = 86400, Location = ResponseCacheLocation.Any)]
    public IActionResult Get(string owner, string fileName)
    {
        var file = fileStorage.ResolveProtectedFile("hotel-images", owner, fileName, allowLegacyFallback: false);
        if (file is null || file.ContentType == "application/pdf") return NotFound();
        Response.Headers["Cross-Origin-Resource-Policy"] = "cross-origin";
        return PhysicalFile(file.Path, file.ContentType);
    }
}
