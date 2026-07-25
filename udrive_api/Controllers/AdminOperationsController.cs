using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations,VerificationOfficer,SupportAgent,FinanceOfficer,SafetyOfficer,TourismManager")]
[Route("api/v1/admin/operations")]
public sealed class AdminOperationsController(AdminOperationsService service) : ControllerBase
{
    [HttpGet("dashboard")] public async Task<IActionResult> Dashboard(CancellationToken ct)=>Result(await service.DashboardAsync(ct));
    [HttpGet("bookings")] public async Task<IActionResult> Bookings([FromQuery]string? status,[FromQuery]string? search,CancellationToken ct)=>Result(await service.BookingsAsync(status,search,ct));
    [HttpGet("bookings/{id:guid}")] public async Task<IActionResult> Booking(Guid id,CancellationToken ct)=>Result(await service.BookingDetailAsync(id,ct));
    [HttpPut("bookings/{id:guid}/status")] public async Task<IActionResult> BookingStatus(Guid id,UpdateBookingStatusRequest request,CancellationToken ct)=>Result(await service.UpdateBookingStatusAsync(User.GetRequiredUserId(),id,request,ct));
    [HttpGet("ride-requests")] public async Task<IActionResult> RideRequests(CancellationToken ct)=>Result(await service.RideRequestsAsync(ct));
    [HttpGet("users")] public async Task<IActionResult> Users([FromQuery]string? search,CancellationToken ct)=>Result(await service.UsersAsync(search,ct));
    [Authorize(Roles="SuperAdmin")][HttpPut("users/{id:guid}/status")] public async Task<IActionResult> UserStatus(Guid id,UpdateUserStatusRequest request,CancellationToken ct)=>Result(await service.UpdateUserStatusAsync(User.GetRequiredUserId(),id,request,ct));
    [Authorize(Roles="SuperAdmin")][HttpPut("users/{id:guid}/roles")] public async Task<IActionResult> UserRoles(Guid id,UpdateUserRolesRequest request,CancellationToken ct)=>Result(await service.UpdateUserRolesAsync(User.GetRequiredUserId(),id,request,ct));
    [HttpGet("drivers")] public async Task<IActionResult> Drivers(CancellationToken ct)=>Result(await service.DriversAsync(ct));
    [HttpGet("vehicles")] public async Task<IActionResult> Vehicles(CancellationToken ct)=>Result(await service.VehiclesAsync(ct));
    [HttpGet("destinations")] public async Task<IActionResult> Destinations(CancellationToken ct)=>Result(await service.DestinationsAsync(ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations,TourismManager")][HttpPost("destinations")] public async Task<IActionResult> CreateDestination(UpsertDestinationRequest request,CancellationToken ct)=>Result(await service.CreateDestinationAsync(User.GetRequiredUserId(),request,ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations,TourismManager")][HttpPut("destinations/{id:guid}")] public async Task<IActionResult> UpdateDestination(Guid id,UpsertDestinationRequest request,CancellationToken ct)=>Result(await service.UpdateDestinationAsync(User.GetRequiredUserId(),id,request,ct));
    [HttpGet("routes")] public async Task<IActionResult> Routes(CancellationToken ct)=>Result(await service.RoutesAsync(ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations,TourismManager")][HttpPost("routes")] public async Task<IActionResult> CreateRoute(UpsertRouteRequest request,CancellationToken ct)=>Result(await service.CreateRouteAsync(User.GetRequiredUserId(),request,ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations,TourismManager")][HttpPut("routes/{id:guid}")] public async Task<IActionResult> UpdateRoute(Guid id,UpsertRouteRequest request,CancellationToken ct)=>Result(await service.UpdateRouteAsync(User.GetRequiredUserId(),id,request,ct));
    [HttpGet("advisories")] public async Task<IActionResult> Advisories(CancellationToken ct)=>Result(await service.AdvisoriesAsync(ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations,TourismManager,SafetyOfficer")][HttpPost("advisories")] public async Task<IActionResult> CreateAdvisory(UpsertAdvisoryRequest request,CancellationToken ct)=>Result(await service.CreateAdvisoryAsync(User.GetRequiredUserId(),request,ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations,TourismManager,SafetyOfficer")][HttpPut("advisories/{id:guid}")] public async Task<IActionResult> UpdateAdvisory(Guid id,UpsertAdvisoryRequest request,CancellationToken ct)=>Result(await service.UpdateAdvisoryAsync(User.GetRequiredUserId(),id,request,ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations,SafetyOfficer")][HttpGet("safety-incidents")] public async Task<IActionResult> Safety(CancellationToken ct)=>Result(await service.SafetyIncidentsAsync(ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations,SafetyOfficer")][HttpPut("safety-incidents/{id:guid}")] public async Task<IActionResult> SafetyUpdate(Guid id,UpdateSafetyIncidentRequest request,CancellationToken ct)=>Result(await service.UpdateSafetyIncidentAsync(User.GetRequiredUserId(),id,request,ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations,FinanceOfficer")][HttpGet("payments")] public async Task<IActionResult> Payments(CancellationToken ct)=>Result(await service.PaymentsAsync(ct));
    [Authorize(Roles="SuperAdmin,Admin,FinanceOfficer")][HttpPut("payments/{id:guid}")] public async Task<IActionResult> PaymentUpdate(Guid id,UpdatePaymentRequest request,CancellationToken ct)=>Result(await service.UpdatePaymentAsync(User.GetRequiredUserId(),id,request,ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations,SupportAgent")][HttpGet("tickets")] public async Task<IActionResult> Tickets(CancellationToken ct)=>Result(await service.TicketsAsync(ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations,SupportAgent")][HttpPost("tickets")] public async Task<IActionResult> CreateTicket(CreateSupportTicketRequest request,CancellationToken ct)=>Result(await service.CreateTicketAsync(User.GetRequiredUserId(),request,ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations,SupportAgent")][HttpPut("tickets/{id:guid}")] public async Task<IActionResult> UpdateTicket(Guid id,UpdateSupportTicketRequest request,CancellationToken ct)=>Result(await service.UpdateTicketAsync(User.GetRequiredUserId(),id,request,ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations,SupportAgent,SafetyOfficer,TourismManager")][HttpPost("notifications/broadcast")] public async Task<IActionResult> Broadcast(BroadcastNotificationRequest request,CancellationToken ct)=>Result(await service.BroadcastAsync(User.GetRequiredUserId(),request,ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations")][HttpGet("audit-logs")] public async Task<IActionResult> Audit(CancellationToken ct)=>Result(await service.AuditLogsAsync(ct));
    [Authorize(Roles="SuperAdmin,Admin,Operations")][HttpGet("settings")] public async Task<IActionResult> Settings(CancellationToken ct)=>Result(await service.SettingsAsync(ct));
    [Authorize(Roles="SuperAdmin")][HttpPut("settings")] public async Task<IActionResult> SettingsUpdate(UpdateSettingsRequest request,CancellationToken ct)=>Result(await service.UpdateSettingsAsync(User.GetRequiredUserId(),request,ct));

    private IActionResult Result<T>(ServiceResult<T> result)
    {
        if(!result.Success) return StatusCode(result.StatusCode,new{success=false,error=result.ErrorCode,message=result.Message,traceId=HttpContext.TraceIdentifier});
        var body=ApiResponse<T>.Ok(result.Data!,result.Message);
        return result.StatusCode==StatusCodes.Status201Created?StatusCode(201,body):Ok(body);
    }
}
