using Npgsql;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// What routes are actually agreed at, against what the platform suggests.
/// </summary>
/// <remarks>
/// This is the learning loop, and it is a median and two counts. There is no
/// model here and nothing to explain to a driver beyond the numbers on the
/// screen — which is the point. A fare a driver cannot have explained to him
/// is a fare he stops trusting, and the documented failure of the bidding
/// model in this market is drivers feeling pushed by something they could not
/// see.
///
/// Nothing here changes a price. It produces a row the admin can read and a
/// suggested percentage they can choose to apply, and that is the whole extent
/// of its authority.
///
/// The tell is <c>RequestsWithNoOffer</c>, not the median. A route where the
/// suggestion is close to the agreed fare but half the requests attract no
/// offer at all is priced below what a driver will get out of bed for — and
/// the median cannot show that, because the rides nobody accepted are not in
/// it.
/// </remarks>
public sealed class RateInsightsService(string connectionString)
{
    public async Task<IReadOnlyList<RouteInsightDto>> ListAsync(
        int days,
        int minimumSample,
        CancellationToken cancellationToken)
    {
        // Zones are resolved per request rather than stored on it, so that
        // changing a zone re-reads history through the new shape instead of
        // leaving months of rows labelled with a boundary that no longer
        // exists.
        const string sql = """
            WITH scoped AS (
                SELECT r.id, r.vehicle_category, r.created_at, r.quoted_recommended,
                       r.pickup_location, r.destination_location
                FROM udrive.ride_requests r
                WHERE r.created_at > now() - make_interval(days => @days)
            ),
            zoned AS (
                SELECT s.id, s.vehicle_category, s.created_at, s.quoted_recommended,
                       COALESCE(oz.name, 'Unzoned') AS origin_zone,
                       COALESCE(dz.name, 'Unzoned') AS destination_zone
                FROM scoped s
                LEFT JOIN LATERAL (
                    SELECT z.name
                    FROM udrive.pricing_zones z
                    JOIN udrive.pricing_zone_areas a ON a.zone_id = z.id
                    WHERE z.is_active
                      AND ST_DWithin(a.centre, s.pickup_location, a.radius_km * 1000.0)
                    ORDER BY z.priority DESC, a.radius_km ASC
                    LIMIT 1
                ) oz ON true
                LEFT JOIN LATERAL (
                    SELECT z.name
                    FROM udrive.pricing_zones z
                    JOIN udrive.pricing_zone_areas a ON a.zone_id = z.id
                    WHERE z.is_active
                      AND ST_DWithin(a.centre, s.destination_location, a.radius_km * 1000.0)
                    ORDER BY z.priority DESC, a.radius_km ASC
                    LIMIT 1
                ) dz ON true
            ),
            offers AS (
                SELECT ride_request_id, min(created_at) AS first_offer_at
                FROM udrive.driver_offers
                GROUP BY ride_request_id
            ),
            agreed AS (
                -- Grouped, because nothing stops a ride request having two
                -- surviving bookings and an ungrouped join would count that
                -- request twice in every column below.
                SELECT ride_request_id, max(total_amount) AS total_amount
                FROM udrive.bookings
                WHERE status = 'Completed'
                  AND ride_request_id IS NOT NULL
                GROUP BY ride_request_id
            )
            SELECT
                z.origin_zone,
                z.destination_zone,
                z.vehicle_category,
                count(*)::int AS requests,
                count(a.total_amount)::int AS completed,
                count(*) FILTER (WHERE o.ride_request_id IS NULL)::int AS no_offer,
                -- Cast back to numeric: percentile_cont only has a
                -- double-precision sort variant, so these arrive as float8 and
                -- reading them as decimal throws. Casting in SQL rather than in
                -- C# also keeps money off a binary float.
                percentile_cont(0.5) WITHIN GROUP (ORDER BY a.total_amount)::numeric AS median_agreed,
                percentile_cont(0.5) WITHIN GROUP (ORDER BY z.quoted_recommended)::numeric AS median_suggested,
                percentile_cont(0.5) WITHIN GROUP (
                    ORDER BY EXTRACT(EPOCH FROM (o.first_offer_at - z.created_at))) AS median_first_offer
            FROM zoned z
            LEFT JOIN offers o ON o.ride_request_id = z.id
            LEFT JOIN agreed a ON a.ride_request_id = z.id
            GROUP BY z.origin_zone, z.destination_zone, z.vehicle_category
            HAVING count(*) >= @minSample
            ORDER BY count(*) DESC, z.origin_zone, z.destination_zone;
            """;

        var list = new List<RouteInsightDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("days", days <= 0 ? 60 : Math.Min(days, 365));
        command.Parameters.AddWithValue("minSample", minimumSample <= 0 ? 20 : minimumSample);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var requests = reader.GetInt32(3);
            var completed = reader.GetInt32(4);
            var noOffer = reader.GetInt32(5);
            decimal? medianAgreed = reader.IsDBNull(6) ? null : reader.GetDecimal(6);
            decimal? medianSuggested = reader.IsDBNull(7) ? null : reader.GetDecimal(7);
            double? medianFirstOffer = reader.IsDBNull(8) ? null : reader.GetDouble(8);

            list.Add(new RouteInsightDto(
                reader.GetString(0),
                reader.GetString(1),
                reader.GetString(2),
                completed,
                noOffer,
                requests == 0 ? 0m : Math.Round((decimal)noOffer * 100m / requests, 1),
                medianAgreed is null ? null : Math.Round(medianAgreed.Value, 0),
                medianSuggested is null ? null : Math.Round(medianSuggested.Value, 0),
                medianFirstOffer is null ? null : Math.Round((decimal)medianFirstOffer.Value, 0),
                SuggestedChange(medianAgreed, medianSuggested, completed)));
        }

        return list;
    }

    /// <summary>
    /// How far the suggestion is from the number drivers actually accept.
    /// </summary>
    /// <remarks>
    /// Null until the route has enough completed rides to mean anything —
    /// three accepted fares is an anecdote, and a suggestion built on one is
    /// worse than none because it looks like evidence.
    ///
    /// Capped at a quarter in either direction. This figure is read by a
    /// person who clicks Apply, and a row suggesting a rate be tripled is
    /// either a data problem or a route so unusual that it wants a human
    /// looking at it rather than a button.
    /// </remarks>
    private static decimal? SuggestedChange(
        decimal? medianAgreed, decimal? medianSuggested, int completed)
    {
        const int minimumCompleted = 10;

        if (completed < minimumCompleted) return null;
        if (medianAgreed is null or <= 0m) return null;
        if (medianSuggested is null or <= 0m) return null;

        var change = (medianAgreed.Value - medianSuggested.Value) / medianSuggested.Value * 100m;
        return Math.Round(Math.Clamp(change, -25m, 25m), 1);
    }
}
