using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Whether a driver is online, and how long they have actually been online.
/// </summary>
/// <remarks>
/// Until now "online" lived in the phone's own storage. `toggleDriverOnline`
/// wrote a boolean to SharedPreferences and told nobody; the server's
/// `driver_profiles.is_online` was flipped as a side effect of other work. That
/// was survivable while the only thing it controlled was whether the driver saw
/// the request list — but every launch incentive is measured in minutes online,
/// and a number the phone keeps to itself can be neither trusted nor disputed.
///
/// So the toggle is now a request, and a stretch of being online is a row.
///
/// Three rules, and each exists because of a specific way this gets gamed or
/// goes wrong:
///
/// * <b>One open session per driver.</b> Enforced by a partial unique index, so
///   two phones signed into one account — or one phone retrying a request on a
///   bad connection — cannot both be counting the same minutes.
///
/// * <b>Time is credited, not measured.</b> A session's `credited_seconds` only
///   advances by the gap between two heartbeats that actually arrived close
///   together. A phone that slept in a drawer for an hour and then beat once
///   adds one gap to its record and nothing to its credit. Wall-clock time from
///   `started_at` would have paid for the drawer.
///
/// * <b>A session that stops beating is closed at its last heartbeat</b>, not at
///   the moment somebody noticed. A driver whose battery died at 7pm was not
///   online until midnight.
/// </remarks>
public sealed class DriverPresenceService(string connectionString)
{
    /// <summary>How often the app is told to beat.</summary>
    public const int HeartbeatSeconds = 60;

    /// <summary>
    /// The longest gap between heartbeats that still counts as continuous.
    /// </summary>
    /// <remarks>
    /// Two and a half beats. Generous enough that one missed beat on a weak
    /// signal in a valley does not cost the driver two minutes, tight enough
    /// that a backgrounded app cannot bank an hour.
    /// </remarks>
    private const int MaxCreditedGapSeconds = HeartbeatSeconds * 5 / 2;

    /// <summary>After this long with no heartbeat the session is closed.</summary>
    private const int StaleSessionSeconds = HeartbeatSeconds * 5;

    /// <summary>Above this, between two heartbeats, the position is not real.</summary>
    /// <remarks>
    /// 120 km/h. The fastest road in Azad Kashmir does not support it for a
    /// minute at a stretch, and a driver who appears to hold it between two
    /// beats is either reporting a faked position or running the app on a
    /// device that is not in the car.
    /// <para>
    /// Deliberately not a ban. The flag goes in the review queue and an admin
    /// decides, which is the same rule the whole growth system follows.
    /// </para>
    /// </remarks>
    private const double MaxPlausibleKmh = 120;

    /// <summary>
    /// Below this gap, GPS jitter alone produces absurd speeds, so nothing is
    /// judged.
    /// </summary>
    private const int MinSpeedCheckSeconds = 20;

    /// <summary>
    /// Below this distance the two points are the same place as far as a phone
    /// can tell, whatever the arithmetic says.
    /// </summary>
    private const double MinSpeedCheckMetres = 400;

    private NpgsqlConnection Open() => new(connectionString);

    // ───────────────────────────────────────────────────────────────── online

    public async Task<ServiceResult<DriverPresenceDto>> GoOnlineAsync(
        Guid userId,
        DriverPresenceRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var driver = await ResolveDriverAsync(connection, userId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<DriverPresenceDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "This account does not have a driver profile.");
        }

        if (!string.Equals(driver.Value.VerificationStatus, "Approved", StringComparison.Ordinal))
        {
            return ServiceResult<DriverPresenceDto>.Fail(
                StatusCodes.Status409Conflict,
                "driver_not_approved",
                "Your driver account is not approved yet, so you cannot go online.");
        }

        // Every ride vehicle on review or suspended from the Approved page:
        // there is nothing to go online with.
        await using (var held = new NpgsqlCommand(
            """
            SELECT EXISTS (
                       SELECT 1 FROM udrive.listing_holds lh
                       JOIN udrive.vehicles v ON v.id = lh.entity_id
                       WHERE lh.kind = 'city' AND lh.released_at IS NULL AND v.driver_profile_id = @driver)
               AND NOT EXISTS (
                       SELECT 1 FROM udrive.vehicles v
                       WHERE v.driver_profile_id = @driver
                         AND COALESCE(v.listed_via, 'Driver') = 'Driver'
                         AND lower(v.status) IN ('verified', 'approved')
                         AND NOT COALESCE(v.available_for_rent, false)
                         AND (COALESCE(v.available_for_city, true) OR COALESCE(v.available_for_intercity, true))
                         AND NOT EXISTS (SELECT 1 FROM udrive.listing_holds lh
                                         WHERE lh.kind = 'city' AND lh.entity_id = v.id AND lh.released_at IS NULL));
            """, connection))
        {
            held.Parameters.AddWithValue("driver", driver.Value.ProfileId);
            if (await held.ExecuteScalarAsync(cancellationToken) is true)
            {
                return ServiceResult<DriverPresenceDto>.Fail(
                    StatusCodes.Status409Conflict,
                    "vehicle_on_hold",
                    "Aap ki gaari review / suspend mein hai. Jab tak review nahi hoti, aap ko koi ride nahi milegi.");
            }
        }

        await CloseStaleSessionsAsync(connection, cancellationToken);

        await using var transaction =
            await connection.BeginTransactionAsync(cancellationToken);

        // ON CONFLICT against the partial index, so a retried request refreshes
        // the session the driver already has rather than failing or opening a
        // second one.
        const string sql = """
            INSERT INTO udrive.driver_online_sessions
                (id, driver_profile_id, launch_city_id, started_at,
                 last_heartbeat_at, last_latitude, last_longitude,
                 mock_location_seen, created_at, updated_at)
            VALUES (gen_random_uuid(), @driver, @city, now(), now(), @lat, @lng,
                    @mock, now(), now())
            ON CONFLICT (driver_profile_id) WHERE ended_at IS NULL
            DO UPDATE SET
                last_heartbeat_at = now(),
                last_latitude = COALESCE(EXCLUDED.last_latitude, udrive.driver_online_sessions.last_latitude),
                last_longitude = COALESCE(EXCLUDED.last_longitude, udrive.driver_online_sessions.last_longitude),
                mock_location_seen = udrive.driver_online_sessions.mock_location_seen OR EXCLUDED.mock_location_seen,
                updated_at = now()
            RETURNING id;
            """;

        Guid sessionId;
        await using (var command = new NpgsqlCommand(sql, connection, transaction))
        {
            command.Parameters.AddWithValue("driver", driver.Value.ProfileId);
            command.Parameters.AddWithValue("city",
                (object?)driver.Value.CityId ?? DBNull.Value);
            command.Parameters.AddWithValue("lat",
                (object?)request.Latitude ?? DBNull.Value);
            command.Parameters.AddWithValue("lng",
                (object?)request.Longitude ?? DBNull.Value);
            command.Parameters.AddWithValue("mock", request.MockLocation);
            sessionId = (Guid)(await command.ExecuteScalarAsync(cancellationToken))!;
        }

        await SetOnlineFlagAsync(
            connection, transaction, driver.Value.ProfileId, true, cancellationToken);

        if (request.MockLocation)
        {
            await RaiseFlagAsync(
                connection, transaction, driver.Value.ProfileId, sessionId,
                "MockLocation",
                "The device reported a mocked position when going online.",
                cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);

        var state = await ReadStateAsync(
            connection, driver.Value, cancellationToken);
        return ServiceResult<DriverPresenceDto>.Ok(state);
    }

    // ──────────────────────────────────────────────────────────── heartbeat

    public async Task<ServiceResult<DriverPresenceDto>> HeartbeatAsync(
        Guid userId,
        DriverPresenceRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var driver = await ResolveDriverAsync(connection, userId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<DriverPresenceDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "This account does not have a driver profile.");
        }

        await using var transaction =
            await connection.BeginTransactionAsync(cancellationToken);

        // The whole crediting rule, in one statement so there is no window in
        // which another beat could be counted against the same gap.
        // floor, not round — and the clock only moves by what was credited.
        //
        // `::int` on a numeric rounds. So a beat 0.6 seconds after the last one
        // credited a whole second and reset the clock, and a driver beating
        // twice a second was paid about two seconds of online time for every
        // second they were actually online. Online seconds are what the daily
        // missions and the peak-hour rewards are measured in, so that was a
        // way to be paid for time not worked, from the app, with no access to
        // anything.
        //
        // Flooring alone would fix the inflation and introduce a smaller
        // unfairness — the discarded fraction is lost every beat. So
        // last_heartbeat_at advances by exactly the seconds credited and keeps
        // the remainder for the next beat. Credited time can then never exceed
        // the real elapsed time, and never silently falls behind it either. A
        // beat inside the same second credits nothing and leaves the anchor
        // alone, so hammering the endpoint gains precisely nothing.
        // `prev` carries the position and the beat gap as they were *before*
        // this statement overwrites them. RETURNING sees the new row, so
        // without the CTE there is no way to know where the driver was a minute
        // ago — and that is the whole of the speed check below. One statement
        // rather than a SELECT and then an UPDATE, so no second beat can slip
        // between the two and be measured against a position already replaced.
        const string sql = """
            WITH prev AS (
                SELECT id,
                       last_latitude  AS plat,
                       last_longitude AS plng,
                       EXTRACT(EPOCH FROM (now() - last_heartbeat_at))::float8 AS psecs
                FROM udrive.driver_online_sessions
                WHERE driver_profile_id = @driver AND ended_at IS NULL
            )
            UPDATE udrive.driver_online_sessions s
            SET credited_seconds = s.credited_seconds +
                    CASE WHEN EXTRACT(EPOCH FROM (now() - s.last_heartbeat_at)) <= @maxgap
                         THEN floor(GREATEST(0,
                                  EXTRACT(EPOCH FROM (now() - s.last_heartbeat_at))))::int
                         ELSE 0 END,
                gap_count = s.gap_count +
                    CASE WHEN EXTRACT(EPOCH FROM (now() - s.last_heartbeat_at)) > @maxgap
                         THEN 1 ELSE 0 END,
                heartbeat_count = s.heartbeat_count + 1,
                last_heartbeat_at =
                    CASE WHEN EXTRACT(EPOCH FROM (now() - s.last_heartbeat_at)) > @maxgap
                         THEN now()
                         ELSE s.last_heartbeat_at + make_interval(secs =>
                                  floor(GREATEST(0,
                                      EXTRACT(EPOCH FROM (now() - s.last_heartbeat_at)))))
                         END,
                last_latitude = COALESCE(@lat, s.last_latitude),
                last_longitude = COALESCE(@lng, s.last_longitude),
                mock_location_seen = s.mock_location_seen OR @mock,
                updated_at = now()
            FROM prev
            WHERE s.id = prev.id
            RETURNING s.id, prev.plat, prev.plng, prev.psecs;
            """;

        Guid? sessionId = null;
        double? previousLatitude = null;
        double? previousLongitude = null;
        double previousGapSeconds = 0;

        await using (var command = new NpgsqlCommand(sql, connection, transaction))
        {
            command.Parameters.AddWithValue("driver", driver.Value.ProfileId);
            command.Parameters.AddWithValue("maxgap", MaxCreditedGapSeconds);
            command.Parameters.AddWithValue("lat",
                (object?)request.Latitude ?? DBNull.Value);
            command.Parameters.AddWithValue("lng",
                (object?)request.Longitude ?? DBNull.Value);
            command.Parameters.AddWithValue("mock", request.MockLocation);

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                sessionId = reader.GetGuid(0);
                previousLatitude = reader.IsDBNull(1) ? null : reader.GetDouble(1);
                previousLongitude = reader.IsDBNull(2) ? null : reader.GetDouble(2);
                previousGapSeconds = reader.IsDBNull(3) ? 0 : reader.GetDouble(3);
            }
        }

        // A beat with no open session means the app thinks it is online and the
        // server does not — after a timeout, a redeploy, or an admin action.
        // Opening one here is the repair: the alternative is a driver who looks
        // online in their own app and receives nothing.
        if (sessionId is null)
        {
            await transaction.RollbackAsync(cancellationToken);
            return await GoOnlineAsync(userId, request, cancellationToken);
        }

        if (request.MockLocation)
        {
            await RaiseFlagAsync(
                connection, transaction, driver.Value.ProfileId, sessionId.Value,
                "MockLocation",
                "The device reported a mocked position during an online session.",
                cancellationToken);
        }

        var jump = ImplausibleJump(
            previousLatitude, previousLongitude, previousGapSeconds,
            request.Latitude, request.Longitude);

        if (jump is not null)
        {
            await RaiseFlagAsync(
                connection, transaction, driver.Value.ProfileId, sessionId.Value,
                "ImpossibleSpeed", jump, cancellationToken, severity: "Severe");
        }

        await transaction.CommitAsync(cancellationToken);

        var state = await ReadStateAsync(connection, driver.Value, cancellationToken);
        return ServiceResult<DriverPresenceDto>.Ok(state);
    }

    // ──────────────────────────────────────────────────────────────── offline

    public async Task<ServiceResult<DriverPresenceDto>> GoOfflineAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var driver = await ResolveDriverAsync(connection, userId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<DriverPresenceDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "This account does not have a driver profile.");
        }

        await using var transaction =
            await connection.BeginTransactionAsync(cancellationToken);

        // The last stretch is credited the same way a heartbeat would have
        // credited it, so going offline two seconds after a beat is not two
        // seconds lost and going offline an hour after one is not an hour
        // gained.
        const string sql = """
            UPDATE udrive.driver_online_sessions s
            SET credited_seconds = s.credited_seconds +
                    CASE WHEN EXTRACT(EPOCH FROM (now() - s.last_heartbeat_at)) <= @maxgap
                         THEN floor(GREATEST(0,
                                  EXTRACT(EPOCH FROM (now() - s.last_heartbeat_at))))::int
                         ELSE 0 END,
                ended_at = now(),
                end_reason = 'DriverOffline',
                updated_at = now()
            WHERE s.driver_profile_id = @driver AND s.ended_at IS NULL;
            """;

        await using (var command = new NpgsqlCommand(sql, connection, transaction))
        {
            command.Parameters.AddWithValue("driver", driver.Value.ProfileId);
            command.Parameters.AddWithValue("maxgap", MaxCreditedGapSeconds);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await SetOnlineFlagAsync(
            connection, transaction, driver.Value.ProfileId, false, cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        var state = await ReadStateAsync(connection, driver.Value, cancellationToken);
        return ServiceResult<DriverPresenceDto>.Ok(state);
    }

    // ────────────────────────────────────────────────────────────────── state

    public async Task<ServiceResult<DriverPresenceDto>> StateAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var driver = await ResolveDriverAsync(connection, userId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<DriverPresenceDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "This account does not have a driver profile.");
        }

        await CloseStaleSessionsAsync(connection, cancellationToken);
        var state = await ReadStateAsync(connection, driver.Value, cancellationToken);
        return ServiceResult<DriverPresenceDto>.Ok(state);
    }

    // ─────────────────────────────────────────────────────────────── internals

    /// <summary>
    /// Closes sessions whose heartbeat stopped, at the time it stopped.
    /// </summary>
    /// <remarks>
    /// Runs on the presence endpoints rather than on a timer. A background
    /// sweeper is one more thing to deploy, monitor and forget; doing it here
    /// means the first driver to touch the API each minute tidies up after
    /// everyone, and a stale session is never read as open by the reward
    /// evaluator because that evaluator reads these same rows.
    /// </remarks>
    internal static async Task CloseStaleSessionsAsync(
        NpgsqlConnection connection,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.driver_online_sessions s
            SET ended_at = s.last_heartbeat_at,
                end_reason = 'Timeout',
                updated_at = now()
            WHERE s.ended_at IS NULL
              AND s.last_heartbeat_at < now() - make_interval(secs => @stale);
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("stale", (double)StaleSessionSeconds);
        await command.ExecuteNonQueryAsync(cancellationToken);

        // The flag follows the session. A driver shown as online in the
        // marketplace while their phone is off is worse than one shown offline:
        // requests go to them and time out.
        const string flagSql = """
            UPDATE udrive.driver_profiles p
            SET is_online = false, updated_at = now()
            WHERE p.is_online
              AND NOT EXISTS (
                  SELECT 1 FROM udrive.driver_online_sessions s
                  WHERE s.driver_profile_id = p.id AND s.ended_at IS NULL);
            """;

        await using var flagCommand = new NpgsqlCommand(flagSql, connection);
        await flagCommand.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task SetOnlineFlagAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid driverProfileId,
        bool online,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.driver_profiles
            SET is_online = @online, updated_at = now()
            WHERE id = @driver AND is_online <> @online;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("driver", driverProfileId);
        command.Parameters.AddWithValue("online", online);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>
    /// The sentence for the review queue when two beats cannot both be true,
    /// or null when they can.
    /// </summary>
    /// <remarks>
    /// Four things have to hold before this says anything, and each of them
    /// exists to keep an honest driver out of the queue:
    /// <list type="bullet">
    /// <item>Both positions are known. A beat with no fix proves nothing.</item>
    /// <item>The gap is at least <see cref="MinSpeedCheckSeconds"/>. Over two
    /// seconds, ordinary GPS drift in a valley reads as 300 km/h.</item>
    /// <item>The gap is within <see cref="MaxCreditedGapSeconds"/>. A longer one
    /// means the app was closed or the signal was gone, and a driver who drove
    /// to Islamabad with the app shut is not a fraud.</item>
    /// <item>The distance is at least <see cref="MinSpeedCheckMetres"/>. Below
    /// that the two points are the same place as far as a phone can tell.</item>
    /// </list>
    /// What it does not do is decide anything. It writes a sentence an admin
    /// reads.
    /// </remarks>
    internal static string? ImplausibleJump(
        double? fromLatitude,
        double? fromLongitude,
        double gapSeconds,
        double? toLatitude,
        double? toLongitude)
    {
        if (fromLatitude is null || fromLongitude is null
            || toLatitude is null || toLongitude is null)
        {
            return null;
        }

        if (gapSeconds < MinSpeedCheckSeconds || gapSeconds > MaxCreditedGapSeconds)
        {
            return null;
        }

        var metres = DistanceMetres(
            fromLatitude.Value, fromLongitude.Value,
            toLatitude.Value, toLongitude.Value);

        if (metres < MinSpeedCheckMetres) return null;

        var kmh = metres / gapSeconds * 3.6;
        if (kmh <= MaxPlausibleKmh) return null;

        return $"{Math.Round(kmh)} km/h between two heartbeats "
             + $"{Math.Round(gapSeconds)}s apart "
             + $"({Math.Round(metres / 1000, 1)} km).";
    }

    /// <summary>Great-circle metres between two points.</summary>
    /// <remarks>
    /// Haversine rather than PostGIS: this runs on every heartbeat of every
    /// online driver, and a round trip to the database to measure a straight
    /// line is a round trip for nothing. Over the distances involved here the
    /// difference between the two is centimetres.
    /// </remarks>
    private static double DistanceMetres(
        double fromLatitude, double fromLongitude,
        double toLatitude, double toLongitude)
    {
        const double earthRadiusMetres = 6_371_000;
        static double Radians(double degrees) => degrees * Math.PI / 180;

        var dLat = Radians(toLatitude - fromLatitude);
        var dLng = Radians(toLongitude - fromLongitude);

        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2)
              + Math.Cos(Radians(fromLatitude)) * Math.Cos(Radians(toLatitude))
                * Math.Sin(dLng / 2) * Math.Sin(dLng / 2);

        return 2 * earthRadiusMetres * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }

    internal static async Task RaiseFlagAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        Guid driverProfileId,
        Guid? sessionId,
        string flagType,
        string detail,
        CancellationToken cancellationToken,
        string severity = "Review")
    {
        // One flag per kind per local day — the unique index does the work, and
        // DO NOTHING keeps a repeating signal from filling the review queue.
        const string sql = """
            INSERT INTO udrive.driver_fraud_flags
                (id, driver_profile_id, session_id, flag_type, detail,
                 severity, created_at)
            VALUES (gen_random_uuid(), @driver, @session, @type, @detail,
                    @severity, now())
            ON CONFLICT DO NOTHING;
            """;

        await using var command = transaction is null
            ? new NpgsqlCommand(sql, connection)
            : new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("driver", driverProfileId);
        command.Parameters.AddWithValue("session", (object?)sessionId ?? DBNull.Value);
        command.Parameters.AddWithValue("type", flagType);
        command.Parameters.AddWithValue("detail", detail);
        command.Parameters.AddWithValue("severity", severity);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    internal readonly record struct DriverContext(
        Guid ProfileId,
        Guid UserId,
        string VerificationStatus,
        Guid? CityId,
        string? CityName);

    internal static async Task<DriverContext?> ResolveDriverAsync(
        NpgsqlConnection connection,
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT p.id, p.verification_status, p.launch_city_id, c.name
            FROM udrive.driver_profiles p
            LEFT JOIN udrive.launch_cities c ON c.id = p.launch_city_id
            WHERE p.user_id = @user
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("user", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return null;

        return new DriverContext(
            reader.GetGuid(0),
            userId,
            reader.GetString(1),
            reader.IsDBNull(2) ? null : reader.GetGuid(2),
            reader.IsDBNull(3) ? null : reader.GetString(3));
    }

    private static async Task<DriverPresenceDto> ReadStateAsync(
        NpgsqlConnection connection,
        DriverContext driver,
        CancellationToken cancellationToken)
    {
        // Today is the driver's day, not UTC's. A session that started at
        // 11pm Pakistan time belongs to that evening.
        const string sql = """
            SELECT
                open_session.id,
                open_session.started_at,
                open_session.credited_seconds,
                COALESCE(today.total, 0)
            FROM (SELECT 1) AS anchor
            LEFT JOIN LATERAL (
                SELECT s.id, s.started_at, s.credited_seconds
                FROM udrive.driver_online_sessions s
                WHERE s.driver_profile_id = @driver AND s.ended_at IS NULL
                LIMIT 1
            ) AS open_session ON true
            LEFT JOIN LATERAL (
                SELECT SUM(s.credited_seconds)::int AS total
                FROM udrive.driver_online_sessions s
                WHERE s.driver_profile_id = @driver
                  AND (s.started_at AT TIME ZONE 'Asia/Karachi')::date
                      = (now() AT TIME ZONE 'Asia/Karachi')::date
            ) AS today ON true;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driver", driver.ProfileId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        Guid? sessionId = null;
        DateTimeOffset? since = null;
        var sessionSeconds = 0;
        var todaySeconds = 0;

        if (await reader.ReadAsync(cancellationToken))
        {
            if (!reader.IsDBNull(0)) sessionId = reader.GetGuid(0);
            if (!reader.IsDBNull(1)) since = reader.GetFieldValue<DateTimeOffset>(1);
            if (!reader.IsDBNull(2)) sessionSeconds = reader.GetInt32(2);
            if (!reader.IsDBNull(3)) todaySeconds = reader.GetInt32(3);
        }

        return new DriverPresenceDto(
            sessionId is not null,
            sessionId,
            since,
            sessionSeconds,
            todaySeconds,
            HeartbeatSeconds,
            driver.CityName,
            driver.CityId);
    }
}
