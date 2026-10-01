using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Everything the growth system can be configured with, from the admin portal.
/// </summary>
/// <remarks>
/// This is the whole reason the driver-facing code has no numbers in it. A
/// welcome bonus, its six milestones, a peak-hour window, a mission, a demand
/// forecast, an announcement — all of it is rows written here, which means a
/// campaign can start on Friday evening without a release and can be stopped
/// just as fast when it is costing more than it is bringing in.
///
/// Two things are deliberately not possible from here:
///
/// * <b>Paying a driver directly.</b> Money only moves through
///   <see cref="DriverGrowthService"/>, against a campaign, with an audit row
///   and an idempotency key. An admin who could credit a wallet by hand from a
///   campaign screen is an admin who can do it twice by accident.
/// * <b>Deleting a campaign that has paid.</b> Deactivating stops it; the rows
///   stay, because they are the record of money that left the business.
/// </remarks>
public sealed class AdminGrowthService(string connectionString)
{
    private NpgsqlConnection Open() => new(connectionString);

    // ────────────────────────────────────────────────────────────────  cities

    public async Task<ServiceResult<IReadOnlyList<LaunchCityDto>>> CitiesAsync(
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT c.id, c.name, c.is_active, c.launch_status,
                   c.customer_campaign_active, c.founding_enabled, c.founding_limit,
                   c.founding_window_ends_at, c.support_phone, c.community_url,
                   c.activated_at,
                   (SELECT count(*) FROM udrive.driver_profiles p
                     WHERE p.launch_city_id = c.id),
                   (SELECT count(*) FROM udrive.founding_drivers f
                     WHERE f.launch_city_id = c.id AND f.revoked_at IS NULL)
            FROM udrive.launch_cities c
            ORDER BY c.is_active DESC, c.name;
            """;

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var rows = new List<LaunchCityDto>();
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new LaunchCityDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetBoolean(2),
                reader.GetString(3),
                reader.GetBoolean(4),
                reader.GetBoolean(5),
                reader.IsDBNull(6) ? null : reader.GetInt32(6),
                reader.IsDBNull(7) ? null : reader.GetFieldValue<DateTimeOffset>(7),
                reader.IsDBNull(8) ? null : reader.GetString(8),
                reader.IsDBNull(9) ? null : reader.GetString(9),
                reader.IsDBNull(10) ? null : reader.GetFieldValue<DateTimeOffset>(10),
                (int)reader.GetInt64(11),
                (int)reader.GetInt64(12)));
        }

        return ServiceResult<IReadOnlyList<LaunchCityDto>>.Ok(rows);
    }

    public async Task<ServiceResult<Guid>> SaveCityAsync(
        Guid? id,
        LaunchCityRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest,
                "name_required",
                "The city needs a name.");
        }

        var allowed = new[]
        {
            "BuildingNetwork", "CampaignSoon", "CampaignActive", "PublicLaunch",
        };

        if (!allowed.Contains(request.LaunchStatus, StringComparer.Ordinal))
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest,
                "status_invalid",
                "Launch status must be one of: " + string.Join(", ", allowed) + ".");
        }

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        // activated_at is set the first time a city goes live and never reset,
        // so "we opened Mirpur on the 3rd" stays true after it is paused and
        // resumed.
        const string sql = """
            INSERT INTO udrive.launch_cities
                (id, name, is_active, launch_status, customer_campaign_active,
                 founding_enabled, founding_limit, founding_window_ends_at,
                 support_phone, community_url, notes, activated_at,
                 created_at, updated_at)
            VALUES (COALESCE(@id, gen_random_uuid()), @name, @active, @status,
                    @campaign, @founding, @limit, @window, @phone, @community,
                    @notes,
                    CASE WHEN @active THEN now() ELSE NULL END, now(), now())
            ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                is_active = EXCLUDED.is_active,
                launch_status = EXCLUDED.launch_status,
                customer_campaign_active = EXCLUDED.customer_campaign_active,
                founding_enabled = EXCLUDED.founding_enabled,
                founding_limit = EXCLUDED.founding_limit,
                founding_window_ends_at = EXCLUDED.founding_window_ends_at,
                support_phone = EXCLUDED.support_phone,
                community_url = EXCLUDED.community_url,
                notes = EXCLUDED.notes,
                activated_at = COALESCE(
                    udrive.launch_cities.activated_at,
                    CASE WHEN EXCLUDED.is_active THEN now() ELSE NULL END),
                updated_at = now()
            RETURNING id;
            """;

        try
        {
            await using var command = new NpgsqlCommand(sql, connection);
            command.Parameters.AddWithValue("id", (object?)id ?? DBNull.Value);
            command.Parameters.AddWithValue("name", request.Name.Trim());
            command.Parameters.AddWithValue("active", request.IsActive);
            command.Parameters.AddWithValue("status", request.LaunchStatus);
            command.Parameters.AddWithValue("campaign", request.CustomerCampaignActive);
            command.Parameters.AddWithValue("founding", request.FoundingEnabled);
            command.Parameters.AddWithValue("limit",
                (object?)request.FoundingLimit ?? DBNull.Value);
            command.Parameters.AddWithValue("window",
                (object?)request.FoundingWindowEndsAt ?? DBNull.Value);
            command.Parameters.AddWithValue("phone",
                (object?)request.SupportPhone ?? DBNull.Value);
            command.Parameters.AddWithValue("community",
                (object?)request.CommunityUrl ?? DBNull.Value);
            command.Parameters.AddWithValue("notes",
                (object?)request.Notes ?? DBNull.Value);

            var result = (Guid)(await command.ExecuteScalarAsync(cancellationToken))!;
            return ServiceResult<Guid>.Ok(result);
        }
        catch (PostgresException error)
            when (error.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status409Conflict,
                "city_exists",
                "A launch city with that name already exists.");
        }
    }

    // ─────────────────────────────────────────────────────────────  campaigns

    public async Task<ServiceResult<IReadOnlyList<GrowthCampaignDto>>> CampaignsAsync(
        Guid? cityId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT c.id, c.campaign_type, c.code, c.title, c.description,
                   c.launch_city_id, city.name, c.zone_id, z.name,
                   c.reward_amount, c.starts_at, c.ends_at,
                   to_char(c.daily_start_time, 'HH24:MI'),
                   to_char(c.daily_end_time, 'HH24:MI'),
                   c.days_of_week, c.driver_segment,
                   c.min_online_seconds, c.min_completed_rides, c.min_accepted_rides,
                   c.max_cancellations, c.min_rating, c.min_acceptance_rate,
                   c.inactive_days, c.max_awards_per_driver, c.total_budget,
                   c.is_active,
                   COALESCE((SELECT SUM(g.reward_amount)
                             FROM udrive.driver_campaign_progress g
                             WHERE g.campaign_id = c.id AND g.status = 'Credited'), 0)
            FROM udrive.growth_campaigns c
            LEFT JOIN udrive.launch_cities city ON city.id = c.launch_city_id
            LEFT JOIN udrive.pricing_zones z ON z.id = c.zone_id
            WHERE (@city::uuid IS NULL OR c.launch_city_id = @city)
            ORDER BY c.is_active DESC, c.campaign_type, c.created_at DESC;
            """;

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var rows = new List<GrowthCampaignDto>();
        var ids = new List<Guid>();

        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("city", (object?)cityId ?? DBNull.Value);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var days = reader.IsDBNull(14)
                    ? Array.Empty<int>()
                    : reader.GetFieldValue<short[]>(14).Select(d => (int)d).ToArray();

                var id = reader.GetGuid(0);
                ids.Add(id);

                rows.Add(new GrowthCampaignDto(
                    id,
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4),
                    reader.IsDBNull(5) ? null : reader.GetGuid(5),
                    reader.IsDBNull(6) ? null : reader.GetString(6),
                    reader.IsDBNull(7) ? null : reader.GetGuid(7),
                    reader.IsDBNull(8) ? null : reader.GetString(8),
                    reader.GetDecimal(9),
                    reader.IsDBNull(10) ? null : reader.GetFieldValue<DateTimeOffset>(10),
                    reader.IsDBNull(11) ? null : reader.GetFieldValue<DateTimeOffset>(11),
                    reader.IsDBNull(12) ? null : reader.GetString(12),
                    reader.IsDBNull(13) ? null : reader.GetString(13),
                    days,
                    reader.GetString(15),
                    reader.IsDBNull(16) ? null : reader.GetInt32(16),
                    reader.IsDBNull(17) ? null : reader.GetInt32(17),
                    reader.IsDBNull(18) ? null : reader.GetInt32(18),
                    reader.IsDBNull(19) ? null : reader.GetInt32(19),
                    reader.IsDBNull(20) ? null : reader.GetDecimal(20),
                    reader.IsDBNull(21) ? null : reader.GetDecimal(21),
                    reader.IsDBNull(22) ? null : reader.GetInt32(22),
                    reader.GetInt32(23),
                    reader.IsDBNull(24) ? null : reader.GetDecimal(24),
                    reader.GetDecimal(26),
                    reader.GetBoolean(25),
                    Array.Empty<GrowthMilestoneDto>()));
            }
        }

        if (ids.Count == 0)
        {
            return ServiceResult<IReadOnlyList<GrowthCampaignDto>>.Ok(rows);
        }

        var milestones = new Dictionary<Guid, List<GrowthMilestoneDto>>();
        const string milestoneSql = """
            SELECT id, campaign_id, sort_order, title, description,
                   reward_amount, condition_type, condition_value
            FROM udrive.growth_campaign_milestones
            WHERE campaign_id = ANY(@ids)
            ORDER BY campaign_id, sort_order;
            """;

        await using (var command = new NpgsqlCommand(milestoneSql, connection))
        {
            command.Parameters.AddWithValue("ids", ids.ToArray());
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var campaignId = reader.GetGuid(1);
                if (!milestones.TryGetValue(campaignId, out var list))
                {
                    list = [];
                    milestones[campaignId] = list;
                }

                list.Add(new GrowthMilestoneDto(
                    reader.GetGuid(0),
                    reader.GetInt32(2),
                    reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4),
                    reader.GetDecimal(5),
                    reader.GetString(6),
                    reader.GetDecimal(7)));
            }
        }

        var merged = rows
            .Select(row => milestones.TryGetValue(row.Id, out var list)
                ? row with { Milestones = list }
                : row)
            .ToList();

        return ServiceResult<IReadOnlyList<GrowthCampaignDto>>.Ok(merged);
    }

    public async Task<ServiceResult<Guid>> SaveCampaignAsync(
        Guid? id,
        GrowthCampaignRequest request,
        Guid? actorUserId,
        CancellationToken cancellationToken)
    {
        var validation = Validate(request);
        if (validation is not null)
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest, validation.Value.Code,
                validation.Value.Message);
        }

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await using var transaction =
            await connection.BeginTransactionAsync(cancellationToken);

        const string sql = """
            INSERT INTO udrive.growth_campaigns
                (id, campaign_type, code, title, description, launch_city_id,
                 zone_id, reward_amount, starts_at, ends_at, daily_start_time,
                 daily_end_time, days_of_week, driver_segment, min_online_seconds,
                 min_completed_rides, min_accepted_rides, max_cancellations,
                 min_rating, min_acceptance_rate, inactive_days,
                 max_awards_per_driver, total_budget, is_active,
                 created_by_user_id, created_at, updated_at)
            VALUES (COALESCE(@id, gen_random_uuid()), @type, @code, @title, @desc,
                    @city, @zone, @reward, @starts, @ends, @dstart::time,
                    @dend::time, @days, @segment, @minsec, @minrides, @minacc,
                    @maxcancel, @minrating, @minrate, @inactive, @maxawards,
                    @budget, @active, @actor, now(), now())
            ON CONFLICT (id) DO UPDATE SET
                campaign_type = EXCLUDED.campaign_type,
                code = EXCLUDED.code,
                title = EXCLUDED.title,
                description = EXCLUDED.description,
                launch_city_id = EXCLUDED.launch_city_id,
                zone_id = EXCLUDED.zone_id,
                reward_amount = EXCLUDED.reward_amount,
                starts_at = EXCLUDED.starts_at,
                ends_at = EXCLUDED.ends_at,
                daily_start_time = EXCLUDED.daily_start_time,
                daily_end_time = EXCLUDED.daily_end_time,
                days_of_week = EXCLUDED.days_of_week,
                driver_segment = EXCLUDED.driver_segment,
                min_online_seconds = EXCLUDED.min_online_seconds,
                min_completed_rides = EXCLUDED.min_completed_rides,
                min_accepted_rides = EXCLUDED.min_accepted_rides,
                max_cancellations = EXCLUDED.max_cancellations,
                min_rating = EXCLUDED.min_rating,
                min_acceptance_rate = EXCLUDED.min_acceptance_rate,
                inactive_days = EXCLUDED.inactive_days,
                max_awards_per_driver = EXCLUDED.max_awards_per_driver,
                total_budget = EXCLUDED.total_budget,
                is_active = EXCLUDED.is_active,
                updated_at = now()
            RETURNING id;
            """;

        Guid campaignId;
        try
        {
            await using var command = new NpgsqlCommand(sql, connection, transaction);
            command.Parameters.AddWithValue("id", (object?)id ?? DBNull.Value);
            command.Parameters.AddWithValue("type", request.CampaignType);
            command.Parameters.AddWithValue("code", request.Code.Trim());
            command.Parameters.AddWithValue("title", request.Title.Trim());
            command.Parameters.AddWithValue("desc",
                (object?)request.Description ?? DBNull.Value);
            command.Parameters.AddWithValue("city", (object?)request.CityId ?? DBNull.Value);
            command.Parameters.AddWithValue("zone", (object?)request.ZoneId ?? DBNull.Value);
            command.Parameters.AddWithValue("reward", request.RewardAmount);
            command.Parameters.AddWithValue("starts", (object?)request.StartsAt ?? DBNull.Value);
            command.Parameters.AddWithValue("ends", (object?)request.EndsAt ?? DBNull.Value);
            command.Parameters.AddWithValue("dstart",
                (object?)request.DailyStartTime ?? DBNull.Value);
            command.Parameters.AddWithValue("dend",
                (object?)request.DailyEndTime ?? DBNull.Value);

            var days = request.DaysOfWeek is { Count: > 0 }
                ? request.DaysOfWeek.Select(d => (short)d).ToArray()
                : null;
            command.Parameters.Add(new NpgsqlParameter("days", NpgsqlDbType.Array | NpgsqlDbType.Smallint)
            {
                Value = (object?)days ?? DBNull.Value,
            });

            command.Parameters.AddWithValue("segment", request.DriverSegment);
            command.Parameters.AddWithValue("minsec",
                (object?)request.MinOnlineSeconds ?? DBNull.Value);
            command.Parameters.AddWithValue("minrides",
                (object?)request.MinCompletedRides ?? DBNull.Value);
            command.Parameters.AddWithValue("minacc",
                (object?)request.MinAcceptedRides ?? DBNull.Value);
            command.Parameters.AddWithValue("maxcancel",
                (object?)request.MaxCancellations ?? DBNull.Value);
            command.Parameters.AddWithValue("minrating",
                (object?)request.MinRating ?? DBNull.Value);
            command.Parameters.AddWithValue("minrate",
                (object?)request.MinAcceptanceRate ?? DBNull.Value);
            command.Parameters.AddWithValue("inactive",
                (object?)request.InactiveDays ?? DBNull.Value);
            command.Parameters.AddWithValue("maxawards", request.MaxAwardsPerDriver);
            command.Parameters.AddWithValue("budget",
                (object?)request.TotalBudget ?? DBNull.Value);
            command.Parameters.AddWithValue("active", request.IsActive);
            command.Parameters.AddWithValue("actor",
                (object?)actorUserId ?? DBNull.Value);

            campaignId = (Guid)(await command.ExecuteScalarAsync(cancellationToken))!;
        }
        catch (PostgresException error)
            when (error.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status409Conflict,
                "code_exists",
                "Another campaign already uses that code.");
        }

        if (request.Milestones is not null)
        {
            // Milestones a driver has already been paid for are left alone. The
            // alternative — delete and reinsert — would orphan the progress rows
            // that point at them and lose the record of what was paid for what.
            const string deleteSql = """
                DELETE FROM udrive.growth_campaign_milestones m
                WHERE m.campaign_id = @campaign
                  AND NOT EXISTS (
                      SELECT 1 FROM udrive.driver_campaign_progress g
                      WHERE g.milestone_id = m.id AND g.status = 'Credited');
                """;

            await using (var command = new NpgsqlCommand(deleteSql, connection, transaction))
            {
                command.Parameters.AddWithValue("campaign", campaignId);
                await command.ExecuteNonQueryAsync(cancellationToken);
            }

            const string insertSql = """
                INSERT INTO udrive.growth_campaign_milestones
                    (id, campaign_id, sort_order, title, description,
                     reward_amount, condition_type, condition_value,
                     created_at, updated_at)
                VALUES (gen_random_uuid(), @campaign, @sort, @title, @desc,
                        @reward, @condition, @value, now(), now())
                ON CONFLICT (campaign_id, sort_order) DO UPDATE SET
                    title = EXCLUDED.title,
                    description = EXCLUDED.description,
                    reward_amount = EXCLUDED.reward_amount,
                    condition_type = EXCLUDED.condition_type,
                    condition_value = EXCLUDED.condition_value,
                    updated_at = now();
                """;

            foreach (var milestone in request.Milestones)
            {
                await using var command =
                    new NpgsqlCommand(insertSql, connection, transaction);
                command.Parameters.AddWithValue("campaign", campaignId);
                command.Parameters.AddWithValue("sort", milestone.SortOrder);
                command.Parameters.AddWithValue("title", milestone.Title.Trim());
                command.Parameters.AddWithValue("desc",
                    (object?)milestone.Description ?? DBNull.Value);
                command.Parameters.AddWithValue("reward", milestone.RewardAmount);
                command.Parameters.AddWithValue("condition", milestone.ConditionType);
                command.Parameters.AddWithValue("value", milestone.ConditionValue);
                await command.ExecuteNonQueryAsync(cancellationToken);
            }
        }

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<Guid>.Ok(campaignId);
    }

    private static (string Code, string Message)? Validate(GrowthCampaignRequest request)
    {
        var types = new[]
        {
            "WelcomeBonus", "DailyMission", "PeakHourReward", "Referral",
            "WeeklyReward", "Reactivation", "FoundingBenefit",
        };

        if (!types.Contains(request.CampaignType, StringComparer.Ordinal))
        {
            return ("type_invalid",
                "Campaign type must be one of: " + string.Join(", ", types) + ".");
        }

        if (string.IsNullOrWhiteSpace(request.Code))
        {
            return ("code_required", "The campaign needs a code.");
        }

        if (string.IsNullOrWhiteSpace(request.Title))
        {
            return ("title_required", "The campaign needs a title drivers will read.");
        }

        var segments = new[] { "All", "New", "Founding", "Inactive" };
        if (!segments.Contains(request.DriverSegment, StringComparer.Ordinal))
        {
            return ("segment_invalid",
                "Driver segment must be one of: " + string.Join(", ", segments) + ".");
        }

        if (request.MaxAwardsPerDriver < 1)
        {
            return ("awards_invalid", "A campaign must award at least once.");
        }

        // A peak-hour reward with no window is a reward for existing. It would
        // pay every driver in the city the moment it was saved.
        if (request.CampaignType == "PeakHourReward"
            && (string.IsNullOrWhiteSpace(request.DailyStartTime)
                || string.IsNullOrWhiteSpace(request.DailyEndTime)))
        {
            return ("window_required",
                "A peak hour reward needs a start and end time.");
        }

        if (request.CampaignType is "PeakHourReward" or "DailyMission"
            && request.MinOnlineSeconds is null
            && request.MinCompletedRides is null
            && request.MinAcceptedRides is null
            && (request.Milestones is null || request.Milestones.Count == 0))
        {
            return ("condition_required",
                "This campaign needs at least one condition — online time, "
                + "completed rides, accepted rides, or milestones.");
        }

        if (request.CampaignType == "WelcomeBonus"
            && (request.Milestones is null || request.Milestones.Count == 0))
        {
            return ("milestones_required",
                "A welcome bonus is paid through milestones, so it needs at least one.");
        }

        if (request.Milestones is not null
            && request.Milestones.Select(m => m.SortOrder).Distinct().Count()
               != request.Milestones.Count)
        {
            return ("milestone_order", "Each milestone needs its own position.");
        }

        if (request.EndsAt is not null && request.StartsAt is not null
            && request.EndsAt <= request.StartsAt)
        {
            return ("dates_invalid", "The campaign ends before it starts.");
        }

        return null;
    }

    public async Task<ServiceResult<bool>> SetCampaignActiveAsync(
        Guid id,
        bool active,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.growth_campaigns
            SET is_active = @active, updated_at = now()
            WHERE id = @id;
            """;

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("active", active);
        var rows = await command.ExecuteNonQueryAsync(cancellationToken);

        return rows == 0
            ? ServiceResult<bool>.Fail(
                StatusCodes.Status404NotFound, "not_found", "No such campaign.")
            : ServiceResult<bool>.Ok(true);
    }

    public async Task<ServiceResult<IReadOnlyList<CampaignAwardDto>>> AwardsAsync(
        Guid campaignId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT g.id, g.driver_profile_id, COALESCE(u.full_name, 'Driver'),
                   m.title, g.period_key, g.progress_value, g.target_value,
                   g.status, g.reward_amount, g.qualified_at, g.credited_at
            FROM udrive.driver_campaign_progress g
            JOIN udrive.driver_profiles p ON p.id = g.driver_profile_id
            LEFT JOIN udrive.users u ON u.id = p.user_id
            LEFT JOIN udrive.growth_campaign_milestones m ON m.id = g.milestone_id
            WHERE g.campaign_id = @campaign
            ORDER BY g.updated_at DESC
            LIMIT 500;
            """;

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var rows = new List<CampaignAwardDto>();
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("campaign", campaignId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new CampaignAwardDto(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetString(3),
                reader.GetString(4),
                reader.GetDecimal(5),
                reader.GetDecimal(6),
                reader.GetString(7),
                reader.GetDecimal(8),
                reader.IsDBNull(9) ? null : reader.GetFieldValue<DateTimeOffset>(9),
                reader.IsDBNull(10) ? null : reader.GetFieldValue<DateTimeOffset>(10)));
        }

        return ServiceResult<IReadOnlyList<CampaignAwardDto>>.Ok(rows);
    }

    // ───────────────────────────────────────────────────────── demand windows

    public async Task<ServiceResult<Guid>> SaveDemandWindowAsync(
        Guid? id,
        ExpectedDemandRequest request,
        Guid? actorUserId,
        CancellationToken cancellationToken)
    {
        if (!new[] { "High", "Medium", "Low" }
                .Contains(request.Level, StringComparer.Ordinal))
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest,
                "level_invalid",
                "Demand level must be High, Medium or Low.");
        }

        const string sql = """
            INSERT INTO udrive.expected_demand_windows
                (id, launch_city_id, zone_id, level, reason, days_of_week,
                 start_time, end_time, valid_from, valid_to, campaign_id,
                 is_active, created_by_user_id, created_at, updated_at)
            VALUES (COALESCE(@id, gen_random_uuid()), @city, @zone, @level, @reason,
                    @days, @start::time, @end::time, @from, @to, @campaign,
                    @active, @actor, now(), now())
            ON CONFLICT (id) DO UPDATE SET
                launch_city_id = EXCLUDED.launch_city_id,
                zone_id = EXCLUDED.zone_id,
                level = EXCLUDED.level,
                reason = EXCLUDED.reason,
                days_of_week = EXCLUDED.days_of_week,
                start_time = EXCLUDED.start_time,
                end_time = EXCLUDED.end_time,
                valid_from = EXCLUDED.valid_from,
                valid_to = EXCLUDED.valid_to,
                campaign_id = EXCLUDED.campaign_id,
                is_active = EXCLUDED.is_active,
                updated_at = now()
            RETURNING id;
            """;

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);

        command.Parameters.AddWithValue("id", (object?)id ?? DBNull.Value);
        command.Parameters.AddWithValue("city", (object?)request.CityId ?? DBNull.Value);
        command.Parameters.AddWithValue("zone", request.ZoneId);
        command.Parameters.AddWithValue("level", request.Level);
        command.Parameters.AddWithValue("reason", (object?)request.Reason ?? DBNull.Value);

        var days = request.DaysOfWeek is { Count: > 0 }
            ? request.DaysOfWeek.Select(d => (short)d).ToArray()
            : null;
        command.Parameters.Add(new NpgsqlParameter("days", NpgsqlDbType.Array | NpgsqlDbType.Smallint)
        {
            Value = (object?)days ?? DBNull.Value,
        });

        command.Parameters.AddWithValue("start", request.StartTime);
        command.Parameters.AddWithValue("end", request.EndTime);
        command.Parameters.Add(new NpgsqlParameter("from", NpgsqlDbType.Date)
        {
            Value = request.ValidFrom is { } from
                ? from.ToDateTime(TimeOnly.MinValue)
                : DBNull.Value,
        });
        command.Parameters.Add(new NpgsqlParameter("to", NpgsqlDbType.Date)
        {
            Value = request.ValidTo is { } to
                ? to.ToDateTime(TimeOnly.MinValue)
                : DBNull.Value,
        });
        command.Parameters.AddWithValue("campaign",
            (object?)request.CampaignId ?? DBNull.Value);
        command.Parameters.AddWithValue("active", request.IsActive);
        command.Parameters.AddWithValue("actor", (object?)actorUserId ?? DBNull.Value);

        var result = (Guid)(await command.ExecuteScalarAsync(cancellationToken))!;
        return ServiceResult<Guid>.Ok(result);
    }

    public async Task<ServiceResult<bool>> DeleteDemandWindowAsync(
        Guid id,
        CancellationToken cancellationToken)
    {
        const string sql = "DELETE FROM udrive.expected_demand_windows WHERE id = @id;";

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        var rows = await command.ExecuteNonQueryAsync(cancellationToken);

        return rows == 0
            ? ServiceResult<bool>.Fail(
                StatusCodes.Status404NotFound, "not_found", "No such demand window.")
            : ServiceResult<bool>.Ok(true);
    }

    // ───────────────────────────────────────────────────────────────  updates

    public async Task<ServiceResult<Guid>> SaveUpdateAsync(
        Guid? id,
        DriverUpdateRequest request,
        Guid? actorUserId,
        CancellationToken cancellationToken)
    {
        var categories = new[] { "Demand", "Rewards", "Policy", "Service", "System" };
        if (!categories.Contains(request.Category, StringComparer.Ordinal))
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest,
                "category_invalid",
                "Category must be one of: " + string.Join(", ", categories) + ".");
        }

        if (string.IsNullOrWhiteSpace(request.Title)
            || string.IsNullOrWhiteSpace(request.Body))
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest,
                "content_required",
                "An update needs a title and a body.");
        }

        const string sql = """
            INSERT INTO udrive.driver_updates
                (id, launch_city_id, category, title, body, action_path,
                 publish_at, expires_at, is_published, created_by_user_id,
                 created_at, updated_at)
            VALUES (COALESCE(@id, gen_random_uuid()), @city, @category, @title,
                    @body, @action, COALESCE(@publish, now()), @expires,
                    @published, @actor, now(), now())
            ON CONFLICT (id) DO UPDATE SET
                launch_city_id = EXCLUDED.launch_city_id,
                category = EXCLUDED.category,
                title = EXCLUDED.title,
                body = EXCLUDED.body,
                action_path = EXCLUDED.action_path,
                publish_at = EXCLUDED.publish_at,
                expires_at = EXCLUDED.expires_at,
                is_published = EXCLUDED.is_published,
                updated_at = now()
            RETURNING id;
            """;

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", (object?)id ?? DBNull.Value);
        command.Parameters.AddWithValue("city", (object?)request.CityId ?? DBNull.Value);
        command.Parameters.AddWithValue("category", request.Category);
        command.Parameters.AddWithValue("title", request.Title.Trim());
        command.Parameters.AddWithValue("body", request.Body.Trim());
        command.Parameters.AddWithValue("action",
            (object?)request.ActionPath ?? DBNull.Value);
        command.Parameters.AddWithValue("publish",
            (object?)request.PublishAt ?? DBNull.Value);
        command.Parameters.AddWithValue("expires",
            (object?)request.ExpiresAt ?? DBNull.Value);
        command.Parameters.AddWithValue("published", request.IsPublished);
        command.Parameters.AddWithValue("actor", (object?)actorUserId ?? DBNull.Value);

        var result = (Guid)(await command.ExecuteScalarAsync(cancellationToken))!;
        return ServiceResult<Guid>.Ok(result);
    }

    // ─────────────────────────────────────────────────────────── fraud review

    public async Task<ServiceResult<IReadOnlyList<FraudFlagDto>>> FraudFlagsAsync(
        string? status,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT f.id, f.driver_profile_id, COALESCE(u.full_name, 'Driver'),
                   f.flag_type, f.detail, f.severity, f.status, f.created_at,
                   f.reviewed_at, f.review_notes
            FROM udrive.driver_fraud_flags f
            JOIN udrive.driver_profiles p ON p.id = f.driver_profile_id
            LEFT JOIN udrive.users u ON u.id = p.user_id
            WHERE (@status::text IS NULL OR f.status = @status)
            ORDER BY f.created_at DESC
            LIMIT 300;
            """;

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var rows = new List<FraudFlagDto>();
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("status", (object?)status ?? DBNull.Value);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new FraudFlagDto(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.GetString(5),
                reader.GetString(6),
                reader.GetFieldValue<DateTimeOffset>(7),
                reader.IsDBNull(8) ? null : reader.GetFieldValue<DateTimeOffset>(8),
                reader.IsDBNull(9) ? null : reader.GetString(9)));
        }

        return ServiceResult<IReadOnlyList<FraudFlagDto>>.Ok(rows);
    }

    public async Task<ServiceResult<bool>> ReviewFraudFlagAsync(
        Guid id,
        FraudReviewRequest request,
        Guid? actorUserId,
        CancellationToken cancellationToken)
    {
        if (!new[] { "Open", "Cleared", "Confirmed" }
                .Contains(request.Status, StringComparer.Ordinal))
        {
            return ServiceResult<bool>.Fail(
                StatusCodes.Status400BadRequest,
                "status_invalid",
                "Status must be Open, Cleared or Confirmed.");
        }

        const string sql = """
            UPDATE udrive.driver_fraud_flags
            SET status = @status, review_notes = @notes,
                reviewed_by_user_id = @actor, reviewed_at = now()
            WHERE id = @id;
            """;

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("status", request.Status);
        command.Parameters.AddWithValue("notes", (object?)request.Notes ?? DBNull.Value);
        command.Parameters.AddWithValue("actor", (object?)actorUserId ?? DBNull.Value);
        var rows = await command.ExecuteNonQueryAsync(cancellationToken);

        return rows == 0
            ? ServiceResult<bool>.Fail(
                StatusCodes.Status404NotFound, "not_found", "No such flag.")
            : ServiceResult<bool>.Ok(true);
    }

    // ────────────────────────────────────────────────────────── founding grant

    /// <summary>
    /// Gives a driver the next founding number in their city.
    /// </summary>
    /// <remarks>
    /// The number comes from a single statement that reads the current maximum
    /// and inserts in one go, so two admins pressing the button at the same
    /// moment produce #74 and #75 rather than two #74s — and the unique
    /// constraint on (city, sequence_no) is there in case they manage it anyway.
    /// </remarks>
    public async Task<ServiceResult<int>> GrantFoundingAsync(
        Guid driverProfileId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            WITH target AS (
                SELECT p.id AS driver, c.id AS city, c.founding_limit
                FROM udrive.driver_profiles p
                JOIN udrive.launch_cities c ON c.id = p.launch_city_id
                WHERE p.id = @driver
                  AND c.is_active
                  AND c.founding_enabled
                  AND (c.founding_window_ends_at IS NULL
                       OR c.founding_window_ends_at > now())
            ), next AS (
                SELECT target.driver, target.city, target.founding_limit,
                       COALESCE(MAX(f.sequence_no), 0) + 1 AS seq
                FROM target
                LEFT JOIN udrive.founding_drivers f ON f.launch_city_id = target.city
                GROUP BY target.driver, target.city, target.founding_limit
            )
            INSERT INTO udrive.founding_drivers
                (driver_profile_id, launch_city_id, sequence_no, granted_at)
            SELECT next.driver, next.city, next.seq, now()
            FROM next
            WHERE next.founding_limit IS NULL OR next.seq <= next.founding_limit
            ON CONFLICT (driver_profile_id) DO NOTHING
            RETURNING sequence_no;
            """;

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driver", driverProfileId);
        var result = await command.ExecuteScalarAsync(cancellationToken);

        if (result is null or DBNull)
        {
            return ServiceResult<int>.Fail(
                StatusCodes.Status409Conflict,
                "not_eligible",
                "This driver already has founding status, or their city is not "
                + "accepting founding drivers.");
        }

        return ServiceResult<int>.Ok(Convert.ToInt32(result));
    }
}
