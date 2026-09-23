using Microsoft.AspNetCore.Http;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Tour pricing, which each Driver sets for their own vehicle.
/// </summary>
/// <remarks>
/// The admin's per-kilometre rules cover City and PrivateVehicle and stop
/// there. A multi-day trip through the mountains is not a metered ride — the
/// Driver is away from home, feeding and housing themselves, on roads that
/// punish a vehicle — and what that is worth is a judgement only the person
/// driving can make.
///
/// Nothing here is enforced on the Customer. They still name their own offer
/// and the Driver still answers with theirs; these figures are what the Driver
/// publishes so both sides start from something real.
/// </remarks>
public sealed class TourRatesService(string connectionString)
{
    /// <summary>Every vehicle belonging to the signed-in Driver.</summary>
    public async Task<ServiceResult<IReadOnlyList<TourRateDto>>> ForDriverAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT v.id, v.category,
                   trim(concat_ws(' ', v.make, v.model)),
                   COALESCE(v.available_for_tour, false),
                   v.tour_per_day_rate, v.tour_per_km_rate,
                   v.tour_minimum_fare, v.tour_notes
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            WHERE dp.user_id = @userId
            ORDER BY v.category, v.make, v.model;
            """;

        var list = new List<TourRateDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(new TourRateDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.IsDBNull(2) ? string.Empty : reader.GetString(2),
                reader.GetBoolean(3),
                reader.IsDBNull(4) ? null : reader.GetDecimal(4),
                reader.IsDBNull(5) ? null : reader.GetDecimal(5),
                reader.IsDBNull(6) ? null : reader.GetDecimal(6),
                reader.IsDBNull(7) ? null : reader.GetString(7)));
        }

        return ServiceResult<IReadOnlyList<TourRateDto>>.Ok(list);
    }

    /// <summary>Sets one vehicle's tour price.</summary>
    /// <remarks>
    /// Works on a verified vehicle, unlike the main vehicle edit. Verification
    /// approves what the vehicle is; the price is not part of that, and locking
    /// it would mean a Driver had to ask an Admin before changing what they
    /// charge.
    /// </remarks>
    public async Task<ServiceResult<TourRateDto>> UpdateAsync(
        Guid userId,
        Guid vehicleId,
        UpsertTourRateRequest request,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.vehicles v
            SET tour_per_day_rate = @perDay,
                tour_per_km_rate = @perKm,
                tour_minimum_fare = @minimum,
                tour_notes = @notes,
                available_for_tour = @available,
                updated_at = now()
            FROM udrive.driver_profiles dp
            WHERE v.id = @vehicleId
              AND v.driver_profile_id = dp.id
              AND dp.user_id = @userId
            RETURNING v.id, v.category,
                      trim(concat_ws(' ', v.make, v.model)),
                      COALESCE(v.available_for_tour, false),
                      v.tour_per_day_rate, v.tour_per_km_rate,
                      v.tour_minimum_fare, v.tour_notes;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("vehicleId", vehicleId);
        command.Parameters.AddWithValue("userId", userId);
        command.Parameters.AddWithValue("available", request.AvailableForTour);
        AddDecimal(command, "perDay", request.PerDayRate);
        AddDecimal(command, "perKm", request.PerKmRate);
        AddDecimal(command, "minimum", request.MinimumFare);
        command.Parameters.Add(new NpgsqlParameter("notes", NpgsqlDbType.Text)
        {
            Value = string.IsNullOrWhiteSpace(request.Notes)
                ? DBNull.Value
                : request.Notes.Trim(),
        });

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<TourRateDto>.Fail(
                StatusCodes.Status404NotFound,
                "vehicle_not_found",
                "That vehicle was not found on your account.");
        }

        return ServiceResult<TourRateDto>.Ok(new TourRateDto(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.IsDBNull(2) ? string.Empty : reader.GetString(2),
            reader.GetBoolean(3),
            reader.IsDBNull(4) ? null : reader.GetDecimal(4),
            reader.IsDBNull(5) ? null : reader.GetDecimal(5),
            reader.IsDBNull(6) ? null : reader.GetDecimal(6),
            reader.IsDBNull(7) ? null : reader.GetString(7)));
    }

    /// <summary>
    /// What tour vehicles are asking, by category, near a point.
    /// </summary>
    /// <remarks>
    /// A range, not a recommendation. Every figure in it was typed by a Driver
    /// about their own vehicle, so it tells the Customer what people actually
    /// charge without the platform pretending to set a price it does not set.
    ///
    /// The typical figure is the median rather than the mean: one operator
    /// asking 200,000 for a luxury coach should not drag the middle of the
    /// range away from what most drivers charge.
    /// </remarks>
    public async Task<ServiceResult<IReadOnlyList<TourRateGuideDto>>> GuideAsync(
        double? latitude,
        double? longitude,
        double radiusKm,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT v.category,
                   count(*)::int,
                   min(v.tour_per_day_rate),
                   percentile_cont(0.5) WITHIN GROUP (ORDER BY v.tour_per_day_rate),
                   max(v.tour_per_day_rate)
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            LEFT JOIN udrive.driver_presence_locations dpl
                   ON dpl.driver_profile_id = dp.id
            WHERE COALESCE(v.available_for_tour, false) = true
              AND v.tour_per_day_rate IS NOT NULL
              AND v.tour_per_day_rate > 0
              AND v.status = 'Verified'
              AND u.status = 'Approved'
              AND (
                    @lat IS NULL OR @lng IS NULL
                    OR dpl.location IS NULL
                    OR ST_DWithin(
                        dpl.location,
                        ST_SetSRID(ST_MakePoint(@lng, @lat), 4326)::geography,
                        @radiusMeters)
                  )
            GROUP BY v.category
            ORDER BY v.category;
            """;

        var list = new List<TourRateGuideDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.Add(new NpgsqlParameter("lat", NpgsqlDbType.Double)
        {
            Value = (object?)latitude ?? DBNull.Value,
        });
        command.Parameters.Add(new NpgsqlParameter("lng", NpgsqlDbType.Double)
        {
            Value = (object?)longitude ?? DBNull.Value,
        });
        command.Parameters.AddWithValue("radiusMeters", radiusKm * 1000.0);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(new TourRateGuideDto(
                reader.GetString(0),
                reader.GetInt32(1),
                reader.GetDecimal(2),
                reader.GetDecimal(3),
                reader.GetDecimal(4)));
        }

        return ServiceResult<IReadOnlyList<TourRateGuideDto>>.Ok(list);
    }

    private static void AddDecimal(NpgsqlCommand command, string name, decimal? value)
    {
        command.Parameters.Add(new NpgsqlParameter(name, NpgsqlDbType.Numeric)
        {
            // Zero is treated as "not set". A Driver clearing the field means
            // they have no published price, not that they will tour for free.
            Value = value is null || value <= 0 ? DBNull.Value : value,
        });
    }
}
