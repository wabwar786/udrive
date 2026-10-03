using System.Globalization;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The reward engine: what a driver has earned, is earning, and is owed.
/// </summary>
/// <remarks>
/// Everything a driver can be paid for that is not a ride goes through here —
/// the welcome bonus, daily missions, peak-hour rewards, referrals — and all of
/// it is configuration an admin writes, not code.
///
/// <b>Where the money goes.</b> A credited reward is a row in
/// <c>driver_wallet_entries</c> with <c>balance_bucket = 'Commission'</c> and
/// <c>entry_type = 'Bonus'</c>, and it increases
/// <c>driver_wallets.commission_balance</c> — the prepaid balance a driver's
/// commission is already taken from. So a bonus is real money to the driver and
/// is spent the moment they drive, but it can never leave as cash. That was the
/// decision, and putting it in the existing bucket rather than a new one means
/// payouts, statements and finance reports needed no changes at all.
///
/// <b>Why evaluation runs on read.</b> There is no background job. Progress is
/// recomputed whenever the driver's app asks for it, which is every time they
/// open the home screen. That makes the whole thing self-healing — a missed
/// run, a redeploy mid-evaluation, a campaign edited at noon — because the next
/// read recomputes from the source rows rather than from a counter that drifted.
/// The duplicate-payment risk this would normally create is handled in the
/// database, not here: <c>ux_driver_campaign_progress</c> allows exactly one row
/// per driver per campaign per period, and the wallet entry's
/// <c>idempotency_key</c> allows exactly one credit per row. Two evaluations
/// racing each other produce one payment.
///
/// <b>What is never done automatically.</b> Nothing is blocked, refused or
/// clawed back by this code. A mocked position or an impossible pattern writes
/// a row in <c>driver_fraud_flags</c> and an admin decides. A launch incentive
/// that bans drivers on its own will eventually ban an honest one, and that
/// driver tells every other driver in the city.
/// </remarks>
public sealed class DriverGrowthService(string connectionString)
{
    private NpgsqlConnection Open() => new(connectionString);

    /// <summary>Pakistan time. Every "today" in this file means this.</summary>
    private static readonly TimeZoneInfo Local = ResolveLocalZone();

    private static TimeZoneInfo ResolveLocalZone()
    {
        foreach (var id in new[] { "Asia/Karachi", "Pakistan Standard Time" })
        {
            try { return TimeZoneInfo.FindSystemTimeZoneById(id); }
            catch (TimeZoneNotFoundException) { }
            catch (InvalidTimeZoneException) { }
        }

        // A container with no tz database still has to serve requests. UTC+5
        // is Pakistan all year — the country has observed no daylight saving
        // since 2009 — so this fallback is exact rather than approximate.
        return TimeZoneInfo.CreateCustomTimeZone(
            "UDrive/PKT", TimeSpan.FromHours(5), "Pakistan Time", "PKT");
    }

    private static DateTimeOffset NowLocal() =>
        TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, Local);

    /// <summary>Local midnight that opens the day <paramref name="moment"/> is in.</summary>
    /// <remarks>
    /// This exists because <c>DateTimeOffset.Date</c> hands back a plain
    /// <see cref="DateTime"/> with <c>Kind.Unspecified</c>, and the implicit
    /// conversion back to <see cref="DateTimeOffset"/> then stamps it with the
    /// *machine's* zone. On Railway the machine is UTC, so every local
    /// midnight silently became a UTC midnight — five hours adrift — and
    /// anything compared against it was wrong by those five hours.
    ///
    /// The peak-hour window is where that showed. For a 10pm–2am reward the
    /// "has tonight's window started yet" test read five hours early, so it
    /// always concluded the window belonged to the previous night. A driver
    /// working the peak hours was measured against last night's window, scored
    /// zero, and the reward could not be paid — not on some nights, on every
    /// night. Keeping the offset explicit here is the whole fix.
    /// </remarks>
    internal static DateTimeOffset LocalDayStart(DateTimeOffset moment) =>
        new(moment.Year, moment.Month, moment.Day, 0, 0, 0, moment.Offset);

    // ─────────────────────────────────────────────────────────────── the home

    public async Task<ServiceResult<DriverHomeDto>> HomeAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var driver = await DriverPresenceService.ResolveDriverAsync(
            connection, userId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<DriverHomeDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "This account does not have a driver profile.");
        }

        await DriverPresenceService.CloseStaleSessionsAsync(connection, cancellationToken);

        var metrics = await LoadMetricsAsync(
            connection, driver.Value.ProfileId, cancellationToken);

        await EvaluateAsync(connection, driver.Value, metrics, cancellationToken);

        var presence = await PresenceAsync(
            connection, driver.Value, cancellationToken);
        var welcome = await LoadWelcomeBonusAsync(
            connection, driver.Value, cancellationToken);
        var missions = await LoadMissionsAsync(
            connection, driver.Value, cancellationToken);
        var launch = await LoadLaunchAsync(
            connection, driver.Value.CityId, cancellationToken);
        var founding = await LoadFoundingAsync(
            connection, driver.Value, cancellationToken);
        var demand = await LoadDemandAsync(
            connection, driver.Value.CityId, cancellationToken);
        var updates = await LoadUpdatesAsync(
            connection, driver.Value.CityId, 5, cancellationToken);

        // The one mission worth the space on a home screen: the closest to
        // being finished among those still in progress. A list of five belongs
        // on the missions screen; the home screen answers "what am I in the
        // middle of".
        var active = missions
            .Where(m => m.Status == "InProgress" && m.TargetValue > 0)
            .OrderByDescending(m => m.ProgressValue / m.TargetValue)
            .FirstOrDefault()
            ?? missions.FirstOrDefault(m => m.Status == "Qualified");

        return ServiceResult<DriverHomeDto>.Ok(new DriverHomeDto(
            presence,
            metrics.EarningsToday,
            metrics.RidesToday,
            metrics.Rating,
            metrics.AcceptanceRate,
            metrics.AvailableBalance,
            metrics.BonusBalance,
            metrics.CommissionPercentage,
            active,
            welcome,
            launch,
            founding,
            demand,
            updates));
    }

    public async Task<ServiceResult<IReadOnlyList<MissionDto>>> MissionsAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var driver = await DriverPresenceService.ResolveDriverAsync(
            connection, userId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<IReadOnlyList<MissionDto>>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "This account does not have a driver profile.");
        }

        var metrics = await LoadMetricsAsync(
            connection, driver.Value.ProfileId, cancellationToken);
        await EvaluateAsync(connection, driver.Value, metrics, cancellationToken);

        return ServiceResult<IReadOnlyList<MissionDto>>.Ok(
            await LoadMissionsAsync(connection, driver.Value, cancellationToken));
    }

    public async Task<ServiceResult<WelcomeBonusDto?>> WelcomeBonusAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var driver = await DriverPresenceService.ResolveDriverAsync(
            connection, userId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<WelcomeBonusDto?>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "This account does not have a driver profile.");
        }

        var metrics = await LoadMetricsAsync(
            connection, driver.Value.ProfileId, cancellationToken);
        await EvaluateAsync(connection, driver.Value, metrics, cancellationToken);

        return ServiceResult<WelcomeBonusDto?>.Ok(
            await LoadWelcomeBonusAsync(connection, driver.Value, cancellationToken));
    }

    public async Task<ServiceResult<ReferralSummaryDto>> ReferralAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var driver = await DriverPresenceService.ResolveDriverAsync(
            connection, userId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<ReferralSummaryDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "This account does not have a driver profile.");
        }

        var code = await EnsureReferralCodeAsync(
            connection, driver.Value.ProfileId, cancellationToken);

        const string sql = """
            SELECT r.id, COALESCE(u.full_name, 'Driver'), r.status,
                   r.verified_at, r.first_ride_at,
                   COALESCE(earned.amount, 0), COALESCE(pending.amount, 0)
            FROM udrive.driver_referrals r
            JOIN udrive.driver_profiles p ON p.id = r.referred_driver_profile_id
            LEFT JOIN udrive.users u ON u.id = p.user_id
            LEFT JOIN LATERAL (
                SELECT SUM(g.reward_amount) AS amount
                FROM udrive.driver_campaign_progress g
                WHERE g.driver_profile_id = r.referrer_driver_profile_id
                  AND g.campaign_id = r.campaign_id
                  AND g.status = 'Credited'
            ) AS earned ON true
            LEFT JOIN LATERAL (
                SELECT SUM(g.reward_amount) AS amount
                FROM udrive.driver_campaign_progress g
                WHERE g.driver_profile_id = r.referrer_driver_profile_id
                  AND g.campaign_id = r.campaign_id
                  AND g.status IN ('InProgress', 'Qualified')
            ) AS pending ON true
            WHERE r.referrer_driver_profile_id = @driver
            ORDER BY r.created_at DESC
            LIMIT 100;
            """;

        var entries = new List<ReferralEntryDto>();
        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("driver", driver.Value.ProfileId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                entries.Add(new ReferralEntryDto(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetFieldValue<DateTimeOffset>(3),
                    reader.IsDBNull(4) ? null : reader.GetFieldValue<DateTimeOffset>(4),
                    reader.GetDecimal(5),
                    reader.GetDecimal(6)));
            }
        }

        return ServiceResult<ReferralSummaryDto>.Ok(new ReferralSummaryDto(
            code,
            entries.Count,
            entries.Count(e => e.VerifiedAt is not null),
            entries.Count(e => e.Status == "Active"),
            entries.Sum(e => e.RewardEarned),
            entries.Sum(e => e.RewardPending),
            entries));
    }

    /// <summary>This week's target, and what last week came to.</summary>
    /// <remarks>
    /// The engine has understood <c>WeeklyReward</c> from the start — it has a
    /// period key, an expiry that lands on Monday, and a place in every list of
    /// campaign types. What it never had was anywhere to appear. A target a
    /// Driver cannot see is not a target; it is a rule the platform applies to
    /// them privately, and nobody changes their week for one of those.
    ///
    /// Last week is here as well, and deliberately short: what was earned, how
    /// many rides, whether the reward landed, and the single day that paid
    /// best. That last line is the only part a Driver can act on — it tells
    /// them which day to keep clear next week.
    /// </remarks>
    public async Task<ServiceResult<DriverWeeklyDto>> WeeklyAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var driver = await DriverPresenceService.ResolveDriverAsync(
            connection, userId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<DriverWeeklyDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "This account does not have a driver profile.");
        }

        // Weeks run Monday to Sunday in Pakistan time, which is also what the
        // engine's ISO period key buckets by. Measuring either of them in UTC
        // would put Sunday night's rides in the wrong week for every driver.
        const string sql = """
            WITH bounds AS (
                SELECT date_trunc('week', now() AT TIME ZONE 'Asia/Karachi') AS this_start,
                       date_trunc('week', now() AT TIME ZONE 'Asia/Karachi')
                           - interval '7 days' AS last_start
            ),
            rides AS (
                SELECT b.updated_at AT TIME ZONE 'Asia/Karachi' AS at,
                       COALESCE(e.net_amount, 0) AS net
                FROM udrive.bookings b
                LEFT JOIN udrive.driver_earnings e ON e.booking_id = b.id
                WHERE b.driver_profile_id = @driver
                  AND b.status = 'Completed'
            )
            SELECT
                (SELECT count(*) FROM rides, bounds
                  WHERE rides.at >= bounds.this_start),
                (SELECT count(*) FROM rides, bounds
                  WHERE rides.at >= bounds.last_start AND rides.at < bounds.this_start),
                (SELECT COALESCE(sum(net), 0) FROM rides, bounds
                  WHERE rides.at >= bounds.last_start AND rides.at < bounds.this_start),
                (SELECT COALESCE(sum(s.credited_seconds), 0)::int
                   FROM udrive.driver_online_sessions s, bounds
                  WHERE s.driver_profile_id = @driver
                    AND s.started_at AT TIME ZONE 'Asia/Karachi' >= bounds.last_start
                    AND s.started_at AT TIME ZONE 'Asia/Karachi' < bounds.this_start),
                (SELECT to_char(bounds.this_start + interval '7 days', 'YYYY-MM-DD')
                   FROM bounds);
            """;

        int ridesThisWeek, ridesLastWeek, onlineLastWeek;
        decimal earningsLastWeek;

        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("driver", driver.Value.ProfileId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            await reader.ReadAsync(cancellationToken);
            ridesThisWeek = (int)reader.GetInt64(0);
            ridesLastWeek = (int)reader.GetInt64(1);
            earningsLastWeek = reader.GetDecimal(2);
            onlineLastWeek = reader.GetInt32(3);
        }

        // Best day of last week, as a day name and its two numbers.
        const string bestSql = """
            SELECT to_char(day, 'FMDay'), COALESCE(sum(net), 0), count(*)
            FROM (
                SELECT date_trunc('day', b.updated_at AT TIME ZONE 'Asia/Karachi') AS day,
                       COALESCE(e.net_amount, 0) AS net
                FROM udrive.bookings b
                LEFT JOIN udrive.driver_earnings e ON e.booking_id = b.id
                WHERE b.driver_profile_id = @driver
                  AND b.status = 'Completed'
                  AND b.updated_at AT TIME ZONE 'Asia/Karachi'
                      >= date_trunc('week', now() AT TIME ZONE 'Asia/Karachi')
                         - interval '7 days'
                  AND b.updated_at AT TIME ZONE 'Asia/Karachi'
                      < date_trunc('week', now() AT TIME ZONE 'Asia/Karachi')
            ) AS d
            GROUP BY day
            ORDER BY 2 DESC
            LIMIT 1;
            """;

        string? bestDay = null;
        decimal bestDayEarnings = 0;
        var bestDayRides = 0;

        await using (var command = new NpgsqlCommand(bestSql, connection))
        {
            command.Parameters.AddWithValue("driver", driver.Value.ProfileId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                bestDay = reader.GetString(0).Trim();
                bestDayEarnings = reader.GetDecimal(1);
                bestDayRides = (int)reader.GetInt64(2);
            }
        }

        // The live weekly campaign, if the city has one, and whether this week's
        // and last week's awards landed.
        const string campaignSql = """
            SELECT c.id, c.reward_amount,
                   COALESCE(MAX(m.condition_value), c.min_completed_rides, 0)::int,
                   bool_or(g.status = 'Credited' AND g.period_key = @thisWeek),
                   bool_or(g.status = 'Credited' AND g.period_key = @lastWeek),
                   COALESCE(MAX(g.reward_amount) FILTER (
                       WHERE g.period_key = @lastWeek AND g.status = 'Credited'), 0)
            FROM udrive.growth_campaigns c
            JOIN udrive.launch_cities city ON city.id = c.launch_city_id
            LEFT JOIN udrive.growth_campaign_milestones m ON m.campaign_id = c.id
            LEFT JOIN udrive.driver_campaign_progress g
                   ON g.campaign_id = c.id AND g.driver_profile_id = @driver
            WHERE c.campaign_type = 'WeeklyReward'
              AND c.is_active AND city.is_active
              AND city.id = @city
              AND (c.starts_at IS NULL OR c.starts_at <= now())
              AND (c.ends_at IS NULL OR c.ends_at >= now())
            GROUP BY c.id, c.reward_amount, c.min_completed_rides
            ORDER BY c.created_at
            LIMIT 1;
            """;

        int? target = null;
        decimal reward = 0, lastWeekReward = 0;
        bool earned = false, lastWeekEarned = false;

        if (driver.Value.CityId is not null)
        {
            var now = NowLocal();
            await using var command = new NpgsqlCommand(campaignSql, connection);
            command.Parameters.AddWithValue("driver", driver.Value.ProfileId);
            command.Parameters.AddWithValue("city", driver.Value.CityId.Value);
            command.Parameters.AddWithValue("thisWeek", IsoWeek(now));
            command.Parameters.AddWithValue("lastWeek", IsoWeek(now.AddDays(-7)));

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                reward = reader.GetDecimal(1);
                var configured = reader.GetInt32(2);
                target = configured > 0 ? configured : null;
                earned = !reader.IsDBNull(3) && reader.GetBoolean(3);
                lastWeekEarned = !reader.IsDBNull(4) && reader.GetBoolean(4);
                lastWeekReward = reader.GetDecimal(5);
            }
        }

        var localNow = NowLocal();
        return ServiceResult<DriverWeeklyDto>.Ok(new DriverWeeklyDto(
            IsoWeek(localNow),
            target,
            ridesThisWeek,
            reward,
            earned,
            LocalDayStart(localNow).AddDays(
                localNow.DayOfWeek == DayOfWeek.Sunday ? 1 : 8 - (int)localNow.DayOfWeek),
            earningsLastWeek,
            ridesLastWeek,
            onlineLastWeek,
            lastWeekReward,
            lastWeekEarned,
            bestDay,
            bestDayEarnings,
            bestDayRides));
    }

    /// <summary>The same ISO week string the engine uses as a period key.</summary>
    private static string IsoWeek(DateTimeOffset moment) => string.Create(
        CultureInfo.InvariantCulture,
        $"{ISOWeek.GetYear(moment.DateTime)}-W{ISOWeek.GetWeekOfYear(moment.DateTime):00}");

    public async Task<ServiceResult<IReadOnlyList<ExpectedDemandDto>>> DemandAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var driver = await DriverPresenceService.ResolveDriverAsync(
            connection, userId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<IReadOnlyList<ExpectedDemandDto>>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "This account does not have a driver profile.");
        }

        return ServiceResult<IReadOnlyList<ExpectedDemandDto>>.Ok(
            await LoadDemandAsync(connection, driver.Value.CityId, cancellationToken));
    }

    public async Task<ServiceResult<IReadOnlyList<DriverUpdateDto>>> UpdatesAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var driver = await DriverPresenceService.ResolveDriverAsync(
            connection, userId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<IReadOnlyList<DriverUpdateDto>>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "This account does not have a driver profile.");
        }

        return ServiceResult<IReadOnlyList<DriverUpdateDto>>.Ok(
            await LoadUpdatesAsync(connection, driver.Value.CityId, 50, cancellationToken));
    }

    // ─────────────────────────────────────────────────────────────── earnings

    /// <summary>Today, this week and this month — and where the money came from.</summary>
    /// <remarks>
    /// Every figure here is measured from rows that exist: completed trips in
    /// driver_earnings, credited rewards in driver_wallet_entries, credited
    /// seconds in driver_online_sessions. Nothing is projected, averaged from a
    /// sample, or rounded up to look encouraging. A Driver who cannot trust this
    /// screen has no way to tell whether driving for UDrive is worth their fuel.
    /// </remarks>
    public async Task<ServiceResult<DriverEarningsDto>> EarningsAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var driver = await DriverPresenceService.ResolveDriverAsync(
            connection, userId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<DriverEarningsDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "This account does not have a driver profile.");
        }

        var now = NowLocal();
        var today = LocalDayStart(now);
        var monday = today.AddDays(
            now.DayOfWeek == DayOfWeek.Sunday ? -6 : 1 - (int)now.DayOfWeek);
        var firstOfMonth = new DateTimeOffset(
            now.Year, now.Month, 1, 0, 0, 0, now.Offset);

        var periods = new List<EarningsPeriodDto>();
        foreach (var (label, from, to) in new[]
        {
            ("Today", today, today.AddDays(1)),
            ("This week", monday, monday.AddDays(7)),
            ("This month", firstOfMonth, firstOfMonth.AddMonths(1)),
        })
        {
            periods.Add(await LoadPeriodAsync(
                connection, driver.Value.ProfileId, label, from, to,
                cancellationToken));
        }

        var metrics = await LoadMetricsAsync(
            connection, driver.Value.ProfileId, cancellationToken);

        return ServiceResult<DriverEarningsDto>.Ok(new DriverEarningsDto(
            periods[0],
            periods[1],
            periods[2],
            metrics.CommissionPercentage,
            metrics.BonusBalance,
            metrics.AvailableBalance,
            await PendingBalanceAsync(
                connection, driver.Value.ProfileId, cancellationToken),
            await LoadWaysToEarnAsync(
                connection, driver.Value, metrics, cancellationToken)));
    }

    /// <summary>How little online time still gives an honest hourly figure.</summary>
    /// <remarks>
    /// Fifteen minutes. One good fare in four minutes online works out to
    /// thousands an hour, and a Driver who reads that and plans their week
    /// around it has been misled by their own earnings screen.
    /// </remarks>
    private const int MinSecondsForPerHour = 900;

    private static async Task<EarningsPeriodDto> LoadPeriodAsync(
        NpgsqlConnection connection,
        Guid driverProfileId,
        string label,
        DateTimeOffset from,
        DateTimeOffset to,
        CancellationToken cancellationToken)
    {
        // One round trip for the whole period. Three periods on a phone is
        // three round trips already; twelve would be the screen's whole budget.
        const string sql = """
            SELECT
                -- Fares. created_at, not available_at: a Driver counts a fare
                -- on the day they drove it, not on the day it clears.
                COALESCE((SELECT SUM(e.net_amount) FROM udrive.driver_earnings e
                           WHERE e.driver_profile_id = @driver
                             AND e.created_at >= @from AND e.created_at < @to), 0),
                COALESCE((SELECT SUM(e.gross_amount) FROM udrive.driver_earnings e
                           WHERE e.driver_profile_id = @driver
                             AND e.created_at >= @from AND e.created_at < @to), 0),
                COALESCE((SELECT SUM(e.commission_amount) FROM udrive.driver_earnings e
                           WHERE e.driver_profile_id = @driver
                             AND e.created_at >= @from AND e.created_at < @to), 0),
                (SELECT count(*) FROM udrive.driver_earnings e
                  WHERE e.driver_profile_id = @driver
                    AND e.created_at >= @from AND e.created_at < @to),

                -- Rewards actually credited. Positive Bonus entries only, so a
                -- correction an admin had to make does not read as earnings.
                COALESCE((SELECT SUM(w.amount)
                            FROM udrive.driver_wallet_entries w
                            JOIN udrive.driver_wallets dw ON dw.id = w.wallet_id
                           WHERE dw.driver_profile_id = @driver
                             AND w.entry_type = 'Bonus'
                             AND w.amount > 0
                             AND w.created_at >= @from AND w.created_at < @to), 0),

                -- Online time, counting only the part inside the window: a
                -- session that began last night contributes its morning hours
                -- to today and its evening hours to yesterday.
                COALESCE((SELECT SUM(LEAST(
                            GREATEST(0, EXTRACT(EPOCH FROM (
                                LEAST(COALESCE(s.ended_at, now()), @to)
                                - GREATEST(s.started_at, @from))))::int,
                            s.credited_seconds))
                          FROM udrive.driver_online_sessions s
                          WHERE s.driver_profile_id = @driver
                            AND s.started_at < @to
                            AND COALESCE(s.ended_at, now()) > @from), 0);
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driver", driverProfileId);
        command.Parameters.AddWithValue("from", from);
        command.Parameters.AddWithValue("to", to);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return new EarningsPeriodDto(label, from, to, 0, 0, 0, 0, 0, 0, null);
        }

        var rideNet = reader.GetDecimal(0);
        var bonus = reader.GetDecimal(4);
        var seconds = Convert.ToInt32(reader.GetValue(5));

        return new EarningsPeriodDto(
            label,
            from,
            to,
            rideNet,
            reader.GetDecimal(1),
            reader.GetDecimal(2),
            bonus,
            (int)reader.GetInt64(3),
            seconds,
            seconds >= MinSecondsForPerHour
                ? Math.Round((rideNet + bonus) / (seconds / 3600m), 0)
                : null);
    }

    private static async Task<decimal> PendingBalanceAsync(
        NpgsqlConnection connection,
        Guid driverProfileId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT COALESCE(pending_balance, 0) FROM udrive.driver_wallets
            WHERE driver_profile_id = @driver;
            """,
            connection);
        command.Parameters.AddWithValue("driver", driverProfileId);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is null or DBNull ? 0 : Convert.ToDecimal(result);
    }

    /// <summary>Every live way this Driver can earn, from configured campaigns.</summary>
    /// <remarks>
    /// The specification is explicit: no fake earning numbers, and no guaranteed
    /// income unless an Admin has configured and funded that guarantee. So this
    /// list is assembled from rows — the commission rate in settings, the
    /// campaigns live in this Driver's city, the tour packages they may publish
    /// — and a Driver in a city with no campaigns sees the two routes that
    /// always exist and no invented third.
    /// </remarks>
    private static async Task<List<WayToEarnDto>> LoadWaysToEarnAsync(
        NpgsqlConnection connection,
        DriverPresenceService.DriverContext driver,
        DriverMetrics metrics,
        CancellationToken cancellationToken)
    {
        var ways = new List<WayToEarnDto>
        {
            new("Rides",
                "Ride fares",
                $"You keep {100 - metrics.CommissionPercentage:0.##}% of every "
                + "fare. The rest is commission, taken from your wallet.",
                null,
                null),
            new("Tour",
                "Tour packages",
                "Publish a multi-day package and set your own price. Admin "
                + "approves the route and pricing before it goes live.",
                null,
                "driverPackages"),
        };

        if (driver.CityId is null) return ways;

        // Live campaigns, described by what they actually pay. A campaign paid
        // through milestones reports the sum of them, because that is the figure
        // a Driver would otherwise have to add up themselves.
        const string sql = """
            SELECT c.campaign_type, c.title, c.description,
                   c.reward_amount,
                   COALESCE((SELECT SUM(m.reward_amount)
                               FROM udrive.growth_campaign_milestones m
                              WHERE m.campaign_id = c.id), 0) AS milestone_total,
                   c.daily_start_time, c.daily_end_time, c.driver_segment
            FROM udrive.growth_campaigns c
            JOIN udrive.launch_cities city ON city.id = c.launch_city_id
            WHERE c.is_active
              AND city.is_active
              AND city.id = @city
              AND (c.starts_at IS NULL OR c.starts_at <= now())
              AND (c.ends_at IS NULL OR c.ends_at >= now())
            ORDER BY c.campaign_type, c.created_at;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("city", driver.CityId.Value);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            var type = reader.GetString(0);
            var title = reader.GetString(1);
            var description = reader.IsDBNull(2) ? null : reader.GetString(2);
            var reward = reader.GetDecimal(3);
            var milestoneTotal = reader.GetDecimal(4);
            var segment = reader.GetString(7);

            // A campaign aimed at a segment this Driver is not in is not a way
            // for them to earn, and listing it is the same false promise as
            // inventing one.
            if (!MatchesSegment(
                    new CampaignRow(
                        Guid.Empty, type, title, description, reward,
                        null, null, null, null, Array.Empty<int>(), segment,
                        null, null, null, null, null, null, 1, null, null, null),
                    metrics))
            {
                continue;
            }

            var amount = milestoneTotal > 0 ? milestoneTotal : reward;
            var detail = description;

            if (type == "PeakHourReward"
                && !reader.IsDBNull(5) && !reader.IsDBNull(6))
            {
                var window = $"{reader.GetTimeSpan(5):hh\\:mm}"
                           + $"–{reader.GetTimeSpan(6):hh\\:mm}";
                detail = string.IsNullOrWhiteSpace(description)
                    ? $"Drive between {window}."
                    : $"{description} ({window})";
            }

            ways.Add(new WayToEarnDto(
                type,
                title,
                detail ?? "Open the rewards screen for what this needs.",
                amount > 0 ? amount : null,
                type switch
                {
                    "WelcomeBonus" => "driverWelcomeBonus",
                    "Referral" => "driverReferrals",
                    "FoundingBenefit" => "driverFounding",
                    _ => "driverMissions",
                }));
        }

        return ways;
    }

    // ───────────────────────────────────────────────────────────────  metrics

    internal readonly record struct DriverMetrics(
        string VerificationStatus,
        DateTimeOffset? ApprovedAt,
        bool ProfileComplete,
        bool VehicleApproved,
        int RidesTotal,
        int RidesToday,
        int OnlineSecondsToday,
        decimal EarningsToday,
        decimal Rating,
        decimal? AcceptanceRate,
        decimal AvailableBalance,
        decimal BonusBalance,
        int ReferralsVerified,
        int ReferralsFirstRide,
        int ReferralsActive,
        decimal CommissionPercentage,

        /// <summary>A live, unrevoked row in founding_drivers.</summary>
        bool IsFoundingDriver,

        /// <summary>Their last completed ride, or null if they never had one.</summary>
        DateTimeOffset? LastRideAt,

        /// <summary>Rides this driver cancelled today, Pakistan time.</summary>
        int CancellationsToday);

    private static async Task<DriverMetrics> LoadMetricsAsync(
        NpgsqlConnection connection,
        Guid driverProfileId,
        CancellationToken cancellationToken)
    {
        // One round trip. Each of these is cheap on its own and ruinous as ten
        // separate calls from a phone on a mountain road.
        const string sql = """
            SELECT
                p.verification_status,
                p.approved_at,
                (p.residential_address IS NOT NULL
                 AND p.emergency_contact_phone IS NOT NULL
                 AND p.payout_method IS NOT NULL) AS profile_complete,
                -- 'Verified' or 'Approved', either case: the admin panel writes
                -- one, the API's own checks accept both, and matching only the
                -- exact string 'Approved' here meant a driver whose vehicle had
                -- been verified never completed the VehicleApproved milestone.
                -- Their welcome bonus stopped on that step and stayed there.
                EXISTS (SELECT 1 FROM udrive.vehicles v
                        WHERE v.driver_profile_id = p.id
                          AND lower(v.status) IN ('verified', 'approved')),
                (SELECT count(*) FROM udrive.trip_assignments ta
                   JOIN udrive.trip_operations t ON t.booking_id = ta.booking_id
                  WHERE ta.driver_profile_id = p.id
                    AND t.trip_status = 'TripCompleted'),
                (SELECT count(*) FROM udrive.trip_assignments ta
                   JOIN udrive.trip_operations t ON t.booking_id = ta.booking_id
                  WHERE ta.driver_profile_id = p.id
                    AND t.trip_status = 'TripCompleted'
                    AND (t.completed_at AT TIME ZONE 'Asia/Karachi')::date
                        = (now() AT TIME ZONE 'Asia/Karachi')::date),
                (SELECT COALESCE(SUM(s.credited_seconds), 0)
                   FROM udrive.driver_online_sessions s
                  WHERE s.driver_profile_id = p.id
                    AND (s.started_at AT TIME ZONE 'Asia/Karachi')::date
                        = (now() AT TIME ZONE 'Asia/Karachi')::date),
                (SELECT COALESCE(SUM(e.net_amount), 0)
                   FROM udrive.driver_earnings e
                  WHERE e.driver_profile_id = p.id
                    AND (e.created_at AT TIME ZONE 'Asia/Karachi')::date
                        = (now() AT TIME ZONE 'Asia/Karachi')::date),
                p.average_rating,
                (SELECT CASE
                          WHEN count(*) FILTER (
                               WHERE d.decision IN ('Accepted', 'Rejected')) = 0
                          THEN NULL
                          ELSE round(100.0
                               * count(*) FILTER (WHERE d.decision = 'Accepted')
                               / count(*) FILTER (
                                   WHERE d.decision IN ('Accepted', 'Rejected')), 2)
                        END
                   FROM udrive.driver_ride_request_decisions d
                  WHERE d.driver_profile_id = p.id
                    AND d.updated_at > now() - interval '14 days'),
                COALESCE(w.available_balance, 0),
                COALESCE(w.commission_balance, 0),
                (SELECT count(*) FROM udrive.driver_referrals r
                  WHERE r.referrer_driver_profile_id = p.id
                    AND r.verified_at IS NOT NULL),
                (SELECT count(*) FROM udrive.driver_referrals r
                  WHERE r.referrer_driver_profile_id = p.id
                    AND r.first_ride_at IS NOT NULL),
                (SELECT count(*) FROM udrive.driver_referrals r
                  WHERE r.referrer_driver_profile_id = p.id
                    AND r.active_at IS NOT NULL),
                -- The same setting the wallet screen reads, clamped the same
                -- way. Read here so the request card can show a net figure
                -- without a second round trip.
                COALESCE((SELECT LEAST(40, GREATEST(0,
                            (s.value_json #>> '{}')::numeric))
                          FROM udrive.system_settings s
                          WHERE s.key = 'driver.commission.percentage'), 10),
                -- Founding status, for the Founding segment. A revoked row is
                -- not a founding driver any more.
                EXISTS (SELECT 1 FROM udrive.founding_drivers f
                        WHERE f.driver_profile_id = p.id
                          AND f.revoked_at IS NULL),
                -- Last completed ride, for the Inactive segment.
                (SELECT MAX(t.completed_at)
                   FROM udrive.trip_assignments ta
                   JOIN udrive.trip_operations t ON t.booking_id = ta.booking_id
                  WHERE ta.driver_profile_id = p.id
                    AND t.trip_status = 'TripCompleted'),
                -- Rides this driver called off today, for max_cancellations.
                -- Read from the status history because that is the only place
                -- that records *who* cancelled; the booking row only knows that
                -- someone did.
                (SELECT count(*)
                   FROM udrive.trip_status_history h
                   JOIN udrive.trip_assignments ta
                     ON ta.booking_id = h.booking_id
                  WHERE ta.driver_profile_id = p.id
                    AND h.source = 'Driver'
                    AND h.to_status IN ('Cancelled', 'NoShow')
                    AND (h.created_at AT TIME ZONE 'Asia/Karachi')::date
                        = (now() AT TIME ZONE 'Asia/Karachi')::date)
            FROM udrive.driver_profiles p
            LEFT JOIN udrive.driver_wallets w ON w.driver_profile_id = p.id
            WHERE p.id = @driver;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driver", driverProfileId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return new DriverMetrics(
                "Unknown", null, false, false, 0, 0, 0, 0m, 0m, null, 0m, 0m,
                0, 0, 0, 10m, false, null, 0);
        }

        return new DriverMetrics(
            reader.GetString(0),
            reader.IsDBNull(1) ? null : reader.GetFieldValue<DateTimeOffset>(1),
            reader.GetBoolean(2),
            reader.GetBoolean(3),
            (int)reader.GetInt64(4),
            (int)reader.GetInt64(5),
            reader.GetInt32(6),
            reader.GetDecimal(7),
            reader.GetDecimal(8),
            reader.IsDBNull(9) ? null : reader.GetDecimal(9),
            reader.GetDecimal(10),
            reader.GetDecimal(11),
            (int)reader.GetInt64(12),
            (int)reader.GetInt64(13),
            (int)reader.GetInt64(14),
            reader.GetDecimal(15),
            reader.GetBoolean(16),
            reader.IsDBNull(17) ? null : reader.GetFieldValue<DateTimeOffset>(17),
            (int)reader.GetInt64(18));
    }

    // ────────────────────────────────────────────────────────────── the engine

    internal sealed record CampaignRow(
        Guid Id,
        string CampaignType,
        string Title,
        string? Description,
        decimal RewardAmount,
        DateTimeOffset? StartsAt,
        DateTimeOffset? EndsAt,
        TimeSpan? DailyStart,
        TimeSpan? DailyEnd,
        int[] DaysOfWeek,
        string DriverSegment,
        int? MinOnlineSeconds,
        int? MinCompletedRides,
        int? MinAcceptedRides,
        int? MaxCancellations,
        decimal? MinRating,
        decimal? MinAcceptanceRate,
        int MaxAwards,
        decimal? TotalBudget,
        Guid? ZoneId,
        string? ZoneName);

    private sealed record MilestoneRow(
        Guid Id,
        Guid CampaignId,
        int SortOrder,
        string Title,
        string? Description,
        decimal RewardAmount,
        string ConditionType,
        decimal ConditionValue);

    /// <summary>
    /// Brings every live campaign up to date for one driver, and credits the
    /// ones that have been earned.
    /// </summary>
    private static async Task EvaluateAsync(
        NpgsqlConnection connection,
        DriverPresenceService.DriverContext driver,
        DriverMetrics metrics,
        CancellationToken cancellationToken)
    {
        var campaigns = await LoadLiveCampaignsAsync(
            connection, driver, metrics, cancellationToken);

        // Note what is NOT here any more: an early return when there are no
        // live campaigns.
        //
        // Crediting used to sit at the bottom of this method, after that
        // return. So a reward already earned and sitting at 'Qualified' was
        // only ever paid on a visit where the driver *also* had a live
        // campaign. Finish a peak-hour reward at 1:59am and the window closes
        // at 2am: from then on there is no live campaign, the method returns
        // early, and the money is never moved. The one that mattered most was
        // a driver whose only campaign was switched off by an admin the next
        // morning — earned the night before, never paid, and nothing in the
        // app or the panel to show it had been withheld.
        if (campaigns.Count > 0)
        {
            await MeasureCampaignsAsync(
                connection, driver, metrics, campaigns, cancellationToken);
        }

        // Referral is reconciled rather than measured: the pass asks the
        // database which of this driver's invitees have since been verified,
        // taken a ride or become active, stamps those dates, and writes the
        // reward rows. It runs here so the money arrives the next time the
        // driver so much as opens the app, with no hook in admin verification
        // or trip completion to be forgotten or routed around.
        await DriverReferralService.SyncAsync(
            connection, driver.ProfileId, cancellationToken);

        await CreditQualifiedAsync(
            connection, driver.ProfileId, metrics, cancellationToken);
    }

    private static async Task MeasureCampaignsAsync(
        NpgsqlConnection connection,
        DriverPresenceService.DriverContext driver,
        DriverMetrics metrics,
        List<CampaignRow> campaigns,
        CancellationToken cancellationToken)
    {
        var milestones = await LoadMilestonesAsync(
            connection, campaigns.Select(c => c.Id).ToArray(), cancellationToken);

        foreach (var campaign in campaigns)
        {
            // Referral is measured by DriverReferralService, not here.
            //
            // Its rewards are written one per referred driver, keyed by that
            // driver's id. Letting the generic loop run as well would add a
            // second row keyed '-' measuring "referrals >= 1", which pays a
            // referrer once in their life on top of the per-person rewards —
            // the same money twice, for the first invitee only.
            if (campaign.CampaignType == "Referral") continue;

            var period = PeriodKey(campaign);
            var expires = PeriodExpiry(campaign);
            var campaignMilestones = milestones
                .Where(m => m.CampaignId == campaign.Id)
                .OrderBy(m => m.SortOrder)
                .ToList();

            if (campaignMilestones.Count > 0)
            {
                foreach (var milestone in campaignMilestones)
                {
                    var progress = await MeasureAsync(
                        connection, driver, metrics, campaign,
                        milestone.ConditionType, cancellationToken);

                    await UpsertProgressAsync(
                        connection, driver.ProfileId, campaign.Id, milestone.Id,
                        period, progress, milestone.ConditionValue,
                        milestone.RewardAmount, expires,
                        $"{campaign.Title} — {milestone.Title}", cancellationToken);
                }

                continue;
            }

            // A campaign with no milestones is one condition expressed through
            // the campaign's own minimums. Online time is the headline; the rest
            // are gates, checked at crediting time.
            var target = campaign.MinOnlineSeconds
                ?? campaign.MinCompletedRides
                ?? campaign.MinAcceptedRides
                ?? 1;

            var value = campaign.MinOnlineSeconds is not null
                ? await WindowOnlineSecondsAsync(
                    connection, driver.ProfileId, campaign, cancellationToken)
                : campaign.MinCompletedRides is not null
                    ? await WindowCompletedRidesAsync(
                        connection, driver.ProfileId, campaign, cancellationToken)
                    : await WindowAcceptedRidesAsync(
                        connection, driver.ProfileId, campaign, cancellationToken);

            await UpsertProgressAsync(
                connection, driver.ProfileId, campaign.Id, null, period,
                value, target, campaign.RewardAmount, expires,
                campaign.Title, cancellationToken);
        }
    }

    private static async Task<List<CampaignRow>> LoadLiveCampaignsAsync(
        NpgsqlConnection connection,
        DriverPresenceService.DriverContext driver,
        DriverMetrics metrics,
        CancellationToken cancellationToken)
    {
        // A campaign reaches a driver only through an active city. That is the
        // city switch: nothing offered, nothing measured, nothing paid until an
        // admin turns a city on.
        const string sql = """
            SELECT c.id, c.campaign_type, c.title, c.description, c.reward_amount,
                   c.starts_at, c.ends_at, c.daily_start_time, c.daily_end_time,
                   c.days_of_week, c.driver_segment,
                   c.min_online_seconds, c.min_completed_rides, c.min_accepted_rides,
                   c.max_cancellations, c.min_rating, c.min_acceptance_rate,
                   c.max_awards_per_driver, c.total_budget, c.zone_id, z.name
            FROM udrive.growth_campaigns c
            JOIN udrive.launch_cities city ON city.id = c.launch_city_id
            LEFT JOIN udrive.pricing_zones z ON z.id = c.zone_id
            WHERE c.is_active
              AND city.is_active
              AND city.id = @city
              AND (c.starts_at IS NULL OR c.starts_at <= now())
              AND (c.ends_at IS NULL OR c.ends_at >= now())
              -- Every type an admin can save. This list used to stop at
              -- 'Referral', so a WeeklyReward or a Reactivation campaign could
              -- be created, funded and switched on in the admin panel and then
              -- sat there measuring nothing for ever — no progress row, no
              -- payment, and no error anywhere to say why.
              AND c.campaign_type IN
                  ('WelcomeBonus', 'DailyMission', 'PeakHourReward', 'Referral',
                   'WeeklyReward', 'Reactivation', 'FoundingBenefit')
            ORDER BY c.campaign_type, c.created_at;
            """;

        var rows = new List<CampaignRow>();
        if (driver.CityId is null) return rows;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("city", driver.CityId.Value);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            var days = reader.IsDBNull(9)
                ? Array.Empty<int>()
                : reader.GetFieldValue<short[]>(9).Select(d => (int)d).ToArray();

            rows.Add(new CampaignRow(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetString(3),
                reader.GetDecimal(4),
                reader.IsDBNull(5) ? null : reader.GetFieldValue<DateTimeOffset>(5),
                reader.IsDBNull(6) ? null : reader.GetFieldValue<DateTimeOffset>(6),
                reader.IsDBNull(7) ? null : reader.GetTimeSpan(7),
                reader.IsDBNull(8) ? null : reader.GetTimeSpan(8),
                days,
                reader.GetString(10),
                reader.IsDBNull(11) ? null : reader.GetInt32(11),
                reader.IsDBNull(12) ? null : reader.GetInt32(12),
                reader.IsDBNull(13) ? null : reader.GetInt32(13),
                reader.IsDBNull(14) ? null : reader.GetInt32(14),
                reader.IsDBNull(15) ? null : reader.GetDecimal(15),
                reader.IsDBNull(16) ? null : reader.GetDecimal(16),
                reader.GetInt32(17),
                reader.IsDBNull(18) ? null : reader.GetDecimal(18),
                reader.IsDBNull(19) ? null : reader.GetGuid(19),
                reader.IsDBNull(20) ? null : reader.GetString(20)));
        }

        var now = NowLocal();
        return rows.Where(c => MatchesSegment(c, metrics) && MatchesDay(c, now)).ToList();
    }

    /// <summary>How many days of silence makes a driver inactive.</summary>
    /// <remarks>
    /// Fourteen. Short enough that the reactivation nudge still means
    /// something, long enough that a driver away for Eid or a week of rain is
    /// not "won back" with the company's money for coming to work.
    /// </remarks>
    private const int InactiveAfterDays = 14;

    /// <remarks>
    /// Founding and Inactive used to return <c>true</c> with a comment
    /// promising they were narrowed somewhere else. They were not: nothing
    /// anywhere joined founding_drivers or looked at a last-ride date at
    /// crediting time. So a campaign aimed at the city's founding drivers paid
    /// every driver in the city, and a reactivation bonus meant to win back
    /// drivers who had stopped was paid to the ones who had never stopped — the
    /// two most expensive campaign types to get wrong, both wide open.
    /// </remarks>
    internal static bool MatchesSegment(CampaignRow campaign, DriverMetrics metrics) =>
        campaign.DriverSegment switch
        {
            // "New" is measured from approval, not from registration. A driver
            // who signed up in July and was approved yesterday is new today.
            "New" => metrics.ApprovedAt is not null
                     && metrics.ApprovedAt > DateTimeOffset.UtcNow.AddDays(-30),

            // A founding driver is a row in founding_drivers that has not been
            // revoked. Nothing else counts, whatever an admin wishes.
            "Founding" => metrics.IsFoundingDriver,

            // Inactive means they have actually been away: no completed ride
            // for InactiveAfterDays, or never a ride at all since approval.
            "Inactive" => metrics.LastRideAt is null
                ? metrics.ApprovedAt is not null
                  && metrics.ApprovedAt
                     < DateTimeOffset.UtcNow.AddDays(-InactiveAfterDays)
                : metrics.LastRideAt
                  < DateTimeOffset.UtcNow.AddDays(-InactiveAfterDays),

            _ => true,
        };

    private static bool MatchesDay(CampaignRow campaign, DateTimeOffset now) =>
        campaign.DaysOfWeek.Length == 0
        || campaign.DaysOfWeek.Contains((int)now.DayOfWeek);

    /// <summary>
    /// Which bucket of time this award belongs to — the thing that makes a
    /// repeating reward repeat and a one-off reward one-off.
    /// </summary>
    internal static string PeriodKey(CampaignRow campaign)
    {
        var now = NowLocal();
        return campaign.CampaignType switch
        {
            "DailyMission" =>
                now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),

            // A peak-hour window is keyed by the day it STARTED, not by today.
            //
            // A 10pm–2am window spans two calendar dates, and keying it by the
            // date at evaluation time gave last night's window and tonight's
            // the same key: finish last night's at 1am (key the 3rd), and at
            // 10pm on the 3rd tonight's window — also key the 3rd — lands on
            // the same progress row, overwrites a Qualified night with a fresh
            // zero and drops it back to InProgress. The reward earned last
            // night is gone, and the only trace is a row that now says the
            // driver has done nothing.
            //
            // Keying by the window's start makes the two nights two rows,
            // which is what they are.
            "PeakHourReward" =>
                campaign.DailyStart is not null && campaign.DailyEnd is not null
                    ? Window(campaign).From
                        .ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
                    : now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            "WeeklyReward" => string.Create(
                CultureInfo.InvariantCulture,
                $"{ISOWeek.GetYear(now.DateTime)}-W{ISOWeek.GetWeekOfYear(now.DateTime):00}"),
            _ => "-",
        };
    }

    /// <summary>When an unpaid award for this period stops being payable.</summary>
    /// <remarks>
    /// A peak-hour award expires at midnight after the window closed, not when
    /// the window closed.
    /// <para>
    /// The old expiry was the window's own end, which made the award unpayable
    /// almost exactly when it was earned. Crediting happens on the driver's
    /// next request — a heartbeat, opening the home screen — and a driver who
    /// finishes a 10pm–2am window and goes straight to bed makes no request
    /// until the evening. By then expires_at had passed, CreditQualifiedAsync
    /// skipped the row, and the money was never moved. The driver had done the
    /// work, the app had told them they qualified, and the reward quietly
    /// aged out. Finishing a window right at its end is the normal way to earn
    /// one of these, so this was most of them.
    /// </para>
    /// <para>
    /// Midnight after the window gives roughly a day of slack, which is enough
    /// for any real driver to open the app, and still short enough that a stale
    /// row cannot be paid a week later.
    /// </para>
    /// </remarks>
    internal static DateTimeOffset? PeriodExpiry(CampaignRow campaign)
    {
        var now = NowLocal();
        return campaign.CampaignType switch
        {
            "DailyMission" => LocalDayStart(now).AddDays(1),
            "PeakHourReward" =>
                campaign.DailyStart is not null && campaign.DailyEnd is not null
                    ? LocalDayStart(Window(campaign).To).AddDays(1)
                    : LocalDayStart(now).AddDays(1),
            // Monday 00:00 after this ISO week — which is what PeriodKey
            // buckets by. Sunday is day 0 in .NET but the last day of an ISO
            // week, so it gets one day, not eight.
            "WeeklyReward" => LocalDayStart(now).AddDays(
                now.DayOfWeek == DayOfWeek.Sunday ? 1 : 8 - (int)now.DayOfWeek),
            _ => campaign.EndsAt,
        };
    }

    private static async Task<decimal> MeasureAsync(
        NpgsqlConnection connection,
        DriverPresenceService.DriverContext driver,
        DriverMetrics metrics,
        CampaignRow campaign,
        string conditionType,
        CancellationToken cancellationToken) => conditionType switch
        {
            "AccountVerified" => metrics.VerificationStatus == "Approved" ? 1 : 0,
            "ProfileCompleted" => metrics.ProfileComplete ? 1 : 0,
            "VehicleApproved" => metrics.VehicleApproved ? 1 : 0,
            "FirstRide" => metrics.RidesTotal > 0 ? 1 : 0,
            "CompletedRides" => await WindowCompletedRidesAsync(
                connection, driver.ProfileId, campaign, cancellationToken),
            "OnlineSeconds" => await WindowOnlineSecondsAsync(
                connection, driver.ProfileId, campaign, cancellationToken),
            "OnlineSessions" => await WindowOnlineDaysAsync(
                connection, driver.ProfileId, campaign, cancellationToken),
            "AcceptanceRate" => metrics.AcceptanceRate ?? 0,
            "ReferralVerified" => metrics.ReferralsVerified,
            "ReferralFirstRide" => metrics.ReferralsFirstRide,
            "ReferralActive" => metrics.ReferralsActive,
            // Manual, or anything an older build wrote that this one does not
            // know: left at zero so an admin decides rather than the engine
            // guessing and paying.
            _ => 0,
        };

    /// <summary>The window a campaign measures over, in local time.</summary>
    internal static (DateTimeOffset From, DateTimeOffset To) Window(CampaignRow campaign)
    {
        var now = NowLocal();

        if (campaign.CampaignType is "PeakHourReward"
            && campaign.DailyStart is { } start && campaign.DailyEnd is { } end)
        {
            // Every value here stays a DateTimeOffset carrying Pakistan's
            // offset, so the comparison below means what it reads as. See
            // LocalDayStart for what happened when it did not.
            var today = LocalDayStart(now);

            // A window that ends before it starts crosses midnight — 10pm to
            // 2am is one window, not a negative one.
            var from = today + start;
            var to = end > start ? today + end : today.AddDays(1) + end;

            // Before tonight's window opens, the window to measure is the most
            // recent one, which for a midnight-crossing campaign began
            // yesterday: at 1am the 10pm–2am window is last night's, and it is
            // still running. Between 2am and 10pm it is last night's and
            // finished, which is still the right one to measure — rolling
            // forward early would zero a driver's progress hours after they
            // earned it. PeriodExpiry is what keeps the earned award payable.
            if (end <= start && now < from)
            {
                from = from.AddDays(-1);
                to = to.AddDays(-1);
            }

            return (from, to);
        }

        if (campaign.CampaignType is "DailyMission")
        {
            var today = LocalDayStart(now);
            return (today, today.AddDays(1));
        }

        // A weekly reward measures this ISO week, Monday to Monday — the same
        // bucket PeriodKey names. Measuring it from the campaign's start date
        // instead, as this used to, meant week two counted week one's rides
        // again and every driver qualified for ever.
        if (campaign.CampaignType is "WeeklyReward")
        {
            var monday = LocalDayStart(now).AddDays(
                now.DayOfWeek == DayOfWeek.Sunday ? -6 : 1 - (int)now.DayOfWeek);
            return (monday, monday.AddDays(7));
        }

        // Everything else measures from when the campaign opened.
        return (campaign.StartsAt ?? DateTimeOffset.UnixEpoch,
                campaign.EndsAt ?? DateTimeOffset.UtcNow.AddYears(1));
    }

    private static async Task<decimal> WindowOnlineSecondsAsync(
        NpgsqlConnection connection,
        Guid driverProfileId,
        CampaignRow campaign,
        CancellationToken cancellationToken)
    {
        var (from, to) = Window(campaign);

        // Overlap of the session with the window, but never more than the
        // session actually credited. Both halves matter: the overlap keeps a
        // night shift from counting towards a 5–9pm reward, and the cap keeps a
        // session that slept through the window from counting at all.
        const string sql = """
            SELECT COALESCE(SUM(LEAST(
                GREATEST(0, EXTRACT(EPOCH FROM (
                    LEAST(COALESCE(s.ended_at, now()), @to)
                    - GREATEST(s.started_at, @from))))::int,
                s.credited_seconds)), 0)
            FROM udrive.driver_online_sessions s
            WHERE s.driver_profile_id = @driver
              AND s.started_at < @to
              AND COALESCE(s.ended_at, now()) > @from;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driver", driverProfileId);
        command.Parameters.AddWithValue("from", from);
        command.Parameters.AddWithValue("to", to);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return Convert.ToDecimal(result ?? 0);
    }

    private static async Task<decimal> WindowOnlineDaysAsync(
        NpgsqlConnection connection,
        Guid driverProfileId,
        CampaignRow campaign,
        CancellationToken cancellationToken)
    {
        var (from, to) = Window(campaign);

        // "Sessions" counts days with a real stretch online, not sessions. Ten
        // minutes in a day is not a session anyone should be paid for, and
        // counting rows would pay for toggling the switch ten times.
        const string sql = """
            SELECT count(DISTINCT (s.started_at AT TIME ZONE 'Asia/Karachi')::date)
            FROM udrive.driver_online_sessions s
            WHERE s.driver_profile_id = @driver
              AND s.started_at >= @from AND s.started_at < @to
              AND s.credited_seconds >= 1800;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driver", driverProfileId);
        command.Parameters.AddWithValue("from", from);
        command.Parameters.AddWithValue("to", to);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return Convert.ToDecimal(result ?? 0);
    }

    private static async Task<decimal> WindowCompletedRidesAsync(
        NpgsqlConnection connection,
        Guid driverProfileId,
        CampaignRow campaign,
        CancellationToken cancellationToken)
    {
        var (from, to) = Window(campaign);

        const string sql = """
            SELECT count(*)
            FROM udrive.trip_assignments ta
            JOIN udrive.trip_operations t ON t.booking_id = ta.booking_id
            WHERE ta.driver_profile_id = @driver
              AND t.trip_status = 'TripCompleted'
              AND t.completed_at >= @from AND t.completed_at < @to;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driver", driverProfileId);
        command.Parameters.AddWithValue("from", from);
        command.Parameters.AddWithValue("to", to);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return Convert.ToDecimal(result ?? 0);
    }

    private static async Task<decimal> WindowAcceptedRidesAsync(
        NpgsqlConnection connection,
        Guid driverProfileId,
        CampaignRow campaign,
        CancellationToken cancellationToken)
    {
        var (from, to) = Window(campaign);

        const string sql = """
            SELECT count(*)
            FROM udrive.driver_ride_request_decisions d
            WHERE d.driver_profile_id = @driver
              AND d.decision = 'Accepted'
              AND d.updated_at >= @from AND d.updated_at < @to;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driver", driverProfileId);
        command.Parameters.AddWithValue("from", from);
        command.Parameters.AddWithValue("to", to);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return Convert.ToDecimal(result ?? 0);
    }

    private static async Task<List<MilestoneRow>> LoadMilestonesAsync(
        NpgsqlConnection connection,
        Guid[] campaignIds,
        CancellationToken cancellationToken)
    {
        var rows = new List<MilestoneRow>();
        if (campaignIds.Length == 0) return rows;

        const string sql = """
            SELECT id, campaign_id, sort_order, title, description,
                   reward_amount, condition_type, condition_value
            FROM udrive.growth_campaign_milestones
            WHERE campaign_id = ANY(@ids)
            ORDER BY campaign_id, sort_order;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("ids", campaignIds);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new MilestoneRow(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetInt32(2),
                reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.GetDecimal(5),
                reader.GetString(6),
                reader.GetDecimal(7)));
        }

        return rows;
    }

    /// <summary>
    /// Writes this driver's progress, and marks it qualified once the target is
    /// met. Never moves a row backwards out of Credited.
    /// </summary>
    private static async Task UpsertProgressAsync(
        NpgsqlConnection connection,
        Guid driverProfileId,
        Guid campaignId,
        Guid? milestoneId,
        string periodKey,
        decimal progress,
        decimal target,
        decimal reward,
        DateTimeOffset? expires,
        string reason,
        CancellationToken cancellationToken)
    {
        // The WHERE on the update is the important part. Once a row is Credited
        // or Rejected it is finished, and a later evaluation — a recalculated
        // metric, an edited campaign, a driver whose ride was voided — must not
        // reopen it and pay again.
        const string sql = """
            INSERT INTO udrive.driver_campaign_progress
                (id, campaign_id, milestone_id, driver_profile_id, period_key,
                 progress_value, target_value, status, reward_amount,
                 qualified_at, expires_at, reason, created_at, updated_at)
            VALUES (gen_random_uuid(), @campaign, @milestone, @driver, @period,
                    @progress, @target,
                    CASE WHEN @progress >= @target THEN 'Qualified' ELSE 'InProgress' END,
                    @reward,
                    CASE WHEN @progress >= @target THEN now() ELSE NULL END,
                    @expires, @reason, now(), now())
            ON CONFLICT (driver_profile_id, campaign_id,
                         COALESCE(milestone_id, '00000000-0000-0000-0000-000000000000'::uuid),
                         period_key)
            DO UPDATE SET
                progress_value = EXCLUDED.progress_value,
                target_value = EXCLUDED.target_value,
                reward_amount = EXCLUDED.reward_amount,
                status = CASE
                    WHEN udrive.driver_campaign_progress.status IN ('Credited', 'Rejected')
                        THEN udrive.driver_campaign_progress.status
                    WHEN EXCLUDED.progress_value >= EXCLUDED.target_value
                        THEN 'Qualified'
                    ELSE 'InProgress' END,
                qualified_at = COALESCE(
                    udrive.driver_campaign_progress.qualified_at,
                    CASE WHEN EXCLUDED.progress_value >= EXCLUDED.target_value
                         THEN now() ELSE NULL END),
                expires_at = EXCLUDED.expires_at,
                updated_at = now()
            WHERE udrive.driver_campaign_progress.status
                  NOT IN ('Credited', 'Rejected');
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("campaign", campaignId);
        command.Parameters.AddWithValue("milestone", (object?)milestoneId ?? DBNull.Value);
        command.Parameters.AddWithValue("driver", driverProfileId);
        command.Parameters.AddWithValue("period", periodKey);
        command.Parameters.AddWithValue("progress", progress);
        command.Parameters.AddWithValue("target", target);
        command.Parameters.AddWithValue("reward", reward);
        command.Parameters.AddWithValue("expires", (object?)expires ?? DBNull.Value);
        command.Parameters.AddWithValue("reason", reason);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>
    /// Pays every qualified reward this driver has, once each.
    /// </summary>
    /// <remarks>
    /// The gates live here rather than in the progress calculation on purpose.
    /// A driver can finish two hours online and still fail the campaign's
    /// cancellation limit; marking that as unqualified would tell them they had
    /// not done the work, which is not true. It stays qualified-but-unpaid with
    /// the reason recorded, which is what an admin needs to answer the phone
    /// call about it.
    /// </remarks>
    private static async Task CreditQualifiedAsync(
        NpgsqlConnection connection,
        Guid driverProfileId,
        DriverMetrics metrics,
        CancellationToken cancellationToken)
    {
        const string selectSql = """
            SELECT g.id, g.reward_amount, g.reason, c.min_rating,
                   c.min_acceptance_rate, c.max_cancellations, c.total_budget,
                   c.id AS campaign_id,
                   COALESCE(spent.amount, 0),
                   c.max_awards_per_driver,
                   COALESCE(awarded.count, 0),
                   c.campaign_type
            FROM udrive.driver_campaign_progress g
            JOIN udrive.growth_campaigns c ON c.id = g.campaign_id
            LEFT JOIN LATERAL (
                SELECT SUM(p.reward_amount) AS amount
                FROM udrive.driver_campaign_progress p
                WHERE p.campaign_id = c.id AND p.status = 'Credited'
            ) AS spent ON true
            -- How many times THIS driver has already been paid by THIS
            -- campaign, which is what max_awards_per_driver limits.
            LEFT JOIN LATERAL (
                SELECT count(*) AS count
                FROM udrive.driver_campaign_progress p
                WHERE p.campaign_id = c.id
                  AND p.driver_profile_id = g.driver_profile_id
                  AND p.status = 'Credited'
            ) AS awarded ON true
            WHERE g.driver_profile_id = @driver
              AND g.status = 'Qualified'
              AND g.reward_amount > 0
              AND (g.expires_at IS NULL OR g.expires_at >= now())
            ORDER BY g.qualified_at;
            """;

        var payable = new List<PayableRow>();

        await using (var command = new NpgsqlCommand(selectSql, connection))
        {
            command.Parameters.AddWithValue("driver", driverProfileId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var amount = reader.GetDecimal(1);
                var minRating = reader.IsDBNull(3) ? null : (decimal?)reader.GetDecimal(3);
                var minAcceptance = reader.IsDBNull(4) ? null : (decimal?)reader.GetDecimal(4);
                var maxCancellations = reader.IsDBNull(5) ? null : (int?)reader.GetInt32(5);
                var budget = reader.IsDBNull(6) ? null : (decimal?)reader.GetDecimal(6);
                var campaignId = reader.GetGuid(7);
                var spent = reader.GetDecimal(8);
                var alreadyAwarded = (int)reader.GetInt64(10);
                var maxAwards = LifetimeCap(reader.GetInt32(9), reader.GetString(11));

                string? block = null;
                if (minRating is not null && metrics.Rating < minRating)
                {
                    block = $"Rating {metrics.Rating} is below the required {minRating}.";
                }
                else if (minAcceptance is not null
                         && (metrics.AcceptanceRate ?? 0) < minAcceptance)
                {
                    block = $"Acceptance rate {metrics.AcceptanceRate ?? 0}% is below "
                          + $"the required {minAcceptance}%.";
                }
                // max_cancellations was read from the database and then never
                // looked at. A campaign could say "no more than two
                // cancellations" and a driver who cancelled eleven rides that
                // day was paid in full — the one rule most of these campaigns
                // exist to enforce.
                else if (maxCancellations is not null
                         && metrics.CancellationsToday > maxCancellations)
                {
                    block = $"{metrics.CancellationsToday} cancellations today is "
                          + $"above the limit of {maxCancellations}.";
                }
                // Same story: max_awards_per_driver was loaded into the campaign
                // row and never consulted, so "once per driver" meant once per
                // period, for ever. A daily mission capped at one award paid
                // every day of the month.
                else if (maxAwards > 0 && alreadyAwarded >= maxAwards)
                {
                    block = maxAwards == 1
                        ? "This reward is paid once per driver and has already been paid."
                        : $"This reward is capped at {maxAwards} per driver and "
                          + $"{alreadyAwarded} have already been paid.";
                }
                else if (budget is not null && spent + amount > budget)
                {
                    block = "This campaign's budget is fully committed.";
                }

                payable.Add(new PayableRow(
                    reader.GetGuid(0),
                    campaignId,
                    amount,
                    reader.IsDBNull(2) ? "UDrive reward" : reader.GetString(2),
                    budget,
                    maxAwards,
                    block));
            }
        }

        foreach (var row in payable)
        {
            if (row.Block is not null)
            {
                await HoldAsync(connection, row.Id, row.Block, cancellationToken);
                continue;
            }

            await CreditAsync(
                connection, driverProfileId, row, cancellationToken);
        }
    }

    private sealed record PayableRow(
        Guid Id,
        Guid CampaignId,
        decimal Amount,
        string Reason,
        decimal? Budget,
        int MaxAwards,
        string? Block);

    /// <summary>
    /// How many times in total this campaign may pay one driver — 0 for no
    /// lifetime limit.
    /// </summary>
    /// <remarks>
    /// The column is called max_awards_per_driver and the validator insists on
    /// at least 1, so 1 is what an admin saving a form will almost always end
    /// up with. Read literally that would make a *daily* mission pay once and
    /// never again, which is the opposite of a daily mission — a trap built
    /// into the default value.
    /// <para>
    /// A repeating campaign already has a per-period guarantee: the unique
    /// index on (driver, campaign, milestone, period_key) means one award per
    /// day, per peak window or per week, whatever else happens. So for those
    /// types a 1 means that guarantee and nothing more, and only a number above
    /// 1 is read as a lifetime cap — which is the only way an admin would ever
    /// type one.
    /// </para>
    /// <para>
    /// For a welcome bonus, a referral, a reactivation offer or a founding
    /// benefit there is no period at all. There, 1 means once, for ever, which
    /// is exactly what those campaigns are for.
    /// </para>
    /// </remarks>
    internal static int LifetimeCap(int configured, string campaignType) =>
        // Referral joined this family when referral rewards started carrying
        // the referred driver's id as their period key. A referral campaign has
        // a period in exactly the sense the remarks above describe — one award
        // per person brought in — so a configured 1 is that guarantee, not a
        // lifetime cap. Left out of this list, a referrer was paid for their
        // first invitee and for nobody else, ever.
        campaignType is "DailyMission" or "PeakHourReward" or "WeeklyReward"
            or "Referral"
            ? configured > 1 ? configured : 0
            : configured;

    private static async Task HoldAsync(
        NpgsqlConnection connection,
        Guid progressId,
        string reason,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.driver_campaign_progress
            SET status = 'OnHold', reason = @reason, updated_at = now()
            WHERE id = @id AND status = 'Qualified';
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", progressId);
        command.Parameters.AddWithValue("reason", reason);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>
    /// Moves one reward into the wallet. Safe to call twice.
    /// </summary>
    /// <remarks>
    /// Two independent guards, which is deliberate: the wallet entry's
    /// idempotency key is <c>growth:{progressId}</c> so the same award can never
    /// produce two entries even if this runs concurrently, and the progress row
    /// only flips to Credited when an entry was actually written. If the second
    /// caller finds the entry already there it credits nothing and changes
    /// nothing — the first caller already did both.
    /// </remarks>
    private static async Task CreditAsync(
        NpgsqlConnection connection,
        Guid driverProfileId,
        PayableRow row,
        CancellationToken cancellationToken)
    {
        var progressId = row.Id;
        var amount = row.Amount;
        var description = row.Reason;

        await using var transaction =
            await connection.BeginTransactionAsync(cancellationToken);

        // The budget and the per-driver cap are re-checked here, inside the
        // transaction, with the campaign row locked.
        //
        // CreditQualifiedAsync checks them too, but it reads every qualified
        // award in one SELECT and then pays them one transaction at a time. The
        // figures it read go stale the moment the first one is paid, so a
        // driver holding three awards against a budget with room for one had
        // all three pass the check and all three paid. Two phones, or two
        // overlapping requests, did the same thing to a one-per-driver reward.
        //
        // Locking the campaign row serialises every payment from that campaign,
        // so the second caller reads what the first one actually spent.
        if (row.Budget is not null || row.MaxAwards > 0)
        {
            const string recheckSql = """
                WITH locked AS (
                    SELECT c.id, c.total_budget, c.max_awards_per_driver,
                           c.campaign_type
                    FROM udrive.growth_campaigns c
                    WHERE c.id = @campaign
                    FOR UPDATE
                )
                SELECT
                    locked.total_budget,
                    locked.max_awards_per_driver,
                    COALESCE((SELECT SUM(p.reward_amount)
                              FROM udrive.driver_campaign_progress p
                              WHERE p.campaign_id = locked.id
                                AND p.status = 'Credited'), 0),
                    COALESCE((SELECT count(*)
                              FROM udrive.driver_campaign_progress p
                              WHERE p.campaign_id = locked.id
                                AND p.driver_profile_id = @driver
                                AND p.status = 'Credited'), 0),
                    locked.campaign_type
                FROM locked;
                """;

            decimal? budget = null;
            var maxAwards = 0;
            var spent = 0m;
            var awarded = 0L;

            await using (var recheck =
                new NpgsqlCommand(recheckSql, connection, transaction))
            {
                recheck.Parameters.AddWithValue("campaign", row.CampaignId);
                recheck.Parameters.AddWithValue("driver", driverProfileId);
                await using var reader =
                    await recheck.ExecuteReaderAsync(cancellationToken);
                if (await reader.ReadAsync(cancellationToken))
                {
                    budget = reader.IsDBNull(0) ? null : reader.GetDecimal(0);
                    spent = reader.GetDecimal(2);
                    awarded = reader.GetInt64(3);
                    maxAwards = LifetimeCap(reader.GetInt32(1), reader.GetString(4));
                }
            }

            var stop = maxAwards > 0 && awarded >= maxAwards
                ? maxAwards == 1
                    ? "This reward is paid once per driver and has already been paid."
                    : $"This reward is capped at {maxAwards} per driver and "
                      + $"{awarded} have already been paid."
                : budget is not null && spent + amount > budget
                    ? "This campaign's budget is fully committed."
                    : null;

            if (stop is not null)
            {
                const string holdSql = """
                    UPDATE udrive.driver_campaign_progress
                    SET status = 'OnHold', reason = @reason, updated_at = now()
                    WHERE id = @id AND status = 'Qualified';
                    """;

                await using var hold =
                    new NpgsqlCommand(holdSql, connection, transaction);
                hold.Parameters.AddWithValue("id", progressId);
                hold.Parameters.AddWithValue("reason", stop);
                await hold.ExecuteNonQueryAsync(cancellationToken);
                await transaction.CommitAsync(cancellationToken);
                return;
            }
        }

        // A driver may have no wallet row yet — nothing creates one until their
        // first earning — and a reward is a perfectly good first entry.
        const string walletSql = """
            INSERT INTO udrive.driver_wallets
                (id, driver_profile_id, created_at, updated_at)
            VALUES (gen_random_uuid(), @driver, now(), now())
            ON CONFLICT (driver_profile_id) DO NOTHING;
            """;

        await using (var command = new NpgsqlCommand(walletSql, connection, transaction))
        {
            command.Parameters.AddWithValue("driver", driverProfileId);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        const string creditSql = """
            WITH wallet AS (
                SELECT id FROM udrive.driver_wallets
                WHERE driver_profile_id = @driver
            ), entry AS (
                INSERT INTO udrive.driver_wallet_entries
                    (id, wallet_id, entry_type, amount, balance_bucket,
                     description, reference, idempotency_key, created_at)
                SELECT gen_random_uuid(), wallet.id, 'Bonus', @amount, 'Commission',
                       @description, @reference, @key, now()
                FROM wallet
                ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL
                DO NOTHING
                RETURNING id, wallet_id, amount
            )
            UPDATE udrive.driver_wallets w
            SET commission_balance = w.commission_balance + entry.amount,
                version = w.version + 1,
                updated_at = now()
            FROM entry
            WHERE w.id = entry.wallet_id
            RETURNING entry.id;
            """;

        Guid? entryId = null;
        await using (var command = new NpgsqlCommand(creditSql, connection, transaction))
        {
            command.Parameters.AddWithValue("driver", driverProfileId);
            command.Parameters.AddWithValue("amount", amount);
            command.Parameters.AddWithValue("description", Truncate(description, 500));
            command.Parameters.AddWithValue("reference", $"GROW-{progressId:N}"[..24]);
            command.Parameters.AddWithValue("key", $"growth:{progressId}");
            var result = await command.ExecuteScalarAsync(cancellationToken);
            if (result is Guid id) entryId = id;
        }

        if (entryId is null)
        {
            // Already paid by another caller. Make the progress row agree with
            // the wallet rather than leaving it stuck on Qualified and retried
            // on every future read.
            const string reconcileSql = """
                UPDATE udrive.driver_campaign_progress g
                SET status = 'Credited',
                    credited_at = COALESCE(g.credited_at, e.created_at),
                    wallet_entry_id = e.id,
                    updated_at = now()
                FROM udrive.driver_wallet_entries e
                WHERE g.id = @id
                  AND e.idempotency_key = @key
                  AND g.status <> 'Credited';
                """;

            await using var command =
                new NpgsqlCommand(reconcileSql, connection, transaction);
            command.Parameters.AddWithValue("id", progressId);
            command.Parameters.AddWithValue("key", $"growth:{progressId}");
            await command.ExecuteNonQueryAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return;
        }

        const string markSql = """
            UPDATE udrive.driver_campaign_progress
            SET status = 'Credited', credited_at = now(),
                wallet_entry_id = @entry, updated_at = now()
            WHERE id = @id;
            """;

        await using (var command = new NpgsqlCommand(markSql, connection, transaction))
        {
            command.Parameters.AddWithValue("id", progressId);
            command.Parameters.AddWithValue("entry", entryId.Value);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        // The driver is told. A bonus they do not notice does not keep anyone
        // on the platform, which is the entire point of paying it.
        const string notifySql = """
            INSERT INTO udrive.notifications
                (id, user_id, type, title, body, data_json, action_path,
                 created_at, updated_at)
            SELECT gen_random_uuid(), p.user_id, 'GrowthReward',
                   'Rs ' || trim(to_char(@amount, 'FM999999990')) || ' bonus credited',
                   @description,
                   jsonb_build_object('progressId', @id::text),
                   '/driver/rewards', now(), now()
            FROM udrive.driver_profiles p
            WHERE p.id = @driver;
            """;

        await using (var command = new NpgsqlCommand(notifySql, connection, transaction))
        {
            command.Parameters.AddWithValue("driver", driverProfileId);
            command.Parameters.AddWithValue("amount", amount);
            command.Parameters.AddWithValue("description", Truncate(description, 500));
            command.Parameters.AddWithValue("id", progressId);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
    }

    private static string Truncate(string value, int max) =>
        value.Length <= max ? value : value[..max];

    // ─────────────────────────────────────────────────────────────────  reads

    private static async Task<DriverPresenceDto> PresenceAsync(
        NpgsqlConnection connection,
        DriverPresenceService.DriverContext driver,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT s.id, s.started_at, s.credited_seconds,
                   COALESCE((SELECT SUM(x.credited_seconds)::int
                             FROM udrive.driver_online_sessions x
                             WHERE x.driver_profile_id = @driver
                               AND (x.started_at AT TIME ZONE 'Asia/Karachi')::date
                                   = (now() AT TIME ZONE 'Asia/Karachi')::date), 0)
            FROM udrive.driver_online_sessions s
            WHERE s.driver_profile_id = @driver AND s.ended_at IS NULL
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driver", driver.ProfileId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            var today = await TodaySecondsAsync(
                connection, driver.ProfileId, cancellationToken);
            return new DriverPresenceDto(
                false, null, null, 0, today,
                DriverPresenceService.HeartbeatSeconds,
                driver.CityName, driver.CityId);
        }

        return new DriverPresenceDto(
            true,
            reader.GetGuid(0),
            reader.GetFieldValue<DateTimeOffset>(1),
            reader.GetInt32(2),
            reader.GetInt32(3),
            DriverPresenceService.HeartbeatSeconds,
            driver.CityName,
            driver.CityId);
    }

    private static async Task<int> TodaySecondsAsync(
        NpgsqlConnection connection,
        Guid driverProfileId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT COALESCE(SUM(s.credited_seconds), 0)::int
            FROM udrive.driver_online_sessions s
            WHERE s.driver_profile_id = @driver
              AND (s.started_at AT TIME ZONE 'Asia/Karachi')::date
                  = (now() AT TIME ZONE 'Asia/Karachi')::date;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driver", driverProfileId);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return Convert.ToInt32(result ?? 0);
    }

    private static async Task<WelcomeBonusDto?> LoadWelcomeBonusAsync(
        NpgsqlConnection connection,
        DriverPresenceService.DriverContext driver,
        CancellationToken cancellationToken)
    {
        if (driver.CityId is null) return null;

        const string sql = """
            SELECT c.id, c.title, c.reward_amount, c.ends_at,
                   m.id, m.title, m.description, m.reward_amount,
                   g.id, g.progress_value, g.target_value, g.status,
                   g.qualified_at, g.credited_at, g.expires_at, m.sort_order
            FROM udrive.growth_campaigns c
            JOIN udrive.growth_campaign_milestones m ON m.campaign_id = c.id
            LEFT JOIN udrive.driver_campaign_progress g
                   ON g.campaign_id = c.id
                  AND g.milestone_id = m.id
                  AND g.driver_profile_id = @driver
            WHERE c.campaign_type = 'WelcomeBonus'
              AND c.is_active
              AND c.launch_city_id = @city
            ORDER BY c.created_at DESC, m.sort_order;
            """;

        Guid? campaignId = null;
        var title = string.Empty;
        decimal total = 0;
        DateTimeOffset? endsAt = null;
        var milestones = new List<GrowthRewardProgressDto>();

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driver", driver.ProfileId);
        command.Parameters.AddWithValue("city", driver.CityId.Value);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            var id = reader.GetGuid(0);

            // Only the newest welcome bonus. An admin replacing one with another
            // should not show the driver two.
            if (campaignId is not null && campaignId != id) break;

            campaignId = id;
            title = reader.GetString(1);
            total = reader.GetDecimal(2);
            endsAt = reader.IsDBNull(3) ? null : reader.GetFieldValue<DateTimeOffset>(3);

            milestones.Add(new GrowthRewardProgressDto(
                reader.IsDBNull(8) ? Guid.Empty : reader.GetGuid(8),
                id,
                reader.GetGuid(4),
                reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetString(6),
                reader.GetDecimal(7),
                reader.IsDBNull(9) ? 0 : reader.GetDecimal(9),
                reader.IsDBNull(10) ? 1 : reader.GetDecimal(10),
                reader.IsDBNull(11) ? "InProgress" : reader.GetString(11),
                reader.IsDBNull(12) ? null : reader.GetFieldValue<DateTimeOffset>(12),
                reader.IsDBNull(13) ? null : reader.GetFieldValue<DateTimeOffset>(13),
                reader.IsDBNull(14) ? null : reader.GetFieldValue<DateTimeOffset>(14)));
        }

        if (campaignId is null) return null;

        var unlocked = milestones
            .Where(m => m.Status == "Credited")
            .Sum(m => m.RewardAmount);

        var next = milestones.FirstOrDefault(m => m.Status is "InProgress" or "Qualified");

        return new WelcomeBonusDto(
            campaignId.Value,
            title,
            total > 0 ? total : milestones.Sum(m => m.RewardAmount),
            unlocked,
            Math.Max(0, (total > 0 ? total : milestones.Sum(m => m.RewardAmount)) - unlocked),
            endsAt,
            next,
            milestones);
    }

    private static async Task<IReadOnlyList<MissionDto>> LoadMissionsAsync(
        NpgsqlConnection connection,
        DriverPresenceService.DriverContext driver,
        CancellationToken cancellationToken)
    {
        if (driver.CityId is null) return Array.Empty<MissionDto>();

        const string sql = """
            SELECT c.id, c.campaign_type, c.title, c.description, c.reward_amount,
                   COALESCE(g.progress_value, 0), COALESCE(g.target_value, 1),
                   COALESCE(g.status, 'InProgress'),
                   c.starts_at, COALESCE(g.expires_at, c.ends_at), z.name,
                   to_char(c.daily_start_time, 'HH24:MI'),
                   to_char(c.daily_end_time, 'HH24:MI'),
                   c.min_online_seconds, c.min_completed_rides,
                   c.min_accepted_rides, c.max_cancellations,
                   c.min_rating, c.min_acceptance_rate,
                   CASE WHEN g.status = 'OnHold' THEN g.reason ELSE NULL END
            FROM udrive.growth_campaigns c
            LEFT JOIN udrive.pricing_zones z ON z.id = c.zone_id
            LEFT JOIN udrive.driver_campaign_progress g
                   ON g.campaign_id = c.id
                  AND g.milestone_id IS NULL
                  AND g.driver_profile_id = @driver
                  AND g.period_key = @period
            WHERE c.is_active
              AND c.launch_city_id = @city
              AND c.campaign_type IN ('DailyMission', 'PeakHourReward')
              AND (c.starts_at IS NULL OR c.starts_at <= now())
              AND (c.ends_at IS NULL OR c.ends_at >= now())
            ORDER BY
                CASE COALESCE(g.status, 'InProgress')
                    WHEN 'Qualified' THEN 0
                    WHEN 'InProgress' THEN 1
                    WHEN 'Credited' THEN 2
                    ELSE 3 END,
                c.reward_amount DESC;
            """;

        var rows = new List<MissionDto>();
        var today = NowLocal().ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driver", driver.ProfileId);
        command.Parameters.AddWithValue("city", driver.CityId.Value);
        command.Parameters.AddWithValue("period", today);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new MissionDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetString(3),
                reader.GetDecimal(4),
                reader.GetDecimal(5),
                reader.GetDecimal(6),
                reader.GetString(7),
                reader.IsDBNull(8) ? null : reader.GetFieldValue<DateTimeOffset>(8),
                reader.IsDBNull(9) ? null : reader.GetFieldValue<DateTimeOffset>(9),
                reader.IsDBNull(10) ? null : reader.GetString(10),
                reader.IsDBNull(11) ? null : reader.GetString(11),
                reader.IsDBNull(12) ? null : reader.GetString(12),
                reader.IsDBNull(13) ? null : reader.GetInt32(13),
                reader.IsDBNull(14) ? null : reader.GetInt32(14),
                reader.IsDBNull(15) ? null : reader.GetInt32(15),
                reader.IsDBNull(16) ? null : reader.GetInt32(16),
                reader.IsDBNull(17) ? null : reader.GetDecimal(17),
                reader.IsDBNull(18) ? null : reader.GetDecimal(18),
                reader.IsDBNull(19) ? null : reader.GetString(19)));
        }

        return rows;
    }

    private static async Task<LaunchStatusDto?> LoadLaunchAsync(
        NpgsqlConnection connection,
        Guid? cityId,
        CancellationToken cancellationToken)
    {
        if (cityId is null) return null;

        // Every number here is counted, never configured. A launch card that can
        // be typed into is a launch card nobody believes twice.
        const string sql = """
            SELECT c.id, c.name, c.launch_status, c.customer_campaign_active,
                   (SELECT count(*) FROM udrive.driver_profiles p
                     WHERE p.launch_city_id = c.id
                       AND p.verification_status = 'Approved'),
                   (SELECT count(*) FROM udrive.customer_profiles),
                   (SELECT count(*) FROM udrive.ride_requests r
                     WHERE r.created_at > now() - interval '7 days'),
                   (SELECT count(*) FROM udrive.trip_operations t
                     WHERE t.trip_status = 'TripCompleted'
                       AND t.completed_at > now() - interval '7 days')
            FROM udrive.launch_cities c
            WHERE c.id = @city AND c.is_active;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("city", cityId.Value);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return null;

        return new LaunchStatusDto(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetBoolean(3),
            (int)reader.GetInt64(4),
            (int)reader.GetInt64(5),
            (int)reader.GetInt64(6),
            (int)reader.GetInt64(7));
    }

    private static async Task<FoundingDriverDto?> LoadFoundingAsync(
        NpgsqlConnection connection,
        DriverPresenceService.DriverContext driver,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT f.sequence_no, c.name, f.granted_at
            FROM udrive.founding_drivers f
            JOIN udrive.launch_cities c ON c.id = f.launch_city_id
            WHERE f.driver_profile_id = @driver AND f.revoked_at IS NULL;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driver", driver.ProfileId);

        int sequence;
        string cityName;
        DateTimeOffset granted;

        // Scoped rather than declared with `await using var`: the benefits
        // query below runs on this same connection, and Npgsql allows only one
        // open reader at a time. The block closes this one first.
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            if (!await reader.ReadAsync(cancellationToken))
            {
                return new FoundingDriverDto(
                    false, null, null, null, Array.Empty<MissionDto>());
            }

            sequence = reader.GetInt32(0);
            cityName = reader.GetString(1);
            granted = reader.GetFieldValue<DateTimeOffset>(2);
        }

        return new FoundingDriverDto(
            true,
            sequence,
            cityName,
            granted,
            await LoadFoundingBenefitsAsync(connection, driver.CityId, cancellationToken));
    }

    /// <summary>
    /// What founding status is actually worth, as configured.
    /// </summary>
    /// <remarks>
    /// Read from FoundingBenefit campaigns rather than written into the app. A
    /// badge with a list of benefits baked into a release is a promise nobody
    /// can withdraw or change, and these are launch-period terms that will
    /// change.
    /// </remarks>
    private static async Task<IReadOnlyList<MissionDto>> LoadFoundingBenefitsAsync(
        NpgsqlConnection connection,
        Guid? cityId,
        CancellationToken cancellationToken)
    {
        if (cityId is null) return Array.Empty<MissionDto>();

        const string sql = """
            SELECT c.id, c.campaign_type, c.title, c.description, c.reward_amount,
                   c.starts_at, c.ends_at
            FROM udrive.growth_campaigns c
            WHERE c.campaign_type = 'FoundingBenefit'
              AND c.is_active
              AND c.launch_city_id = @city
              AND (c.starts_at IS NULL OR c.starts_at <= now())
              AND (c.ends_at IS NULL OR c.ends_at >= now())
            ORDER BY c.created_at;
            """;

        var rows = new List<MissionDto>();
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("city", cityId.Value);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new MissionDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetString(3),
                reader.GetDecimal(4),
                0,
                1,
                "Active",
                reader.IsDBNull(5) ? null : reader.GetFieldValue<DateTimeOffset>(5),
                reader.IsDBNull(6) ? null : reader.GetFieldValue<DateTimeOffset>(6),
                null));
        }

        return rows;
    }

    private static async Task<IReadOnlyList<ExpectedDemandDto>> LoadDemandAsync(
        NpgsqlConnection connection,
        Guid? cityId,
        CancellationToken cancellationToken)
    {
        if (cityId is null) return Array.Empty<ExpectedDemandDto>();

        // Live first, expected second, and the flag says which. A zone with real
        // open requests right now beats anybody's forecast of it.
        const string sql = """
            SELECT w.zone_id, z.name, w.level, w.reason,
                   to_char(w.start_time, 'HH24:MI'), to_char(w.end_time, 'HH24:MI'),
                   a.latitude, a.longitude, a.radius_km,
                   COALESCE(live.open_requests, 0) AS open_requests
            FROM udrive.expected_demand_windows w
            JOIN udrive.pricing_zones z ON z.id = w.zone_id
            LEFT JOIN LATERAL (
                SELECT a2.latitude, a2.longitude, a2.radius_km
                FROM udrive.pricing_zone_areas a2
                WHERE a2.zone_id = w.zone_id
                ORDER BY a2.radius_km DESC
                LIMIT 1
            ) AS a ON true
            LEFT JOIN LATERAL (
                SELECT s.open_requests
                FROM udrive.zone_demand_snapshots s
                WHERE s.zone_id = w.zone_id
                  AND s.captured_at > now() - interval '20 minutes'
                ORDER BY s.captured_at DESC
                LIMIT 1
            ) AS live ON true
            WHERE w.is_active
              AND (w.launch_city_id IS NULL OR w.launch_city_id = @city)
              AND (w.valid_from IS NULL
                   OR w.valid_from <= (now() AT TIME ZONE 'Asia/Karachi')::date)
              AND (w.valid_to IS NULL
                   OR w.valid_to >= (now() AT TIME ZONE 'Asia/Karachi')::date)
              AND (w.days_of_week IS NULL
                   OR EXTRACT(DOW FROM (now() AT TIME ZONE 'Asia/Karachi'))::smallint
                      = ANY(w.days_of_week))
            ORDER BY CASE w.level WHEN 'High' THEN 0 WHEN 'Medium' THEN 1 ELSE 2 END,
                     z.name
            LIMIT 20;
            """;

        var rows = new List<ExpectedDemandDto>();
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("city", cityId.Value);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new ExpectedDemandDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetString(3),
                reader.GetString(4),
                reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetDouble(6),
                reader.IsDBNull(7) ? null : reader.GetDouble(7),
                reader.IsDBNull(8) ? null : (double)reader.GetDecimal(8),
                reader.GetInt32(9) > 0));
        }

        return rows;
    }

    private static async Task<IReadOnlyList<DriverUpdateDto>> LoadUpdatesAsync(
        NpgsqlConnection connection,
        Guid? cityId,
        int limit,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT id, category, title, body, action_path, publish_at
            FROM udrive.driver_updates
            WHERE is_published
              AND publish_at <= now()
              AND (expires_at IS NULL OR expires_at > now())
              AND (launch_city_id IS NULL OR launch_city_id = @city)
            ORDER BY publish_at DESC
            LIMIT @limit;
            """;

        var rows = new List<DriverUpdateDto>();
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("city", (object?)cityId ?? DBNull.Value);
        command.Parameters.AddWithValue("limit", limit);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new DriverUpdateDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.GetFieldValue<DateTimeOffset>(5)));
        }

        return rows;
    }

    /// <summary>
    /// The driver's invite code, created the first time they ask for it.
    /// </summary>
    /// <remarks>
    /// Generated on demand rather than at registration so the thousands of
    /// drivers who will never open the referral screen do not each hold a code
    /// in a unique index. The retry loop exists because the code is short enough
    /// to read down a phone line, which means collisions are possible.
    /// </remarks>
    private static async Task<string> EnsureReferralCodeAsync(
        NpgsqlConnection connection,
        Guid driverProfileId,
        CancellationToken cancellationToken)
    {
        const string readSql = """
            SELECT referral_code FROM udrive.driver_profiles WHERE id = @driver;
            """;

        await using (var command = new NpgsqlCommand(readSql, connection))
        {
            command.Parameters.AddWithValue("driver", driverProfileId);
            var existing = await command.ExecuteScalarAsync(cancellationToken);
            if (existing is string code && !string.IsNullOrWhiteSpace(code)) return code;
        }

        // No I, O, 0 or 1 — they are read back wrongly over the phone, which is
        // exactly how this code gets shared.
        const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

        for (var attempt = 0; attempt < 8; attempt++)
        {
            var suffix = new string(Enumerable.Range(0, 5)
                .Select(_ => alphabet[Random.Shared.Next(alphabet.Length)])
                .ToArray());
            var candidate = $"UDRIVE-{suffix}";

            const string writeSql = """
                UPDATE udrive.driver_profiles
                SET referral_code = @code, updated_at = now()
                WHERE id = @driver AND referral_code IS NULL
                  AND NOT EXISTS (
                      SELECT 1 FROM udrive.driver_profiles x
                      WHERE upper(x.referral_code) = upper(@code))
                RETURNING referral_code;
                """;

            await using var command = new NpgsqlCommand(writeSql, connection);
            command.Parameters.AddWithValue("code", candidate);
            command.Parameters.AddWithValue("driver", driverProfileId);
            var result = await command.ExecuteScalarAsync(cancellationToken);
            if (result is string written) return written;

            // Either someone else took the code, or this driver already had one
            // written by a concurrent request. Re-read before trying again.
            await using var reread = new NpgsqlCommand(readSql, connection);
            reread.Parameters.AddWithValue("driver", driverProfileId);
            var now = await reread.ExecuteScalarAsync(cancellationToken);
            if (now is string code && !string.IsNullOrWhiteSpace(code)) return code;
        }

        throw new InvalidOperationException(
            "A referral code could not be generated after several attempts.");
    }
}
