using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>Operations → Team. Team users reach it only with the Team permission.</summary>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin")]
[Route("api/v1/admin/team")]
public sealed class TeamController(TeamService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct) => Result(await service.ListAsync(ct));

    [HttpGet("catalog")]
    public IActionResult Catalog() => Ok(ApiResponse<TeamCatalogDto>.Ok(service.Catalog()));

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct) => Result(await service.GetAsync(id, ct));

    [HttpPost]
    public async Task<IActionResult> Create(SaveTeamUserRequest request, CancellationToken ct) =>
        Result(await service.SaveAsync(User.GetRequiredUserId(), TeamAccess.IsTeamUser(User), null, request, ct));

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, SaveTeamUserRequest request, CancellationToken ct) =>
        Result(await service.SaveAsync(User.GetRequiredUserId(), TeamAccess.IsTeamUser(User), id, request, ct));

    [HttpPost("{id:guid}/status")]
    public async Task<IActionResult> Status(Guid id, TeamStatusRequest request, CancellationToken ct) =>
        Result(await service.SetStatusAsync(User.GetRequiredUserId(), id, request.IsActive, ct));

    private IActionResult Result<T>(ServiceResult<T> result) =>
        result.Success
            ? StatusCode(result.StatusCode, ApiResponse<T>.Ok(result.Data!, result.Message))
            : StatusCode(result.StatusCode, new { success = false, error = result.ErrorCode, message = result.Message });
}

/// <summary>What the signed-in portal user may open; used to hide menus and buttons.</summary>
[ApiController]
[Authorize]
[Route("api/v1/admin/team/me")]
public sealed class TeamMeController(TeamService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Me(CancellationToken ct)
    {
        var result = await service.MeAsync(User.GetRequiredUserId(), TeamAccess.IsTeamUser(User), ct);
        return Ok(ApiResponse<TeamMeDto>.Ok(result.Data!));
    }
}
