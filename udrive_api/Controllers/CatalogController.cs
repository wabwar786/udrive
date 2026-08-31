using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Route("api/v1/catalog")]
public sealed class CatalogController(CatalogService catalogService, LocalFileStorageService fileStorage, MarketplacePricingService pricingService, TourRatesService tourRatesService, SeatFaresService seatFaresService) : ControllerBase
{
    /// <summary>The fixed per-seat fare for a route, if it has one.</summary>
    /// <remarks>
    /// A Coster running per seat charges a known fare for a known route, not a
    /// figure worked out from the pickup pin. When this returns a fare it is
    /// the fare: the app shows it fixed and the customer does not bid.
    ///
    /// Returns no data when the route is not listed, which is the normal case
    /// and means the app falls back to per-kilometre pricing.
    /// </remarks>
    [HttpGet("seat-fare")]
    public async Task<IActionResult> SeatFare(
        [FromQuery] double fromLat,
        [FromQuery] double fromLng,
        [FromQuery] double toLat,
        [FromQuery] double toLng,
        [FromQuery] string category = "Coster",
        CancellationToken cancellationToken = default)
    {
        var result = await seatFaresService.ResolveAsync(
            category, fromLat, fromLng, toLat, toLng, cancellationToken);
        return result.Success
            ? Ok(ApiResponse<SeatFareQuoteDto?>.Ok(result.Data))
            : StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
            });
    }

    /// <summary>What tour vehicles nearby are asking per day, by category.</summary>
    /// <remarks>
    /// Tour is priced by the Driver, not by the admin's per-kilometre rules, so
    /// there is no single figure to quote. This returns the range Drivers have
    /// actually published, which is what a Customer needs before naming an
    /// offer of their own.
    /// </remarks>
    [HttpGet("tour-rates")]
    public async Task<IActionResult> TourRateGuide(
        [FromQuery] double? lat = null,
        [FromQuery] double? lng = null,
        [FromQuery] double radiusKm = 150,
        CancellationToken cancellationToken = default)
    {
        var result = await tourRatesService.GuideAsync(
            lat, lng, radiusKm, cancellationToken);
        return result.Success
            ? Ok(ApiResponse<IReadOnlyList<TourRateGuideDto>>.Ok(result.Data!))
            : StatusCode(result.StatusCode, new
            {
                success = false,
                error = result.ErrorCode,
                message = result.Message,
            });
    }

    [HttpGet("destinations")]
    public async Task<ActionResult<ApiResponse<IReadOnlyList<DestinationDto>>>> GetDestinations(
        [FromQuery] string language = "en",
        CancellationToken cancellationToken = default)
    {
        var data = await catalogService.GetDestinationsAsync(language, cancellationToken);
        return Ok(ApiResponse<IReadOnlyList<DestinationDto>>.Ok(data));
    }

    /// <summary>Rates for pricing a trip.</summary>
    /// <remarks>
    /// <paramref name="lat"/> and <paramref name="lng"/> are the pickup. They
    /// are optional so an older app build still gets the flat rates, but with
    /// them the admin's area and day rules apply.
    /// </remarks>
    [HttpGet("service-rates")]
    public async Task<ActionResult<ApiResponse<IReadOnlyList<ServiceVehicleRateDto>>>> GetServiceRates(
        [FromQuery] string serviceType = "City",
        [FromQuery] double? lat = null,
        [FromQuery] double? lng = null,
        CancellationToken cancellationToken = default)
    {
        var data = await pricingService.GetRatesAsync(
            serviceType, cancellationToken, lat, lng);
        return Ok(ApiResponse<IReadOnlyList<ServiceVehicleRateDto>>.Ok(data));
    }

    /// <summary>
    /// Vehicles online near a point, for the customer home-screen map.
    /// </summary>
    /// <remarks>
    /// Unauthenticated on purpose — the home map loads before a customer signs
    /// in. The response carries no driver identity and coordinates are rounded,
    /// so there is nothing here worth harvesting.
    /// </remarks>
    [HttpGet("vehicles/nearby")]
    [ResponseCache(Duration = 5, Location = ResponseCacheLocation.Any)]
    public async Task<ActionResult<object>> GetNearbyVehicles(
        [FromQuery] double lat,
        [FromQuery] double lng,
        [FromQuery] double radiusKm = 5,
        [FromQuery] string? category = null,
        [FromQuery] bool tourOnly = false,
        [FromQuery] int limit = 40,
        CancellationToken cancellationToken = default)
    {
        if (lat is < -90 or > 90 || lng is < -180 or > 180)
        {
            return BadRequest(new
            {
                success = false,
                code = "invalid_coordinates",
                message = "Latitude and longitude are out of range."
            });
        }

        var clampedRadius = Math.Clamp(radiusKm, 0.5, 25);
        var items = await pricingService.GetNearbyVehiclesAsync(
            lat,
            lng,
            clampedRadius,
            category,
            tourOnly,
            Math.Clamp(limit, 1, 100),
            cancellationToken);

        return Ok(ApiResponse<object>.Ok(new
        {
            items,
            total = items.Count,
            radiusKm = clampedRadius
        }));
    }

    [HttpGet("vehicles")]
    public async Task<ActionResult<ApiResponse<IReadOnlyList<PublicVehicleDto>>>> GetVehicles(
        [FromQuery] string serviceType = "City",
        [FromQuery] string? query = null,
        [FromQuery] int limit = 80,
        CancellationToken cancellationToken = default)
    {
        var data = await pricingService.GetAvailableVehiclesAsync(
            serviceType,
            query,
            Math.Clamp(limit, 1, 150),
            cancellationToken);
        return Ok(ApiResponse<IReadOnlyList<PublicVehicleDto>>.Ok(data));
    }


    [HttpGet("ambulance-cities")]
    public async Task<ActionResult<ApiResponse<IReadOnlyList<string>>>> GetAmbulanceCities(CancellationToken cancellationToken)
    {
        var data = await pricingService.GetAmbulanceCitiesAsync(cancellationToken);
        return Ok(ApiResponse<IReadOnlyList<string>>.Ok(data));
    }

    [HttpGet("ambulances")]
    public async Task<ActionResult<ApiResponse<IReadOnlyList<AmbulanceServiceDto>>>> GetAmbulances(
        [FromQuery] string? city = null, CancellationToken cancellationToken = default)
    {
        var data = await pricingService.GetAmbulancesAsync(city, cancellationToken);
        return Ok(ApiResponse<IReadOnlyList<AmbulanceServiceDto>>.Ok(data));
    }

    [HttpGet("destination-images/{owner}/{fileName}")]
    [ResponseCache(Duration = 3600, Location = ResponseCacheLocation.Client)]
    public IActionResult DestinationImage(string owner, string fileName)
    {
        var file = fileStorage.ResolveProtectedFile("destinations", owner, fileName);
        if (file is null) return NotFound();
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        Response.Headers["Cross-Origin-Resource-Policy"] = "cross-origin";
        return new PhysicalFileResult(file.Path, file.ContentType) { EnableRangeProcessing = true };
    }

    [HttpGet("routes")]
    public async Task<ActionResult<ApiResponse<IReadOnlyList<RouteDto>>>> GetRoutes(
        CancellationToken cancellationToken)
    {
        var data = await catalogService.GetRoutesAsync(cancellationToken);
        return Ok(ApiResponse<IReadOnlyList<RouteDto>>.Ok(data));
    }

    [HttpGet("packages")]
    public async Task<ActionResult<ApiResponse<IReadOnlyList<PackageDto>>>> GetPackages(
        CancellationToken cancellationToken)
    {
        var data = await catalogService.GetPackagesAsync(cancellationToken);
        return Ok(ApiResponse<IReadOnlyList<PackageDto>>.Ok(data));
    }
}
