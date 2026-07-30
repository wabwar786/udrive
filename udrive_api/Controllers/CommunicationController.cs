using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;
namespace UDrive.Api.Controllers;
[ApiController,Authorize,Route("api/v1")]
public sealed class CommunicationController(CommunicationService service, WhatsAppService whatsAppService):ControllerBase
{
 [HttpGet("notifications")]public async Task<IActionResult> Notifications([FromQuery]int take=50,CancellationToken ct=default)=>R(await service.NotificationsAsync(User.GetRequiredUserId(),take,ct));
 [HttpPut("notifications/{id:guid}/read")]public async Task<IActionResult> Read(Guid id,CancellationToken ct)=>R(await service.MarkReadAsync(User.GetRequiredUserId(),id,ct));
 [HttpPut("notifications/read-all")]public async Task<IActionResult> ReadAll(CancellationToken ct)=>R(await service.MarkReadAsync(User.GetRequiredUserId(),null,ct));
 [HttpGet("notification-preferences")]public async Task<IActionResult> Preferences(CancellationToken ct)=>R(await service.PreferencesAsync(User.GetRequiredUserId(),ct));
 [HttpPut("notification-preferences")]public async Task<IActionResult> Save(NotificationPreferencesDto request,CancellationToken ct)=>R(await service.SavePreferencesAsync(User.GetRequiredUserId(),request,ct));
 [HttpPost("devices/register")]public async Task<IActionResult> Register(RegisterDeviceRequest request,CancellationToken ct)=>R(await service.RegisterDeviceAsync(User.GetRequiredUserId(),request,ct));
 [HttpGet("bookings/{bookingId:guid}/messages")]public async Task<IActionResult> Messages(Guid bookingId,CancellationToken ct)=>R(await service.MessagesAsync(User.GetRequiredUserId(),bookingId,ct));
 [HttpPost("bookings/{bookingId:guid}/messages")]public async Task<IActionResult> Send(Guid bookingId,SendBookingMessageRequest request,CancellationToken ct)=>R(await service.SendAsync(User.GetRequiredUserId(),bookingId,request,ct));
 [HttpPost("communication/whatsapp/location-share")]public async Task<IActionResult> ShareLocation(WhatsAppLocationShareRequest request,CancellationToken ct)=>R(await whatsAppService.ShareLocationAsync(request,ct));
 IActionResult R<T>(ServiceResult<T> x)=>x.Success?Ok(ApiResponse<T>.Ok(x.Data!,x.Message)):StatusCode(x.StatusCode,new{success=false,error=x.ErrorCode,message=x.Message,traceId=HttpContext.TraceIdentifier});
}
