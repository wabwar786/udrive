using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The customer's side of all this: which city am I in, is UDrive running here,
/// put me on the list, and let me ask to be the partner here.
/// </summary>
/// <remarks>
/// Everything in this class is readable by any signed-in customer, which is why
/// nothing in it returns a figure that is nobody's business. A territory is
/// "taken" or "free" and the holder's name is shown — a partner is a public
/// role in a town, and a customer deciding whether to apply has to know whether
/// the job is open. What is not returned: deposits paid, share percentages,
/// statements, or anybody's contract.
/// </remarks>
public sealed class PartnerDirectoryService(string connectionString)
{
    private NpgsqlConnection Open() => new(connectionString);

    // ─────────────────────────────────────────────────────── where am I

    /// <summary>
    /// Resolves the customer's city from a point, and says whether UDrive runs
    /// there.
    /// </summary>
    /// <remarks>
    /// Until this existed the app had no idea where it was. Somebody in
    /// Rawalakot saw the same home screen as somebody in Muzaffarabad and could
    /// try to book a car in a city with no drivers — and then concluded the app
    /// was broken, which is a fair conclusion.
    ///
    /// <para>The city is the nearest circle that actually contains the point.
    /// Nearest-centre without the containment test would put a customer in
    /// Muzaffarabad from forty kilometres away, and a city gate that is
    /// confidently wrong is worse than no gate.</para>
    ///
    /// <para>No point, or no circle containing it, returns a null city and the
    /// full city list. The app then asks. It does not guess, and it does not
    /// lock anybody out: a customer whose GPS is off is still a customer.</para>
    /// </remarks>
    public async Task<ServiceResult<CityStatusDto>> CityStatusAsync(
        double? latitude,
        double? longitude,
        Guid? userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var cities = new List<CityStatusEntryDto>();
        const string listSql = """
            SELECT c.id, c.name, c.is_active, c.launch_status,
                   (SELECT count(*) FROM udrive.city_waitlist w WHERE w.launch_city_id = c.id),
                   EXISTS(
                       SELECT 1 FROM udrive.territories t
                        JOIN udrive.partners p ON p.territory_id = t.id
                                              AND p.status IN ('Pending','Active')
                       WHERE t.launch_city_id = c.id)
            FROM udrive.launch_cities c
            ORDER BY c.is_active DESC, c.name;
            """;

        await using (var list = new NpgsqlCommand(listSql, connection))
        await using (var reader = await list.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                var live = reader.GetBoolean(2);
                var hasPartner = reader.GetBoolean(5);
                cities.Add(new CityStatusEntryDto(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    live,
                    reader.GetString(3),
                    (int)reader.GetInt64(4),
                    // "Partner wanted" means exactly one thing: the city is not
                    // live and nobody holds it. Anything looser turns the line
                    // into noise the first time somebody reads it.
                    !live && !hasPartner));
            }
        }

        Guid? cityId = null;
        if (latitude is not null && longitude is not null)
        {
            const string resolveSql = """
                SELECT a.launch_city_id
                FROM udrive.launch_city_areas a
                WHERE ST_DWithin(
                        a.centre,
                        ST_SetSRID(ST_MakePoint(@lng, @lat), 4326)::geography,
                        a.radius_km * 1000)
                ORDER BY ST_Distance(
                        a.centre,
                        ST_SetSRID(ST_MakePoint(@lng, @lat), 4326)::geography)
                LIMIT 1;
                """;

            await using var resolve = new NpgsqlCommand(resolveSql, connection);
            resolve.Parameters.AddWithValue("lat", latitude.Value);
            resolve.Parameters.AddWithValue("lng", longitude.Value);
            var found = await resolve.ExecuteScalarAsync(cancellationToken);
            if (found is Guid guid)
            {
                cityId = guid;
            }
        }

        var match = cityId is null
            ? null
            : cities.FirstOrDefault(city => city.Id == cityId);

        var onWaitlist = false;
        var driverCount = 0;
        if (match is not null)
        {
            const string extrasSql = """
                SELECT
                    (SELECT count(*) FROM udrive.driver_profiles d
                      WHERE d.launch_city_id = @city
                        AND d.verification_status = 'Approved'),
                    (SELECT EXISTS(SELECT 1 FROM udrive.city_waitlist w
                                    WHERE w.launch_city_id = @city AND w.user_id = @user));
                """;

            await using var extras = new NpgsqlCommand(extrasSql, connection);
            extras.Parameters.AddWithValue("city", match.Id);
            extras.Parameters.AddWithValue("user", (object?)userId ?? DBNull.Value);
            await using var reader = await extras.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                driverCount = (int)reader.GetInt64(0);
                onWaitlist = !reader.IsDBNull(1) && reader.GetBoolean(1);
            }
        }

        return ServiceResult<CityStatusDto>.Ok(new CityStatusDto(
            match?.Id,
            match?.Name,
            match?.IsLive ?? false,
            match?.LaunchStatus,
            onWaitlist,
            match?.WaitingCount ?? 0,
            driverCount,
            match?.PartnerWanted ?? false,
            cities));
    }

    // ───────────────────────────────────────────────────────── the waitlist

    public async Task<ServiceResult<object>> JoinWaitlistAsync(
        Guid userId,
        WaitlistJoinRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        // The phone number is copied in rather than joined on every read, so the
        // list survives the account deletion flow nulling the user.
        const string sql = """
            INSERT INTO udrive.city_waitlist
                (launch_city_id, user_id, phone_number, notify_on_open, source)
            SELECT @city, u.id, u.phone_number, @notify, 'App'
            FROM udrive.users u
            WHERE u.id = @user
            ON CONFLICT (launch_city_id, user_id) DO UPDATE SET
                notify_on_open = excluded.notify_on_open,
                updated_at = now()
            RETURNING id;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("city", request.CityId);
        command.Parameters.AddWithValue("user", userId);
        command.Parameters.AddWithValue("notify", request.NotifyOnOpen);

        var id = await command.ExecuteScalarAsync(cancellationToken);
        return id is null
            ? ServiceResult<object>.Fail(
                StatusCodes.Status404NotFound,
                "city_not_found",
                "That city is no longer listed.")
            : ServiceResult<object>.Ok(new { onWaitlist = true });
    }

    public async Task<ServiceResult<object>> LeaveWaitlistAsync(
        Guid userId,
        Guid cityId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(
            """
            DELETE FROM udrive.city_waitlist
            WHERE launch_city_id = @city AND user_id = @user;
            """,
            connection);
        command.Parameters.AddWithValue("city", cityId);
        command.Parameters.AddWithValue("user", userId);
        await command.ExecuteNonQueryAsync(cancellationToken);

        return ServiceResult<object>.Ok(new { onWaitlist = false });
    }

    // ────────────────────────────────────── what a customer can apply for

    public async Task<ServiceResult<PartnerOpeningsDto>> OpeningsAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var tiers = await LoadTiersAsync(connection, activeOnly: true, cancellationToken);
        var territories = await LoadTreeAsync(connection, cancellationToken);
        var mine = await LoadSelfAsync(connection, userId, cancellationToken);

        return ServiceResult<PartnerOpeningsDto>.Ok(
            new PartnerOpeningsDto(tiers, territories, mine));
    }

    public async Task<ServiceResult<PartnerSelfDto>> MineAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        var mine = await LoadSelfAsync(connection, userId, cancellationToken);
        return ServiceResult<PartnerSelfDto>.Ok(
            mine ?? new PartnerSelfDto(
                null, null, null, null, null, null, null, null, null, false));
    }

    public async Task<ServiceResult<Guid>> ApplyAsync(
        Guid userId,
        PartnerApplicationRequest request,
        CancellationToken cancellationToken)
    {
        if (request.TerritoryId == Guid.Empty || string.IsNullOrWhiteSpace(request.TierKey))
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest,
                "territory_required",
                "Choose a tier and an area first.");
        }

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        // The tier and the territory have to agree about what kind of place this
        // is. Without this check a City Head application can be filed against a
        // tehsil, and every number on the contract afterwards is measured over
        // the wrong area.
        const string checkSql = """
            SELECT t.kind, t.is_active, ti.territory_kind, ti.is_active,
                   EXISTS(SELECT 1 FROM udrive.partners p
                           WHERE p.territory_id = t.id
                             AND p.status IN ('Pending','Active','Suspended')),
                   EXISTS(SELECT 1 FROM udrive.partner_applications a
                           WHERE a.territory_id = t.id AND a.status = 'Pending'
                             AND a.user_id <> @user)
            FROM udrive.territories t
            CROSS JOIN udrive.partner_tiers ti
            WHERE t.id = @territory AND ti.tier_key = @tier;
            """;

        await using (var check = new NpgsqlCommand(checkSql, connection))
        {
            check.Parameters.AddWithValue("territory", request.TerritoryId);
            check.Parameters.AddWithValue("tier", request.TierKey);
            check.Parameters.AddWithValue("user", userId);
            await using var reader = await check.ExecuteReaderAsync(cancellationToken);

            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<Guid>.Fail(
                    StatusCodes.Status404NotFound,
                    "not_found",
                    "That tier or area is no longer available.");
            }

            var territoryKind = reader.GetString(0);
            var territoryActive = reader.GetBoolean(1);
            var tierKind = reader.GetString(2);
            var tierActive = reader.GetBoolean(3);
            var taken = reader.GetBoolean(4);

            if (!territoryActive || !tierActive)
            {
                return ServiceResult<Guid>.Fail(
                    StatusCodes.Status409Conflict,
                    "not_open",
                    "That area is not open for applications right now.");
            }

            if (!string.Equals(territoryKind, tierKind, StringComparison.Ordinal))
            {
                return ServiceResult<Guid>.Fail(
                    StatusCodes.Status400BadRequest,
                    "tier_mismatch",
                    $"A {tierKind} partner can only be appointed for a {tierKind}.");
            }

            // Said at the moment of asking rather than six weeks later in a
            // rejection. This is the whole point of showing availability in the
            // app: nobody should find out from a refusal that the job was never
            // open.
            if (taken)
            {
                return ServiceResult<Guid>.Fail(
                    StatusCodes.Status409Conflict,
                    "territory_taken",
                    "This area already has a partner. Pick another area.");
            }
        }

        const string insertSql = """
            INSERT INTO udrive.partner_applications
                (user_id, tier_key, territory_id, applicant_note, contact_phone, status)
            VALUES (@user, @tier, @territory, nullif(btrim(@note), ''),
                    nullif(btrim(@phone), ''), 'Pending')
            RETURNING id;
            """;

        try
        {
            await using var insert = new NpgsqlCommand(insertSql, connection);
            insert.Parameters.AddWithValue("user", userId);
            insert.Parameters.AddWithValue("tier", request.TierKey);
            insert.Parameters.AddWithValue("territory", request.TerritoryId);
            insert.Parameters.AddWithValue("note", (object?)request.Note ?? string.Empty);
            insert.Parameters.AddWithValue("phone", (object?)request.ContactPhone ?? string.Empty);
            var id = (Guid)(await insert.ExecuteScalarAsync(cancellationToken))!;
            return ServiceResult<Guid>.Created(id, "Your request has been sent.");
        }
        catch (PostgresException error) when (error.SqlState == "23505")
        {
            // The partial unique index on (user_id) WHERE status='Pending'.
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status409Conflict,
                "already_applied",
                "You already have a request waiting. We will come back to you on that one first.");
        }
    }

    public async Task<ServiceResult<object>> WithdrawAsync(
        Guid userId,
        Guid applicationId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.partner_applications
               SET status = 'Withdrawn', updated_at = now()
             WHERE id = @id AND user_id = @user AND status = 'Pending';
            """,
            connection);
        command.Parameters.AddWithValue("id", applicationId);
        command.Parameters.AddWithValue("user", userId);

        var affected = await command.ExecuteNonQueryAsync(cancellationToken);
        return affected == 0
            ? ServiceResult<object>.Fail(
                StatusCodes.Status409Conflict,
                "not_pending",
                "That request has already been decided.")
            : ServiceResult<object>.Ok(new { withdrawn = true });
    }

    // ─────────────────────────────────────────────────────── shared loaders

    /// <remarks>
    /// Public and static so the admin service reads the tiers and the tree from
    /// exactly the same SQL. Two copies of a "who holds this territory" query is
    /// how an admin ends up approving an application the app had already marked
    /// unavailable.
    /// </remarks>
    public static async Task<IReadOnlyList<PartnerTierDto>> LoadTiersAsync(
        NpgsqlConnection connection,
        bool activeOnly,
        CancellationToken cancellationToken)
    {
        var tiers = new List<(PartnerTierDto Tier, string Key)>();

        var sql = """
            SELECT tier_key, display_name, territory_kind, security_deposit,
                   commission_share_pct, term_months, description, is_active
            FROM udrive.partner_tiers
            """
            + (activeOnly ? " WHERE is_active" : string.Empty)
            + " ORDER BY sort_order, tier_key;";

        await using (var command = new NpgsqlCommand(sql, connection))
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                var key = reader.GetString(0);
                tiers.Add((new PartnerTierDto(
                    key,
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetDecimal(3),
                    reader.GetDecimal(4),
                    reader.GetInt32(5),
                    reader.IsDBNull(6) ? null : reader.GetString(6),
                    reader.GetBoolean(7),
                    Array.Empty<PartnerCommitmentDefaultDto>()), key));
            }
        }

        var defaults = new Dictionary<string, List<PartnerCommitmentDefaultDto>>(StringComparer.Ordinal);
        await using (var command = new NpgsqlCommand(
            """
            SELECT id, tier_key, metric_key, target_value, label, is_active
            FROM udrive.partner_tier_commitments
            ORDER BY tier_key, sort_order, metric_key;
            """,
            connection))
        await using (var reader = await command.ExecuteReaderAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                var key = reader.GetString(1);
                if (!defaults.TryGetValue(key, out var list))
                {
                    list = [];
                    defaults[key] = list;
                }

                list.Add(new PartnerCommitmentDefaultDto(
                    reader.GetGuid(0),
                    reader.GetString(2),
                    reader.GetDecimal(3),
                    reader.GetString(4),
                    reader.GetBoolean(5)));
            }
        }

        return tiers
            .Select(entry => entry.Tier with
            {
                Commitments = defaults.TryGetValue(entry.Key, out var list)
                    ? list
                    : Array.Empty<PartnerCommitmentDefaultDto>(),
            })
            .ToArray();
    }

    /// <summary>The whole tree, each node carrying who holds it.</summary>
    /// <remarks>
    /// Walked in SQL rather than assembled in C# because `Path` and `Depth` are
    /// what make the tree readable in a flat list, and computing them here means
    /// every caller gets the same ordering. A tree sorted differently on two
    /// screens reads as two different trees.
    /// </remarks>
    public static async Task<IReadOnlyList<TerritoryNodeDto>> LoadTreeAsync(
        NpgsqlConnection connection,
        CancellationToken cancellationToken)
    {
        const string sql = """
            WITH RECURSIVE walk AS (
                SELECT t.id, t.parent_id, t.kind, t.name, t.launch_city_id,
                       t.is_active, 0 AS depth, t.name::text AS path
                FROM udrive.territories t
                WHERE t.parent_id IS NULL
                UNION ALL
                SELECT t.id, t.parent_id, t.kind, t.name, t.launch_city_id,
                       t.is_active, w.depth + 1, w.path || ' › ' || t.name
                FROM udrive.territories t
                JOIN walk w ON t.parent_id = w.id
            )
            SELECT w.id, w.parent_id, w.kind, w.name, w.launch_city_id,
                   c.launch_status, w.is_active, w.depth, w.path,
                   p.id, u.full_name, p.status, p.tier_key,
                   (SELECT count(*) FROM udrive.driver_profiles d
                     WHERE d.territory_id = w.id
                        OR (d.territory_id IS NULL AND d.launch_city_id = w.launch_city_id
                            AND w.launch_city_id IS NOT NULL)),
                   (SELECT count(*) FROM udrive.city_waitlist cw
                     WHERE cw.launch_city_id = w.launch_city_id),
                   (SELECT count(*) FROM udrive.partner_applications a
                     WHERE a.territory_id = w.id AND a.status = 'Pending')
            FROM walk w
            LEFT JOIN udrive.launch_cities c ON c.id = w.launch_city_id
            LEFT JOIN udrive.partners p ON p.territory_id = w.id
                                       AND p.status IN ('Pending','Active','Suspended')
            LEFT JOIN udrive.users u ON u.id = p.user_id
            ORDER BY w.path;
            """;

        var rows = new List<TerritoryNodeDto>();
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new TerritoryNodeDto(
                reader.GetGuid(0),
                reader.IsDBNull(1) ? null : reader.GetGuid(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetGuid(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.GetBoolean(6),
                reader.GetInt32(7),
                reader.GetString(8),
                reader.IsDBNull(9) ? null : reader.GetGuid(9),
                reader.IsDBNull(10) ? null : reader.GetString(10),
                reader.IsDBNull(11) ? null : reader.GetString(11),
                reader.IsDBNull(12) ? null : reader.GetString(12),
                (int)reader.GetInt64(13),
                (int)reader.GetInt64(14),
                (int)reader.GetInt64(15)));
        }

        return RollUp(rows);
    }

    /// <summary>
    /// Adds every node's descendants into its own counts.
    /// </summary>
    /// <remarks>
    /// The SQL above counts what each node holds directly: a city's own drivers
    /// are the ones nobody has placed in a tehsil, and a region holds almost
    /// nothing directly. Left like that, a Regional Head's row says "0 drivers"
    /// beside a city row saying 74, and the first person to see that reasonably
    /// concludes the screen is broken.
    ///
    /// <para>Rolled up here rather than in SQL because the counts are already in
    /// hand and a correlated recursive subquery per node would walk the tree once
    /// per row. Nothing is double counted: a driver placed in a tehsil is
    /// excluded from their city's direct count by the <c>territory_id IS NULL</c>
    /// test, so they are added exactly once, by this method.</para>
    /// </remarks>
    private static IReadOnlyList<TerritoryNodeDto> RollUp(List<TerritoryNodeDto> rows)
    {
        var drivers = rows.ToDictionary(row => row.Id, row => row.DriverCount);
        var waiting = rows.ToDictionary(row => row.Id, row => row.WaitingCount);
        var parents = rows.ToDictionary(row => row.Id, row => row.ParentId);

        // Deepest first, so a tehsil's figure has already reached its city by the
        // time the city's figure reaches the region.
        foreach (var row in rows.OrderByDescending(row => row.Depth))
        {
            if (parents.TryGetValue(row.Id, out var parentId)
                && parentId is not null
                && drivers.ContainsKey(parentId.Value))
            {
                drivers[parentId.Value] += drivers[row.Id];
                waiting[parentId.Value] += waiting[row.Id];
            }
        }

        return rows
            .Select(row => row with
            {
                DriverCount = drivers[row.Id],
                WaitingCount = waiting[row.Id],
            })
            .ToArray();
    }

    private static async Task<PartnerSelfDto?> LoadSelfAsync(
        NpgsqlConnection connection,
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                a.id, a.status, at.name, a.decision_reason, a.created_at,
                p.id, p.status, ti.display_name, pt.name,
                EXISTS(SELECT 1 FROM udrive.partner_contracts c
                        WHERE c.partner_id = p.id AND c.status = 'Sent')
            FROM udrive.users u
            LEFT JOIN udrive.partner_applications a
                   ON a.user_id = u.id
                  AND a.id = (SELECT a2.id FROM udrive.partner_applications a2
                               WHERE a2.user_id = u.id
                               ORDER BY a2.created_at DESC LIMIT 1)
            LEFT JOIN udrive.territories at ON at.id = a.territory_id
            LEFT JOIN udrive.partners p
                   ON p.user_id = u.id AND p.status IN ('Pending','Active','Suspended')
            LEFT JOIN udrive.partner_tiers ti ON ti.tier_key = p.tier_key
            LEFT JOIN udrive.territories pt ON pt.id = p.territory_id
            WHERE u.id = @user
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("user", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new PartnerSelfDto(
            reader.IsDBNull(0) ? null : reader.GetGuid(0),
            reader.IsDBNull(1) ? null : reader.GetString(1),
            reader.IsDBNull(2) ? null : reader.GetString(2),
            reader.IsDBNull(3) ? null : reader.GetString(3),
            reader.IsDBNull(4) ? null : reader.GetFieldValue<DateTimeOffset>(4),
            reader.IsDBNull(5) ? null : reader.GetGuid(5),
            reader.IsDBNull(6) ? null : reader.GetString(6),
            reader.IsDBNull(7) ? null : reader.GetString(7),
            reader.IsDBNull(8) ? null : reader.GetString(8),
            !reader.IsDBNull(9) && reader.GetBoolean(9));
    }
}
