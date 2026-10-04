using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>Near me: browsing is public, listing a business needs an account.</summary>
[ApiController]
[Route("api/v1/businesses")]
public sealed class BusinessesController(BusinessService service) : ControllerBase
{
    [AllowAnonymous, HttpGet("nearby")]
    public async Task<IActionResult> Nearby(
        [FromQuery] double lat,
        [FromQuery] double lng,
        [FromQuery] double radiusKm = 3,
        [FromQuery] string? category = null,
        [FromQuery] string? q = null,
        CancellationToken ct = default) =>
        Result(await service.NearbyAsync(lat, lng, radiusKm, category, q, ct));

    [Authorize, HttpGet("mine")]
    public async Task<IActionResult> Mine(CancellationToken ct) =>
        Result(await service.MineAsync(User.GetRequiredUserId(), ct));

    [AllowAnonymous, HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct) =>
        Result(await service.GetAsync(id, ct));

    [Authorize, HttpPost]
    public async Task<IActionResult> Create(SaveBusinessRequest request, CancellationToken ct) =>
        Result(await service.CreateAsync(User.GetRequiredUserId(), request, ct));

    [Authorize, HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, SaveBusinessRequest request, CancellationToken ct) =>
        Result(await service.UpdateAsync(User.GetRequiredUserId(), id, request, ct));

    private IActionResult Result<T>(ServiceResult<T> r) =>
        r.Success
            ? StatusCode(r.StatusCode, new { success = true, data = r.Data, message = r.Message })
            : StatusCode(r.StatusCode, new { success = false, error = r.ErrorCode, message = r.Message });
}

/// <summary>The portal's approval queue for Near me.</summary>
[ApiController]
[Route("api/v1/admin/businesses")]
[Authorize(Roles = "Admin,SuperAdmin")]
public sealed class AdminBusinessesController(BusinessService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] string? status, CancellationToken ct) =>
        Result(await service.AdminListAsync(status, ct));

    [HttpPost("{id:guid}/review")]
    public async Task<IActionResult> Review(Guid id, ReviewBusinessRequest request, CancellationToken ct) =>
        Result(await service.ReviewAsync(User.GetRequiredUserId(), id, request, ct));

    [HttpPatch("{id:guid}/active")]
    public async Task<IActionResult> SetActive(Guid id, SetBusinessActiveRequest request, CancellationToken ct) =>
        Result(await service.SetActiveAsync(User.GetRequiredUserId(), id, request.IsActive, ct));

    private IActionResult Result<T>(ServiceResult<T> r) =>
        r.Success
            ? Ok(new { success = true, data = r.Data })
            : StatusCode(r.StatusCode, new { success = false, error = r.ErrorCode, message = r.Message });
}
