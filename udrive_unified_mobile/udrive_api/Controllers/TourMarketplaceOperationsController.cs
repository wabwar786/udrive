using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/tour-marketplace")]
public sealed class TourMarketplaceOperationsController(Phase18TourService service) : ControllerBase
{
    [AllowAnonymous]
    [HttpGet("packages/{packageId:guid}/content")]
    public async Task<IActionResult> Content(Guid packageId, CancellationToken ct) => Result(await service.GetContentAsync(packageId, ct));

    [HttpPut("driver/packages/{packageId:guid}/content")]
    public async Task<IActionResult> ReplaceContent(Guid packageId, UpdateTourPackageContentRequest request, CancellationToken ct) => Result(await service.ReplaceContentAsync(User.GetRequiredUserId(), packageId, request, ct));

    [HttpGet("customer/bookings")]
    public async Task<IActionResult> CustomerBookings(CancellationToken ct) => Result(await service.GetCustomerPackageBookingsAsync(User.GetRequiredUserId(), ct));

    [HttpGet("driver/operations")]
    public async Task<IActionResult> DriverOperations(CancellationToken ct) => Result(await service.GetDriverOperationsAsync(User.GetRequiredUserId(), ct));

    [HttpPut("driver/operations/{operationId:guid}/status")]
    public async Task<IActionResult> Status(Guid operationId, UpdateTourStatusRequest request, CancellationToken ct) => Result(await service.ChangeStatusAsync(User.GetRequiredUserId(), operationId, request, ct));

    [HttpPost("driver/operations/{operationId:guid}/check-ins")]
    public async Task<IActionResult> CheckIn(Guid operationId, CheckInPassengerRequest request, CancellationToken ct) => Result(await service.CheckInAsync(User.GetRequiredUserId(), operationId, request, ct));

    private IActionResult Result<T>(ServiceResult<T> result) => result.Success
        ? Ok(ApiResponse<T>.Ok(result.Data!, result.Message))
        : StatusCode(result.StatusCode, new { success=false, error=result.ErrorCode, message=result.Message, traceId=HttpContext.TraceIdentifier });
}
