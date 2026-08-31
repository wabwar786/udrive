using Microsoft.AspNetCore.Http;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Fixed per-seat fares for named routes.
/// </summary>
/// <remarks>
/// A Coster running per seat is not a metered vehicle. It runs a known route
/// and every passenger pays the same known fare — Muzaffarabad to Rawalakot is
/// a price people already have in their heads, not a figure multiplied out of a
/// distance.
///
/// So when a per-seat trip matches a route listed here, the listed fare is the
/// fare: no per-kilometre arithmetic and no bidding. Whole-vehicle bookings are
/// untouched, because hiring the same Coster outright genuinely is negotiable.
/// </remarks>
public sealed class SeatFaresService(string connectionString)
{
    private const string Columns = """
        id, vehicle_category, origin_label, origin_latitude, origin_longitude,
        origin_radius_km, destination_label, destination_latitude,
        destination_longitude, destination_radius_km, per_seat_fare,
        applies_both_ways, notes, is_active, updated_at
        """;

    public async Task<ServiceResult<IReadOnlyList<SeatFareDto>>> ListAsync(
        CancellationToken cancellationToken)
    {
        var sql = $"""
            SELECT {Columns}
            FROM udrive.seat_fares
            ORDER BY vehicle_category, origin_label, destination_label;
            """;

        var list = new List<SeatFareDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(Map(reader));
        }

        return ServiceResult<IReadOnlyList<SeatFareDto>>.Ok(list);
    }

    /// <summary>
    /// The fixed fare for a trip, or null when the route is not listed.
    /// </summary>
    /// <remarks>
    /// Both ends have to fall inside their circles. A route marked
    /// <c>applies_both_ways</c> also matches travelled backwards, so an admin
    /// enters Muzaffarabad → Rawalakot once instead of twice and the two halves
    /// cannot drift apart.
    ///
    /// Ties go to the tightest pair of circles. A rule written for one town
    /// should beat one written for a whole valley that happens to contain it.
    /// </remarks>
    public async Task<ServiceResult<SeatFareQuoteDto?>> ResolveAsync(
        string vehicleCategory,
        double fromLatitude,
        double fromLongitude,
        double toLatitude,
        double toLongitude,
        CancellationToken cancellationToken)
    {
        const string sql = """
            WITH point_from AS (
                SELECT ST_SetSRID(ST_MakePoint(@fromLng, @fromLat), 4326)::geography AS g
            ), point_to AS (
                SELECT ST_SetSRID(ST_MakePoint(@toLng, @toLat), 4326)::geography AS g
            ), origin AS (
                SELECT id, ST_SetSRID(ST_MakePoint(origin_longitude, origin_latitude), 4326)::geography AS g
                FROM udrive.seat_fares
            ), dest AS (
                SELECT id, ST_SetSRID(ST_MakePoint(destination_longitude, destination_latitude), 4326)::geography AS g
                FROM udrive.seat_fares
            )
            SELECT f.id, f.vehicle_category, f.origin_label, f.destination_label,
                   f.per_seat_fare, f.notes,
                   NOT ST_DWithin(o.g, (SELECT g FROM point_from), f.origin_radius_km * 1000.0)
                       AS reversed
            FROM udrive.seat_fares f
            JOIN origin o ON o.id = f.id
            JOIN dest d ON d.id = f.id
            WHERE f.is_active = true
              AND lower(f.vehicle_category) = lower(@category)
              AND (
                    (
                        ST_DWithin(o.g, (SELECT g FROM point_from), f.origin_radius_km * 1000.0)
                        AND ST_DWithin(d.g, (SELECT g FROM point_to), f.destination_radius_km * 1000.0)
                    )
                    OR (
                        f.applies_both_ways
                        AND ST_DWithin(d.g, (SELECT g FROM point_from), f.destination_radius_km * 1000.0)
                        AND ST_DWithin(o.g, (SELECT g FROM point_to), f.origin_radius_km * 1000.0)
                    )
                  )
            ORDER BY (f.origin_radius_km + f.destination_radius_km) ASC,
                     f.updated_at DESC
            LIMIT 1;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("category", vehicleCategory);
        command.Parameters.AddWithValue("fromLat", fromLatitude);
        command.Parameters.AddWithValue("fromLng", fromLongitude);
        command.Parameters.AddWithValue("toLat", toLatitude);
        command.Parameters.AddWithValue("toLng", toLongitude);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<SeatFareQuoteDto?>.Ok(null);
        }

        var reversed = !reader.IsDBNull(6) && reader.GetBoolean(6);
        var origin = reader.GetString(2);
        var destination = reader.GetString(3);

        return ServiceResult<SeatFareQuoteDto?>.Ok(new SeatFareQuoteDto(
            reader.GetGuid(0),
            reader.GetString(1),
            // Named the way the customer is actually travelling, so a return
            // leg does not read back to front.
            reversed ? destination : origin,
            reversed ? origin : destination,
            reader.GetDecimal(4),
            reversed,
            reader.IsDBNull(5) ? null : reader.GetString(5)));
    }

    public async Task<ServiceResult<SeatFareDto>> CreateAsync(
        UpsertSeatFareRequest request,
        CancellationToken cancellationToken)
    {
        var sql = $"""
            INSERT INTO udrive.seat_fares
                (vehicle_category, origin_label, origin_latitude, origin_longitude,
                 origin_radius_km, destination_label, destination_latitude,
                 destination_longitude, destination_radius_km, per_seat_fare,
                 applies_both_ways, notes, is_active)
            VALUES
                (@category, @originLabel, @originLat, @originLng, @originRadius,
                 @destLabel, @destLat, @destLng, @destRadius, @fare,
                 @bothWays, @notes, @active)
            RETURNING {Columns};
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        Bind(command, request);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<SeatFareDto>.Fail(
                StatusCodes.Status500InternalServerError,
                "seat_fare_not_created",
                "The route fare could not be saved.");
        }

        return ServiceResult<SeatFareDto>.Created(Map(reader));
    }

    public async Task<ServiceResult<SeatFareDto>> UpdateAsync(
        Guid id,
        UpsertSeatFareRequest request,
        CancellationToken cancellationToken)
    {
        var sql = $"""
            UPDATE udrive.seat_fares SET
                vehicle_category = @category,
                origin_label = @originLabel,
                origin_latitude = @originLat,
                origin_longitude = @originLng,
                origin_radius_km = @originRadius,
                destination_label = @destLabel,
                destination_latitude = @destLat,
                destination_longitude = @destLng,
                destination_radius_km = @destRadius,
                per_seat_fare = @fare,
                applies_both_ways = @bothWays,
                notes = @notes,
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
            return ServiceResult<SeatFareDto>.Fail(
                StatusCodes.Status404NotFound,
                "seat_fare_not_found",
                "That route fare no longer exists.");
        }

        return ServiceResult<SeatFareDto>.Ok(Map(reader));
    }

    public async Task<ServiceResult<bool>> DeleteAsync(
        Guid id,
        CancellationToken cancellationToken)
    {
        const string sql = "DELETE FROM udrive.seat_fares WHERE id = @id;";

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        var affected = await command.ExecuteNonQueryAsync(cancellationToken);

        return affected == 0
            ? ServiceResult<bool>.Fail(
                StatusCodes.Status404NotFound,
                "seat_fare_not_found",
                "That route fare no longer exists.")
            : ServiceResult<bool>.Ok(true);
    }

    private static void Bind(NpgsqlCommand command, UpsertSeatFareRequest request)
    {
        command.Parameters.AddWithValue("category", request.VehicleCategory.Trim());
        command.Parameters.AddWithValue("originLabel", request.OriginLabel.Trim());
        command.Parameters.AddWithValue("originLat", request.OriginLatitude);
        command.Parameters.AddWithValue("originLng", request.OriginLongitude);
        command.Parameters.AddWithValue("originRadius", request.OriginRadiusKm);
        command.Parameters.AddWithValue("destLabel", request.DestinationLabel.Trim());
        command.Parameters.AddWithValue("destLat", request.DestinationLatitude);
        command.Parameters.AddWithValue("destLng", request.DestinationLongitude);
        command.Parameters.AddWithValue("destRadius", request.DestinationRadiusKm);
        command.Parameters.AddWithValue("fare", request.PerSeatFare);
        command.Parameters.AddWithValue("bothWays", request.AppliesBothWays);
        command.Parameters.Add(new NpgsqlParameter("notes", NpgsqlDbType.Text)
        {
            Value = string.IsNullOrWhiteSpace(request.Notes)
                ? DBNull.Value
                : request.Notes.Trim(),
        });
        command.Parameters.AddWithValue("active", request.IsActive);
    }

    private static SeatFareDto Map(NpgsqlDataReader reader) => new(
        reader.GetGuid(0),
        reader.GetString(1),
        reader.GetString(2),
        reader.GetDouble(3),
        reader.GetDouble(4),
        reader.GetDouble(5),
        reader.GetString(6),
        reader.GetDouble(7),
        reader.GetDouble(8),
        reader.GetDouble(9),
        reader.GetDecimal(10),
        reader.GetBoolean(11),
        reader.IsDBNull(12) ? null : reader.GetString(12),
        reader.GetBoolean(13),
        reader.GetFieldValue<DateTimeOffset>(14));
}
