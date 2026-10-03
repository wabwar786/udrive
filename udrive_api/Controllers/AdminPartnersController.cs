using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// Territory partners, from the admin portal.
/// </summary>
/// <remarks>
/// The role list is narrow for the same reason the growth section's is: approving
/// an application hands somebody an exclusive territory and a share of the
/// business's commission. That is not a support-desk action.
///
/// <para>Two routes are narrower still. The signature evidence — the live
/// photograph and the video — is <b>SuperAdmin only</b>, and both routes that
/// touch it write an <c>audit_logs</c> row naming who looked. Personal data of
/// this kind needs a list of who has seen it, not just a lock.</para>
/// </remarks>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations")]
[Route("api/v1/admin/partners")]
public sealed class AdminPartnersController(
    AdminPartnerService service,
    LocalFileStorageService storage) : ControllerBase
{
    // ─────────────────────────────────────────────────────────────── tiers

    [HttpGet("tiers")]
    public async Task<IActionResult> Tiers(CancellationToken ct) =>
        Result(await service.TiersAsync(ct));

    [HttpPut("tiers/{tierKey}")]
    [Authorize(Roles = "SuperAdmin,Admin")]
    public async Task<IActionResult> SaveTier(
        string tierKey,
        PartnerTierRequest request,
        CancellationToken ct) =>
        Result(await service.SaveTierAsync(tierKey, request, User.GetUserIdOrNull(), ct));

    // ───────────────────────────────────────────────────────── territories

    [HttpGet("territories")]
    public async Task<IActionResult> Territories(CancellationToken ct) =>
        Result(await service.TerritoriesAsync(ct));

    [HttpPost("territories")]
    public async Task<IActionResult> CreateTerritory(
        TerritoryRequest request,
        CancellationToken ct) =>
        Result(await service.SaveTerritoryAsync(null, request, User.GetUserIdOrNull(), ct));

    [HttpPut("territories/{id:guid}")]
    public async Task<IActionResult> UpdateTerritory(
        Guid id,
        TerritoryRequest request,
        CancellationToken ct) =>
        Result(await service.SaveTerritoryAsync(id, request, User.GetUserIdOrNull(), ct));

    [HttpDelete("territories/{id:guid}")]
    [Authorize(Roles = "SuperAdmin,Admin")]
    public async Task<IActionResult> DeleteTerritory(Guid id, CancellationToken ct) =>
        Result(await service.DeleteTerritoryAsync(id, User.GetUserIdOrNull(), ct));

    /// <summary>Places one driver in a tehsil, or takes them out of one.</summary>
    /// <remarks>
    /// The only way a tehsil's numbers become real. Nothing in the schema has ever
    /// known which tehsil a driver works in, and a GPS point is not an answer to
    /// that question.
    /// </remarks>
    [HttpPut("drivers/{driverProfileId:guid}/territory")]
    public async Task<IActionResult> SetDriverTerritory(
        Guid driverProfileId,
        [FromQuery] Guid? territoryId,
        CancellationToken ct) =>
        Result(await service.SetDriverTerritoryAsync(
            driverProfileId, territoryId, User.GetUserIdOrNull(), ct));

    // ──────────────────────────────────────────────────── city map circles

    [HttpGet("city-areas")]
    public async Task<IActionResult> CityAreas([FromQuery] Guid? cityId, CancellationToken ct) =>
        Result(await service.CityAreasAsync(cityId, ct));

    [HttpPost("city-areas")]
    public async Task<IActionResult> CreateCityArea(
        LaunchCityAreaRequest request,
        CancellationToken ct) =>
        Result(await service.SaveCityAreaAsync(request, User.GetUserIdOrNull(), ct));

    [HttpDelete("city-areas/{id:guid}")]
    public async Task<IActionResult> DeleteCityArea(Guid id, CancellationToken ct) =>
        Result(await service.DeleteCityAreaAsync(id, User.GetUserIdOrNull(), ct));

    [HttpGet("waitlist")]
    public async Task<IActionResult> Waitlist([FromQuery] Guid? cityId, CancellationToken ct) =>
        Result(await service.WaitlistAsync(cityId, ct));

    // ─────────────────────────────────────────────────────────── the queue

    [HttpGet("applications")]
    public async Task<IActionResult> Applications(
        [FromQuery] string? status,
        CancellationToken ct) =>
        Result(await service.ApplicationsAsync(status, ct));

    [HttpPost("applications/{id:guid}/decision")]
    public async Task<IActionResult> Decide(
        Guid id,
        PartnerDecisionRequest request,
        CancellationToken ct) =>
        Result(await service.DecideAsync(id, request, User.GetUserIdOrNull(), ct));

    // ──────────────────────────────────────────────────────── the partners

    [HttpGet]
    public async Task<IActionResult> Partners([FromQuery] string? status, CancellationToken ct) =>
        Result(await service.PartnersAsync(status, ct));

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Detail(Guid id, CancellationToken ct) =>
        Result(await service.PartnerDetailAsync(id, User.IsInRole("SuperAdmin"), ct));

    [HttpPost("{id:guid}/status")]
    public async Task<IActionResult> SetStatus(
        Guid id,
        PartnerStatusRequest request,
        CancellationToken ct) =>
        Result(await service.SetPartnerStatusAsync(id, request, User.GetUserIdOrNull(), ct));

    // ──────────────────────────────────────────────────────── the contract

    [HttpPost("{id:guid}/contract")]
    public async Task<IActionResult> CreateContract(
        Guid id,
        PartnerContractDraftRequest request,
        CancellationToken ct) =>
        Result(await service.CreateContractAsync(id, request, User.GetUserIdOrNull(), ct));

    [HttpPut("contracts/{contractId:guid}")]
    public async Task<IActionResult> EditContract(
        Guid contractId,
        PartnerContractEditRequest request,
        CancellationToken ct) =>
        Result(await service.EditContractAsync(contractId, request, User.GetUserIdOrNull(), ct));

    [HttpPost("contracts/{contractId:guid}/send")]
    public async Task<IActionResult> SendContract(Guid contractId, CancellationToken ct) =>
        Result(await service.SendContractAsync(contractId, User.GetUserIdOrNull(), ct));

    [HttpPost("contracts/{contractId:guid}/terminate")]
    [Authorize(Roles = "SuperAdmin,Admin")]
    public async Task<IActionResult> TerminateContract(
        Guid contractId,
        PartnerTerminateRequest request,
        CancellationToken ct) =>
        Result(await service.TerminateContractAsync(
            contractId, request, User.GetUserIdOrNull(), ct));

    [HttpPost("contracts/{contractId:guid}/recompute")]
    public async Task<IActionResult> Recompute(Guid contractId, CancellationToken ct) =>
        Result(await service.RecomputeAsync(contractId, ct));

    [HttpGet("templates")]
    public async Task<IActionResult> Templates(CancellationToken ct) =>
        Result(await service.TemplatesAsync(ct));

    [HttpPut("templates/{templateId:guid}")]
    [Authorize(Roles = "SuperAdmin,Admin")]
    public async Task<IActionResult> SaveTemplate(
        Guid templateId,
        PartnerContractTemplateRequest request,
        CancellationToken ct) =>
        Result(await service.SaveTemplateAsync(
            templateId, request, User.GetUserIdOrNull(), ct));

    // ──────────────────────────────────────────── months and statements

    [HttpPost("periods/{periodId:guid}/record")]
    public async Task<IActionResult> RecordPeriod(
        Guid periodId,
        PartnerPeriodRecordRequest request,
        CancellationToken ct) =>
        Result(await service.RecordPeriodAsync(
            periodId, request, User.GetUserIdOrNull(), ct));

    [HttpPost("statements/{statementId:guid}/close")]
    public async Task<IActionResult> CloseStatement(Guid statementId, CancellationToken ct) =>
        Result(await service.CloseStatementAsync(statementId, User.GetUserIdOrNull(), ct));

    /// <remarks>
    /// Records that a payment happened outside the app. Nothing here moves money —
    /// there is no payout path in this feature at all, by design.
    /// </remarks>
    [HttpPost("statements/{statementId:guid}/paid")]
    [Authorize(Roles = "SuperAdmin,Admin,FinanceOfficer")]
    public async Task<IActionResult> MarkStatementPaid(
        Guid statementId,
        PartnerStatementPaidRequest request,
        CancellationToken ct) =>
        Result(await service.MarkStatementPaidAsync(
            statementId, request, User.GetUserIdOrNull(), ct));

    // ───────────────────────────────────────────── the signature evidence

    /// <summary>The photograph, the video and the server's own record of it.</summary>
    [HttpGet("contracts/{contractId:guid}/evidence")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<IActionResult> Evidence(Guid contractId, CancellationToken ct) =>
        Result(await service.ViewEvidenceAsync(
            contractId,
            User.GetUserIdOrNull(),
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            ct));

    /// <summary>Serves one evidence file.</summary>
    /// <remarks>
    /// Resolved by contract and exact filename, with no search across storage —
    /// somebody authorised for one contract's evidence must not be able to reach
    /// another's by guessing a name. Every served file is logged.
    /// </remarks>
    [HttpGet("evidence/{contractId:guid}/{fileName}")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<IActionResult> EvidenceFile(
        Guid contractId,
        string fileName,
        CancellationToken ct)
    {
        var served = await service.LogEvidenceFileAsync(
            contractId,
            fileName,
            User.GetUserIdOrNull(),
            HttpContext.Connection.RemoteIpAddress?.ToString(),
            ct);

        if (!served.Success)
        {
            return Result(served);
        }

        var resolved = storage.ResolveSignatureEvidence(contractId, fileName);
        return resolved is null
            ? StatusCode(
                StatusCodes.Status404NotFound,
                new
                {
                    success = false,
                    error = "file_missing",
                    message = "The record exists but the file is not in storage. "
                        + "Check that the uploads volume is mounted.",
                    traceId = HttpContext.TraceIdentifier,
                })
            : PhysicalFile(resolved.Path, resolved.ContentType);
    }

    [HttpPost("contracts/{contractId:guid}/evidence/purge")]
    [Authorize(Roles = "SuperAdmin")]
    public async Task<IActionResult> PurgeEvidence(Guid contractId, CancellationToken ct) =>
        Result(await service.PurgeEvidenceAsync(
            contractId, storage, User.GetUserIdOrNull(), ct));

    private IActionResult Result<T>(ServiceResult<T> result) =>
        result.Success
            ? Ok(ApiResponse<T>.Ok(result.Data!, result.Message))
            : StatusCode(
                result.StatusCode,
                new
                {
                    success = false,
                    error = result.ErrorCode,
                    message = result.Message,
                    traceId = HttpContext.TraceIdentifier,
                });
}
