using Microsoft.AspNetCore.Authorization;using Microsoft.AspNetCore.Mvc;using UDrive.Api.Common;using UDrive.Api.Models;using UDrive.Api.Security;using UDrive.Api.Services;
namespace UDrive.Api.Controllers;
[ApiController][Authorize][Route("api/v1/safety")]public sealed class SafetyController(SafetyService s):ControllerBase{
[HttpGet("trusted-contacts")]public async Task<IActionResult> Contacts(CancellationToken ct)=>R(await s.Contacts(User.GetRequiredUserId(),ct));
[HttpPost("trusted-contacts")]public async Task<IActionResult> Save(TrustedContactRequest x,CancellationToken ct)=>R(await s.SaveContact(User.GetRequiredUserId(),x,ct));
[HttpDelete("trusted-contacts/{id:guid}")]public async Task<IActionResult> Delete(Guid id,CancellationToken ct)=>R(await s.DeleteContact(User.GetRequiredUserId(),id,ct));
[HttpPost("sos")]public async Task<IActionResult> Sos(RaiseSosRequest x,CancellationToken ct)=>R(await s.RaiseSos(User.GetRequiredUserId(),x,ct));
[HttpPost("reports")]public async Task<IActionResult> Report(CreateSafetyReportRequest x,CancellationToken ct)=>R(await s.Report(User.GetRequiredUserId(),x,ct));
[HttpPost("trips/{bookingId:guid}/pin")]public async Task<IActionResult> Pin(Guid bookingId,CancellationToken ct)=>R(await s.CreatePin(User.GetRequiredUserId(),bookingId,ct));
[HttpPost("trips/{bookingId:guid}/pin/verify")]public async Task<IActionResult> Verify(Guid bookingId,VerifyTripPinRequest x,CancellationToken ct)=>R(await s.VerifyPin(User.GetRequiredUserId(),bookingId,x,ct));
IActionResult R<T>(ServiceResult<T>x)=>x.Success?StatusCode(x.StatusCode,ApiResponse<T>.Ok(x.Data!,x.Message)):StatusCode(x.StatusCode,new{success=false,error=x.ErrorCode,message=x.Message,traceId=HttpContext.TraceIdentifier});}
[ApiController][Authorize(Roles="SuperAdmin,Admin,Manager,Operations,SafetyOfficer")][Route("api/v1/admin/safety")]public sealed class AdminSafetyController(SafetyService s):ControllerBase{
[HttpGet("dashboard")]public async Task<IActionResult> Dashboard(CancellationToken ct)=>R(await s.Dashboard(ct));
[HttpGet("emergencies")]public async Task<IActionResult> Cases([FromQuery]string? status,CancellationToken ct)=>R(await s.Cases(status,ct));
[HttpPut("emergencies/{id:guid}")]public async Task<IActionResult> Update(Guid id,UpdateEmergencyRequest x,CancellationToken ct)=>R(await s.Update(User.GetRequiredUserId(),id,x,ct));
IActionResult R<T>(ServiceResult<T>x)=>x.Success?Ok(ApiResponse<T>.Ok(x.Data!,x.Message)):StatusCode(x.StatusCode,new{success=false,error=x.ErrorCode,message=x.Message,traceId=HttpContext.TraceIdentifier});}
