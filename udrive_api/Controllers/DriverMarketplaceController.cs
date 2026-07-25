using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/driver/marketplace")]
public sealed class DriverMarketplaceController(
    BookingService bookingService,
    PackageMarketplaceService packageService) : ControllerBase
{
    [HttpGet("ride-requests")]
    public async Task<IActionResult> GetRideRequests(
        CancellationToken cancellationToken) =>
        ToActionResult(await bookingService.GetEligibleRideRequestsAsync(
            User.GetRequiredUserId(),
            cancellationToken));

    [HttpPost("ride-requests/{rideRequestId:guid}/offers")]
    public async Task<IActionResult> SubmitOffer(
        Guid rideRequestId,
        SubmitDriverOfferRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await bookingService.SubmitDriverOfferAsync(
            User.GetRequiredUserId(),
            rideRequestId,
            request,
            cancellationToken));

    [HttpPost("packages")]
    public async Task<IActionResult> CreatePackage(
        CreateTourPackageRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.CreateDriverPackageAsync(
            User.GetRequiredUserId(),
            request,
            cancellationToken));

    [HttpPut("packages/{packageId:guid}")]
    public async Task<IActionResult> UpdatePackage(
        Guid packageId,
        CreateTourPackageRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.UpdateDriverPackageAsync(
            User.GetRequiredUserId(),
            packageId,
            request,
            cancellationToken));

    [HttpPost("packages/{packageId:guid}/submit")]
    public async Task<IActionResult> SubmitPackage(
        Guid packageId,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.SubmitPackageAsync(
            User.GetRequiredUserId(),
            packageId,
            cancellationToken));

    [HttpPost("packages/{packageId:guid}/pause")]
    public async Task<IActionResult> PausePackage(
        Guid packageId,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.TogglePackageAsync(
            User.GetRequiredUserId(),
            packageId,
            activate: false,
            cancellationToken));

    [HttpPost("packages/{packageId:guid}/activate")]
    public async Task<IActionResult> ActivatePackage(
        Guid packageId,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.TogglePackageAsync(
            User.GetRequiredUserId(),
            packageId,
            activate: true,
            cancellationToken));

    [HttpGet("packages")]
    public async Task<IActionResult> GetPackages(
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.GetDriverPackagesAsync(
            User.GetRequiredUserId(),
            cancellationToken));

    [HttpGet("packages/bookings")]
    public async Task<IActionResult> GetPackageBookings(
        [FromQuery] Guid? packageId,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.GetDriverPackageBookingsAsync(
            User.GetRequiredUserId(),
            packageId,
            cancellationToken));

    [HttpGet("packages/waitlist")]
    public async Task<IActionResult> GetPackageWaitlist(
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.GetDriverWaitlistAsync(
            User.GetRequiredUserId(),
            cancellationToken));

    [HttpGet("bookings/{bookingId:guid}/passengers")]
    public async Task<IActionResult> GetPassengerManifest(
        Guid bookingId,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.GetPassengerManifestAsync(
            User.GetRequiredUserId(),
            bookingId,
            cancellationToken));

    [HttpGet("packages/offers")]
    public async Task<IActionResult> GetPackageOffers(
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.GetMyPackageOffersAsync(
            User.GetRequiredUserId(),
            asDriver: true,
            cancellationToken));

    [HttpPut("packages/offers/{offerId:guid}")]
    public async Task<IActionResult> ReviewPackageOffer(
        Guid offerId,
        ReviewPackageOfferRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.ReviewPackageOfferAsync(
            User.GetRequiredUserId(),
            offerId,
            request,
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
