using Microsoft.AspNetCore.Http;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The half of referral that was never built: writing it down.
/// </summary>
/// <remarks>
/// <c>driver_referrals</c> has existed since the growth system shipped, and it
/// was designed properly — four milestone timestamps, a unique index so a driver
/// can be referred once in their life, a CHECK against referring yourself. The
/// engine has known its three triggers all along. What never existed anywhere in
/// the codebase was a single INSERT, so the table was read on every referral
/// screen and written by nobody. Every driver saw "0 invites" for ever, and a
/// Referral campaign could be created, funded and switched on while measuring
/// nothing at all.
///
/// Two jobs here:
///
///   * <see cref="ApplyCodeAsync"/> — the row finally gets created, with the
///     guards that stop the obvious abuse.
///   * <see cref="SyncAsync"/> — the four timestamps get stamped, and the
///     reward rows get written, from a single reconciliation pass.
///
/// The reconciliation is deliberate and is the design decision worth defending.
/// The alternative was hooking five call sites — admin verification, vehicle
/// approval, trip completion, and two more — each of which can be bypassed, each
/// of which someone will forget when they add a sixth path. This pass asks the
/// database what is true now and writes down what it finds, so it is idempotent,
/// self-healing for rows that predate it, and cannot be routed around.
/// </remarks>
public sealed class DriverReferralService(string connectionString)
{
    /// <summary>Completed rides that make a referred driver "active".</summary>
    public const int DefaultActiveRides = 20;

    /// <summary>Days from their first ride to reach that count.</summary>
    public const int DefaultActiveWindowDays = 30;

    // ─────────────────────────────────────────────────────── applying a code

    /// <summary>Records who brought this driver to the platform.</summary>
    /// <remarks>
    /// Refused after verification, on purpose and against the obvious
    /// temptation to be generous about it. Allowing an established driver to
    /// enter a code means two drivers who already work here enter each other's,
    /// both collect, and the platform pays a referral fee for nobody new. The
    /// whole programme only works if the code arrives before the driver does.
    /// </remarks>
    public async Task<ServiceResult<ReferralApplyResultDto>> ApplyCodeAsync(
        Guid userId,
        string? code,
        CancellationToken cancellationToken)
    {
        var cleaned = (code ?? string.Empty).Trim().ToUpperInvariant();
        if (cleaned.Length is < 4 or > 24)
        {
            return ServiceResult<ReferralApplyResultDto>.Fail(
                StatusCodes.Status400BadRequest,
                "referral_code_invalid",
                "That does not look like a referral code. It looks like "
                + "UDRIVE-ABCDE.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var me = await DriverPresenceService.ResolveDriverAsync(
            connection, userId, cancellationToken);
        if (me is null)
        {
            return ServiceResult<ReferralApplyResultDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "This account does not have a driver profile.");
        }

        const string meSql = """
            SELECT lower(dp.verification_status),
                   EXISTS (SELECT 1 FROM udrive.driver_referrals r
                            WHERE r.referred_driver_profile_id = dp.id)
            FROM udrive.driver_profiles dp
            WHERE dp.id = @me;
            """;

        string myStatus;
        bool alreadyReferred;
        await using (var command = new NpgsqlCommand(meSql, connection))
        {
            command.Parameters.AddWithValue("me", me.Value.ProfileId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            await reader.ReadAsync(cancellationToken);
            myStatus = reader.IsDBNull(0) ? string.Empty : reader.GetString(0);
            alreadyReferred = reader.GetBoolean(1);
        }

        if (alreadyReferred)
        {
            return ServiceResult<ReferralApplyResultDto>.Fail(
                StatusCodes.Status409Conflict,
                "referral_already_used",
                "You have already used a referral code.");
        }

        if (myStatus is "approved" or "verified")
        {
            return ServiceResult<ReferralApplyResultDto>.Fail(
                StatusCodes.Status409Conflict,
                "referral_too_late",
                "A referral code can only be added before your account is "
                + "verified. Yours is already approved.");
        }

        const string referrerSql = """
            SELECT dp.id, COALESCE(NULLIF(u.full_name, ''), 'Driver'),
                   lower(dp.verification_status), u.status, dp.launch_city_id
            FROM udrive.driver_profiles dp
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE upper(dp.referral_code) = @code;
            """;

        Guid referrerId;
        string referrerName;
        string referrerStatus;
        string referrerUserStatus;
        Guid? referrerCity;

        await using (var command = new NpgsqlCommand(referrerSql, connection))
        {
            command.Parameters.AddWithValue("code", cleaned);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<ReferralApplyResultDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "referral_code_not_found",
                    "No driver has that code. Check the spelling with whoever "
                    + "gave it to you.");
            }

            referrerId = reader.GetGuid(0);
            referrerName = reader.GetString(1);
            referrerStatus = reader.IsDBNull(2) ? string.Empty : reader.GetString(2);
            referrerUserStatus = reader.IsDBNull(3) ? string.Empty : reader.GetString(3);
            referrerCity = reader.IsDBNull(4) ? null : reader.GetGuid(4);
        }

        if (referrerId == me.Value.ProfileId)
        {
            return ServiceResult<ReferralApplyResultDto>.Fail(
                StatusCodes.Status409Conflict,
                "referral_self",
                "That is your own code.");
        }

        // A suspended or rejected driver's code is dead. Otherwise the fastest
        // way back onto the platform is to be thrown off it and keep collecting
        // referral fees.
        if (referrerStatus is not ("approved" or "verified")
            || referrerUserStatus is "Suspended" or "Rejected")
        {
            return ServiceResult<ReferralApplyResultDto>.Fail(
                StatusCodes.Status409Conflict,
                "referral_code_inactive",
                "That code belongs to an account that is not active.");
        }

        // One phone, one person. Two accounts on the same number referring each
        // other is the cheapest fraud available here, and it costs nothing to
        // close.
        const string sameContactSql = """
            SELECT EXISTS (
                SELECT 1
                FROM udrive.driver_profiles a
                JOIN udrive.users au ON au.id = a.user_id
                JOIN udrive.driver_profiles b ON b.id = @referrer
                JOIN udrive.users bu ON bu.id = b.user_id
                WHERE a.id = @me
                  AND (au.phone_number = bu.phone_number
                       OR (a.cnic_number IS NOT NULL
                           AND a.cnic_number = b.cnic_number)));
            """;

        await using (var command = new NpgsqlCommand(sameContactSql, connection))
        {
            command.Parameters.AddWithValue("me", me.Value.ProfileId);
            command.Parameters.AddWithValue("referrer", referrerId);
            if (await command.ExecuteScalarAsync(cancellationToken) is true)
            {
                return ServiceResult<ReferralApplyResultDto>.Fail(
                    StatusCodes.Status409Conflict,
                    "referral_same_person",
                    "That code belongs to the same phone or CNIC as this "
                    + "account.");
            }
        }

        // The campaign is attached now rather than later, so the reward a
        // referrer was promised on the day they shared the code is the reward
        // they get — not whatever an Admin has changed it to by the time the
        // referred driver finally takes a ride.
        var campaignId = await ReferralCampaignAsync(
            connection, referrerCity, cancellationToken);

        const string insertSql = """
            INSERT INTO udrive.driver_referrals
                (referrer_driver_profile_id, referred_driver_profile_id,
                 referral_code, campaign_id, status, created_at, updated_at)
            VALUES (@referrer, @me, @code, @campaign, 'Pending', now(), now())
            ON CONFLICT (referred_driver_profile_id) DO NOTHING;
            """;

        await using (var command = new NpgsqlCommand(insertSql, connection))
        {
            command.Parameters.AddWithValue("referrer", referrerId);
            command.Parameters.AddWithValue("me", me.Value.ProfileId);
            command.Parameters.AddWithValue("code", cleaned);
            command.Parameters.Add(new NpgsqlParameter("campaign", NpgsqlDbType.Uuid)
            {
                Value = (object?)campaignId ?? DBNull.Value,
            });

            if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                return ServiceResult<ReferralApplyResultDto>.Fail(
                    StatusCodes.Status409Conflict,
                    "referral_already_used",
                    "You have already used a referral code.");
            }
        }

        // Their account may already satisfy a milestone — an admin can approve
        // documents in the minute between sign-up and this screen.
        await SyncAsync(connection, referrerId, cancellationToken);

        return ServiceResult<ReferralApplyResultDto>.Ok(
            new ReferralApplyResultDto(referrerName, cleaned),
            $"Added. {referrerName} will earn as you get going.");
    }

    // ──────────────────────────────────────────────────── the reconciliation

    /// <summary>
    /// Stamps every milestone that has become true, and writes the rewards.
    /// </summary>
    /// <remarks>
    /// Safe to run as often as anything likes: every statement is conditional on
    /// the timestamp being null or the reward row not existing, so a second pass
    /// a second later changes nothing.
    /// <para>
    /// Run with no referrer to reconcile the whole table — which is what makes
    /// this self-healing for the referrals that were never stamped because this
    /// code did not exist when they were made.
    /// </para>
    /// </remarks>
    public static async Task SyncAsync(
        NpgsqlConnection connection,
        Guid? referrerProfileId,
        CancellationToken cancellationToken)
    {
        var activeRides = await SettingAsync(
            connection, "referral.active_rides", DefaultActiveRides, cancellationToken);
        var activeWindow = await SettingAsync(
            connection, "referral.active_window_days", DefaultActiveWindowDays, cancellationToken);

        // One statement, four milestones. Each COALESCE keeps a timestamp that
        // is already set: the first time a thing became true is the date that
        // matters, and re-deriving it every pass would move it.
        const string stampSql = """
            UPDATE udrive.driver_referrals r
            SET verified_at = COALESCE(r.verified_at,
                    CASE WHEN lower(d.verification_status) IN ('approved', 'verified')
                         THEN now() END),
                vehicle_approved_at = COALESCE(r.vehicle_approved_at,
                    CASE WHEN EXISTS (
                            SELECT 1 FROM udrive.vehicles v
                            WHERE v.driver_profile_id = d.id
                              AND lower(v.status) IN ('verified', 'approved'))
                         THEN now() END),
                first_ride_at = COALESCE(r.first_ride_at, rides.first_at),
                active_at = COALESCE(r.active_at,
                    CASE WHEN rides.first_at IS NOT NULL
                          AND rides.done_in_window >= @activeRides
                         THEN now() END),
                status = CASE
                    WHEN COALESCE(r.active_at,
                            CASE WHEN rides.first_at IS NOT NULL
                                  AND rides.done_in_window >= @activeRides
                                 THEN now() END) IS NOT NULL THEN 'Active'
                    WHEN COALESCE(r.verified_at,
                            CASE WHEN lower(d.verification_status)
                                      IN ('approved', 'verified')
                                 THEN now() END) IS NOT NULL THEN 'Verified'
                    ELSE r.status END,
                updated_at = now()
            FROM udrive.driver_profiles d
            -- Measured from the referred driver's own first completed ride,
            -- never from the stored first_ride_at. A FROM item in an UPDATE
            -- cannot reference the row being updated, and leaning on the stored
            -- date would anyway make the window move the first time anybody
            -- corrected it.
            CROSS JOIN LATERAL (
                SELECT fr.first_at,
                       (SELECT count(*)
                          FROM udrive.bookings b
                         WHERE b.driver_profile_id = d.id
                           AND b.status = 'Completed'
                           AND b.updated_at
                               <= fr.first_at + (@activeWindow * interval '1 day')
                       ) AS done_in_window
                FROM (
                    SELECT min(b2.updated_at) AS first_at
                    FROM udrive.bookings b2
                    WHERE b2.driver_profile_id = d.id
                      AND b2.status = 'Completed'
                ) AS fr
            ) AS rides
            WHERE d.id = r.referred_driver_profile_id
              AND r.status <> 'Rejected'
              AND (@referrer::uuid IS NULL
                   OR r.referrer_driver_profile_id = @referrer::uuid);
            """;

        await using (var command = new NpgsqlCommand(stampSql, connection))
        {
            command.Parameters.AddWithValue("activeRides", activeRides);
            command.Parameters.AddWithValue("activeWindow", activeWindow);
            command.Parameters.Add(new NpgsqlParameter("referrer", NpgsqlDbType.Uuid)
            {
                Value = (object?)referrerProfileId ?? DBNull.Value,
            });
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await WriteRewardsAsync(connection, referrerProfileId, cancellationToken);
    }

    /// <summary>
    /// Creates a Qualified reward row per referred driver, per milestone.
    /// </summary>
    /// <remarks>
    /// The progress table's <c>period_key</c> carries the referred driver's id
    /// with its dashes removed — thirty-two characters, which is exactly the
    /// column's width. That is what turns one referral campaign into a reward
    /// that pays per person brought in, using the same per-period guarantee the
    /// unique index already gives a daily mission. Without it the engine would
    /// pay a referrer once, the first time they reached one verified invitee,
    /// and never again — which nobody would call a referral programme.
    ///
    /// Rows are written straight to <c>Qualified</c>. The existing
    /// <c>CreditQualifiedAsync</c> moves the money on the referrer's next
    /// request, applying the campaign's budget, rating and cancellation rules
    /// exactly as it does for every other reward. Nothing about paying is
    /// reimplemented here.
    /// </remarks>
    private static async Task WriteRewardsAsync(
        NpgsqlConnection connection,
        Guid? referrerProfileId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.driver_campaign_progress
                (campaign_id, milestone_id, driver_profile_id, period_key,
                 progress_value, target_value, status, reward_amount,
                 qualified_at, expires_at, reason, created_at, updated_at)
            SELECT r.campaign_id, m.id, r.referrer_driver_profile_id,
                   replace(r.referred_driver_profile_id::text, '-', ''),
                   1, 1, 'Qualified', m.reward_amount, now(), c.ends_at,
                   m.title, now(), now()
            FROM udrive.driver_referrals r
            JOIN udrive.growth_campaigns c ON c.id = r.campaign_id
            JOIN udrive.growth_campaign_milestones m ON m.campaign_id = c.id
            WHERE c.is_active
              AND c.campaign_type = 'Referral'
              AND r.status <> 'Rejected'
              AND (@referrer::uuid IS NULL
                   OR r.referrer_driver_profile_id = @referrer::uuid)
              AND CASE m.condition_type
                    WHEN 'ReferralVerified'  THEN r.verified_at
                    WHEN 'ReferralFirstRide' THEN r.first_ride_at
                    WHEN 'ReferralActive'    THEN r.active_at
                    ELSE NULL
                  END IS NOT NULL
            ON CONFLICT DO NOTHING;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.Add(new NpgsqlParameter("referrer", NpgsqlDbType.Uuid)
        {
            Value = (object?)referrerProfileId ?? DBNull.Value,
        });
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    // ────────────────────────────────────────────────────────────── helpers

    /// <summary>The live Referral campaign for a city, if there is one.</summary>
    private static async Task<Guid?> ReferralCampaignAsync(
        NpgsqlConnection connection,
        Guid? cityId,
        CancellationToken cancellationToken)
    {
        if (cityId is null) return null;

        await using var command = new NpgsqlCommand(
            """
            SELECT c.id
            FROM udrive.growth_campaigns c
            JOIN udrive.launch_cities city ON city.id = c.launch_city_id
            WHERE c.campaign_type = 'Referral'
              AND c.is_active
              AND city.is_active
              AND city.id = @city
              AND (c.starts_at IS NULL OR c.starts_at <= now())
              AND (c.ends_at IS NULL OR c.ends_at >= now())
            ORDER BY c.created_at
            LIMIT 1;
            """,
            connection);
        command.Parameters.AddWithValue("city", cityId.Value);
        return await command.ExecuteScalarAsync(cancellationToken) as Guid?;
    }

    private static async Task<int> SettingAsync(
        NpgsqlConnection connection,
        string key,
        int fallback,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT COALESCE((SELECT GREATEST(1, (value_json #>> '{}')::int)
                             FROM udrive.system_settings WHERE key = @key), @fallback);
            """,
            connection);
        command.Parameters.AddWithValue("key", key);
        command.Parameters.AddWithValue("fallback", fallback);
        return await command.ExecuteScalarAsync(cancellationToken) is int value ? value : fallback;
    }
}
