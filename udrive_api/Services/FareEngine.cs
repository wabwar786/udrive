using Microsoft.AspNetCore.Http;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The one place a UDrive fare is worked out.
/// </summary>
/// <remarks>
/// It used to be worked out in Dart, in two screens, differently — one with a
/// per-minute term and a floor, one with neither — while the API stored
/// whatever number arrived. Every minimum an admin set was advisory, and a
/// PKR 1 ride request was valid.
///
/// The order of operations is the whole design, so it is written out here
/// once:
///
///   distance cost = per-km × fuel index × km
///   time cost     = per-minute × minutes
///   meter         = base fare + distance cost + time cost
///   terrain       = meter × zone difficulty
///   empty return  = distance cost × zone return share × zone difficulty
///   subtotal      = terrain + empty return
///   floor         = minimum fare × fuel index × zone difficulty
///   charged       = max(subtotal, floor)
///
/// and then the band:
///
///   recommended   = charged × surge
///   minimum       = charged × (1 + (surge − 1) × minimum share)
///   maximum       = recommended × ceiling
///
/// Two things about that band. The minimum rises more slowly than the
/// suggestion, so a customer in a busy area is guided upward rather than
/// forced upward — which is the difference between this and Uber's surge, and
/// the right shape for a platform where the customer names the price. And at
/// surge 1.0 the minimum and the recommendation are the same number: there is
/// one figure on screen and the only direction to move it is up, which is what
/// inDrive does and is much easier to explain than two.
///
/// Every multiplier defaults to the value that reproduces the old arithmetic.
/// Zones ship inactive, the fuel baseline ships at zero and surge ships off,
/// so the day this lands every fare is what it was the day before.
/// </remarks>
public sealed class FareEngine(
    string connectionString,
    MarketplacePricingService marketplacePricing,
    SeatFaresService seatFares,
    PricingZoneService zoneService,
    DemandService demandService,
    FuelPriceService fuelPriceService,
    PricingSettingsService settingsService,
    QuoteTokenService quoteTokens)
{
    public async Task<ServiceResult<FareQuoteDto>> QuoteAsync(
        Guid customerUserId,
        FareQuoteRequest request,
        CancellationToken cancellationToken)
    {
        var settings = await settingsService.GetAsync(cancellationToken);

        var implausible = CheckDistance(request, settings);
        if (implausible is not null) return implausible;

        var rates = await marketplacePricing.GetRatesAsync(
            request.ServiceType,
            cancellationToken,
            request.PickupLatitude,
            request.PickupLongitude);

        var rate = rates.FirstOrDefault(entry => string.Equals(
            entry.VehicleCategory, request.VehicleCategory, StringComparison.OrdinalIgnoreCase));

        if (rate is null)
        {
            // Deliberately a refusal rather than a guess. The client used to
            // fall back to figures compiled into the app, which is how a
            // vehicle could be sold at a price no admin had ever set.
            return ServiceResult<FareQuoteDto>.Fail(
                StatusCodes.Status422UnprocessableEntity,
                "rate_not_configured",
                $"No rate is set for {request.VehicleCategory} on {request.ServiceType}. "
                + "Add one under Pricing before this vehicle can be booked.");
        }

        var perSeat = string.Equals(request.BookingType, "PerSeat", StringComparison.OrdinalIgnoreCase);

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var originZone = await zoneService.ResolveAsync(
            connection, request.PickupLatitude, request.PickupLongitude, cancellationToken);
        var destinationZone = await zoneService.ResolveAsync(
            connection, request.DestinationLatitude, request.DestinationLongitude, cancellationToken);

        var fuelPrices = await fuelPriceService.CurrentAsync(cancellationToken);
        var fuelFactor = FuelPriceService.Factor(fuelPrices, settings, rate.FuelType);
        fuelPrices.TryGetValue(rate.FuelType, out var fuelPrice);

        var (surge, surgeReason) = await demandService.MultiplierAsync(
            connection,
            originZone.Id,
            originZone.SurgeEnabled && destinationZone.SurgeEnabled,
            settings,
            cancellationToken);

        // Clamped, not trusted. These come from a settings table an admin can
        // type into, and Math.Ceiling(value / step) with a step of zero or a
        // ceiling of a million is an OverflowException on the one endpoint that
        // must never fail — a customer who cannot be quoted cannot book.
        var step = Math.Clamp(
            PricingSettingsService.Decimal(settings, "pricing.rounding.step", 5m), 0.01m, 1000m);

        // The trip's difficulty is the harder of the two ends. A run from the
        // city up to Kel is a mountain trip whichever way round it is driven.
        var zoneFactor = Math.Max(originZone.DifficultyFactor, destinationZone.DifficultyFactor);

        // Only the destination's return share counts. Whether the driver gets
        // another fare afterwards is a question about where he ends up.
        var returnShare = destinationZone.ReturnShare;

        var distanceKm = (decimal)request.DistanceKm;
        var minutes = (decimal)request.DurationMinutes;

        var perKmEffective = rate.PerKmRate * fuelFactor;
        var distanceCost = perKmEffective * distanceKm;
        var timeCost = rate.PerMinuteRate * minutes;
        var meter = rate.BaseFare + distanceCost + timeCost;
        var terrain = meter * zoneFactor;
        var returnCost = distanceCost * returnShare * zoneFactor;
        var subtotal = terrain + returnCost;

        decimal charged;
        decimal floor;
        decimal? perSeatFare = null;
        var capacity = rate.SeatCapacity > 0 ? rate.SeatCapacity : 4;
        var negotiable = true;
        string? fixedRouteLabel = null;

        if (perSeat)
        {
            // A published route fare wins outright. The seat_fares table has
            // described itself as non-negotiable since it was added; until the
            // server checked it, that was a claim the client could ignore.
            var fixedFare = await seatFares.ResolveAsync(
                request.VehicleCategory,
                request.PickupLatitude,
                request.PickupLongitude,
                request.DestinationLatitude,
                request.DestinationLongitude,
                cancellationToken);

            if (fixedFare is { Success: true, Data: not null } && fixedFare.Data.PerSeatFare > 0)
            {
                perSeatFare = fixedFare.Data.PerSeatFare;
                charged = perSeatFare.Value * request.Seats;
                floor = charged;
                negotiable = false;
                surge = 1.0m;
                surgeReason = null;
                fixedRouteLabel = fixedFare.Data.Reversed
                    ? $"{fixedFare.Data.DestinationLabel} → {fixedFare.Data.OriginLabel}"
                    : $"{fixedFare.Data.OriginLabel} → {fixedFare.Data.DestinationLabel}";
            }
            else
            {
                var margin = PricingSettingsService.Decimal(settings, "pricing.per_seat.margin", 1.35m);
                var seatFloor = rate.PerSeatRate * fuelFactor * zoneFactor;
                var unit = Math.Max(subtotal / capacity * margin, seatFloor);
                perSeatFare = RoundUp(unit, step);
                charged = perSeatFare.Value * request.Seats;
                floor = seatFloor * request.Seats;
            }
        }
        else
        {
            floor = rate.WholeVehicleRate * fuelFactor * zoneFactor;
            charged = Math.Max(subtotal, floor);
        }

        if (charged <= 0m)
        {
            return ServiceResult<FareQuoteDto>.Fail(
                StatusCodes.Status422UnprocessableEntity,
                "rate_not_configured",
                $"The rate for {request.VehicleCategory} prices this trip at zero. "
                + "Check the per-kilometre rate and minimum fare under Pricing.");
        }

        // Rounded up at every step, never to nearest. A fare rounded down is a
        // fare that can land below the floor it was just clamped to, which is
        // exactly the bug that let the app offer less than its own stated
        // minimum.
        var chargedRounded = RoundUp(charged, step);
        var minimumShare = Math.Clamp(
            PricingSettingsService.Decimal(settings, "pricing.surge.minimum_share", 0.5m), 0m, 1m);
        var ceiling = Math.Clamp(
            PricingSettingsService.Decimal(settings, "pricing.offer.ceiling_multiplier", 3m), 1m, 10m);

        var recommended = RoundUp(chargedRounded * surge, step);
        var minimum = negotiable
            ? RoundUp(chargedRounded * (1m + (surge - 1m) * minimumShare), step)
            : chargedRounded;
        var maximum = negotiable ? RoundUp(recommended * ceiling, step) : chargedRounded;

        // Rounding is monotonic, so minimum <= recommended holds by
        // construction — but a hand-edited minimum_share above 1 would break
        // that, and a band whose floor is above its suggestion is unusable.
        if (minimum > recommended) minimum = recommended;
        if (maximum < recommended) maximum = recommended;

        // An hour is already generous for a number the customer is looking at.
        // Unclamped, a mistyped 100000 would keep quotes spendable for seventy
        // days while the rate card moved underneath them.
        var ttlMinutes = Math.Clamp(
            PricingSettingsService.Int(settings, "pricing.quote.ttl_minutes", 15), 1, 60);
        var now = DateTimeOffset.UtcNow;
        var expiresAt = now.AddMinutes(ttlMinutes);
        var quoteId = Guid.NewGuid();

        var token = quoteTokens.Issue(new QuoteTokenService.Payload(
            quoteId,
            customerUserId,
            request.ServiceType,
            request.VehicleCategory,
            request.BookingType,
            request.Seats,
            request.PickupLatitude,
            request.PickupLongitude,
            request.DestinationLatitude,
            request.DestinationLongitude,
            request.DistanceKm,
            minimum,
            recommended,
            maximum,
            surge,
            now.ToUnixTimeSeconds(),
            expiresAt.ToUnixTimeSeconds()));

        return ServiceResult<FareQuoteDto>.Ok(new FareQuoteDto(
            quoteId,
            token,
            expiresAt,
            minimum,
            recommended,
            maximum,
            surge,
            negotiable,
            fixedRouteLabel,
            rate.Currency,
            new FareBreakdownDto(
                rate.BaseFare,
                rate.PerKmRate,
                rate.PerMinuteRate,
                request.DistanceKm,
                request.DurationMinutes,
                Math.Round(distanceCost, 2),
                Math.Round(timeCost, 2),
                Math.Round(fuelFactor, 4),
                rate.FuelType,
                fuelPrice > 0 ? fuelPrice : null,
                zoneFactor,
                originZone.Name,
                destinationZone.Name,
                returnShare,
                Math.Round(returnCost, 2),
                Math.Round(meter, 2),
                Math.Round(floor, 2),
                surge,
                surgeReason,
                perSeat ? capacity : null,
                perSeatFare)));
    }

    /// <summary>
    /// Refuses a distance that cannot belong to these two points.
    /// </summary>
    /// <remarks>
    /// The distance is supplied by the client, and the floor is proportional
    /// to it, so a client that claims half a kilometre for a hundred-kilometre
    /// trip would be handed a floor it could then legally offer. The straight
    /// line between the two coordinates costs nothing to compute and bounds
    /// the claim from both sides.
    ///
    /// The upper bound is loose because mountain roads are: the run into Leepa
    /// crosses a pass and is several times its own straight line. The lower
    /// bound is the one that matters, and it is close to exact — no road is
    /// shorter than the line.
    /// </remarks>
    private static ServiceResult<FareQuoteDto>? CheckDistance(
        FareQuoteRequest request,
        IReadOnlyDictionary<string, string> settings)
    {
        var straightKm = QuoteTokenService.DistanceMetres(
            request.PickupLatitude, request.PickupLongitude,
            request.DestinationLatitude, request.DestinationLongitude) / 1000.0;

        // Under half a kilometre the phone's own error is the same size as the
        // trip, so the lower bound means nothing — but the upper one still
        // does, and skipping it let a sub-500 m trip claim any distance at all
        // and so name its own ceiling.
        if (straightKm >= 0.5 && request.DistanceKm < straightKm * 0.9)
        {
            return ServiceResult<FareQuoteDto>.Fail(
                StatusCodes.Status400BadRequest,
                "distance_implausible",
                "The route is shorter than the straight line between those points. "
                + "Search for the destination again.");
        }

        var maxRatio = (double)PricingSettingsService.Decimal(
            settings, "pricing.distance.max_detour_ratio", 4.0m);

        // A floor under the comparison distance, so a trip too short to have a
        // meaningful straight line still has a ceiling on what it may claim.
        if (request.DistanceKm > Math.Max(straightKm, 0.5) * maxRatio)
        {
            return ServiceResult<FareQuoteDto>.Fail(
                StatusCodes.Status400BadRequest,
                "distance_implausible",
                "The route is far longer than the distance between those points. "
                + "Search for the destination again.");
        }

        return null;
    }

    public static decimal RoundUp(decimal value, decimal step) =>
        step <= 0m ? value : Math.Ceiling(value / step) * step;
}
