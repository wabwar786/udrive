using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>Which services the customer app may open.</summary>
/// <remarks>
/// Anonymous on purpose. The customer app reads this before anyone signs in —
/// the home screen has to know what to dim on first launch — and there is
/// nothing private here: it is the same information the tiles display.
/// </remarks>
[ApiController]
[AllowAnonymous]
[Route("api/v1/services")]
public sealed class PublicServiceAvailabilityController(
    ServiceAvailabilityService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var result = await service.ListAsync(ct);
        return Ok(ApiResponse<IReadOnlyList<ServiceAvailabilityDto>>.Ok(result.Data!));
    }
}

/// <summary>Opening and closing services.</summary>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin")]
[Route("api/v1/admin/services")]
public sealed class AdminServiceAvailabilityController(
    ServiceAvailabilityService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var result = await service.ListAsync(ct);
        return Ok(ApiResponse<IReadOnlyList<ServiceAvailabilityDto>>.Ok(result.Data!));
    }

    [HttpPut("{serviceKey}")]
    public async Task<IActionResult> Update(
        string serviceKey,
        UpdateServiceAvailabilityRequest request,
        CancellationToken ct)
    {
        var result = await service.UpdateAsync(
            User.GetRequiredUserId(), serviceKey, request, ct);

        return result.Success
            ? Ok(ApiResponse<bool>.Ok(true))
            : StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
            });
    }
}
