using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/bookings")]
public sealed class BookingsController(BookingService bookingService) : ControllerBase
{
    [HttpPost("ride-requests")]
    public async Task<IActionResult> CreateRideRequest(
        CreateRideRequestRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await bookingService.CreateRideRequestAsync(
            User.GetRequiredUserId(),
            request,
            cancellationToken));

    [HttpGet("ride-requests/my")]
    public async Task<IActionResult> GetMyRideRequests(
        CancellationToken cancellationToken) =>
        ToActionResult(await bookingService.GetMyRideRequestsAsync(
            User.GetRequiredUserId(),
            cancellationToken));

    [HttpGet("ride-requests/{rideRequestId:guid}/offers")]
    public async Task<IActionResult> GetOffers(
        Guid rideRequestId,
        CancellationToken cancellationToken) =>
        ToActionResult(await bookingService.GetRideOffersAsync(
            User.GetRequiredUserId(),
            rideRequestId,
            cancellationToken));

    [HttpPost("ride-requests/{rideRequestId:guid}/offers/{offerId:guid}/decline")]
    public async Task<IActionResult> DeclineOffer(
        Guid rideRequestId,
        Guid offerId,
        [FromQuery] bool countTowardsDriverRejectLimit = true,
        CancellationToken cancellationToken = default) =>
        ToActionResult(await bookingService.DeclineDriverOfferAsync(
            User.GetRequiredUserId(),
            rideRequestId,
            offerId,
            countTowardsDriverRejectLimit,
            cancellationToken));

    [HttpPost("ride-requests/{rideRequestId:guid}/offers/{offerId:guid}/select")]
    public async Task<IActionResult> SelectOffer(
        Guid rideRequestId,
        Guid offerId,
        SelectDriverOfferRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await bookingService.SelectDriverOfferAsync(
            User.GetRequiredUserId(),
            rideRequestId,
            offerId,
            request,
            cancellationToken));

    [HttpGet("my")]
    public async Task<IActionResult> GetMyBookings(
        CancellationToken cancellationToken) =>
        ToActionResult(await bookingService.GetMyBookingsAsync(
            User.GetRequiredUserId(),
            cancellationToken));

    [HttpPost("{bookingId:guid}/cancel")]
    public async Task<IActionResult> Cancel(
        Guid bookingId,
        CancelBookingRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await bookingService.CancelBookingAsync(
            User.GetRequiredUserId(),
            bookingId,
            request,
            cancellationToken));

    [HttpPut("{bookingId:guid}/reschedule")]
    public async Task<IActionResult> Reschedule(
        Guid bookingId,
        RescheduleBookingRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await bookingService.RescheduleBookingAsync(
            User.GetRequiredUserId(),
            bookingId,
            request,
            cancellationToken));

    [HttpGet("{bookingId:guid}/history")]
    public async Task<IActionResult> GetHistory(
        Guid bookingId,
        CancellationToken cancellationToken) =>
        ToActionResult(await bookingService.GetHistoryAsync(
            User.GetRequiredUserId(),
            bookingId,
            cancellationToken));

    private IActionResult ToActionResult<T>(ServiceResult<T> result)
    {
        if (!result.Success)
        {
            return StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
                traceId = HttpContext.TraceIdentifier
            });
        }

        var response = ApiResponse<T>.Ok(result.Data!, result.Message);
        return result.StatusCode == StatusCodes.Status201Created
            ? StatusCode(StatusCodes.Status201Created, response)
            : Ok(response);
    }
}
