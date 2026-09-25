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

    /// <summary>Evidence attached to a dispute this user is a party to.</summary>
    /// <remarks>
    /// This route used to hand every path segment straight to the storage
    /// resolver behind a bare <c>[Authorize]</c> — no role, no ownership check
    /// and no restriction on the category. Any signed-in customer or driver
    /// could therefore ask it for <c>driver-documents/{id}/{file}</c> and be
    /// served another driver's CNIC, and the resolver's legacy fallback
    /// searches every storage root by filename alone, so the category and owner
    /// segments protected nothing at all.
    ///
    /// Three checks now stand in the way, and all three must pass: the category
    /// must be dispute evidence, the owner segment must be a case this user
    /// opened or is named in, and the file must actually be listed as evidence
    /// on that case. The legacy fallback is switched off here, so only the
    /// exact stored path can resolve.
    ///
    /// Everything that fails returns 404 rather than 403: a distinct "forbidden"
    /// would confirm that a given file exists, which is most of what somebody
    /// probing paths wants to learn.
    /// </remarks>
    [HttpGet("files/{category}/{owner}/{fileName}")]
    public async Task<IActionResult> File(string category,string owner,string fileName,CancellationToken ct)
    {
        if(!string.Equals(category,"disputes",StringComparison.Ordinal))return NotFound();
        if(!Guid.TryParse(owner,out var caseId))return NotFound();

        var access=await service.CaseDetailAsync(User.GetRequiredUserId(),caseId,false,ct);
        if(!access.Success)return NotFound();

        var listed=access.Data!.Evidence?.Any(e=>
            e.FileUrl.EndsWith("/"+fileName,StringComparison.Ordinal))??false;
        if(!listed)return NotFound();

        var f=files.ResolveProtectedFile(category,owner,fileName,allowLegacyFallback:false);
        return f is null?NotFound():PhysicalFile(f.Path,f.ContentType,f.DownloadName);
    }
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
    /// <summary>Dispute evidence, for the staff handling the case.</summary>
    /// <remarks>
    /// Restricted to the disputes category with the legacy fallback off. These
    /// roles include SupportAgent, SafetyOfficer, Manager and Operations, none
    /// of whom do verification — and with the fallback on, a filename was
    /// enough to pull a driver's CNIC out of a different category entirely.
    /// </remarks>
    [HttpGet("files/{category}/{owner}/{fileName}")]
    public IActionResult File(string category,string owner,string fileName)
    {
        if(!string.Equals(category,"disputes",StringComparison.Ordinal))return NotFound();
        var f=files.ResolveProtectedFile(category,owner,fileName,allowLegacyFallback:false);
        return f is null?NotFound():PhysicalFile(f.Path,f.ContentType,f.DownloadName);
    }

    IActionResult Result<T>(ServiceResult<T> r)=>r.Success?Ok(ApiResponse<T>.Ok(r.Data!,r.Message)):StatusCode(r.StatusCode,new{success=false,error=r.ErrorCode,message=r.Message,traceId=HttpContext.TraceIdentifier});
}
