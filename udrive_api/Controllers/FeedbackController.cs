using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/feedback")]
public sealed class FeedbackController(FeedbackService service,LocalFileStorageService files):ControllerBase
{
    [HttpGet("eligible-bookings")]public async Task<IActionResult> Eligible(CancellationToken ct)=>Result(await service.EligibleAsync(User.GetRequiredUserId(),ct));
    [HttpPost("ratings")]public async Task<IActionResult> Rate(SubmitRatingRequest request,CancellationToken ct)=>Result(await service.SubmitRatingAsync(User.GetRequiredUserId(),request,ct));
    [HttpGet("ratings/me")]public async Task<IActionResult> Summary(CancellationToken ct)=>Result(await service.SummaryAsync(User.GetRequiredUserId(),ct));
    [HttpPost("cases")]public async Task<IActionResult> CreateCase(CreateDisputeCaseRequest request,CancellationToken ct)=>Result(await service.CreateCaseAsync(User.GetRequiredUserId(),request,ct));
    [HttpGet("cases/my")]public async Task<IActionResult> MyCases(CancellationToken ct)=>Result(await service.MyCasesAsync(User.GetRequiredUserId(),ct));
    [HttpGet("cases/{id:guid}")]public async Task<IActionResult> Detail(Guid id,CancellationToken ct)=>Result(await service.CaseDetailAsync(User.GetRequiredUserId(),id,false,ct));
    [HttpPost("cases/{id:guid}/events")]public async Task<IActionResult> Event(Guid id,AddCaseEventRequest request,CancellationToken ct)=>Result(await service.AddEventAsync(User.GetRequiredUserId(),id,request,false,ct));
    [HttpPost("cases/{id:guid}/evidence")][RequestSizeLimit(10*1024*1024)]public async Task<IActionResult> Evidence(Guid id,[FromForm]IFormFile file,[FromForm]string? description,CancellationToken ct)=>Result(await service.UploadEvidenceAsync(User.GetRequiredUserId(),id,file,description,false,ct));
    [HttpGet("files/{category}/{owner}/{fileName}")]public IActionResult File(string category,string owner,string fileName){var f=files.ResolveProtectedFile(category,owner,fileName);return f is null?NotFound():PhysicalFile(f.Path,f.ContentType,f.DownloadName);}
    IActionResult Result<T>(ServiceResult<T> r)=>r.Success?Ok(ApiResponse<T>.Ok(r.Data!,r.Message)):StatusCode(r.StatusCode,new{success=false,error=r.ErrorCode,message=r.Message,traceId=HttpContext.TraceIdentifier});
}

[ApiController]
[Authorize(Roles="SuperAdmin,Admin,Manager,Operations,SupportAgent,SafetyOfficer")]
[Route("api/v1/admin/disputes")]
public sealed class AdminDisputesController(FeedbackService service,LocalFileStorageService files):ControllerBase
{
    [HttpGet("dashboard")]public async Task<IActionResult> Dashboard(CancellationToken ct)=>Result(await service.DashboardAsync(ct));
    [HttpGet]public async Task<IActionResult> Cases([FromQuery]string? status,[FromQuery]string? priority,[FromQuery]string? search,CancellationToken ct)=>Result(await service.AdminCasesAsync(status,priority,search,ct));
    [HttpGet("{id:guid}")]public async Task<IActionResult> Detail(Guid id,CancellationToken ct)=>Result(await service.CaseDetailAsync(User.GetRequiredUserId(),id,true,ct));
    [HttpPut("{id:guid}/assign")]public async Task<IActionResult> Assign(Guid id,AssignCaseRequest request,CancellationToken ct)=>Result(await service.AssignAsync(User.GetRequiredUserId(),id,request,ct));
    [HttpPut("{id:guid}/status")]public async Task<IActionResult> Update(Guid id,UpdateCaseRequest request,CancellationToken ct)=>Result(await service.UpdateAsync(User.GetRequiredUserId(),id,request,ct));
    [HttpPost("{id:guid}/events")]public async Task<IActionResult> Event(Guid id,AddCaseEventRequest request,CancellationToken ct)=>Result(await service.AddEventAsync(User.GetRequiredUserId(),id,request,true,ct));
    [HttpPost("{id:guid}/actions")]public async Task<IActionResult> Action(Guid id,CaseActionRequest request,CancellationToken ct)=>Result(await service.ActionAsync(User.GetRequiredUserId(),id,request,User.IsInRole("SuperAdmin"),ct));
    [HttpPost("{id:guid}/evidence")][RequestSizeLimit(10*1024*1024)]public async Task<IActionResult> Evidence(Guid id,[FromForm]IFormFile file,[FromForm]string? description,CancellationToken ct)=>Result(await service.UploadEvidenceAsync(User.GetRequiredUserId(),id,file,description,true,ct));
    [HttpGet("files/{category}/{owner}/{fileName}")]public IActionResult File(string category,string owner,string fileName){var f=files.ResolveProtectedFile(category,owner,fileName);return f is null?NotFound():PhysicalFile(f.Path,f.ContentType,f.DownloadName);}
    IActionResult Result<T>(ServiceResult<T> r)=>r.Success?Ok(ApiResponse<T>.Ok(r.Data!,r.Message)):StatusCode(r.StatusCode,new{success=false,error=r.ErrorCode,message=r.Message,traceId=HttpContext.TraceIdentifier});
}
