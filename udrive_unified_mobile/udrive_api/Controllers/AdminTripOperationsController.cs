using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize(Roles="SuperAdmin,Admin,Manager,Operations")]
[Route("api/v1/admin/trip-operations")]
public sealed class AdminTripOperationsController(TripOperationsService service):ControllerBase
{
    [HttpGet] public async Task<IActionResult> Dashboard([FromQuery]string? search,[FromQuery]string? status,[FromQuery]string? paymentStatus,[FromQuery]string? city,[FromQuery]DateTimeOffset? from,[FromQuery]DateTimeOffset? to,[FromQuery]int page=1,[FromQuery]int pageSize=25,CancellationToken ct=default)=>Result(await service.DashboardAsync(search,status,paymentStatus,city,from,to,page,pageSize,ct));
    [HttpGet("{bookingId:guid}")] public async Task<IActionResult> Detail(Guid bookingId,CancellationToken ct)=>Result(await service.DetailAsync(bookingId,ct));
    [HttpGet("{bookingId:guid}/suitable-drivers")] public async Task<IActionResult> Drivers(Guid bookingId,CancellationToken ct)=>Result(await service.SuitableDriversAsync(bookingId,ct));
    [HttpPost("{bookingId:guid}/assign")] public async Task<IActionResult> Assign(Guid bookingId,AssignTripRequest request,CancellationToken ct)=>Result(await service.AssignAsync(User.GetRequiredUserId(),bookingId,request,User.IsInRole("SuperAdmin"),ct));
    [HttpPost("{bookingId:guid}/offers")] public async Task<IActionResult> Offer(Guid bookingId,SendDriverBookingOfferRequest request,CancellationToken ct)=>Result(await service.SendOfferAsync(User.GetRequiredUserId(),bookingId,request,ct));
    [HttpPut("{bookingId:guid}/status")] public async Task<IActionResult> Status(Guid bookingId,ChangeTripStatusRequest request,CancellationToken ct)=>Result(await service.ChangeStatusAsync(User.GetRequiredUserId(),"Admin",User.IsInRole("SuperAdmin"),bookingId,request,ct));
    [HttpPost("{bookingId:guid}/notes")] public async Task<IActionResult> Note(Guid bookingId,AddTripNoteRequest request,CancellationToken ct)=>Result(await service.AddNoteAsync(User.GetRequiredUserId(),bookingId,request,ct));
    [HttpPut("{bookingId:guid}/schedule")] public async Task<IActionResult> Schedule(Guid bookingId,RescheduleTripRequest request,CancellationToken ct)=>Result(await service.RescheduleAsync(User.GetRequiredUserId(),bookingId,request,ct));
    private IActionResult Result<T>(ServiceResult<T> result)=>result.Success?Ok(ApiResponse<T>.Ok(result.Data!,result.Message)):StatusCode(result.StatusCode,new{success=false,error=result.ErrorCode,message=result.Message,traceId=HttpContext.TraceIdentifier});
}
