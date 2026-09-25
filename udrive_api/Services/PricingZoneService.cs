using Npgsql;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Which pricing zone a point falls in, and what that zone does to a fare.
/// </summary>
/// <remarks>
/// A zone is a named set of circles with a difficulty factor and a return
/// share. Circles rather than polygons because <c>pricing_rules</c> already
/// works that way and the portal already knows how to edit a centre and a
/// radius; a long valley is covered by several overlapping circles along the
/// road.
///
/// When a point is in no zone at all the answer is <see cref="Default"/> —
/// factor 1.0, no return share — which prices exactly as the platform did
/// before zones existed. That matters: the seeded zones ship inactive, so
/// until an admin has checked the coordinates on a map, every trip lands here.
/// </remarks>
public sealed class PricingZoneService(string connectionString)
{
    public static readonly PricingZoneDto Default =
        new(null, "Default", 1.000m, 0.000m, true);

    /// <summary>The zone covering a point, or <see cref="Default"/>.</summary>
    /// <remarks>
    /// Highest priority wins where zones overlap, then the tightest circle —
    /// so a small "Muzaffarabad city" circle inside a large regional one takes
    /// precedence without anyone having to order them by hand.
    ///
    /// The month test uses Pakistan time rather than UTC. A zone that switches
    /// off on the last day of October should do so at midnight in Muzaffarabad,
    /// not at five in the morning.
    /// </remarks>
    public async Task<PricingZoneDto> ResolveAsync(
        NpgsqlConnection connection,
        double latitude,
        double longitude,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT z.id, z.name, z.difficulty_factor, z.return_share, z.surge_enabled
            FROM udrive.pricing_zones z
            JOIN udrive.pricing_zone_areas a ON a.zone_id = z.id
            WHERE z.is_active
              AND (z.active_months IS NULL
                   OR EXTRACT(MONTH FROM (now() AT TIME ZONE 'Asia/Karachi'))::smallint
                      = ANY(z.active_months))
              AND ST_DWithin(
                      a.centre,
                      ST_SetSRID(ST_MakePoint(@lng, @lat), 4326)::geography,
                      a.radius_km * 1000.0)
            ORDER BY z.priority DESC, a.radius_km ASC
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("lat", latitude);
        command.Parameters.AddWithValue("lng", longitude);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return Default;
        }

        return new PricingZoneDto(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetDecimal(2),
            reader.GetDecimal(3),
            reader.GetBoolean(4));
    }

    // ------------------------------------------------------------- admin

    public async Task<IReadOnlyList<PricingZoneDetailDto>> ListAsync(
        CancellationToken cancellationToken)
    {
        const string zonesSql = """
            SELECT id, name, difficulty_factor, return_share, surge_enabled,
                   active_months, priority, is_active, notes
            FROM udrive.pricing_zones
            ORDER BY priority DESC, name;
            """;

        const string areasSql = """
            SELECT id, zone_id, label, latitude, longitude, radius_km
            FROM udrive.pricing_zone_areas
            ORDER BY zone_id, label NULLS LAST;
            """;

        var zones = new List<(PricingZoneDetailDto Zone, Guid Id)>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        await using (var command = new NpgsqlCommand(zonesSql, connection))
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                var id = reader.GetGuid(0);
                zones.Add((new PricingZoneDetailDto(
                    id,
                    reader.GetString(1),
                    reader.GetDecimal(2),
                    reader.GetDecimal(3),
                    reader.GetBoolean(4),
                    reader.IsDBNull(5) ? null : ToMonthList(reader.GetFieldValue<short[]>(5)),
                    reader.GetInt32(6),
                    reader.GetBoolean(7),
                    reader.IsDBNull(8) ? null : reader.GetString(8),
                    new List<PricingZoneAreaDto>()), id));
            }
        }

        var byId = zones.ToDictionary(entry => entry.Id, entry => entry.Zone);

        await using (var command = new NpgsqlCommand(areasSql, connection))
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                var zoneId = reader.GetGuid(1);
                if (!byId.TryGetValue(zoneId, out var zone)) continue;

                ((List<PricingZoneAreaDto>)zone.Areas).Add(new PricingZoneAreaDto(
                    reader.GetGuid(0),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.GetDouble(3),
                    reader.GetDouble(4),
                    reader.GetDecimal(5)));
            }
        }

        return zones.Select(entry => entry.Zone).ToList();
    }

    public async Task<Guid> SaveAsync(
        SavePricingZoneRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        const string upsertSql = """
            INSERT INTO udrive.pricing_zones
                (id, name, difficulty_factor, return_share, surge_enabled,
                 active_months, priority, is_active, notes, updated_at)
            VALUES (COALESCE(@id, gen_random_uuid()), @name, @difficulty, @returnShare,
                    @surge, @months, @priority, @active, @notes, now())
            ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                difficulty_factor = EXCLUDED.difficulty_factor,
                return_share = EXCLUDED.return_share,
                surge_enabled = EXCLUDED.surge_enabled,
                active_months = EXCLUDED.active_months,
                priority = EXCLUDED.priority,
                is_active = EXCLUDED.is_active,
                notes = EXCLUDED.notes,
                updated_at = now()
            RETURNING id;
            """;

        Guid zoneId;
        await using (var command = new NpgsqlCommand(upsertSql, connection, transaction))
        {
            command.Parameters.AddWithValue("id", (object?)request.Id ?? DBNull.Value);
            command.Parameters.AddWithValue("name", request.Name.Trim());
            command.Parameters.AddWithValue("difficulty", request.DifficultyFactor);
            command.Parameters.AddWithValue("returnShare", request.ReturnShare);
            command.Parameters.AddWithValue("surge", request.SurgeEnabled);
            command.Parameters.AddWithValue(
                "months",
                request.ActiveMonths is { Count: > 0 }
                    ? request.ActiveMonths.Select(month => (short)month).ToArray()
                    : (object)DBNull.Value);
            command.Parameters.AddWithValue("priority", request.Priority);
            command.Parameters.AddWithValue("active", request.IsActive);
            command.Parameters.AddWithValue("notes", (object?)request.Notes ?? DBNull.Value);
            zoneId = (Guid)(await command.ExecuteScalarAsync(cancellationToken))!;
        }

        // The circles are replaced wholesale rather than diffed. A zone has a
        // handful of them, the portal always sends the complete set, and a
        // diff is a way to leave an orphan circle quietly pricing trips.
        await using (var delete = new NpgsqlCommand(
            "DELETE FROM udrive.pricing_zone_areas WHERE zone_id = @id;",
            connection, transaction))
        {
            delete.Parameters.AddWithValue("id", zoneId);
            await delete.ExecuteNonQueryAsync(cancellationToken);
        }

        foreach (var area in request.Areas)
        {
            await using var insert = new NpgsqlCommand("""
                INSERT INTO udrive.pricing_zone_areas
                    (zone_id, label, latitude, longitude, radius_km)
                VALUES (@zone, @label, @lat, @lng, @radius);
                """, connection, transaction);
            insert.Parameters.AddWithValue("zone", zoneId);
            insert.Parameters.AddWithValue("label", (object?)area.Label ?? DBNull.Value);
            insert.Parameters.AddWithValue("lat", area.Latitude);
            insert.Parameters.AddWithValue("lng", area.Longitude);
            insert.Parameters.AddWithValue("radius", area.RadiusKm);
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return zoneId;
    }

    public async Task<bool> DeleteAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "DELETE FROM udrive.pricing_zones WHERE id = @id;", connection);
        command.Parameters.AddWithValue("id", id);
        return await command.ExecuteNonQueryAsync(cancellationToken) > 0;
    }

    private static IReadOnlyList<int> ToMonthList(short[] months) =>
        months.Select(month => (int)month).ToList();
}
