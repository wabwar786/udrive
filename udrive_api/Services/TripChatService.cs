using Microsoft.AspNetCore.Http;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Chat between the two people on one booking, and what each knows about the
/// other before they meet.
/// </summary>
/// <remarks>
/// Every method here starts by proving the caller is one of the two parties to
/// the booking. That check is not a formality: without it, knowing a booking id
/// would be enough to read a stranger's conversation or look up a passenger's
/// history, and booking ids travel through logs, links and screenshots.
/// </remarks>
public sealed class TripChatService(string connectionString)
{
    /// <summary>
    /// Which side of a booking a user is on, or null if neither.
    /// </summary>
    private static async Task<string?> RoleOnBookingAsync(
        NpgsqlConnection connection,
        Guid bookingId,
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT CASE
                     WHEN b.customer_user_id = @user THEN 'Customer'
                     WHEN dp.user_id = @user THEN 'Driver'
                     ELSE NULL
                   END
            FROM udrive.bookings b
            LEFT JOIN udrive.driver_profiles dp ON dp.id = b.driver_profile_id
            WHERE b.id = @booking;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("booking", bookingId);
        command.Parameters.AddWithValue("user", userId);
        var value = await command.ExecuteScalarAsync(cancellationToken);
        return value is string role ? role : null;
    }

    /// <summary>Messages on a booking, oldest first.</summary>
    /// <param name="after">
    /// Only messages created after this instant. The app passes the timestamp
    /// of the last message it holds, so polling every few seconds costs one
    /// index lookup and usually returns nothing.
    /// </param>
    public async Task<ServiceResult<IReadOnlyList<TripMessageDto>>> MessagesAsync(
        Guid userId,
        Guid bookingId,
        DateTimeOffset? after,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var role = await RoleOnBookingAsync(connection, bookingId, userId, cancellationToken);
        if (role is null) return Forbidden<IReadOnlyList<TripMessageDto>>();

        const string sql = """
            SELECT m.id, m.sender_user_id, m.sender_role, u.full_name, m.body,
                   m.read_at, m.created_at
            FROM udrive.trip_messages m
            JOIN udrive.users u ON u.id = m.sender_user_id
            WHERE m.booking_id = @booking
              AND (@after IS NULL OR m.created_at > @after)
            ORDER BY m.created_at
            LIMIT 300;
            """;

        var list = new List<TripMessageDto>();
        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("booking", bookingId);
            command.Parameters.Add(new NpgsqlParameter("after", NpgsqlDbType.TimestampTz)
            {
                Value = (object?)after ?? DBNull.Value,
            });

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                list.Add(new TripMessageDto(
                    reader.GetGuid(0),
                    reader.GetGuid(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.IsDBNull(5) ? null : reader.GetFieldValue<DateTimeOffset>(5),
                    reader.GetFieldValue<DateTimeOffset>(6)));
            }
        }

        // Reading the thread is what marks the other side's messages read. A
        // separate "mark read" call would be one more round trip that could
        // fail on its own and leave a badge that never clears.
        const string readSql = """
            UPDATE udrive.trip_messages
            SET read_at = now()
            WHERE booking_id = @booking
              AND sender_role <> @role
              AND read_at IS NULL;
            """;

        await using (var command = new NpgsqlCommand(readSql, connection))
        {
            command.Parameters.AddWithValue("booking", bookingId);
            command.Parameters.AddWithValue("role", role);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        return ServiceResult<IReadOnlyList<TripMessageDto>>.Ok(list);
    }

    /// <summary>Sends one message.</summary>
    public async Task<ServiceResult<TripMessageDto>> SendAsync(
        Guid userId,
        Guid bookingId,
        SendTripMessageRequest request,
        CancellationToken cancellationToken)
    {
        var body = request.Body.Trim();
        if (body.Length == 0)
        {
            return ServiceResult<TripMessageDto>.Fail(
                StatusCodes.Status400BadRequest,
                "message_empty",
                "Write something before sending.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var role = await RoleOnBookingAsync(connection, bookingId, userId, cancellationToken);
        if (role is null) return Forbidden<TripMessageDto>();

        const string sql = """
            INSERT INTO udrive.trip_messages
                (booking_id, sender_user_id, sender_role, body)
            VALUES (@booking, @user, @role, @body)
            RETURNING id, sender_user_id, sender_role,
                      (SELECT full_name FROM udrive.users WHERE id = @user),
                      body, read_at, created_at;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("booking", bookingId);
        command.Parameters.AddWithValue("user", userId);
        command.Parameters.AddWithValue("role", role);
        command.Parameters.AddWithValue("body", body);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<TripMessageDto>.Fail(
                StatusCodes.Status500InternalServerError,
                "message_not_sent",
                "The message could not be sent.");
        }

        return ServiceResult<TripMessageDto>.Created(new TripMessageDto(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetString(4),
            reader.IsDBNull(5) ? null : reader.GetFieldValue<DateTimeOffset>(5),
            reader.GetFieldValue<DateTimeOffset>(6)));
    }

    /// <summary>
    /// What a Driver can reasonably know about the passenger before they meet.
    /// </summary>
    /// <remarks>
    /// Built entirely from ratings Drivers have already given after past trips,
    /// which <c>trip_ratings</c> has recorded in both directions since phase 14
    /// — nobody was reading the Customer half of it.
    ///
    /// A Customer with no history returns a null rating rather than a default
    /// score. Showing "5.0" to a Driver about someone nobody has ever rated
    /// would be inventing a reassurance, and a new passenger is not a bad one.
    /// </remarks>
    public async Task<ServiceResult<PassengerStandingDto>> PassengerStandingAsync(
        Guid userId,
        Guid bookingId,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var role = await RoleOnBookingAsync(connection, bookingId, userId, cancellationToken);
        if (role != "Driver") return Forbidden<PassengerStandingDto>();

        const string sql = """
            SELECT u.full_name,
                   u.created_at,
                   (SELECT count(*)::int
                      FROM udrive.bookings b2
                     WHERE b2.customer_user_id = u.id
                       AND b2.status = 'Completed') AS completed,
                   (SELECT count(*)::int
                      FROM udrive.bookings b3
                     WHERE b3.customer_user_id = u.id
                       AND b3.status = 'Cancelled') AS cancelled,
                   (SELECT round(avg(r.overall_rating)::numeric, 2)
                      FROM udrive.trip_ratings r
                     WHERE r.reviewee_user_id = u.id
                       AND r.reviewer_role = 'Driver'
                       AND r.is_visible) AS rating,
                   (SELECT count(*)::int
                      FROM udrive.trip_ratings r2
                     WHERE r2.reviewee_user_id = u.id
                       AND r2.reviewer_role = 'Driver'
                       AND r2.is_visible) AS rating_count
            FROM udrive.bookings b
            JOIN udrive.users u ON u.id = b.customer_user_id
            WHERE b.id = @booking;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("booking", bookingId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<PassengerStandingDto>.Fail(
                StatusCodes.Status404NotFound,
                "booking_not_found",
                "That booking was not found.");
        }

        var completed = reader.GetInt32(2);
        var cancelled = reader.GetInt32(3);
        var rating = reader.IsDBNull(4) ? (decimal?)null : reader.GetDecimal(4);
        var ratingCount = reader.GetInt32(5);

        return ServiceResult<PassengerStandingDto>.Ok(new PassengerStandingDto(
            reader.GetString(0),
            reader.GetFieldValue<DateTimeOffset>(1),
            completed,
            cancelled,
            rating,
            ratingCount,
            Standing(completed, rating, ratingCount)));
    }

    /// <summary>
    /// The signed-in Driver's own dashboard figures.
    /// </summary>
    /// <remarks>
    /// Money is counted in Pakistan time, not UTC. A Driver finishing at 2am
    /// wants that fare in "today", and a UTC day boundary would move it to
    /// tomorrow five hours early — which reads as earnings vanishing overnight.
    ///
    /// Earnings come from completed bookings rather than the wallet ledger, so
    /// the figure is what was driven today, not what has been settled.
    /// </remarks>
    public async Task<ServiceResult<DriverDashboardDto>> DriverDashboardAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            WITH me AS (
                SELECT dp.id AS profile_id, u.id AS user_id, u.full_name,
                       dp.verification_status
                FROM udrive.driver_profiles dp
                JOIN udrive.users u ON u.id = dp.user_id
                WHERE dp.user_id = @user
            )
            SELECT me.full_name,
                   me.verification_status,
                   (SELECT round(avg(r.overall_rating)::numeric, 2)
                      FROM udrive.trip_ratings r
                     WHERE r.reviewee_user_id = me.user_id
                       AND r.reviewer_role = 'Customer' AND r.is_visible),
                   (SELECT count(*)::int
                      FROM udrive.trip_ratings r2
                     WHERE r2.reviewee_user_id = me.user_id
                       AND r2.reviewer_role = 'Customer' AND r2.is_visible),
                   (SELECT count(*)::int
                      FROM udrive.bookings b
                     WHERE b.driver_profile_id = me.profile_id
                       AND b.status = 'Completed'),
                   (SELECT COALESCE(sum(b2.total_amount), 0)
                      FROM udrive.bookings b2
                     WHERE b2.driver_profile_id = me.profile_id
                       AND b2.status = 'Completed'
                       AND (b2.updated_at AT TIME ZONE 'Asia/Karachi')::date
                           = (now() AT TIME ZONE 'Asia/Karachi')::date),
                   (SELECT COALESCE(sum(b3.total_amount), 0)
                      FROM udrive.bookings b3
                     WHERE b3.driver_profile_id = me.profile_id
                       AND b3.status = 'Completed'
                       AND date_trunc('month', b3.updated_at AT TIME ZONE 'Asia/Karachi')
                           = date_trunc('month', now() AT TIME ZONE 'Asia/Karachi')),
                   (SELECT count(*)::int
                      FROM udrive.bookings b4
                     WHERE b4.driver_profile_id = me.profile_id
                       AND b4.status = 'Completed'
                       AND (b4.updated_at AT TIME ZONE 'Asia/Karachi')::date
                           = (now() AT TIME ZONE 'Asia/Karachi')::date),
                   me.user_id
            FROM me;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        string name;
        string status;
        decimal? rating;
        int ratingCount;
        int completed;
        decimal today;
        decimal month;
        int tripsToday;
        Guid driverUserId;

        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("user", userId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<DriverDashboardDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "driver_profile_not_found",
                    "You do not have a driver profile yet.");
            }

            name = reader.GetString(0);
            status = reader.GetString(1);
            rating = reader.IsDBNull(2) ? null : reader.GetDecimal(2);
            ratingCount = reader.GetInt32(3);
            completed = reader.GetInt32(4);
            today = reader.GetDecimal(5);
            month = reader.GetDecimal(6);
            tripsToday = reader.GetInt32(7);
            driverUserId = reader.GetGuid(8);
        }

        const string reviewsSql = """
            SELECT r.overall_rating, r.review_text, r.created_at,
                   split_part(btrim(ru.full_name), ' ', 1)
            FROM udrive.trip_ratings r
            JOIN udrive.users ru ON ru.id = r.reviewer_user_id
            WHERE r.reviewee_user_id = @driver
              AND r.reviewer_role = 'Customer' AND r.is_visible
            ORDER BY r.created_at DESC
            LIMIT 5;
            """;

        var reviews = new List<DriverReviewDto>();
        await using (var command = new NpgsqlCommand(reviewsSql, connection))
        {
            command.Parameters.AddWithValue("driver", driverUserId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                reviews.Add(new DriverReviewDto(
                    reader.GetInt16(0),
                    reader.IsDBNull(1) ? null : reader.GetString(1),
                    reader.IsDBNull(3) || reader.GetString(3).Length == 0
                        ? "Customer"
                        : reader.GetString(3),
                    reader.GetFieldValue<DateTimeOffset>(2)));
            }
        }

        return ServiceResult<DriverDashboardDto>.Ok(new DriverDashboardDto(
            name, status, rating, ratingCount, completed,
            today, month, tripsToday, reviews));
    }

    /// <summary>
    /// What past Customers have said about the Driver on this booking.
    /// </summary>
    /// <remarks>
    /// Only Customer-written reviews, and only published ones — a Driver rating
    /// a Customer is a different conversation and does not belong in front of
    /// the person waiting at the kerb.
    ///
    /// Five most recent. A waiting Customer wants to know what this driver is
    /// like right now, and a five-star review from two years ago says less than
    /// a three-star one from last week. An average over a handful of ratings is
    /// noise dressed as a score, so the count is always shown beside it.
    /// </remarks>
    public async Task<ServiceResult<DriverReputationDto>> DriverReputationAsync(
        Guid userId,
        Guid bookingId,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var role = await RoleOnBookingAsync(connection, bookingId, userId, cancellationToken);
        if (role != "Customer") return Forbidden<DriverReputationDto>();

        const string summarySql = """
            SELECT du.id,
                   du.full_name,
                   (SELECT round(avg(r.overall_rating)::numeric, 2)
                      FROM udrive.trip_ratings r
                     WHERE r.reviewee_user_id = du.id
                       AND r.reviewer_role = 'Customer'
                       AND r.is_visible),
                   (SELECT count(*)::int
                      FROM udrive.trip_ratings r2
                     WHERE r2.reviewee_user_id = du.id
                       AND r2.reviewer_role = 'Customer'
                       AND r2.is_visible),
                   (SELECT count(*)::int
                      FROM udrive.bookings b2
                     WHERE b2.driver_profile_id = b.driver_profile_id
                       AND b2.status = 'Completed')
            FROM udrive.bookings b
            JOIN udrive.driver_profiles dp ON dp.id = b.driver_profile_id
            JOIN udrive.users du ON du.id = dp.user_id
            WHERE b.id = @booking;
            """;

        Guid driverUserId;
        string driverName;
        decimal? rating;
        int ratingCount;
        int completedTrips;

        await using (var command = new NpgsqlCommand(summarySql, connection))
        {
            command.Parameters.AddWithValue("booking", bookingId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<DriverReputationDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "driver_not_found",
                    "No driver is assigned to this booking yet.");
            }

            driverUserId = reader.GetGuid(0);
            driverName = reader.GetString(1);
            rating = reader.IsDBNull(2) ? null : reader.GetDecimal(2);
            ratingCount = reader.GetInt32(3);
            completedTrips = reader.GetInt32(4);
        }

        const string reviewsSql = """
            SELECT r.overall_rating, r.review_text, r.created_at,
                   split_part(btrim(ru.full_name), ' ', 1)
            FROM udrive.trip_ratings r
            JOIN udrive.users ru ON ru.id = r.reviewer_user_id
            WHERE r.reviewee_user_id = @driver
              AND r.reviewer_role = 'Customer'
              AND r.is_visible
            ORDER BY r.created_at DESC
            LIMIT 5;
            """;

        var reviews = new List<DriverReviewDto>();
        await using (var command = new NpgsqlCommand(reviewsSql, connection))
        {
            command.Parameters.AddWithValue("driver", driverUserId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                reviews.Add(new DriverReviewDto(
                    reader.GetInt16(0),
                    reader.IsDBNull(1) ? null : reader.GetString(1),
                    // First name only. A review is about the driver, and the
                    // reviewer did not agree to be identified to strangers.
                    reader.IsDBNull(3) || reader.GetString(3).Length == 0
                        ? "Customer"
                        : reader.GetString(3),
                    reader.GetFieldValue<DateTimeOffset>(2)));
            }
        }

        return ServiceResult<DriverReputationDto>.Ok(new DriverReputationDto(
            driverName,
            rating,
            ratingCount,
            completedTrips,
            reviews));
    }

    /// <summary>
    /// A one-word summary of the passenger's history.
    /// </summary>
    /// <remarks>
    /// Three plain outcomes rather than a tier ladder. "Gold" and "Silver"
    /// would imply the platform is ranking people, and a Driver deciding
    /// whether to take a fare needs a fact, not a loyalty grade.
    ///
    /// "New" is not a warning. Most passengers are new once, and the label says
    /// only that there is nothing to go on yet.
    /// </remarks>
    private static string Standing(int completed, decimal? rating, int ratingCount)
    {
        if (completed == 0) return "New";
        if (rating is null || ratingCount < 3) return "Regular";
        return rating >= 4.5m ? "Trusted" : rating >= 3.5m ? "Regular" : "Mixed";
    }

    private static ServiceResult<T> Forbidden<T>() =>
        ServiceResult<T>.Fail(
            StatusCodes.Status403Forbidden,
            "not_a_trip_participant",
            "You are not part of this trip.");
}
