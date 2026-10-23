using Microsoft.Extensions.Caching.Memory;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>Rent-a-car list for the public website.</summary>
/// <remarks>
/// Reuses the app's rental search (same approval, photo and hold rules), then
/// trims each row for strangers: no registration number, no colour, only the
/// owner's first name, no demo vehicles, and only our own image routes.
/// Booking itself stays in the app.
/// </remarks>
public sealed class WebRentCarsService(RentalService rentals, IMemoryCache cache)
{
    private static readonly string[] Modes = ["", "WithDriver", "SelfDrive"];
    private static readonly string[] Categories = ["", "car", "jeep", "hiace", "coster"];

    public async Task<ServiceResult<IReadOnlyList<WebRentCarDto>>> ListAsync(string? mode, string? category, CancellationToken ct)
    {
        var m = Modes.FirstOrDefault(x => string.Equals(x, (mode ?? "").Trim(), StringComparison.OrdinalIgnoreCase)) ?? "";
        var c = Categories.FirstOrDefault(x => string.Equals(x, (category ?? "").Trim(), StringComparison.OrdinalIgnoreCase)) ?? "";
        var key = $"web:rent:{m}:{c}";
        if (cache.TryGetValue(key, out IReadOnlyList<WebRentCarDto>? cached) && cached is not null)
        {
            return ServiceResult<IReadOnlyList<WebRentCarDto>>.Ok(cached);
        }

        var result = await rentals.SearchAsync(null, null, m, c, ct);
        if (!result.Success || result.Data is null)
        {
            return ServiceResult<IReadOnlyList<WebRentCarDto>>.Fail(result.StatusCode, result.ErrorCode ?? "rent_failed", result.Message ?? "Abhi list nahi mili.");
        }

        IReadOnlyList<WebRentCarDto> list = result.Data
            .Where(v => !v.IsDemo && WebsiteService.SafeImage(v.PhotoUrl ?? ""))
            .Take(30)
            .Select(v => new WebRentCarDto(
                v.VehicleId,
                WebsiteService.Clean(v.Name, 80) ?? "Vehicle",
                v.Category,
                v.Year,
                v.PassengerCapacity,
                v.PhotoUrl,
                v.WithDriverDaily,
                v.SelfDriveDaily,
                v.SecurityDeposit,
                v.MinimumDays,
                v.KmPerDay,
                v.FuelIncluded,
                WebsiteService.Clean(v.PickupPoint, 120),
                WebsiteService.FirstName(v.OwnerName),
                Math.Round(v.OwnerRating, 1),
                v.HasAirConditioning,
                v.IsFourByFour))
            .ToList();

        cache.Set(key, list, TimeSpan.FromSeconds(60));
        return ServiceResult<IReadOnlyList<WebRentCarDto>>.Ok(list);
    }
}
