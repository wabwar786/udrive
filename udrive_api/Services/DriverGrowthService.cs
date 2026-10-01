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
        decimal CommissionPercentage);

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
                EXISTS (SELECT 1 FROM udrive.vehicles v
                        WHERE v.driver_profile_id = p.id AND v.status = 'Approved'),
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
                          WHERE s.key = 'driver.commission.percentage'), 10)
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
                0, 0, 0, 10m);
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
            reader.GetDecimal(15));
    }

    // ────────────────────────────────────────────────────────────── the engine

    private sealed record CampaignRow(
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
        if (campaigns.Count == 0) return;

        var milestones = await LoadMilestonesAsync(
            connection, campaigns.Select(c => c.Id).ToArray(), cancellationToken);

        foreach (var campaign in campaigns)
        {
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

        await CreditQualifiedAsync(
            connection, driver.ProfileId, metrics, cancellationToken);
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
              AND c.campaign_type IN
                  ('WelcomeBonus', 'DailyMission', 'PeakHourReward', 'Referral')
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

    private static bool MatchesSegment(CampaignRow campaign, DriverMetrics metrics) =>
        campaign.DriverSegment switch
        {
            // "New" is measured from approval, not from registration. A driver
            // who signed up in July and was approved yesterday is new today.
            "New" => metrics.ApprovedAt is not null
                     && metrics.ApprovedAt > DateTimeOffset.UtcNow.AddDays(-30),
            "Founding" => true, // narrowed by the founding_drivers join at credit time
            "Inactive" => true, // reactivation is admin-targeted, not self-selected
            _ => true,
        };

    private static bool MatchesDay(CampaignRow campaign, DateTimeOffset now) =>
        campaign.DaysOfWeek.Length == 0
        || campaign.DaysOfWeek.Contains((int)now.DayOfWeek);

    /// <summary>
    /// Which bucket of time this award belongs to — the thing that makes a
    /// repeating reward repeat and a one-off reward one-off.
    /// </summary>
    private static string PeriodKey(CampaignRow campaign)
    {
        var now = NowLocal();
        return campaign.CampaignType switch
        {
            "DailyMission" or "PeakHourReward" =>
                now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            "WeeklyReward" => string.Create(
                CultureInfo.InvariantCulture,
                $"{ISOWeek.GetYear(now.DateTime)}-W{ISOWeek.GetWeekOfYear(now.DateTime):00}"),
            _ => "-",
        };
    }

    private static DateTimeOffset? PeriodExpiry(CampaignRow campaign)
    {
        var now = NowLocal();
        return campaign.CampaignType switch
        {
            "DailyMission" => now.Date.AddDays(1).AddTicks(-1),
            "PeakHourReward" => campaign.DailyEnd is { } end
                ? now.Date.Add(end)
                : now.Date.AddDays(1).AddTicks(-1),
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
    private static (DateTimeOffset From, DateTimeOffset To) Window(CampaignRow campaign)
    {
        var now = NowLocal();

        if (campaign.CampaignType is "PeakHourReward"
            && campaign.DailyStart is { } start && campaign.DailyEnd is { } end)
        {
            // A window that ends before it starts crosses midnight — 10pm to
            // 2am is one window, not a negative one.
            var from = now.Date.Add(start);
            var to = end > start ? now.Date.Add(end) : now.Date.AddDays(1).Add(end);
            if (now < from && end <= start)
            {
                from = from.AddDays(-1);
                to = to.AddDays(-1);
            }

            return (new DateTimeOffset(from, now.Offset),
                    new DateTimeOffset(to, now.Offset));
        }

        if (campaign.CampaignType is "DailyMission")
        {
            return (new DateTimeOffset(now.Date, now.Offset),
                    new DateTimeOffset(now.Date.AddDays(1), now.Offset));
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
                   COALESCE(spent.amount, 0)
            FROM udrive.driver_campaign_progress g
            JOIN udrive.growth_campaigns c ON c.id = g.campaign_id
            LEFT JOIN LATERAL (
                SELECT SUM(p.reward_amount) AS amount
                FROM udrive.driver_campaign_progress p
                WHERE p.campaign_id = c.id AND p.status = 'Credited'
            ) AS spent ON true
            WHERE g.driver_profile_id = @driver
              AND g.status = 'Qualified'
              AND g.reward_amount > 0
              AND (g.expires_at IS NULL OR g.expires_at >= now())
            ORDER BY g.qualified_at;
            """;

        var payable = new List<(Guid Id, decimal Amount, string Reason, string? Block)>();

        await using (var command = new NpgsqlCommand(selectSql, connection))
        {
            command.Parameters.AddWithValue("driver", driverProfileId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var amount = reader.GetDecimal(1);
                var minRating = reader.IsDBNull(3) ? null : (decimal?)reader.GetDecimal(3);
                var minAcceptance = reader.IsDBNull(4) ? null : (decimal?)reader.GetDecimal(4);
                var budget = reader.IsDBNull(6) ? null : (decimal?)reader.GetDecimal(6);
                var spent = reader.GetDecimal(8);

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
                else if (budget is not null && spent + amount > budget)
                {
                    block = "This campaign's budget is fully committed.";
                }

                payable.Add((
                    reader.GetGuid(0),
                    amount,
                    reader.IsDBNull(2) ? "UDrive reward" : reader.GetString(2),
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
                connection, driverProfileId, row.Id, row.Amount, row.Reason,
                cancellationToken);
        }
    }

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
        Guid progressId,
        decimal amount,
        string description,
        CancellationToken cancellationToken)
    {
        await using var transaction =
            await connection.BeginTransactionAsync(cancellationToken);

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
                   c.daily_start_time, c.daily_end_time
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
                reader.IsDBNull(10) ? null : reader.GetString(10)));
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
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            return new FoundingDriverDto(false, null, null, null, Array.Empty<MissionDto>());
        }

        return new FoundingDriverDto(
            true,
            reader.GetInt32(0),
            reader.GetString(1),
            reader.GetFieldValue<DateTimeOffset>(2),
            Array.Empty<MissionDto>());
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
