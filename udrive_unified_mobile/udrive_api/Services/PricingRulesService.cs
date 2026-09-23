using Microsoft.AspNetCore.Http;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Admin-managed per-kilometre pricing, scoped by day of week and by area.
/// </summary>
/// <remarks>
/// A rule carries a per-km rate and two optional scopes. Both empty means the
/// rule applies everywhere, every day — which is how the seeded rules behave, so
/// switching this on changed nothing until an admin added a narrower one.
///
/// Only one rule is ever used for a given trip. Blending several would make the
/// resulting fare impossible for the admin to trace back to anything they typed.
/// </remarks>
public sealed class PricingRulesService(string connectionString)
{
    private const string Columns = """
        id, name, service_type, vehicle_category, per_km_rate, minimum_fare,
        per_minute_rate, days_of_week, area_label, area_latitude,
        area_longitude, area_radius_km, priority, is_active, updated_at
        """;

    // ------------------------------------------------------------------ read

    public async Task<ServiceResult<IReadOnlyList<PricingRuleDto>>> ListAsync(
        CancellationToken cancellationToken)
    {
        var sql = $"""
            SELECT {Columns}
            FROM udrive.pricing_rules
            ORDER BY service_type, vehicle_category, priority DESC, name;
            """;

        var list = new List<PricingRuleDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(Map(reader));
        }

        return ServiceResult<IReadOnlyList<PricingRuleDto>>.Ok(list);
    }

    /// <summary>
    /// The rule that applies to a trip, or null when none does.
    /// </summary>
    /// <remarks>
    /// Ordering is the whole design. Most specific wins: a rule pinned to an
    /// area beats a global one, a smaller area beats a larger one, and a rule
    /// naming particular days beats one that runs all week. <c>priority</c> is
    /// checked first so an admin can override that reasoning by hand when a
    /// promotion has to win regardless.
    ///
    /// The day is read in Pakistan time inside the query, so the answer does not
    /// depend on the server's clock settings.
    /// </remarks>
    internal static async Task<PricingRuleDto?> ResolveAsync(
        NpgsqlConnection connection,
        string serviceType,
        string vehicleCategory,
        double? latitude,
        double? longitude,
        CancellationToken cancellationToken)
    {
        var sql = $"""
            SELECT {Columns}
            FROM udrive.pricing_rules
            WHERE is_active = true
              AND lower(service_type) = lower(@service)
              AND lower(vehicle_category) = lower(@category)
              AND (
                    days_of_week IS NULL
                    OR cardinality(days_of_week) = 0
                    OR EXTRACT(ISODOW FROM (now() AT TIME ZONE 'Asia/Karachi'))
                       = ANY(days_of_week)
                  )
              AND (
                    area_radius_km IS NULL
                    OR (
                        @lat IS NOT NULL AND @lng IS NOT NULL
                        AND ST_DWithin(
                            ST_SetSRID(ST_MakePoint(area_longitude, area_latitude), 4326)::geography,
                            ST_SetSRID(ST_MakePoint(@lng, @lat), 4326)::geography,
                            area_radius_km * 1000.0)
                    )
                  )
            ORDER BY priority DESC,
                     (area_radius_km IS NOT NULL) DESC,
                     area_radius_km ASC NULLS LAST,
                     (days_of_week IS NOT NULL AND cardinality(days_of_week) > 0) DESC,
                     updated_at DESC
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("service", serviceType);
        command.Parameters.AddWithValue("category", vehicleCategory);
        command.Parameters.Add(new NpgsqlParameter("lat", NpgsqlDbType.Double)
        {
            Value = (object?)latitude ?? DBNull.Value,
        });
        command.Parameters.Add(new NpgsqlParameter("lng", NpgsqlDbType.Double)
        {
            Value = (object?)longitude ?? DBNull.Value,
        });

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken) ? Map(reader) : null;
    }

    // ----------------------------------------------------------------- write

    public async Task<ServiceResult<PricingRuleDto>> CreateAsync(
        UpsertPricingRuleRequest request,
        CancellationToken cancellationToken)
    {
        var invalid = Validate(request);
        if (invalid is not null) return invalid;

        var sql = $"""
            INSERT INTO udrive.pricing_rules
                (name, service_type, vehicle_category, per_km_rate, minimum_fare,
                 per_minute_rate, days_of_week, area_label, area_latitude,
                 area_longitude, area_radius_km, priority, is_active)
            VALUES
                (@name, @service, @category, @perKm, @minimum, @perMinute,
                 @days, @areaLabel, @areaLat, @areaLng, @areaRadius,
                 @priority, @active)
            RETURNING {Columns};
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        Bind(command, request);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<PricingRuleDto>.Fail(
                StatusCodes.Status500InternalServerError,
                "pricing_rule_not_created",
                "The rule could not be saved.");
        }

        return ServiceResult<PricingRuleDto>.Created(Map(reader));
    }

    public async Task<ServiceResult<PricingRuleDto>> UpdateAsync(
        Guid id,
        UpsertPricingRuleRequest request,
        CancellationToken cancellationToken)
    {
        var invalid = Validate(request);
        if (invalid is not null) return invalid;

        var sql = $"""
            UPDATE udrive.pricing_rules SET
                name = @name,
                service_type = @service,
                vehicle_category = @category,
                per_km_rate = @perKm,
                minimum_fare = @minimum,
                per_minute_rate = @perMinute,
                days_of_week = @days,
                area_label = @areaLabel,
                area_latitude = @areaLat,
                area_longitude = @areaLng,
                area_radius_km = @areaRadius,
                priority = @priority,
                is_active = @active,
                updated_at = now()
            WHERE id = @id
            RETURNING {Columns};
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        Bind(command, request);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<PricingRuleDto>.Fail(
                StatusCodes.Status404NotFound,
                "pricing_rule_not_found",
                "That pricing rule no longer exists.");
        }

        return ServiceResult<PricingRuleDto>.Ok(Map(reader));
    }

    public async Task<ServiceResult<bool>> DeleteAsync(
        Guid id,
        CancellationToken cancellationToken)
    {
        const string sql = "DELETE FROM udrive.pricing_rules WHERE id = @id;";

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        var affected = await command.ExecuteNonQueryAsync(cancellationToken);

        return affected == 0
            ? ServiceResult<bool>.Fail(
                StatusCodes.Status404NotFound,
                "pricing_rule_not_found",
                "That pricing rule no longer exists.")
            : ServiceResult<bool>.Ok(true);
    }

    // --------------------------------------------------------------- preview

    /// <summary>
    /// What every vehicle would cost for a sample trip, right now.
    /// </summary>
    /// <remarks>
    /// The same arithmetic the customer app uses. Without this the only way to
    /// check a rate change was to book a ride, so a typo in a per-km figure
    /// reached customers before it reached anyone who could see it was wrong.
    /// </remarks>
    public async Task<ServiceResult<IReadOnlyList<PricingPreviewDto>>> PreviewAsync(
        string serviceType,
        double distanceKm,
        int minutes,
        double? latitude,
        double? longitude,
        CancellationToken cancellationToken)
    {
        const string categoriesSql = """
            SELECT DISTINCT vehicle_category
            FROM udrive.pricing_rules
            WHERE is_active = true AND lower(service_type) = lower(@service)
            ORDER BY vehicle_category;
            """;

        var categories = new List<string>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        await using (var command = new NpgsqlCommand(categoriesSql, connection))
        {
            command.Parameters.AddWithValue("service", serviceType);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                categories.Add(reader.GetString(0));
            }
        }

        var list = new List<PricingPreviewDto>();
        foreach (var category in categories)
        {
            var rule = await ResolveAsync(
                connection, serviceType, category, latitude, longitude, cancellationToken);
            if (rule is null) continue;

            var metered = rule.PerKmRate * (decimal)distanceKm
                          + rule.PerMinuteRate * minutes;
            var fare = Math.Max(metered, rule.MinimumFare);

            list.Add(new PricingPreviewDto(
                category,
                rule.Name,
                rule.PerKmRate,
                rule.MinimumFare,
                rule.PerMinuteRate,
                // Rounded the same way the app rounds it, so the preview and
                // the customer's screen agree to the rupee.
                Math.Round(fare / 5m, MidpointRounding.AwayFromZero) * 5m));
        }

        return ServiceResult<IReadOnlyList<PricingPreviewDto>>.Ok(list);
    }

    // ----------------------------------------------------------------- glue

    /// <summary>
    /// Catches the two mistakes the database constraints cannot explain well.
    /// </summary>
    private static ServiceResult<PricingRuleDto>? Validate(
        UpsertPricingRuleRequest request)
    {
        var hasAnyArea = request.AreaLatitude is not null
                         || request.AreaLongitude is not null
                         || request.AreaRadiusKm is not null;
        var hasWholeArea = request.AreaLatitude is not null
                           && request.AreaLongitude is not null
                           && request.AreaRadiusKm is not null;

        if (hasAnyArea && !hasWholeArea)
        {
            return ServiceResult<PricingRuleDto>.Fail(
                StatusCodes.Status400BadRequest,
                "pricing_rule_area_incomplete",
                "An area needs a centre and a radius. Set all three, or clear "
                + "them all to apply this rule everywhere.");
        }

        if (request.DaysOfWeek is not null
            && request.DaysOfWeek.Any(day => day is < 1 or > 7))
        {
            return ServiceResult<PricingRuleDto>.Fail(
                StatusCodes.Status400BadRequest,
                "pricing_rule_days_invalid",
                "Days must be 1 (Monday) to 7 (Sunday).");
        }

        return null;
    }

    private static void Bind(NpgsqlCommand command, UpsertPricingRuleRequest request)
    {
        command.Parameters.AddWithValue("name", request.Name.Trim());
        command.Parameters.AddWithValue("service", request.ServiceType.Trim());
        command.Parameters.AddWithValue("category", request.VehicleCategory.Trim());
        command.Parameters.AddWithValue("perKm", request.PerKmRate);
        command.Parameters.AddWithValue("minimum", request.MinimumFare);
        command.Parameters.AddWithValue("perMinute", request.PerMinuteRate);

        // An empty selection is stored as NULL rather than an empty array, so
        // "every day" has one representation instead of two.
        var days = request.DaysOfWeek?
            .Select(day => (short)day)
            .Distinct()
            .OrderBy(day => day)
            .ToArray();
        command.Parameters.Add(new NpgsqlParameter("days", NpgsqlDbType.Array | NpgsqlDbType.Smallint)
        {
            Value = days is null || days.Length == 0 ? DBNull.Value : days,
        });

        command.Parameters.Add(new NpgsqlParameter("areaLabel", NpgsqlDbType.Text)
        {
            Value = string.IsNullOrWhiteSpace(request.AreaLabel)
                ? DBNull.Value
                : request.AreaLabel.Trim(),
        });
        command.Parameters.Add(new NpgsqlParameter("areaLat", NpgsqlDbType.Double)
        {
            Value = (object?)request.AreaLatitude ?? DBNull.Value,
        });
        command.Parameters.Add(new NpgsqlParameter("areaLng", NpgsqlDbType.Double)
        {
            Value = (object?)request.AreaLongitude ?? DBNull.Value,
        });
        command.Parameters.Add(new NpgsqlParameter("areaRadius", NpgsqlDbType.Double)
        {
            Value = (object?)request.AreaRadiusKm ?? DBNull.Value,
        });
        command.Parameters.AddWithValue("priority", request.Priority);
        command.Parameters.AddWithValue("active", request.IsActive);
    }

    private static PricingRuleDto Map(NpgsqlDataReader reader) => new(
        reader.GetGuid(0),
        reader.GetString(1),
        reader.GetString(2),
        reader.GetString(3),
        reader.GetDecimal(4),
        reader.GetDecimal(5),
        reader.GetDecimal(6),
        reader.IsDBNull(7)
            ? Array.Empty<int>()
            : reader.GetFieldValue<short[]>(7).Select(day => (int)day).ToArray(),
        reader.IsDBNull(8) ? null : reader.GetString(8),
        reader.IsDBNull(9) ? null : reader.GetDouble(9),
        reader.IsDBNull(10) ? null : reader.GetDouble(10),
        reader.IsDBNull(11) ? null : reader.GetDouble(11),
        reader.GetInt32(12),
        reader.GetBoolean(13),
        reader.GetFieldValue<DateTimeOffset>(14));
}
