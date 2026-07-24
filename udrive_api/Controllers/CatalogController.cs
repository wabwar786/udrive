using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

[ApiController]
[Route("api/v1/catalog")]
public sealed class CatalogController(CatalogService catalogService) : ControllerBase
{
    [HttpGet("destinations")]
    public async Task<ActionResult<ApiResponse<IReadOnlyList<DestinationDto>>>> GetDestinations(
        [FromQuery] string language = "en",
        CancellationToken cancellationToken = default)
    {
        var data = await catalogService.GetDestinationsAsync(language, cancellationToken);
        return Ok(ApiResponse<IReadOnlyList<DestinationDto>>.Ok(data));
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
