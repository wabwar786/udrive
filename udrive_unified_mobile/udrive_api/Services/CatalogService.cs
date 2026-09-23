using Microsoft.EntityFrameworkCore;
using UDrive.Api.Infrastructure.Persistence;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

public sealed class CatalogService(UDriveDbContext db)
{
    public async Task<List<DestinationDto>> GetDestinationsAsync(
        string language,
        CancellationToken cancellationToken)
    {
        var urdu = string.Equals(
            language,
            "ur",
            StringComparison.OrdinalIgnoreCase);

        /*
         * Destination.Location is stored as geography(point, 4326).
         *
         * Accessing Location.X / Location.Y inside the EF SQL projection
         * translates to PostGIS ST_X / ST_Y. Those functions accept geometry,
         * not geography, and cause the destinations endpoint to return HTTP 500.
         *
         * Load the Point value first, then extract X/Y in memory.
         */
        var rows = await db.Destinations
            .AsNoTracking()
            .Where(x => x.IsActive)
            .OrderByDescending(x => x.FamilySuitabilityScore)
            .Select(x => new
            {
                x.Id,
                x.Slug,
                x.NameEn,
                x.NameUr,
                x.SummaryEn,
                x.SummaryUr,
                x.Location,
                x.District,
                x.BestSeason,
                x.RecommendedVehicle,
                x.NetworkStatus,
                x.FamilySuitabilityScore,
                x.RouteSafetyScore,
                x.CoverImageUrl
            })
            .ToListAsync(cancellationToken);

        return rows
            .Select(x => new DestinationDto(
                x.Id,
                x.Slug,
                urdu ? x.NameUr : x.NameEn,
                urdu ? x.SummaryUr : x.SummaryEn,
                x.Location.Y,
                x.Location.X,
                x.District,
                x.BestSeason,
                x.RecommendedVehicle,
                x.NetworkStatus,
                x.FamilySuitabilityScore,
                x.RouteSafetyScore,
                x.CoverImageUrl))
            .ToList();
    }

    public Task<List<RouteDto>> GetRoutesAsync(
        CancellationToken cancellationToken) =>
        db.Routes
            .AsNoTracking()
            .Where(x => x.IsActive)
            .OrderBy(x => x.Name)
            .Select(x => new RouteDto(
                x.Id,
                x.Name,
                x.DistanceKm,
                x.EstimatedMinutes,
                x.RecommendedVehicle,
                x.FourByFourRequired,
                x.DaylightOnly,
                x.SafetyScore))
            .ToListAsync(cancellationToken);

    public Task<List<PackageDto>> GetPackagesAsync(
        CancellationToken cancellationToken) =>
        (from package in db.TourPackages.AsNoTracking()
         join destination in db.Destinations.AsNoTracking()
             on package.DestinationId equals destination.Id
         where package.Status == Domain.Enums.PackageStatus.Active
               && package.AvailableSeats > 0
         orderby package.DepartureAt
         select new PackageDto(
             package.Id,
             package.Title,
             package.StartingCity,
             destination.NameEn,
             package.DepartureAt,
             package.AvailableSeats,
             package.PricePerSeat,
             package.WholeVehiclePrice,
             package.FamilyOnly,
             package.WomenOnly,
             package.Status.ToString(),
             package.CoverImageUrl))
        .ToListAsync(cancellationToken);
}
