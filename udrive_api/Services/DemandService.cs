using System.Collections.Concurrent;
using Npgsql;

namespace UDrive.Api.Services;

/// <summary>
/// How short of drivers a zone is right now, as a fare multiplier.
/// </summary>
/// <remarks>
/// Requests per online driver, turned into a multiplier by a ladder of steps
/// the admin sets. Steps rather than a continuous curve for two reasons: a
/// multiplier that slides is one nobody can predict, and a fare that changes
/// every time the screen is refreshed reads as the app making the number up.
///
/// The sample floors do more work than the thresholds. On a quiet evening a
/// zone will have two requests and one driver, which is a ratio of 2.0 and
/// means nothing whatsoever. Below <c>pricing.surge.min_requests</c> and
/// <c>pricing.surge.min_drivers</c> the answer is 1.0 — no shortage claimed,
/// because none has been measured.
///
/// The whole thing is off until <c>pricing.surge.enabled</c> is switched on,
/// which should not happen until enough drivers keep the app open for the
/// ratio to describe anything real.
/// </remarks>
public sealed class DemandService(string connectionString)
{
    private sealed record Reading(int OpenRequests, int OnlineDrivers, decimal Ratio, decimal Multiplier, DateTimeOffset At);

    private static readonly TimeSpan CacheFor = TimeSpan.FromSeconds(60);
    private readonly ConcurrentDictionary<Guid, Reading> _cache = new();

    /// <summary>Statuses that mean a request is still looking for a driver.</summary>
    private static readonly string[] OpenStatuses =
        ["Open", "SearchingDrivers", "ReceivingOffers"];

    public async Task<(decimal Multiplier, string? Reason)> MultiplierAsync(
        NpgsqlConnection connection,
        Guid? zoneId,
        bool zoneAllowsSurge,
        IReadOnlyDictionary<string, string> settings,
        CancellationToken cancellationToken)
    {
        if (zoneId is null || !zoneAllowsSurge)
        {
            return (1.0m, null);
        }

        if (!PricingSettingsService.Bool(settings, "pricing.surge.enabled", false))
        {
            return (1.0m, null);
        }

        var steps = PricingSettingsService.SurgeSteps(settings);
        if (steps.Count == 0)
        {
            return (1.0m, null);
        }

        if (_cache.TryGetValue(zoneId.Value, out var cached)
            && DateTimeOffset.UtcNow - cached.At < CacheFor)
        {
            return (cached.Multiplier, Describe(cached));
        }

        var requestWindow = PricingSettingsService.Int(settings, "pricing.surge.request_window_minutes", 15);
        var driverWindow = PricingSettingsService.Int(settings, "pricing.surge.driver_window_minutes", 5);
        var minRequests = PricingSettingsService.Int(settings, "pricing.surge.min_requests", 5);
        var minDrivers = PricingSettingsService.Int(settings, "pricing.surge.min_drivers", 3);

        // EXISTS rather than a join: a zone has several circles and a join
        // would count a request once per circle that covers it.
        const string sql = """
            SELECT
              (SELECT count(*) FROM udrive.ride_requests r
                WHERE r.created_at > now() - make_interval(mins => @reqWindow)
                  AND r.status = ANY(@openStatuses)
                  AND EXISTS (
                      SELECT 1 FROM udrive.pricing_zone_areas a
                      WHERE a.zone_id = @zone
                        AND ST_DWithin(r.pickup_location, a.centre, a.radius_km * 1000.0)))::int,
              (SELECT count(*) FROM udrive.driver_presence_locations d
                WHERE d.server_timestamp > now() - make_interval(mins => @drvWindow)
                  AND EXISTS (
                      SELECT 1 FROM udrive.pricing_zone_areas a
                      WHERE a.zone_id = @zone
                        AND ST_DWithin(d.location, a.centre, a.radius_km * 1000.0)))::int;
            """;

        int openRequests;
        int onlineDrivers;
        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("zone", zoneId.Value);
            command.Parameters.AddWithValue("reqWindow", requestWindow);
            command.Parameters.AddWithValue("drvWindow", driverWindow);
            command.Parameters.AddWithValue("openStatuses", OpenStatuses);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return (1.0m, null);
            }

            openRequests = reader.GetInt32(0);
            onlineDrivers = reader.GetInt32(1);
        }

        decimal ratio = 0m;
        var multiplier = 1.0m;

        // onlineDrivers > 0 first, and the sample floors are themselves floored
        // at one. An admin setting min_drivers to zero is a plausible way to
        // try turning the sample guard off, and it would otherwise divide by
        // the number of drivers who are not there.
        if (onlineDrivers > 0
            && openRequests >= Math.Max(minRequests, 1)
            && onlineDrivers >= Math.Max(minDrivers, 1))
        {
            ratio = (decimal)openRequests / onlineDrivers;
            foreach (var step in steps)
            {
                if (ratio >= step.Ratio)
                {
                    multiplier = step.Multiplier;
                }
            }

            // A hand-edited step is still a number in a fare. The snapshot
            // column is numeric(5,3) and the fare is real money; neither wants
            // a multiplier of forty.
            multiplier = Math.Clamp(multiplier, 1.0m, 3.0m);
            if (ratio > 99.999m) ratio = 99.999m;
        }

        var reading = new Reading(openRequests, onlineDrivers, ratio, multiplier, DateTimeOffset.UtcNow);
        _cache[zoneId.Value] = reading;

        // Best effort. A snapshot is history, and failing to write history is
        // not a reason to fail to quote a fare.
        try
        {
            await using var snapshot = new NpgsqlCommand("""
                INSERT INTO udrive.zone_demand_snapshots
                    (zone_id, captured_at, open_requests, online_drivers, ratio, multiplier)
                VALUES (@zone, date_trunc('minute', now()), @open, @drivers, @ratio, @multiplier)
                ON CONFLICT (zone_id, captured_at) DO NOTHING;
                """, connection);
            snapshot.Parameters.AddWithValue("zone", zoneId.Value);
            snapshot.Parameters.AddWithValue("open", openRequests);
            snapshot.Parameters.AddWithValue("drivers", onlineDrivers);
            snapshot.Parameters.AddWithValue("ratio", ratio);
            snapshot.Parameters.AddWithValue("multiplier", multiplier);
            await snapshot.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (NpgsqlException)
        {
            // Swallowed deliberately; see above.
        }

        return (multiplier, Describe(reading));
    }

    private static string? Describe(Reading reading) =>
        reading.Multiplier <= 1.0m
            ? null
            : $"{reading.OpenRequests} requests for {reading.OnlineDrivers} drivers nearby";
}
