using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

public sealed class TourInterestService(string connectionString)
{
    public async Task<ServiceResult<TourInterestDto>> CreateAsync(
        Guid userId,
        CreateTourInterestRequest request,
        CancellationToken cancellationToken)
    {
        if (request.PreferredStartDate < DateOnly.FromDateTime(DateTime.UtcNow))
        {
            return ServiceResult<TourInterestDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_start_date",
                "Preferred start date cannot be in the past.");
        }
        if (request.PreferredEndDate is not null && request.PreferredEndDate < request.PreferredStartDate)
        {
            return ServiceResult<TourInterestDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_end_date",
                "Preferred end date must be on or after the start date.");
        }

        var id = Guid.NewGuid();
        const string sql = """
            INSERT INTO udrive.tour_interests
                (id, user_id, destination_id, preferred_start_date,
                 preferred_end_date, persons, group_preference,
                 budget_per_seat, pickup_city, is_active,
                 created_at, updated_at)
            VALUES
                (@id, @userId, @destinationId, @startDate,
                 @endDate, @persons, @groupPreference,
                 @budget, @pickupCity, true, now(), now());
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("userId", userId);
        command.Parameters.AddWithValue("destinationId", request.DestinationId);
        command.Parameters.AddWithValue("startDate", request.PreferredStartDate);
        command.Parameters.Add(new NpgsqlParameter("endDate", NpgsqlDbType.Date) { Value = (object?)request.PreferredEndDate ?? DBNull.Value });
        command.Parameters.AddWithValue("persons", request.Persons);
        command.Parameters.AddWithValue("groupPreference", request.GroupPreference.Trim());
        command.Parameters.Add(new NpgsqlParameter("budget", NpgsqlDbType.Numeric) { Value = (object?)request.BudgetPerSeat ?? DBNull.Value });
        command.Parameters.AddWithValue("pickupCity", request.PickupCity.Trim());
        await command.ExecuteNonQueryAsync(cancellationToken);

        var created = await GetByIdAsync(userId, id, cancellationToken);
        return created.Success && created.Data is not null
            ? ServiceResult<TourInterestDto>.Created(
                created.Data,
                "Tour interest registered. Matching packages will appear automatically.")
            : created;
    }

    public async Task<ServiceResult<IReadOnlyList<TourInterestDto>>> GetMineAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT ti.id, ti.destination_id, d.name_en,
                   ti.preferred_start_date, ti.preferred_end_date,
                   ti.persons, ti.group_preference, ti.budget_per_seat,
                   ti.pickup_city, ti.is_active, ti.created_at
            FROM udrive.tour_interests ti
            JOIN udrive.destinations d ON d.id=ti.destination_id
            WHERE ti.user_id=@userId
            ORDER BY ti.created_at DESC;
            """;
        var result = new List<TourInterestDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(ReadInterest(reader));
        }
        return ServiceResult<IReadOnlyList<TourInterestDto>>.Ok(result);
    }

    public async Task<ServiceResult<IReadOnlyList<TourMatchDto>>> GetMatchesAsync(
        Guid userId,
        Guid? interestId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT ti.id, tp.id, tp.title, d.name_en, tp.departure_at,
                   tp.available_seats, tp.price_per_seat,
                   tp.whole_vehicle_price,
                   LEAST(100,
                       55
                       + CASE WHEN lower(tp.starting_city) LIKE '%' || lower(ti.pickup_city) || '%' THEN 15 ELSE 0 END
                       + CASE WHEN tp.available_seats >= ti.persons THEN 15 ELSE 0 END
                       + CASE WHEN ti.budget_per_seat IS NULL OR tp.price_per_seat <= ti.budget_per_seat THEN 10 ELSE 0 END
                       + CASE WHEN lower(ti.group_preference)='family' AND tp.family_only THEN 5 ELSE 0 END
                   )::int AS match_percent,
                   u.full_name, dp.average_rating, dp.safety_score
            FROM udrive.tour_interests ti
            JOIN udrive.tour_packages tp ON tp.destination_id=ti.destination_id
            JOIN udrive.destinations d ON d.id=tp.destination_id
            JOIN udrive.driver_profiles dp ON dp.id=tp.driver_profile_id
            JOIN udrive.users u ON u.id=dp.user_id
            WHERE ti.user_id=@userId
              AND ti.is_active=true
              AND (@interestId IS NULL OR ti.id=@interestId)
              AND tp.status='Active'
              AND tp.departure_at::date >= ti.preferred_start_date
              AND tp.departure_at::date <= COALESCE(ti.preferred_end_date, ti.preferred_start_date + 7)
              AND tp.available_seats >= ti.persons
            ORDER BY match_percent DESC, tp.departure_at
            LIMIT 100;
            """;
        var result = new List<TourMatchDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);
        command.Parameters.Add(new NpgsqlParameter("interestId", NpgsqlDbType.Uuid) { Value = (object?)interestId ?? DBNull.Value });
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(new TourMatchDto(
                reader.GetGuid(0), reader.GetGuid(1), reader.GetString(2),
                reader.GetString(3), reader.GetFieldValue<DateTimeOffset>(4),
                reader.GetInt32(5), reader.GetDecimal(6), reader.GetDecimal(7),
                reader.GetInt32(8), reader.GetString(9), reader.GetDecimal(10),
                reader.GetInt32(11)));
        }
        return ServiceResult<IReadOnlyList<TourMatchDto>>.Ok(result);
    }

    public async Task<ServiceResult<TourInterestDto>> SetActiveAsync(
        Guid userId,
        Guid interestId,
        bool active,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.tour_interests
            SET is_active=@active, updated_at=now()
            WHERE id=@interestId AND user_id=@userId
            RETURNING id;
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("active", active);
        command.Parameters.AddWithValue("interestId", interestId);
        command.Parameters.AddWithValue("userId", userId);
        if (await command.ExecuteScalarAsync(cancellationToken) is null)
        {
            return ServiceResult<TourInterestDto>.Fail(
                StatusCodes.Status404NotFound,
                "tour_interest_not_found",
                "The tour interest was not found.");
        }
        return await GetByIdAsync(userId, interestId, cancellationToken);
    }

    private async Task<ServiceResult<TourInterestDto>> GetByIdAsync(
        Guid userId,
        Guid id,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT ti.id, ti.destination_id, d.name_en,
                   ti.preferred_start_date, ti.preferred_end_date,
                   ti.persons, ti.group_preference, ti.budget_per_seat,
                   ti.pickup_city, ti.is_active, ti.created_at
            FROM udrive.tour_interests ti
            JOIN udrive.destinations d ON d.id=ti.destination_id
            WHERE ti.id=@id AND ti.user_id=@userId;
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("userId", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? ServiceResult<TourInterestDto>.Ok(ReadInterest(reader))
            : ServiceResult<TourInterestDto>.Fail(
                StatusCodes.Status404NotFound,
                "tour_interest_not_found",
                "The tour interest was not found.");
    }

    private static TourInterestDto ReadInterest(NpgsqlDataReader reader) => new(
        reader.GetGuid(0), reader.GetGuid(1), reader.GetString(2),
        reader.GetFieldValue<DateOnly>(3),
        reader.IsDBNull(4) ? null : reader.GetFieldValue<DateOnly>(4),
        reader.GetInt32(5), reader.GetString(6),
        reader.IsDBNull(7) ? null : reader.GetDecimal(7),
        reader.GetString(8), reader.GetBoolean(9),
        reader.GetFieldValue<DateTimeOffset>(10));
}
