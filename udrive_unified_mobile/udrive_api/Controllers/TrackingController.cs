using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/tracking")]
public sealed class TrackingController(TrackingService service):ControllerBase
{
    [EnableRateLimiting("location")][HttpPost("driver/location")] public async Task<IActionResult> Update(DriverLocationUpdateRequest request,CancellationToken ct)=>Result(await service.UpdateAsync(User.GetRequiredUserId(),request,ct));
    [Authorize(Roles="SuperAdmin,Admin,Manager,Operations")][HttpGet("admin/active")] public async Task<IActionResult> Active([FromQuery]string? search,[FromQuery]string? city,[FromQuery]string? status,[FromQuery]bool emergencyOnly=false,[FromQuery]bool staleOnly=false,CancellationToken ct=default)=>Result(await service.ActiveAsync(search,city,status,emergencyOnly,staleOnly,ct));
    [Authorize(Roles="SuperAdmin,Admin,Manager,Operations")][HttpGet("admin/{bookingId:guid}")] public async Task<IActionResult> AdminTrip(Guid bookingId,CancellationToken ct)=>Result(await service.PrivateAsync(User.GetRequiredUserId(),true,bookingId,ct));

    /// <summary>Creates a link that lets someone follow this trip without an account.</summary>
    /// <remarks>
    /// <c>CreateLinkAsync</c> has existed since phase 12 and no route ever
    /// called it, so the feature was written and then unreachable — a Customer
    /// could not share a ride with anyone.
    ///
    /// The token is returned once and only its hash is stored, so a link cannot
    /// be recovered from the database and re-sent by anyone who reads it there.
    /// The link stops working the moment the trip ends, which is what makes it
    /// safe to send to a family group.
    /// </remarks>
    [HttpPost("{bookingId:guid}/link")]
    public async Task<IActionResult> CreateLink(Guid bookingId,CreateTrackingLinkRequest request,CancellationToken ct)=>Result(await service.CreateLinkAsync(User.GetRequiredUserId(),bookingId,request,ct));

    /// <summary>Kills every share link for this trip.</summary>
    [HttpDelete("{bookingId:guid}/link")]
    public async Task<IActionResult> RevokeLinks(Guid bookingId,CancellationToken ct)=>Result(await service.RevokeLinksAsync(User.GetRequiredUserId(),bookingId,ct));
    private IActionResult Result<T>(ServiceResult<T> result)=>result.Success?Ok(ApiResponse<T>.Ok(result.Data!,result.Message)):StatusCode(result.StatusCode,new{success=false,error=result.ErrorCode,message=result.Message,traceId=HttpContext.TraceIdentifier});
}

[ApiController]
[Route("api/v1/public/tracking")]
public sealed class PublicTrackingController(TrackingService service):ControllerBase
{
    [EnableRateLimiting("public-tracking")][HttpGet("{token}")] public async Task<IActionResult> View(string token,CancellationToken ct){var result=await service.PublicAsync(token,ct);return result.Success?Ok(ApiResponse<TripTrackingDto>.Ok(result.Data!,result.Message)):StatusCode(result.StatusCode,new{success=false,error=result.ErrorCode,message=result.Message,traceId=HttpContext.TraceIdentifier});}
}
