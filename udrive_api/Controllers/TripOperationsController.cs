using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/trips")]
public sealed class TripOperationsController(TripOperationsService operations,TrackingService tracking):ControllerBase
{
    [HttpGet("driver/offers")] public async Task<IActionResult> DriverOffers(CancellationToken ct)=>Result(await operations.DriverOffersAsync(User.GetRequiredUserId(),ct));
    [HttpPut("driver/offers/{offerId:guid}")] public async Task<IActionResult> Respond(Guid offerId,RespondDriverBookingOfferRequest request,CancellationToken ct)=>Result(await operations.RespondOfferAsync(User.GetRequiredUserId(),offerId,request,ct));
    [HttpGet("driver/my")] public async Task<IActionResult> DriverTrips(CancellationToken ct)=>Result(await operations.DriverTripsAsync(User.GetRequiredUserId(),ct));
    [HttpGet("customer/my")] public async Task<IActionResult> CustomerTrips(CancellationToken ct)=>Result(await operations.CustomerTripsAsync(User.GetRequiredUserId(),ct));
    [HttpPut("{bookingId:guid}/driver-status")] public async Task<IActionResult> DriverStatus(Guid bookingId,ChangeTripStatusRequest request,CancellationToken ct)=>Result(await operations.ChangeStatusAsync(User.GetRequiredUserId(),"Driver",false,bookingId,request,ct));
    [HttpPut("{bookingId:guid}/customer-status")] public async Task<IActionResult> CustomerStatus(Guid bookingId,ChangeTripStatusRequest request,CancellationToken ct)=>Result(await operations.ChangeStatusAsync(User.GetRequiredUserId(),"Customer",false,bookingId,request,ct));
    [HttpPost("{bookingId:guid}/tracking-link")] public async Task<IActionResult> CreateLink(Guid bookingId,CreateTrackingLinkRequest request,CancellationToken ct)=>Result(await tracking.CreateLinkAsync(User.GetRequiredUserId(),bookingId,request,ct));
    [HttpDelete("{bookingId:guid}/tracking-link")] public async Task<IActionResult> RevokeLink(Guid bookingId,CancellationToken ct)=>Result(await tracking.RevokeLinksAsync(User.GetRequiredUserId(),bookingId,ct));
    [HttpGet("{bookingId:guid}/tracking")] public async Task<IActionResult> Tracking(Guid bookingId,CancellationToken ct)=>Result(await tracking.PrivateAsync(User.GetRequiredUserId(),User.IsInRole("SuperAdmin")||User.IsInRole("Admin")||User.IsInRole("Manager")||User.IsInRole("Operations"),bookingId,ct));
    private IActionResult Result<T>(ServiceResult<T> result)=>result.Success?Ok(ApiResponse<T>.Ok(result.Data!,result.Message)):StatusCode(result.StatusCode,new{success=false,error=result.ErrorCode,message=result.Message,traceId=HttpContext.TraceIdentifier});
}
