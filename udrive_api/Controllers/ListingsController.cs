using System.Globalization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// "Earn with your vehicle": an owner lists a car for rent and tours, invites
/// the people who drive it, blocks rent days and posts daily departures.
/// </summary>
[ApiController]
[Authorize]
[Route("api/v1/listings")]
public sealed class ListingsController(
    ListingService service,
    WhatsAppService whatsApp,
    ILogger<ListingsController> logger) : ControllerBase
{
    [HttpGet("me")]
    public async Task<IActionResult> Me(CancellationToken ct) =>
        Result(await service.HomeAsync(User.GetRequiredUserId(), ct));

    [HttpPost("vehicles")]
    public async Task<IActionResult> Create(SaveListingVehicleRequest request, CancellationToken ct) =>
        Result(await service.SaveVehicleAsync(User.GetRequiredUserId(), null, request, ct));

    [HttpPut("vehicles/{id:guid}")]
    public async Task<IActionResult> Update(Guid id, SaveListingVehicleRequest request, CancellationToken ct) =>
        Result(await service.SaveVehicleAsync(User.GetRequiredUserId(), id, request, ct));

    [HttpPost("vehicles/{id:guid}/photos/{kind}")]
    [RequestSizeLimit(12 * 1024 * 1024)]
    public async Task<IActionResult> VehiclePhoto(Guid id, string kind, IFormFile file, CancellationToken ct) =>
        Result(await service.UploadVehiclePhotoAsync(User.GetRequiredUserId(), id, kind, file, ct));

    [HttpPost("owner/documents/{kind}")]
    [RequestSizeLimit(12 * 1024 * 1024)]
    public async Task<IActionResult> OwnerDocument(string kind, IFormFile file, CancellationToken ct) =>
        Result(await service.UploadOwnerDocumentAsync(User.GetRequiredUserId(), kind, file, ct));

    [HttpPost("vehicles/{id:guid}/submit")]
    public async Task<IActionResult> Submit(Guid id, SubmitListingRequest request, CancellationToken ct) =>
        Result(await service.SubmitAsync(User.GetRequiredUserId(), id, request, ct));

    // ─────────────────────────────────────────── drivers

    /// <summary>Adds a driver and sends them the invite on WhatsApp.</summary>
    /// <remarks>
    /// The invite is saved first and never undone by WhatsApp failing: the
    /// driver finds it in the app under their own number either way.
    /// </remarks>
    [HttpPost("drivers")]
    public async Task<IActionResult> Invite(InviteDriverRequest request, CancellationToken ct)
    {
        var result = await service.InviteDriverAsync(User.GetRequiredUserId(), request, ct);
        if (!result.Success || result.Data is null) return Result(result);

        var invite = result.Data;
        await SendAsync(
            invite.Phone,
            $"UDrive: {invite.OwnerName} has added you as a driver for their vehicle. "
            + "Install the UDrive app, sign in with this number, and open Profile → Driver invites "
            + "to send your CNIC, licence and a selfie.",
            "driver invite");
        return Ok(ApiResponse<FleetDriverDto>.Ok(invite.Driver, result.Message));
    }

    [HttpPost("drivers/{id:guid}/remove")]
    public async Task<IActionResult> RemoveDriver(Guid id, CancellationToken ct) =>
        Result(await service.RemoveDriverAsync(User.GetRequiredUserId(), id, ct));

    [HttpGet("invites")]
    public async Task<IActionResult> Invites(CancellationToken ct) =>
        Result(await service.InvitesAsync(User.GetRequiredUserId(), ct));

    [HttpPost("invites/{id:guid}/documents/{kind}")]
    [RequestSizeLimit(12 * 1024 * 1024)]
    public async Task<IActionResult> InviteDocument(Guid id, string kind, IFormFile file, CancellationToken ct) =>
        Result(await service.UploadInviteDocumentAsync(User.GetRequiredUserId(), id, kind, file, ct));

    [HttpPost("invites/{id:guid}/submit")]
    public async Task<IActionResult> SubmitInvite(Guid id, SubmitInviteRequest request, CancellationToken ct) =>
        Result(await service.SubmitInviteAsync(User.GetRequiredUserId(), id, request, ct));

    [HttpPost("invites/{id:guid}/decline")]
    public async Task<IActionResult> DeclineInvite(Guid id, CancellationToken ct) =>
        Result(await service.DeclineInviteAsync(User.GetRequiredUserId(), id, ct));

    // ─────────────────────────────────────────── rent calendar

    [HttpGet("vehicles/{id:guid}/calendar")]
    public async Task<IActionResult> Calendar(
        Guid id, [FromQuery] DateOnly? from, [FromQuery] int days = 42, CancellationToken ct = default) =>
        Result(await service.CalendarAsync(User.GetRequiredUserId(), id, from, days, ct));

    [HttpPut("vehicles/{id:guid}/blocked-days")]
    public async Task<IActionResult> BlockedDays(Guid id, BlockedDaysRequest request, CancellationToken ct) =>
        Result(await service.SetBlockedDaysAsync(User.GetRequiredUserId(), id, request, ct));

    // ─────────────────────────────────────────── tour departures

    /// <param name="month"><c>yyyy-MM</c>; this month in Pakistan when left out.</param>
    [HttpGet("vehicles/{id:guid}/departures")]
    public async Task<IActionResult> Departures(Guid id, [FromQuery] string? month, CancellationToken ct)
    {
        var today = ListingService.Today();
        var year = today.Year;
        var number = today.Month;
        if (!string.IsNullOrWhiteSpace(month))
        {
            if (!DateTime.TryParseExact(month.Trim(), "yyyy-MM", CultureInfo.InvariantCulture,
                    DateTimeStyles.None, out var parsed))
            {
                return BadRequest(new { success = false, error = "month_invalid", message = "Month must be yyyy-MM." });
            }

            year = parsed.Year;
            number = parsed.Month;
        }

        return Result(await service.DeparturesAsync(User.GetRequiredUserId(), id, year, number, ct));
    }

    [HttpPut("vehicles/{id:guid}/departures/{date}")]
    public async Task<IActionResult> SaveDeparture(Guid id, string date, SaveDepartureRequest request, CancellationToken ct) =>
        ParseDate(date) is { } day
            ? Result(await service.SaveDepartureAsync(User.GetRequiredUserId(), id, day, request, ct))
            : BadDate();

    [HttpPost("vehicles/{id:guid}/departures/{date}/cancel")]
    public async Task<IActionResult> CancelDeparture(Guid id, string date, CancellationToken ct) =>
        ParseDate(date) is { } day
            ? Result(await service.CancelDepartureAsync(User.GetRequiredUserId(), id, day, ct))
            : BadDate();

    // ─────────────────────────────────────────── helpers

    private async Task SendAsync(string to, string message, string what)
    {
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(12));
            await whatsApp.SendTextAsync(to, message, timeout.Token);
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "The {What} WhatsApp message could not be sent.", what);
        }
    }

    private static DateOnly? ParseDate(string value) =>
        DateOnly.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day)
            ? day
            : null;

    private BadRequestObjectResult BadDate() =>
        BadRequest(new { success = false, error = "date_invalid", message = "Date must be yyyy-MM-dd." });

    private IActionResult Result<T>(ServiceResult<T> result) =>
        result.Success
            ? StatusCode(result.StatusCode, ApiResponse<T>.Ok(result.Data!, result.Message))
            : StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
            });
}

/// <summary>Admin review of listed vehicles and owners' drivers.</summary>
[ApiController]
[Authorize(Roles = "Admin,SuperAdmin")]
[Route("api/v1/admin")]
public sealed class AdminListingsController(
    ListingService service,
    WhatsAppService whatsApp,
    ILogger<AdminListingsController> logger) : ControllerBase
{
    [HttpGet("listings")]
    public async Task<IActionResult> Listings([FromQuery] string? status, CancellationToken ct) =>
        Result(await service.AdminListingsAsync(status, ct));

    [HttpPost("listings/{vehicleId:guid}/approve")]
    public async Task<IActionResult> Approve(Guid vehicleId, CancellationToken ct) =>
        await Notified(await service.ApproveListingAsync(User.GetRequiredUserId(), vehicleId, ct));

    [HttpPost("listings/{vehicleId:guid}/reject")]
    public async Task<IActionResult> Reject(Guid vehicleId, AdminReasonRequest request, CancellationToken ct) =>
        await Notified(await service.RejectListingAsync(
            User.GetRequiredUserId(), vehicleId, request.Reason ?? request.Note, false, ct));

    [HttpPost("listings/{vehicleId:guid}/request-info")]
    public async Task<IActionResult> RequestInfo(Guid vehicleId, AdminReasonRequest request, CancellationToken ct) =>
        await Notified(await service.RejectListingAsync(
            User.GetRequiredUserId(), vehicleId, request.Note ?? request.Reason, true, ct));

    /// <summary>Staff list a vehicle for an owner they met in person.</summary>
    [HttpPost("listings/for-owner")]
    [RequestSizeLimit(60 * 1024 * 1024)]
    public async Task<IActionResult> ForOwner(CancellationToken ct)
    {
        if (!Request.HasFormContentType)
        {
            return BadRequest(new { success = false, error = "form_required", message = "Send the listing as a form with photos." });
        }

        var form = await Request.ReadFormAsync(ct);
        return Result(await service.AddForOwnerAsync(User.GetRequiredUserId(), form, ct));
    }

    [HttpGet("fleet-drivers")]
    public async Task<IActionResult> Drivers([FromQuery] string? status, CancellationToken ct) =>
        Result(await service.AdminDriversAsync(status, ct));

    [HttpPost("fleet-drivers/{id:guid}/approve")]
    public async Task<IActionResult> ApproveDriver(Guid id, CancellationToken ct) =>
        await DriverNotified(await service.ReviewDriverAsync(User.GetRequiredUserId(), id, true, null, ct), true);

    [HttpPost("fleet-drivers/{id:guid}/reject")]
    public async Task<IActionResult> RejectDriver(Guid id, AdminReasonRequest request, CancellationToken ct) =>
        await DriverNotified(await service.ReviewDriverAsync(
            User.GetRequiredUserId(), id, false, request.Reason ?? request.Note, ct), false);

    private async Task<IActionResult> Notified(ServiceResult<ListingService.ApprovalResult> result)
    {
        if (!result.Success || result.Data is null)
        {
            return StatusCode(result.StatusCode, new { success = false, error = result.ErrorCode, message = result.Message });
        }

        if (!string.IsNullOrWhiteSpace(result.Data.Message))
        {
            await SendAsync(result.Data.OwnerPhone, result.Data.Message);
        }

        return Ok(ApiResponse<AdminListingDto>.Ok(result.Data.Listing, result.Message));
    }

    private async Task<IActionResult> DriverNotified(ServiceResult<AdminFleetDriverDto> result, bool approved)
    {
        if (result.Success && result.Data is { } driver && !driver.IsOwner)
        {
            await SendAsync(
                driver.Phone,
                approved
                    ? $"UDrive: you are approved to drive for {driver.OwnerName}. They can now assign you to bookings."
                    : $"UDrive: your driver documents were not approved — {driver.ReviewNote} "
                      + "Open the UDrive app → Profile → Driver invites to send them again.");
        }

        return Result(result);
    }

    private async Task SendAsync(string to, string message)
    {
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(12));
            await whatsApp.SendTextAsync(to, message, timeout.Token);
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "A listing review WhatsApp message could not be sent.");
        }
    }

    private IActionResult Result<T>(ServiceResult<T> result) =>
        result.Success
            ? StatusCode(result.StatusCode, ApiResponse<T>.Ok(result.Data!, result.Message))
            : StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
            });
}
