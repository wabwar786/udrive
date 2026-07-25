using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize(Roles = "SuperAdmin")]
[Route("api/v1/admin/users")]
public sealed class AdminUsersController(AdminUserManagementService service) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Create(
        CreatePortalUserRequest request,
        CancellationToken cancellationToken) =>
        Result(await service.CreateAsync(
            User.GetRequiredUserId(),
            request,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            cancellationToken));

    [HttpPut("{userId:guid}/portal-role")]
    public async Task<IActionResult> UpdatePortalRole(
        Guid userId,
        UpdatePortalRoleRequest request,
        CancellationToken cancellationToken) =>
        Result(await service.UpdatePortalRoleAsync(
            User.GetRequiredUserId(),
            userId,
            request,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            cancellationToken));

    private IActionResult Result<T>(ServiceResult<T> result)
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

        var body = ApiResponse<T>.Ok(result.Data!, result.Message);
        return result.StatusCode == StatusCodes.Status201Created
            ? StatusCode(StatusCodes.Status201Created, body)
            : Ok(body);
    }
}
