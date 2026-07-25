using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize(Roles = "Admin,Operations")]
[Route("api/v1/admin/packages")]
public sealed class AdminPackagesController(
    PackageMarketplaceService packageService) : ControllerBase
{
    [HttpGet("pending")]
    public async Task<IActionResult> GetPending(
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.GetPendingPackagesAsync(
            cancellationToken));

    [HttpPut("{packageId:guid}/review")]
    public async Task<IActionResult> Review(
        Guid packageId,
        AdminPackageReviewRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.ReviewPackageAsync(
            User.GetRequiredUserId(),
            packageId,
            request,
            cancellationToken));

    private IActionResult ToActionResult<T>(ServiceResult<T> result)
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

        return Ok(ApiResponse<T>.Ok(result.Data!, result.Message));
    }
}
