using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Route("api/v1/catalog")]
public sealed class CatalogController(CatalogService catalogService, LocalFileStorageService fileStorage, MarketplacePricingService pricingService) : ControllerBase
{
    [HttpGet("destinations")]
    public async Task<ActionResult<ApiResponse<IReadOnlyList<DestinationDto>>>> GetDestinations(
        [FromQuery] string language = "en",
        CancellationToken cancellationToken = default)
    {
        var data = await catalogService.GetDestinationsAsync(language, cancellationToken);
        return Ok(ApiResponse<IReadOnlyList<DestinationDto>>.Ok(data));
    }

    [HttpGet("service-rates")]
    public async Task<ActionResult<ApiResponse<IReadOnlyList<ServiceVehicleRateDto>>>> GetServiceRates(
        [FromQuery] string serviceType = "City",
        CancellationToken cancellationToken = default)
    {
        var data = await pricingService.GetRatesAsync(serviceType, cancellationToken);
        return Ok(ApiResponse<IReadOnlyList<ServiceVehicleRateDto>>.Ok(data));
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
