using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize(Roles="SuperAdmin,Admin,Manager,Operations,FinanceOfficer,SafetyOfficer,TourismManager")]
[Route("api/v1/admin/executive")]
public sealed class AdminExecutiveController(Phase19AdminService service):ControllerBase
{
 [HttpGet("dashboard")] public async Task<IActionResult> Dashboard([FromQuery]DateTimeOffset? from,[FromQuery]DateTimeOffset? to,CancellationToken ct)=>Result(await service.DashboardAsync(from,to,ct));
 [HttpGet("operations/live")] public async Task<IActionResult> Live(CancellationToken ct)=>Result(await service.LiveOperationsAsync(ct));
 [HttpGet("bookings")] public async Task<IActionResult> Bookings([FromQuery]string? search,[FromQuery]string? status,[FromQuery]DateTimeOffset? from,[FromQuery]DateTimeOffset? to,CancellationToken ct)=>Result(await service.BookingsAsync(search,status,from,to,ct));
 [Authorize(Roles="SuperAdmin,Admin,FinanceOfficer")][HttpGet("finance/reconciliation")] public async Task<IActionResult> Finance([FromQuery]DateTimeOffset? from,[FromQuery]DateTimeOffset? to,CancellationToken ct)=>Result(await service.FinanceAsync(from,to,ct));
 [HttpGet("reports/daily")] public async Task<IActionResult> Report([FromQuery]DateTimeOffset? from,[FromQuery]DateTimeOffset? to,CancellationToken ct)=>Result(await service.ReportAsync(from,to,ct));
 [Authorize(Roles="SuperAdmin,Admin,Operations")][HttpGet("diagnostics")] public async Task<IActionResult> Diagnostics(CancellationToken ct)=>Result(await service.DiagnosticsAsync(ct));
 [Authorize(Roles="SuperAdmin,Admin,Operations")][HttpGet("audit")] public async Task<IActionResult> Audit([FromQuery]string? search,CancellationToken ct)=>Result(await service.AuditAsync(search,ct));
 private IActionResult Result<T>(ServiceResult<T> result)=>result.Success?Ok(ApiResponse<T>.Ok(result.Data!,result.Message)):StatusCode(result.StatusCode,new{success=false,error=result.ErrorCode,message=result.Message,traceId=HttpContext.TraceIdentifier});
}
