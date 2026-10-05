using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>Districts and tehsils: the public list for app pickers.</summary>
[ApiController]
[Route("api/v1/catalog/areas")]
public sealed class AreasCatalogController(AreaService service) : ControllerBase
{
    [AllowAnonymous, HttpGet]
    [ResponseCache(Duration = 300, Location = ResponseCacheLocation.Any)]
    public async Task<IActionResult> Get(CancellationToken ct) =>
        HubResults.From(this, await service.PublicAsync(ct));
}

/// <summary>Settings → Areas.</summary>
[ApiController]
[Authorize(Roles = "Admin,SuperAdmin")]
[Route("api/v1/admin/areas")]
public sealed class AdminAreasController(AreaService service) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct) =>
        HubResults.From(this, await service.AdminAsync(ct));

    [HttpPost("districts")]
    public async Task<IActionResult> AddDistrict(SaveDistrictRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.AddDistrictAsync(User.GetRequiredUserId(), request, ct));

    [HttpPost("tehsils")]
    public async Task<IActionResult> AddTehsil(SaveTehsilRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.AddTehsilAsync(User.GetRequiredUserId(), request, ct));

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, UpdateAreaRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.UpdateAsync(User.GetRequiredUserId(), id, request, ct));
}

/// <summary>
/// The Verification page: tab counts, the tour / rent / hotels / businesses
/// queues and their decisions, and the location fix for every kind. City rides
/// keep their own routes under /api/v1/admin/verification.
/// </summary>
[ApiController]
[Authorize(Roles = "SuperAdmin,Admin,Manager,Operations,VerificationOfficer")]
[Route("api/v1/admin/verify")]
public sealed class VerificationHubController(
    VerificationHubService service,
    WhatsAppService whatsApp,
    ILogger<VerificationHubController> logger) : ControllerBase
{
    [HttpGet("summary")]
    public async Task<IActionResult> Summary([FromQuery] string? area, CancellationToken ct) =>
        HubResults.From(this, await service.SummaryAsync(area, ct));

    [HttpGet("{tab}")]
    public async Task<IActionResult> Queue(
        string tab, [FromQuery] string? status, [FromQuery] string? area, [FromQuery] string? q, CancellationToken ct) =>
        HubResults.From(this, await service.QueueAsync(tab.ToLowerInvariant(), status, area, q, ct));

    [HttpGet("{tab}/{id:guid}")]
    public async Task<IActionResult> Detail(string tab, Guid id, CancellationToken ct) =>
        HubResults.From(this, await service.DetailAsync(tab.ToLowerInvariant(), id, ct));

    [HttpPost("{tab}/{id:guid}/approve")]
    public async Task<IActionResult> Approve(string tab, Guid id, CancellationToken ct) =>
        await Decided(await service.ApproveAsync(User.GetRequiredUserId(), tab.ToLowerInvariant(), id, ct));

    [HttpPost("{tab}/{id:guid}/reject")]
    public async Task<IActionResult> Reject(string tab, Guid id, VerificationNoteRequest request, CancellationToken ct) =>
        await Decided(await service.RejectAsync(User.GetRequiredUserId(), tab.ToLowerInvariant(), id, request.Note, false, ct));

    [HttpPost("{tab}/{id:guid}/request-info")]
    public async Task<IActionResult> RequestInfo(string tab, Guid id, VerificationNoteRequest request, CancellationToken ct) =>
        await Decided(await service.RejectAsync(User.GetRequiredUserId(), tab.ToLowerInvariant(), id, request.Note, true, ct));

    /// <param name="kind">city-driver, city-vehicle, tour, rent, hotels or businesses.</param>
    [HttpPut("{kind}/{id:guid}/location")]
    public async Task<IActionResult> Location(string kind, Guid id, VehicleLocationRequest request, CancellationToken ct) =>
        HubResults.From(this, await service.SetLocationAsync(User.GetRequiredUserId(), kind.ToLowerInvariant(), id, request.TehsilId, ct));

    /// <summary>Saves the decision, then tells the owner on WhatsApp. A slow WhatsApp never undoes it.</summary>
    private async Task<IActionResult> Decided(ServiceResult<VerificationHubService.Decision> result)
    {
        if (result.Success && result.Data is { NotifyPhone: { Length: > 0 } phone, NotifyMessage: { Length: > 0 } message })
        {
            try
            {
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(12));
                await whatsApp.SendTextAsync(phone, message, timeout.Token);
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "A verification WhatsApp message could not be sent.");
            }
        }

        return result.Success
            ? Ok(ApiResponse<object>.Ok(result.Data!.Data, result.Message))
            : StatusCode(result.StatusCode, new { success = false, error = result.ErrorCode, message = result.Message });
    }
}

internal static class HubResults
{
    public static IActionResult From<T>(ControllerBase controller, ServiceResult<T> result) =>
        result.Success
            ? controller.StatusCode(result.StatusCode, ApiResponse<T>.Ok(result.Data!, result.Message))
            : controller.StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
            });
}
