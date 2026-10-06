using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// The Reports Centre. Open to every portal role; what each person sees is
/// decided per report and per area inside <see cref="ReportsService"/> —
/// SuperAdmin sees everything, anyone else only the reports given to them.
/// </summary>
[ApiController]
[Authorize(Roles = PortalRoles)]
[Route("api/v1/admin/reports")]
public sealed class ReportsController(ReportsService service) : ControllerBase
{
    internal const string PortalRoles =
        "SuperAdmin,Admin,Manager,Operations,VerificationOfficer,SupportAgent,FinanceOfficer,SafetyOfficer,TourismManager,Staff";

    private bool Super => User.IsInRole("SuperAdmin");

    /// <summary>The reports this person may open, and the areas they may pick.</summary>
    [HttpGet("catalog")]
    public async Task<IActionResult> Catalog(CancellationToken ct) =>
        Result(await service.CatalogAsync(User.GetRequiredUserId(), Super, ct));

    /// <summary>
    /// Runs one report. Query: from, to (yyyy-MM-dd, Pakistan days), area (a
    /// district or tehsil id), gb (day | week | month) and the report's own
    /// filters by key.
    /// </summary>
    [HttpGet("run/{key}")]
    public async Task<IActionResult> Run(string key, [FromQuery] string? from, [FromQuery] string? to, [FromQuery] Guid? area, CancellationToken ct)
    {
        var filters = Request.Query
            .Where(q => q.Key is not ("from" or "to" or "area"))
            .ToDictionary(q => q.Key, q => q.Value.ToString(), StringComparer.Ordinal);
        return Result(await service.RunAsync(User.GetRequiredUserId(), Super, key, new ReportQuery(from, to, area, filters), ct));
    }

    private IActionResult Result<T>(ServiceResult<T> result) =>
        result.Success
            ? Ok(ApiResponse<T>.Ok(result.Data!, result.Message))
            : StatusCode(result.StatusCode, new { success = false, error = result.ErrorCode, message = result.Message, traceId = HttpContext.TraceIdentifier });
}

/// <summary>Team page: which reports a portal user may open (and, for non-team users, their areas).</summary>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin")]
[Route("api/v1/admin/team/{id:guid}/reports")]
public sealed class TeamReportsController(ReportsService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct) => Result(await service.AccessAsync(id, ct));

    [HttpPut]
    public async Task<IActionResult> Save(Guid id, SaveReportAccessRequest request, CancellationToken ct) =>
        Result(await service.SaveAccessAsync(
            User.GetRequiredUserId(), User.IsInRole("SuperAdmin"), TeamAccess.IsTeamUser(User), id, request, ct));

    private IActionResult Result<T>(ServiceResult<T> result) =>
        result.Success
            ? Ok(ApiResponse<T>.Ok(result.Data!, result.Message))
            : StatusCode(result.StatusCode, new { success = false, error = result.ErrorCode, message = result.Message, traceId = HttpContext.TraceIdentifier });
}
