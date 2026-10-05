using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>Renting a car, from the Customer's side.</summary>
/// <remarks>
/// Browsing is anonymous. Somebody deciding whether this platform has anything
/// worth renting should not have to make an account to find out — and the
/// listing carries no more than a shop window does: the car, its price, and who
/// owns it by first name.
/// </remarks>
[ApiController]
[Route("api/v1/rentals")]
public sealed class RentalController(RentalService service) : ControllerBase
{
    [AllowAnonymous]
    [HttpGet("vehicles")]
    public async Task<IActionResult> Search(
        [FromQuery] DateOnly? from,
        [FromQuery] DateOnly? to,
        [FromQuery] string? mode,
        [FromQuery] string? category,
        CancellationToken ct) =>
        Result(await service.SearchAsync(from, to, mode, category, ct));

    /// <summary>The days this vehicle is already spoken for.</summary>
    [AllowAnonymous]
    [HttpGet("vehicles/{vehicleId:guid}/blocked-days")]
    public async Task<IActionResult> BlockedDays(
        Guid vehicleId,
        [FromQuery] DateOnly? from,
        CancellationToken ct) =>
        Result(await service.BlockedDaysAsync(vehicleId, from, ct));

    /// <summary>What these dates would cost, before committing to them.</summary>
    /// <remarks>
    /// Anonymous as well, so the price is visible before signing in — but the
    /// documents question in the answer can only be true for somebody we can
    /// identify, so a signed-in caller gets a fuller reply from the same route.
    /// </remarks>
    [AllowAnonymous]
    [HttpPost("vehicles/{vehicleId:guid}/quote")]
    public async Task<IActionResult> Quote(
        Guid vehicleId,
        RentalQuoteRequest request,
        CancellationToken ct) =>
        Result(await service.QuoteAsync(User.GetUserIdOrNull(), vehicleId, request, ct));

    /// <summary>
    /// Sends the request to the owner, then tells them on WhatsApp.
    /// </summary>
    /// <remarks>
    /// The message goes after the request is saved and never undoes it. If
    /// WhatsApp is slow or down, the owner still sees the request in the app,
    /// and the sweep sends a reminder before the answer is due.
    /// </remarks>
    [Authorize]
    [HttpPost("bookings")]
    public async Task<IActionResult> Book(
        CreateRentalBookingRequest request,
        [FromServices] WhatsAppService whatsApp,
        [FromServices] ILogger<RentalController> logger,
        CancellationToken ct)
    {
        var result = await service.BookAsync(User.GetRequiredUserId(), request, ct);
        if (result.Success && result.Data is { } booking)
        {
            try
            {
                var notice = await service.OwnerNoticeAsync(booking.Id, CancellationToken.None);
                if (notice is not null)
                {
                    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(12));
                    var sent = await whatsApp.SendTextAsync(notice.To, notice.Message, timeout.Token);
                    if (sent.Success)
                    {
                        await service.RecordOwnerNoticeAsync(booking.Id, false, CancellationToken.None);
                    }
                }
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "Rental {BookingId} was saved but the owner could not be messaged.", booking.Id);
            }
        }

        return Result(result);
    }

    [Authorize]
    [HttpGet("bookings")]
    public async Task<IActionResult> MyBookings(CancellationToken ct) =>
        Result(await service.MyRentalsAsync(User.GetRequiredUserId(), ct));

    [Authorize]
    [HttpPost("bookings/{bookingId:guid}/cancel")]
    public async Task<IActionResult> Cancel(
        Guid bookingId,
        CancelRentalRequest request,
        CancellationToken ct) =>
        Result(await service.CancelAsync(User.GetRequiredUserId(), bookingId, request, ct));

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

/// <summary>The Customer's own identity documents.</summary>
/// <remarks>
/// Needed only for self-drive, asked once, and reviewed by nobody at UDrive.
/// The person handing over the car checks them against the person in front of
/// them — the only check that proves anything.
/// </remarks>
[ApiController]
[Authorize]
[Route("api/v1/customer/documents")]
public sealed class CustomerDocumentsController(CustomerDocumentsService service)
    : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken ct) =>
        Result(await service.GetAsync(User.GetRequiredUserId(), ct));

    [HttpPost("{kind}")]
    [RequestSizeLimit(12 * 1024 * 1024)]
    public async Task<IActionResult> Upload(
        string kind,
        IFormFile file,
        CancellationToken ct) =>
        Result(await service.UploadAsync(User.GetRequiredUserId(), kind, file, ct));

    private IActionResult Result<T>(ServiceResult<T> result) =>
        result.Success
            ? Ok(ApiResponse<T>.Ok(result.Data!, result.Message))
            : StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
            });
}

/// <summary>Renting out a car, from the owner's side.</summary>
[ApiController]
[Authorize]
[Route("api/v1/driver/rentals")]
public sealed class DriverRentalController(
    RentalService service,
    LocalFileStorageService fileStorage) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Mine(CancellationToken ct) =>
        Result(await service.DriverRentalsAsync(User.GetRequiredUserId(), ct));

    /// <summary>The owner confirms or rejects a waiting request.</summary>
    [HttpPost("{bookingId:guid}/respond")]
    public async Task<IActionResult> Respond(
        Guid bookingId,
        RespondRentalRequest request,
        CancellationToken ct) =>
        Result(await service.RespondAsync(User.GetRequiredUserId(), bookingId, request, ct));

    /// <summary>One condition photo: phase handover|return, side front|back|left|right.</summary>
    [HttpPost("{bookingId:guid}/photos/{phase}/{side}")]
    [RequestSizeLimit(12 * 1024 * 1024)]
    public async Task<IActionResult> Photo(
        Guid bookingId,
        string phase,
        string side,
        IFormFile? file,
        CancellationToken ct) =>
        Result(await service.UploadConditionPhotoAsync(User.GetRequiredUserId(), bookingId, phase, side, file, ct));

    [HttpPost("{bookingId:guid}/handover")]
    public async Task<IActionResult> Handover(
        Guid bookingId,
        RentalHandoverRequest request,
        CancellationToken ct) =>
        Result(await service.HandOverAsync(User.GetRequiredUserId(), bookingId, request, ct));

    [HttpPost("{bookingId:guid}/return")]
    public async Task<IActionResult> Return(
        Guid bookingId,
        RentalReturnRequest request,
        CancellationToken ct) =>
        Result(await service.ReturnAsync(User.GetRequiredUserId(), bookingId, request, ct));

    /// <summary>Marks the car handed over, returned, or a no-show.</summary>
    [HttpPost("{bookingId:guid}/status/{status}")]
    public async Task<IActionResult> SetStatus(
        Guid bookingId,
        string status,
        CancellationToken ct) =>
        Result(await service.SetStatusAsync(User.GetRequiredUserId(), bookingId, status, ct));

    /// <summary>
    /// One of the Customer's documents, for the owner of this booking only.
    /// </summary>
    /// <remarks>
    /// The entitlement lives in one statement inside the service: the caller
    /// must own the vehicle on this booking, the rental must be self-drive, and
    /// it must still be live. A finished or cancelled rental stops being a
    /// reason to hold somebody's CNIC on screen.
    ///
    /// Served through the protected file route, never the anonymous
    /// vehicle-images one.
    /// </remarks>
    [HttpGet("{bookingId:guid}/customer-documents/{kind}")]
    public async Task<IActionResult> CustomerDocument(
        Guid bookingId,
        string kind,
        CancellationToken ct)
    {
        var storedUrl = await service.CustomerDocumentUrlAsync(
            User.GetRequiredUserId(), bookingId, kind, ct);
        var file = fileStorage.ResolveStoredUrl(storedUrl);
        if (file is null)
        {
            return NotFound(new
            {
                success = false,
                error = "document_not_found",
                message = "That document has not been uploaded.",
            });
        }

        return PhysicalFile(file.Path, file.ContentType);
    }

    private IActionResult Result<T>(ServiceResult<T> result) =>
        result.Success
            ? Ok(ApiResponse<T>.Ok(result.Data!, result.Message))
            : StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
            });
}
