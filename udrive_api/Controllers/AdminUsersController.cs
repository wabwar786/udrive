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
public sealed class AdminUsersController(
    AdminUserManagementService service,
    AccountDeletionService accountDeletion,
    AuthSqlStore authStore) : ControllerBase
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

    /// <summary>
    /// Deletes an account on a person's emailed request (the public
    /// /account-deletion page offers email for people who cannot open the app).
    /// Same effect as in-app deletion; the audit log records the admin.
    /// </summary>
    [HttpPost("delete-account")]
    public async Task<IActionResult> DeleteAccount(
        AdminDeleteAccountRequest request,
        CancellationToken cancellationToken)
    {
        if (!PhoneNumberNormalizer.TryNormalizePakistan(request.PhoneNumber, out var phone))
        {
            return Result(ServiceResult<bool>.Fail(
                StatusCodes.Status400BadRequest, "invalid_phone_number",
                "Enter a valid Pakistani mobile number, for example 03001234567."));
        }

        var user = await authStore.GetUserByPhoneAsync(phone, cancellationToken);
        if (user is null)
        {
            return Result(ServiceResult<bool>.Fail(
                StatusCodes.Status404NotFound, "user_not_found",
                "No account uses this mobile number."));
        }

        var adminId = User.GetRequiredUserId();
        if (user.Id == adminId)
        {
            return Result(ServiceResult<bool>.Fail(
                StatusCodes.Status400BadRequest, "cannot_delete_self",
                "Use the app to delete your own account."));
        }

        return Result(await accountDeletion.DeleteAsync(
            user.Id,
            adminId,
            request.Reason,
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            cancellationToken));
    }

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
