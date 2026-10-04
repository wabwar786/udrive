using Npgsql;
using UDrive.Api.Common;

namespace UDrive.Api.Services;

/// <summary>One way of getting to a place, from the routes catalogue.</summary>
public sealed record ExploreRouteDto(
    string Name,
    string? FromName,
    decimal DistanceKm,
    int EstimatedMinutes,
    string RecommendedVehicle,
    bool FourByFourRequired,
    bool DaylightOnly,
    int SafetyScore);

/// <summary>A place close to the one being looked at.</summary>
public sealed record ExploreNearbyDto(
    Guid Id,
    string Name,
    string District,
    double DistanceKm,
    string? CoverImageUrl);

/// <summary>
/// Everything the Explore place screen shows beyond the destination row
/// itself: its Urdu name, how to get there, and what UDrive can sell for it.
/// </summary>
public sealed record ExploreDestinationDto(
    Guid Id,
    string NameEn,
    string NameUr,
    ExploreRouteDto? Route,
    int ToursCount,
    DateTimeOffset? NextDeparture,
    int HotelsNearby,
    IReadOnlyList<ExploreNearbyDto> Nearby);

/// <summary>
/// The extra facts behind one Explore place, in one call.
/// </summary>
/// <remarks>
/// Counts only — the screens that sell tours and rooms load their own lists
/// when the customer taps through. "Hotels nearby" is approved, active hotels
/// within <see cref="HotelRadiusKm"/> of the place; "nearby places" are other
/// active destinations within <see cref="NearbyRadiusKm"/>.
/// </remarks>
public sealed class ExploreService(string connectionString)
{
    public const double HotelRadiusKm = 30;
    public const double NearbyRadiusKm = 80;

    public async Task<ServiceResult<ExploreDestinationDto>> GetAsync(Guid id, CancellationToken ct)
    {
        await using var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);

        string nameEn, nameUr;
        await using (var cmd = c.CreateCommand())
        {
            cmd.CommandText = "SELECT name_en, name_ur FROM udrive.destinations WHERE id=@id AND is_active";
            cmd.Parameters.AddWithValue("id", id);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            if (!await r.ReadAsync(ct))
                return ServiceResult<ExploreDestinationDto>.Fail(404, "destination_not_found", "This place is not listed.");
            nameEn = r.GetString(0);
            nameUr = r.GetString(1);
        }

        // The route into this place. When several exist, the safest one is
        // what a first-time visitor should be shown.
        ExploreRouteDto? route = null;
        await using (var cmd = c.CreateCommand())
        {
            cmd.CommandText = """
                SELECT r.name, o.name_en, r.distance_km, r.estimated_minutes, r.recommended_vehicle,
                       r.four_by_four_required, r.daylight_only, r.safety_score
                FROM udrive.routes r
                LEFT JOIN udrive.destinations o ON o.id = r.origin_destination_id
                WHERE r.destination_id=@id AND r.is_active
                ORDER BY r.safety_score DESC, r.distance_km
                LIMIT 1
                """;
            cmd.Parameters.AddWithValue("id", id);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            if (await r.ReadAsync(ct))
            {
                route = new ExploreRouteDto(
                    r.GetString(0),
                    r.IsDBNull(1) ? null : r.GetString(1),
                    r.GetDecimal(2),
                    r.GetInt32(3),
                    r.GetString(4),
                    r.GetBoolean(5),
                    r.GetBoolean(6),
                    r.GetInt32(7));
            }
        }

        int tours; DateTimeOffset? next;
        await using (var cmd = c.CreateCommand())
        {
            cmd.CommandText = """
                SELECT count(*)::int, min(departure_at)
                FROM udrive.tour_packages
                WHERE destination_id=@id AND status='Active' AND departure_at>now() AND available_seats>0
                """;
            cmd.Parameters.AddWithValue("id", id);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            await r.ReadAsync(ct);
            tours = r.GetInt32(0);
            next = r.IsDBNull(1) ? null : r.GetFieldValue<DateTimeOffset>(1);
        }

        int hotels;
        await using (var cmd = c.CreateCommand())
        {
            cmd.CommandText = """
                SELECT count(*)::int
                FROM udrive.hotels h, udrive.destinations d
                WHERE d.id=@id AND lower(h.approval_status)='approved' AND h.is_active
                  AND ST_DWithin(d.location, ST_SetSRID(ST_MakePoint(h.longitude, h.latitude), 4326)::geography, @m)
                """;
            cmd.Parameters.AddWithValue("id", id);
            cmd.Parameters.AddWithValue("m", HotelRadiusKm * 1000);
            hotels = (int)(await cmd.ExecuteScalarAsync(ct) ?? 0);
        }

        var nearby = new List<ExploreNearbyDto>();
        await using (var cmd = c.CreateCommand())
        {
            cmd.CommandText = """
                SELECT o.id, o.name_en, o.district, ST_Distance(d.location, o.location) / 1000.0, o.cover_image_url
                FROM udrive.destinations d
                JOIN udrive.destinations o ON o.id<>d.id AND o.is_active
                WHERE d.id=@id AND ST_DWithin(d.location, o.location, @m)
                ORDER BY ST_Distance(d.location, o.location)
                LIMIT 6
                """;
            cmd.Parameters.AddWithValue("id", id);
            cmd.Parameters.AddWithValue("m", NearbyRadiusKm * 1000);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                nearby.Add(new ExploreNearbyDto(
                    r.GetGuid(0),
                    r.GetString(1),
                    r.GetString(2),
                    Math.Round(r.GetDouble(3), 1),
                    r.IsDBNull(4) ? null : r.GetString(4)));
            }
        }

        return ServiceResult<ExploreDestinationDto>.Ok(
            new ExploreDestinationDto(id, nameEn, nameUr, route, tours, next, hotels, nearby));
    }
}
