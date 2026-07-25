using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Route("api/v1/packages")]
public sealed class PackagesController(
    PackageMarketplaceService packageService) : ControllerBase
{
    [AllowAnonymous]
    [HttpGet]
    public async Task<IActionResult> GetPackages(
        [FromQuery] Guid? destinationId,
        [FromQuery] DateTimeOffset? departureFrom,
        [FromQuery] int? minimumSeats,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.GetPublicPackagesAsync(
            destinationId,
            departureFrom,
            minimumSeats,
            cancellationToken));

    [AllowAnonymous]
    [HttpGet("{packageId:guid}")]
    public async Task<IActionResult> GetPackage(
        Guid packageId,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.GetPublicPackageAsync(
            packageId,
            cancellationToken));

    [AllowAnonymous]
    [HttpGet("{packageId:guid}/availability")]
    public async Task<IActionResult> GetAvailability(
        Guid packageId,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.GetAvailabilityAsync(
            packageId,
            cancellationToken));

    [Authorize]
    [HttpPost("{packageId:guid}/holds")]
    public async Task<IActionResult> AcquireHold(
        Guid packageId,
        AcquirePackageHoldRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.AcquireHoldAsync(
            User.GetRequiredUserId(),
            packageId,
            request,
            cancellationToken));

    [Authorize]
    [HttpPost("{packageId:guid}/bookings")]
    public async Task<IActionResult> ConfirmBooking(
        Guid packageId,
        ConfirmPackageBookingRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.ConfirmHoldAsync(
            User.GetRequiredUserId(),
            packageId,
            request,
            cancellationToken));

    [Authorize]
    [HttpPost("{packageId:guid}/waitlist")]
    public async Task<IActionResult> JoinWaitlist(
        Guid packageId,
        JoinPackageWaitlistRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.JoinWaitlistAsync(
            User.GetRequiredUserId(),
            packageId,
            request,
            cancellationToken));

    [Authorize]
    [HttpGet("waitlist/my")]
    public async Task<IActionResult> GetMyWaitlist(
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.GetCustomerWaitlistAsync(
            User.GetRequiredUserId(),
            cancellationToken));

    [Authorize]
    [HttpPost("{packageId:guid}/offers")]
    public async Task<IActionResult> CreateOffer(
        Guid packageId,
        CreatePackageOfferRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.CreatePackageOfferAsync(
            User.GetRequiredUserId(),
            packageId,
            request,
            cancellationToken));

    [Authorize]
    [HttpGet("offers/my")]
    public async Task<IActionResult> GetMyOffers(
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.GetMyPackageOffersAsync(
            User.GetRequiredUserId(),
            asDriver: false,
            cancellationToken));

    [Authorize]
    [HttpPost("offers/{offerId:guid}/confirm")]
    public async Task<IActionResult> ConfirmOffer(
        Guid offerId,
        [FromBody] ConfirmOfferRequest request,
        CancellationToken cancellationToken) =>
        ToActionResult(await packageService.ConfirmPackageOfferAsync(
            User.GetRequiredUserId(),
            offerId,
            request.AdvanceAmount,
            request.Passengers,
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

public sealed record ConfirmOfferRequest(
    decimal AdvanceAmount,
    IReadOnlyList<PassengerRequest>? Passengers);
