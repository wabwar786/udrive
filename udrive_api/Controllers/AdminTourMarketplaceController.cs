using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize(Roles="SuperAdmin,Admin,Manager,Operations")]
[Route("api/v1/admin/tour-marketplace")]
public sealed class AdminTourMarketplaceController(Phase18TourService service) : ControllerBase
{
    [HttpGet("packages")]
    public async Task<IActionResult> Packages([FromQuery] string? status, CancellationToken ct)
    {
        var result=await service.GetAdminPackagesAsync(status,ct);
        return result.Success ? Ok(ApiResponse<object>.Ok(result.Data!)) : StatusCode(result.StatusCode,new{success=false,error=result.ErrorCode,message=result.Message,traceId=HttpContext.TraceIdentifier});
    }
}
