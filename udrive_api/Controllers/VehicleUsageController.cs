using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// What each of the Driver's approved vehicles is used for.
/// </summary>
/// <remarks>
/// Deliberately separate from <c>DriverVerificationController</c>, which owns
/// registration. Registration is one road with an Admin at the end of it and
/// nothing here touches it: these routes refuse outright until the vehicle is
/// verified. This controller only answers the question that came after —
/// city rides, tours, or rent.
/// </remarks>
[ApiController]
[Authorize]
[Route("api/v1/driver/vehicles")]
public sealed class VehicleUsageController(VehicleUsageService service)
    : ControllerBase
{
    /// <summary>Every vehicle on this account, with its usage and the rules.</summary>
    [HttpGet("usage")]
    public async Task<IActionResult> List(CancellationToken ct) =>
        Result(await service.ListAsync(User.GetRequiredUserId(), ct));

    /// <summary>Moves one usage switch.</summary>
    [HttpPut("{vehicleId:guid}/usage")]
    public async Task<IActionResult> SetUsage(
        Guid vehicleId,
        VehicleUsageRequest request,
        CancellationToken ct) =>
        Result(await service.SetUsageAsync(
            User.GetRequiredUserId(), vehicleId, request, ct));

    /// <summary>The owner's own photograph of this vehicle.</summary>
    /// <remarks>
    /// One picture, replacing whatever was there, public the moment it is
    /// saved. Required before the vehicle can be put out on rent — a rental
    /// listing of names and prices is a listing nobody books from.
    /// </remarks>
    [HttpPost("{vehicleId:guid}/photo")]
    [RequestSizeLimit(12 * 1024 * 1024)]
    public async Task<IActionResult> UploadPhoto(
        Guid vehicleId,
        IFormFile file,
        CancellationToken ct) =>
        Result(await service.UploadPhotoAsync(
            User.GetRequiredUserId(), vehicleId, file, ct));

    /// <summary>Records the equipment carried, and rescores tour readiness.</summary>
    /// <remarks>
    /// The one thing about a verified vehicle a Driver may still change. The
    /// vehicle edit refuses once an Admin has verified it, which left the
    /// readiness bar with no door: a Driver could buy every item on the list and
    /// nothing would record it.
    /// </remarks>
    [HttpPut("{vehicleId:guid}/equipment")]
    public async Task<IActionResult> SetEquipment(
        Guid vehicleId,
        VehicleEquipmentRequest request,
        CancellationToken ct) =>
        Result(await service.SetEquipmentAsync(
            User.GetRequiredUserId(), vehicleId, request, ct));

    /// <summary>Saves the rent rates and terms. Does not switch renting on.</summary>
    [HttpPut("{vehicleId:guid}/rent-settings")]
    public async Task<IActionResult> SetRentSettings(
        Guid vehicleId,
        VehicleRentSettingsRequest request,
        CancellationToken ct) =>
        Result(await service.SetRentSettingsAsync(
            User.GetRequiredUserId(), vehicleId, request, ct));

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
