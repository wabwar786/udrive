using System.Globalization;
using System.Text;
using System.Text.Json;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The admin side of territory partners: the queue, the contract, the monthly
/// record, and the signature evidence.
/// </summary>
/// <remarks>
/// Three things this class will not do, each for a reason that cost something to
/// learn elsewhere in this codebase:
///
/// <list type="bullet">
/// <item><b>Create a partner out of nothing.</b> A partner only ever comes from
/// an approved application, so there is always a record of who asked, for where,
/// and what they were told.</item>
/// <item><b>Move money.</b> There is no payout path here at all. A statement can
/// be marked paid with a reference — that is a note that something happened
/// outside the app, not a transaction.</item>
/// <item><b>Hand out the signature evidence.</b> The photograph and video are
/// returned by exactly one method, only to a SuperAdmin, and that method writes
/// an <c>audit_logs</c> row before it answers.</item>
/// </list>
/// </remarks>
public sealed class AdminPartnerService(string connectionString)
{
    private NpgsqlConnection Open() => new(connectionString);

    private const string PayoutNote =
        "Payment is made outside the app. This statement is the agreed record of "
        + "what is owed for the month.";

    // ════════════════════════════════════════════════════════════════ tiers

    public async Task<ServiceResult<IReadOnlyList<PartnerTierDto>>> TiersAsync(
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        return ServiceResult<IReadOnlyList<PartnerTierDto>>.Ok(
            await PartnerDirectoryService.LoadTiersAsync(connection, false, cancellationToken));
    }

    public async Task<ServiceResult<object>> SaveTierAsync(
        string tierKey,
        PartnerTierRequest request,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        if (request.CommissionSharePct is < 0 or > 100)
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status400BadRequest,
                "share_range",
                "The share must be between 0 and 100 percent of UDrive's commission.");
        }

        if (request.TermMonths is < 1 or > 120)
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status400BadRequest,
                "term_range",
                "The term must be between 1 and 120 months.");
        }

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        await using (var update = new NpgsqlCommand(
            """
            UPDATE udrive.partner_tiers
               SET display_name = @name,
                   security_deposit = @deposit,
                   commission_share_pct = @share,
                   term_months = @term,
                   description = nullif(btrim(@description), ''),
                   is_active = @active,
                   updated_at = now()
             WHERE tier_key = @key;
            """,
            connection,
            transaction))
        {
            update.Parameters.AddWithValue("key", tierKey);
            update.Parameters.AddWithValue("name", request.DisplayName);
            update.Parameters.AddWithValue("deposit", request.SecurityDeposit);
            update.Parameters.AddWithValue("share", request.CommissionSharePct);
            update.Parameters.AddWithValue("term", request.TermMonths);
            update.Parameters.AddWithValue("description", (object?)request.Description ?? string.Empty);
            update.Parameters.AddWithValue("active", request.IsActive);

            if (await update.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                return ServiceResult<object>.Fail(
                    StatusCodes.Status404NotFound, "not_found", "That tier does not exist.");
            }
        }

        if (request.Commitments is { Count: > 0 })
        {
            // Changing a default never touches a signed contract — those carry
            // their own copy in `partner_commitments`. This only changes what the
            // next contract starts from.
            foreach (var commitment in request.Commitments)
            {
                await using var upsert = new NpgsqlCommand(
                    """
                    INSERT INTO udrive.partner_tier_commitments
                        (tier_key, metric_key, target_value, label, is_active)
                    VALUES (@key, @metric, @target, @label, @active)
                    ON CONFLICT (tier_key, metric_key) DO UPDATE SET
                        target_value = excluded.target_value,
                        label = excluded.label,
                        is_active = excluded.is_active,
                        updated_at = now();
                    """,
                    connection,
                    transaction);
                upsert.Parameters.AddWithValue("key", tierKey);
                upsert.Parameters.AddWithValue("metric", commitment.MetricKey);
                upsert.Parameters.AddWithValue("target", commitment.TargetValue);
                upsert.Parameters.AddWithValue("label", commitment.Label);
                upsert.Parameters.AddWithValue("active", commitment.IsActive);
                await upsert.ExecuteNonQueryAsync(cancellationToken);
            }
        }

        await AuditAsync(
            connection, transaction, actorId, "PartnerTierUpdated", "PartnerTier", tierKey,
            new { request.CommissionSharePct, request.SecurityDeposit, request.TermMonths },
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<object>.Ok(new { tierKey });
    }

    // ══════════════════════════════════════════════════════════ territories

    public async Task<ServiceResult<IReadOnlyList<TerritoryNodeDto>>> TerritoriesAsync(
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        return ServiceResult<IReadOnlyList<TerritoryNodeDto>>.Ok(
            await PartnerDirectoryService.LoadTreeAsync(connection, cancellationToken));
    }

    public async Task<ServiceResult<Guid>> SaveTerritoryAsync(
        Guid? id,
        TerritoryRequest request,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest, "name_required", "The area needs a name.");
        }

        if (request.Kind is not ("Region" or "City" or "Tehsil"))
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest, "kind_invalid",
                "An area is a Region, a City or a Tehsil.");
        }

        if (request.Kind == "Tehsil" && request.ParentId is null)
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest, "parent_required",
                "A tehsil has to sit inside a city.");
        }

        if (request.Kind != "City" && request.LaunchCityId is not null)
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest, "launch_city_on_non_city",
                "Only a City can be linked to a launch city.");
        }

        // A node cannot be moved under itself or under its own child. The
        // database's self-parent check catches the first case; a recursive walk
        // is the only thing that catches the second, and the tree query goes
        // infinite without it.
        if (id is not null && request.ParentId is not null)
        {
            await using var connection = Open();
            await connection.OpenAsync(cancellationToken);
            await using var cycle = new NpgsqlCommand(
                """
                WITH RECURSIVE down AS (
                    SELECT id FROM udrive.territories WHERE id = @id
                    UNION ALL
                    SELECT t.id FROM udrive.territories t JOIN down d ON t.parent_id = d.id)
                SELECT EXISTS(SELECT 1 FROM down WHERE id = @parent);
                """,
                connection);
            cycle.Parameters.AddWithValue("id", id.Value);
            cycle.Parameters.AddWithValue("parent", request.ParentId.Value);
            if (await cycle.ExecuteScalarAsync(cancellationToken) is true)
            {
                return ServiceResult<Guid>.Fail(
                    StatusCodes.Status400BadRequest, "cycle",
                    "An area cannot be placed inside itself or inside one of its own areas.");
            }
        }

        await using var writeConnection = Open();
        await writeConnection.OpenAsync(cancellationToken);
        await using var transaction = await writeConnection.BeginTransactionAsync(cancellationToken);

        Guid territoryId;
        try
        {
            if (id is null)
            {
                await using var insert = new NpgsqlCommand(
                    """
                    INSERT INTO udrive.territories
                        (parent_id, kind, name, launch_city_id, is_active, notes)
                    VALUES (@parent, @kind, btrim(@name), @city, @active, nullif(btrim(@notes), ''))
                    RETURNING id;
                    """,
                    writeConnection,
                    transaction);
                insert.Parameters.AddWithValue("parent", (object?)request.ParentId ?? DBNull.Value);
                insert.Parameters.AddWithValue("kind", request.Kind);
                insert.Parameters.AddWithValue("name", request.Name);
                insert.Parameters.AddWithValue("city", (object?)request.LaunchCityId ?? DBNull.Value);
                insert.Parameters.AddWithValue("active", request.IsActive);
                insert.Parameters.AddWithValue("notes", (object?)request.Notes ?? string.Empty);
                territoryId = (Guid)(await insert.ExecuteScalarAsync(cancellationToken))!;
            }
            else
            {
                territoryId = id.Value;
                await using var update = new NpgsqlCommand(
                    """
                    UPDATE udrive.territories
                       SET parent_id = @parent, kind = @kind, name = btrim(@name),
                           launch_city_id = @city, is_active = @active,
                           notes = nullif(btrim(@notes), ''), updated_at = now()
                     WHERE id = @id;
                    """,
                    writeConnection,
                    transaction);
                update.Parameters.AddWithValue("id", territoryId);
                update.Parameters.AddWithValue("parent", (object?)request.ParentId ?? DBNull.Value);
                update.Parameters.AddWithValue("kind", request.Kind);
                update.Parameters.AddWithValue("name", request.Name);
                update.Parameters.AddWithValue("city", (object?)request.LaunchCityId ?? DBNull.Value);
                update.Parameters.AddWithValue("active", request.IsActive);
                update.Parameters.AddWithValue("notes", (object?)request.Notes ?? string.Empty);

                if (await update.ExecuteNonQueryAsync(cancellationToken) == 0)
                {
                    return ServiceResult<Guid>.Fail(
                        StatusCodes.Status404NotFound, "not_found", "That area does not exist.");
                }
            }
        }
        catch (PostgresException error) when (error.SqlState == "23505")
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status409Conflict, "duplicate",
                "There is already an area with that name in the same place, or that "
                + "launch city is already linked to another area.");
        }
        catch (PostgresException error) when (error.SqlState == "23514")
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest, "invalid_shape",
                "A Region sits at the top, a Tehsil must sit inside something, and "
                + "only a City can carry a launch city.");
        }

        await AuditAsync(
            writeConnection, transaction, actorId,
            id is null ? "TerritoryCreated" : "TerritoryUpdated",
            "Territory", territoryId.ToString(),
            new { request.Kind, request.Name, request.ParentId, request.LaunchCityId },
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<Guid>.Ok(territoryId);
    }

    public async Task<ServiceResult<object>> DeleteTerritoryAsync(
        Guid id,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        // Deactivating is the right move almost always, so the error says so
        // rather than just refusing. A territory with history is part of a signed
        // contract; deleting it would orphan the record of what was agreed.
        try
        {
            await using var command = new NpgsqlCommand(
                "DELETE FROM udrive.territories WHERE id = @id;", connection);
            command.Parameters.AddWithValue("id", id);
            if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                return ServiceResult<object>.Fail(
                    StatusCodes.Status404NotFound, "not_found", "That area does not exist.");
            }
        }
        catch (PostgresException error) when (error.SqlState == "23503")
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status409Conflict, "in_use",
                "This area is used by a partner, an application or a smaller area. "
                + "Switch it off instead of deleting it.");
        }

        await using var audit = Open();
        await audit.OpenAsync(cancellationToken);
        await AuditAsync(audit, null, actorId, "TerritoryDeleted", "Territory",
            id.ToString(), new { id }, cancellationToken);

        return ServiceResult<object>.Ok(new { deleted = true });
    }

    public async Task<ServiceResult<object>> SetDriverTerritoryAsync(
        Guid driverProfileId,
        Guid? territoryId,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.driver_profiles
               SET territory_id = @territory, updated_at = now()
             WHERE id = @driver;
            """,
            connection);
        command.Parameters.AddWithValue("driver", driverProfileId);
        command.Parameters.AddWithValue("territory", (object?)territoryId ?? DBNull.Value);

        if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status404NotFound, "not_found", "That driver does not exist.");
        }

        await AuditAsync(connection, null, actorId, "DriverTerritorySet", "DriverProfile",
            driverProfileId.ToString(), new { territoryId }, cancellationToken);

        return ServiceResult<object>.Ok(new { driverProfileId, territoryId });
    }

    // ───────────────────────────────────────────────────── city map circles

    public async Task<ServiceResult<IReadOnlyList<LaunchCityAreaDto>>> CityAreasAsync(
        Guid? cityId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(
            """
            SELECT id, launch_city_id, label, latitude, longitude, radius_km
            FROM udrive.launch_city_areas
            WHERE (@city::uuid IS NULL OR launch_city_id = @city)
            ORDER BY launch_city_id, label NULLS LAST;
            """,
            connection);
        command.Parameters.AddWithValue("city", (object?)cityId ?? DBNull.Value);

        var rows = new List<LaunchCityAreaDto>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new LaunchCityAreaDto(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.IsDBNull(2) ? null : reader.GetString(2),
                reader.GetDouble(3),
                reader.GetDouble(4),
                reader.GetDecimal(5)));
        }

        return ServiceResult<IReadOnlyList<LaunchCityAreaDto>>.Ok(rows);
    }

    public async Task<ServiceResult<Guid>> SaveCityAreaAsync(
        LaunchCityAreaRequest request,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        if (request.RadiusKm is <= 0 or > 200)
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest, "radius_range",
                "The radius has to be between 0 and 200 km.");
        }

        if (request.Latitude is < -90 or > 90 || request.Longitude is < -180 or > 180)
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status400BadRequest, "coordinates_range",
                "Those coordinates are outside the world.");
        }

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.launch_city_areas
                (launch_city_id, label, latitude, longitude, radius_km)
            VALUES (@city, nullif(btrim(@label), ''), @lat, @lng, @radius)
            RETURNING id;
            """,
            connection);
        command.Parameters.AddWithValue("city", request.LaunchCityId);
        command.Parameters.AddWithValue("label", (object?)request.Label ?? string.Empty);
        command.Parameters.AddWithValue("lat", request.Latitude);
        command.Parameters.AddWithValue("lng", request.Longitude);
        command.Parameters.AddWithValue("radius", request.RadiusKm);

        var id = (Guid)(await command.ExecuteScalarAsync(cancellationToken))!;
        await AuditAsync(connection, null, actorId, "LaunchCityAreaCreated", "LaunchCityArea",
            id.ToString(), new { request.LaunchCityId, request.Latitude, request.Longitude, request.RadiusKm },
            cancellationToken);

        return ServiceResult<Guid>.Created(id);
    }

    public async Task<ServiceResult<object>> DeleteCityAreaAsync(
        Guid id,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(
            "DELETE FROM udrive.launch_city_areas WHERE id = @id;", connection);
        command.Parameters.AddWithValue("id", id);
        if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status404NotFound, "not_found", "That circle does not exist.");
        }

        await AuditAsync(connection, null, actorId, "LaunchCityAreaDeleted", "LaunchCityArea",
            id.ToString(), new { id }, cancellationToken);

        return ServiceResult<object>.Ok(new { deleted = true });
    }

    public async Task<ServiceResult<IReadOnlyList<WaitlistEntryDto>>> WaitlistAsync(
        Guid? cityId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(
            """
            SELECT w.id, w.launch_city_id, c.name, w.user_id, u.full_name,
                   coalesce(w.phone_number, u.phone_number), w.notify_on_open, w.created_at
            FROM udrive.city_waitlist w
            JOIN udrive.launch_cities c ON c.id = w.launch_city_id
            LEFT JOIN udrive.users u ON u.id = w.user_id
            WHERE (@city::uuid IS NULL OR w.launch_city_id = @city)
            ORDER BY w.created_at DESC
            LIMIT 500;
            """,
            connection);
        command.Parameters.AddWithValue("city", (object?)cityId ?? DBNull.Value);

        var rows = new List<WaitlistEntryDto>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new WaitlistEntryDto(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.GetGuid(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.GetBoolean(6),
                reader.GetFieldValue<DateTimeOffset>(7)));
        }

        return ServiceResult<IReadOnlyList<WaitlistEntryDto>>.Ok(rows);
    }

    // ═══════════════════════════════════════════════════════ the queue

    public async Task<ServiceResult<IReadOnlyList<PartnerApplicationDto>>> ApplicationsAsync(
        string? status,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(
            """
            SELECT a.id, a.user_id, u.full_name, u.phone_number,
                   a.tier_key, ti.display_name,
                   a.territory_id, t.name, t.kind,
                   a.applicant_note, a.contact_phone, a.status,
                   a.decision_reason, a.decided_at, du.full_name, a.created_at,
                   u.created_at,
                   (SELECT count(*) FROM udrive.bookings b
                     WHERE b.customer_user_id = a.user_id AND b.status = 'Completed'),
                   NOT EXISTS(SELECT 1 FROM udrive.partners p
                               WHERE p.territory_id = a.territory_id
                                 AND p.status IN ('Pending','Active','Suspended'))
            FROM udrive.partner_applications a
            JOIN udrive.users u ON u.id = a.user_id
            JOIN udrive.partner_tiers ti ON ti.tier_key = a.tier_key
            JOIN udrive.territories t ON t.id = a.territory_id
            LEFT JOIN udrive.users du ON du.id = a.decided_by_user_id
            WHERE (@status::text IS NULL OR a.status = @status)
            ORDER BY (a.status = 'Pending') DESC, a.created_at DESC
            LIMIT 400;
            """,
            connection);
        command.Parameters.AddWithValue(
            "status", string.IsNullOrWhiteSpace(status) ? DBNull.Value : status);

        var rows = new List<PartnerApplicationDto>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new PartnerApplicationDto(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.IsDBNull(2) ? null : reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetString(3),
                reader.GetString(4),
                reader.GetString(5),
                reader.GetGuid(6),
                reader.GetString(7),
                reader.GetString(8),
                reader.IsDBNull(9) ? null : reader.GetString(9),
                reader.IsDBNull(10) ? null : reader.GetString(10),
                reader.GetString(11),
                reader.IsDBNull(12) ? null : reader.GetString(12),
                reader.IsDBNull(13) ? null : reader.GetFieldValue<DateTimeOffset>(13),
                reader.IsDBNull(14) ? null : reader.GetString(14),
                reader.GetFieldValue<DateTimeOffset>(15),
                reader.IsDBNull(16) ? null : reader.GetFieldValue<DateTimeOffset>(16),
                (int)reader.GetInt64(17),
                reader.GetBoolean(18)));
        }

        return ServiceResult<IReadOnlyList<PartnerApplicationDto>>.Ok(rows);
    }

    /// <summary>Approve or refuse one application.</summary>
    /// <remarks>
    /// Approving does three things in one transaction: closes the application,
    /// creates the partner as <c>Pending</c>, and builds a Draft contract from the
    /// tier's current terms and commitments. All three or none — a partner with
    /// no contract has a territory and no obligations, which is the one state
    /// nobody could explain later.
    /// </remarks>
    public async Task<ServiceResult<object>> DecideAsync(
        Guid applicationId,
        PartnerDecisionRequest request,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        if (!request.Approve && string.IsNullOrWhiteSpace(request.Reason))
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status400BadRequest, "reason_required",
                "Say why. The applicant is shown this sentence.");
        }

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        Guid userId, territoryId;
        string tierKey;

        await using (var load = new NpgsqlCommand(
            """
            SELECT user_id, tier_key, territory_id
            FROM udrive.partner_applications
            WHERE id = @id AND status = 'Pending'
            FOR UPDATE;
            """,
            connection,
            transaction))
        {
            load.Parameters.AddWithValue("id", applicationId);
            await using var reader = await load.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<object>.Fail(
                    StatusCodes.Status409Conflict, "not_pending",
                    "That request has already been decided.");
            }

            userId = reader.GetGuid(0);
            tierKey = reader.GetString(1);
            territoryId = reader.GetGuid(2);
        }

        await using (var decide = new NpgsqlCommand(
            """
            UPDATE udrive.partner_applications
               SET status = @status, decided_by_user_id = @actor, decided_at = now(),
                   decision_reason = nullif(btrim(@reason), ''), updated_at = now()
             WHERE id = @id;
            """,
            connection,
            transaction))
        {
            decide.Parameters.AddWithValue("id", applicationId);
            decide.Parameters.AddWithValue("status", request.Approve ? "Approved" : "Rejected");
            decide.Parameters.AddWithValue("actor", (object?)actorId ?? DBNull.Value);
            decide.Parameters.AddWithValue("reason", (object?)request.Reason ?? string.Empty);
            await decide.ExecuteNonQueryAsync(cancellationToken);
        }

        if (!request.Approve)
        {
            await AuditAsync(connection, transaction, actorId, "PartnerApplicationRejected",
                "PartnerApplication", applicationId.ToString(),
                new { request.Reason }, cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return ServiceResult<object>.Ok(new { approved = false });
        }

        Guid partnerId;
        try
        {
            await using var insert = new NpgsqlCommand(
                """
                INSERT INTO udrive.partners
                    (user_id, tier_key, territory_id, application_id, status)
                VALUES (@user, @tier, @territory, @application, 'Pending')
                RETURNING id;
                """,
                connection,
                transaction);
            insert.Parameters.AddWithValue("user", userId);
            insert.Parameters.AddWithValue("tier", tierKey);
            insert.Parameters.AddWithValue("territory", territoryId);
            insert.Parameters.AddWithValue("application", applicationId);
            partnerId = (Guid)(await insert.ExecuteScalarAsync(cancellationToken))!;
        }
        catch (PostgresException error) when (error.SqlState == "23505")
        {
            // Somebody else was approved for this territory between the queue
            // loading and this click. The index caught it, which is exactly why
            // it is an index and not a service-level check.
            return ServiceResult<object>.Fail(
                StatusCodes.Status409Conflict, "territory_taken",
                "Another partner already holds that area. Refuse this request, or "
                + "ask the applicant for a different area.");
        }

        var contractId = await CreateContractAsync(
            connection, transaction, partnerId, null, null, null, null, actorId, cancellationToken);

        await AuditAsync(connection, transaction, actorId, "PartnerApplicationApproved",
            "PartnerApplication", applicationId.ToString(),
            new { partnerId, contractId, tierKey, territoryId }, cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<object>.Ok(new { approved = true, partnerId, contractId });
    }

    // ═════════════════════════════════════════════════════════ the partners

    public async Task<ServiceResult<IReadOnlyList<PartnerListItemDto>>> PartnersAsync(
        string? status,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var rows = await LoadPartnersAsync(connection, null, status, cancellationToken);
        return ServiceResult<IReadOnlyList<PartnerListItemDto>>.Ok(rows);
    }

    public async Task<ServiceResult<PartnerDetailDto>> PartnerDetailAsync(
        Guid partnerId,
        bool canViewEvidence,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        var partners = await LoadPartnersAsync(connection, partnerId, null, cancellationToken);
        if (partners.Count == 0)
        {
            return ServiceResult<PartnerDetailDto>.Fail(
                StatusCodes.Status404NotFound, "not_found", "That partner does not exist.");
        }

        var partner = partners[0];
        var contract = partner.ContractId is null
            ? null
            : await LoadContractAsync(connection, partner.ContractId.Value, cancellationToken);

        if (contract is { Status: "Signed" })
        {
            // Opening the screen refreshes the open months. An admin looking at a
            // partner's record is the moment the numbers are most likely to be
            // read aloud on a phone call.
            await PartnerMetricsService.RecomputeAsync(connection, contract.Id, cancellationToken);
        }

        var commitments = contract is null
            ? Array.Empty<PartnerCommitmentDto>()
            : await LoadCommitmentsAsync(
                connection, contract.Id, partner.TerritoryId, partner.TerritoryKind, cancellationToken);

        var periods = contract is null
            ? Array.Empty<PartnerPeriodDto>()
            : await LoadPeriodsAsync(connection, contract.Id, 12, cancellationToken);

        var statements = contract is null
            ? Array.Empty<PartnerStatementDto>()
            : await LoadStatementsAsync(connection, contract.Id, 12, cancellationToken);

        var evidence = contract is null
            ? null
            : await LoadEvidenceSummaryAsync(
                connection, contract.Id, canViewEvidence, cancellationToken);

        return ServiceResult<PartnerDetailDto>.Ok(new PartnerDetailDto(
            partner, contract, commitments, periods, statements, evidence));
    }

    public async Task<ServiceResult<object>> SetPartnerStatusAsync(
        Guid partnerId,
        PartnerStatusRequest request,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        if (request.Status is not ("Active" or "Suspended" or "Ended"))
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status400BadRequest, "status_invalid",
                "A partner is Active, Suspended or Ended.");
        }

        // Active is reached by signing, never by an admin setting it. A partner
        // marked Active without a signature holds an exclusive territory on the
        // strength of nothing, and the signature evidence is the whole point.
        if (request.Status == "Active")
        {
            await using var check = Open();
            await check.OpenAsync(cancellationToken);
            await using var signed = new NpgsqlCommand(
                """
                SELECT EXISTS(SELECT 1 FROM udrive.partner_contracts c
                               WHERE c.partner_id = @partner AND c.status = 'Signed');
                """,
                check);
            signed.Parameters.AddWithValue("partner", partnerId);
            if (await signed.ExecuteScalarAsync(cancellationToken) is not true)
            {
                return ServiceResult<object>.Fail(
                    StatusCodes.Status409Conflict, "not_signed",
                    "This partner has not signed a contract yet. They become active "
                    + "when they sign it in the partner portal.");
            }
        }

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.partners
               SET status = @status,
                   ended_at = CASE WHEN @status = 'Ended' THEN now() ELSE ended_at END,
                   end_reason = CASE WHEN @status = 'Ended'
                                     THEN nullif(btrim(@reason), '') ELSE end_reason END,
                   updated_at = now()
             WHERE id = @id;
            """,
            connection);
        command.Parameters.AddWithValue("id", partnerId);
        command.Parameters.AddWithValue("status", request.Status);
        command.Parameters.AddWithValue("reason", (object?)request.Reason ?? string.Empty);

        if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status404NotFound, "not_found", "That partner does not exist.");
        }

        await AuditAsync(connection, null, actorId, "PartnerStatusChanged", "Partner",
            partnerId.ToString(), new { request.Status, request.Reason }, cancellationToken);

        return ServiceResult<object>.Ok(new { partnerId, request.Status });
    }

    // ════════════════════════════════════════════════════════ the contract

    public async Task<ServiceResult<Guid>> CreateContractAsync(
        Guid partnerId,
        PartnerContractDraftRequest request,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            var id = await CreateContractAsync(
                connection, transaction, partnerId, request.TemplateId,
                request.SecurityDeposit, request.CommissionSharePct, request.TermMonths,
                actorId, cancellationToken);
            await transaction.CommitAsync(cancellationToken);
            return ServiceResult<Guid>.Created(id);
        }
        catch (PostgresException error) when (error.SqlState == "23505")
        {
            return ServiceResult<Guid>.Fail(
                StatusCodes.Status409Conflict, "contract_exists",
                "This partner already has a live contract. Terminate it before "
                + "writing a new one.");
        }
    }

    private static async Task<Guid> CreateContractAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid partnerId,
        Guid? templateId,
        decimal? deposit,
        decimal? sharePct,
        int? termMonths,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        // Everything the template's placeholders need, in one read.
        const string contextSql = """
            SELECT u.full_name, u.phone_number, t.name, t.kind,
                   ti.tier_key, ti.display_name, ti.security_deposit,
                   ti.commission_share_pct, ti.term_months
            FROM udrive.partners p
            JOIN udrive.users u ON u.id = p.user_id
            JOIN udrive.territories t ON t.id = p.territory_id
            JOIN udrive.partner_tiers ti ON ti.tier_key = p.tier_key
            WHERE p.id = @partner;
            """;

        string partnerName, partnerPhone, territoryName, territoryKind, tierKey;
        decimal tierDeposit, tierShare;
        int tierTerm;

        await using (var context = new NpgsqlCommand(contextSql, connection, transaction))
        {
            context.Parameters.AddWithValue("partner", partnerId);
            await using var reader = await context.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                throw new InvalidOperationException("That partner does not exist.");
            }

            partnerName = reader.GetString(0);
            partnerPhone = reader.GetString(1);
            territoryName = reader.GetString(2);
            territoryKind = reader.GetString(3);
            tierKey = reader.GetString(4);
            tierDeposit = reader.GetDecimal(6);
            tierShare = reader.GetDecimal(7);
            tierTerm = reader.GetInt32(8);
        }

        var finalDeposit = deposit ?? tierDeposit;
        var finalShare = sharePct ?? tierShare;
        var finalTerm = termMonths ?? tierTerm;

        // The tier's default commitments, copied — not referenced. This is the
        // list that goes into the contract text and into `partner_commitments`,
        // and from this moment it belongs to this contract alone.
        var commitments = new List<(string Metric, decimal Target, string Label, int Order)>();
        await using (var list = new NpgsqlCommand(
            """
            SELECT metric_key, target_value, label, sort_order
            FROM udrive.partner_tier_commitments
            WHERE tier_key = @tier AND is_active
            ORDER BY sort_order, metric_key;
            """,
            connection,
            transaction))
        {
            list.Parameters.AddWithValue("tier", tierKey);
            await using var reader = await list.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                commitments.Add((
                    reader.GetString(0), reader.GetDecimal(1), reader.GetString(2), reader.GetInt32(3)));
            }
        }

        string templateBody, templateScript;
        Guid? resolvedTemplateId = templateId;

        await using (var template = new NpgsqlCommand(
            """
            SELECT id, body_md, video_script
            FROM udrive.partner_contract_templates
            WHERE (@template::uuid IS NOT NULL AND id = @template)
               OR (@template::uuid IS NULL AND tier_key = @tier AND is_active)
            ORDER BY version DESC
            LIMIT 1;
            """,
            connection,
            transaction))
        {
            template.Parameters.AddWithValue("template", (object?)templateId ?? DBNull.Value);
            template.Parameters.AddWithValue("tier", tierKey);
            await using var reader = await template.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                resolvedTemplateId = reader.GetGuid(0);
                templateBody = reader.GetString(1);
                templateScript = reader.GetString(2);
            }
            else
            {
                // No template at all. Rather than refuse — which would leave an
                // approved partner stuck with nothing to sign — the contract is
                // created with a plain statement of the terms and the admin
                // edits it before sending.
                resolvedTemplateId = null;
                templateBody =
                    "# UDrive partnership agreement\n\n"
                    + "**Reference:** {{reference}}\n**Partner:** {{partner_name}} "
                    + "({{partner_phone}})\n**Territory:** {{territory_name}} "
                    + "({{territory_kind}})\n\nDeposit PKR {{security_deposit}}, "
                    + "share {{commission_share_pct}}% of UDrive's commission, term "
                    + "{{term_months}} months.\n\n{{commitments}}\n\n"
                    + "_No contract template was set up for this tier. Write the "
                    + "agreement here before sending it._";
                templateScript =
                    "Mera naam {{partner_name}} hai. Main UDrive ke sath "
                    + "{{territory_name}} ka partner ban raha hoon. Maine contract "
                    + "number {{reference}} poora parh liya hai aur apni marzi se "
                    + "qubool karta hoon. Aaj {{sign_date}} hai.";
            }
        }

        var reference = BuildReference();
        var commitmentText = commitments.Count == 0
            ? "_No monthly commitments are recorded for this tier._"
            : string.Join(
                "\n",
                commitments.Select(c => $"- {c.Label}: **{Trim(c.Target)}** per month"));

        var fields = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["reference"] = reference,
            ["partner_name"] = partnerName,
            ["partner_phone"] = partnerPhone,
            ["territory_name"] = territoryName,
            ["territory_kind"] = territoryKind,
            ["security_deposit"] = Money(finalDeposit),
            ["commission_share_pct"] = Trim(finalShare),
            ["term_months"] = finalTerm.ToString(CultureInfo.InvariantCulture),
            ["commitments"] = commitmentText,
            ["sent_date"] = DateTime.UtcNow.ToString("d MMMM yyyy", CultureInfo.InvariantCulture),
        };

        var renderedText = Fill(templateBody, fields);

        // `{{sign_date}}` is deliberately left in the script: it is filled by the
        // partner's own screen on the day they sign, and a date rendered now
        // would be wrong by the time anybody reads it aloud.
        var renderedScript = Fill(templateScript, fields, keep: ["sign_date"]);

        Guid contractId;
        await using (var insert = new NpgsqlCommand(
            """
            INSERT INTO udrive.partner_contracts
                (partner_id, template_id, reference, rendered_text, video_script,
                 security_deposit, commission_share_pct, term_months, status,
                 created_by_user_id)
            VALUES (@partner, @template, @reference, @text, @script,
                    @deposit, @share, @term, 'Draft', @actor)
            RETURNING id;
            """,
            connection,
            transaction))
        {
            insert.Parameters.AddWithValue("partner", partnerId);
            insert.Parameters.AddWithValue("template", (object?)resolvedTemplateId ?? DBNull.Value);
            insert.Parameters.AddWithValue("reference", reference);
            insert.Parameters.AddWithValue("text", renderedText);
            insert.Parameters.AddWithValue("script", renderedScript);
            insert.Parameters.AddWithValue("deposit", finalDeposit);
            insert.Parameters.AddWithValue("share", finalShare);
            insert.Parameters.AddWithValue("term", finalTerm);
            insert.Parameters.AddWithValue("actor", (object?)actorId ?? DBNull.Value);
            contractId = (Guid)(await insert.ExecuteScalarAsync(cancellationToken))!;
        }

        foreach (var (metric, target, label, order) in commitments)
        {
            await using var commitment = new NpgsqlCommand(
                """
                INSERT INTO udrive.partner_commitments
                    (contract_id, metric_key, target_value, label, sort_order)
                VALUES (@contract, @metric, @target, @label, @order)
                ON CONFLICT (contract_id, metric_key) DO NOTHING;
                """,
                connection,
                transaction);
            commitment.Parameters.AddWithValue("contract", contractId);
            commitment.Parameters.AddWithValue("metric", metric);
            commitment.Parameters.AddWithValue("target", target);
            commitment.Parameters.AddWithValue("label", label);
            commitment.Parameters.AddWithValue("order", order);
            await commitment.ExecuteNonQueryAsync(cancellationToken);
        }

        return contractId;
    }

    public async Task<ServiceResult<object>> EditContractAsync(
        Guid contractId,
        PartnerContractEditRequest request,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.RenderedText)
            || string.IsNullOrWhiteSpace(request.VideoScript))
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status400BadRequest, "text_required",
                "The contract text and the video words are both needed.");
        }

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        // Only a Draft. A Sent contract is sitting in front of the partner, and a
        // Signed one is settled — editing either rewrites what somebody read.
        await using (var update = new NpgsqlCommand(
            """
            UPDATE udrive.partner_contracts
               SET rendered_text = @text, video_script = @script,
                   security_deposit = @deposit, commission_share_pct = @share,
                   term_months = @term, updated_at = now()
             WHERE id = @id AND status = 'Draft';
            """,
            connection,
            transaction))
        {
            update.Parameters.AddWithValue("id", contractId);
            update.Parameters.AddWithValue("text", request.RenderedText);
            update.Parameters.AddWithValue("script", request.VideoScript);
            update.Parameters.AddWithValue("deposit", request.SecurityDeposit);
            update.Parameters.AddWithValue("share", request.CommissionSharePct);
            update.Parameters.AddWithValue("term", request.TermMonths);

            if (await update.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                return ServiceResult<object>.Fail(
                    StatusCodes.Status409Conflict, "not_draft",
                    "Only a draft can be edited. This contract has already been sent "
                    + "or signed.");
            }
        }

        if (request.Commitments is not null)
        {
            await using (var clear = new NpgsqlCommand(
                "DELETE FROM udrive.partner_commitments WHERE contract_id = @id;",
                connection,
                transaction))
            {
                clear.Parameters.AddWithValue("id", contractId);
                await clear.ExecuteNonQueryAsync(cancellationToken);
            }

            var order = 0;
            foreach (var commitment in request.Commitments)
            {
                await using var insert = new NpgsqlCommand(
                    """
                    INSERT INTO udrive.partner_commitments
                        (contract_id, metric_key, target_value, label, sort_order, is_active)
                    VALUES (@contract, @metric, @target, @label, @order, @active)
                    ON CONFLICT (contract_id, metric_key) DO UPDATE SET
                        target_value = excluded.target_value,
                        label = excluded.label,
                        is_active = excluded.is_active,
                        updated_at = now();
                    """,
                    connection,
                    transaction);
                insert.Parameters.AddWithValue("contract", contractId);
                insert.Parameters.AddWithValue("metric", commitment.MetricKey);
                insert.Parameters.AddWithValue("target", commitment.TargetValue);
                insert.Parameters.AddWithValue("label", commitment.Label);
                insert.Parameters.AddWithValue("order", order++);
                insert.Parameters.AddWithValue("active", commitment.IsActive);
                await insert.ExecuteNonQueryAsync(cancellationToken);
            }
        }

        await AuditAsync(connection, transaction, actorId, "PartnerContractEdited",
            "PartnerContract", contractId.ToString(),
            new { request.CommissionSharePct, request.SecurityDeposit, request.TermMonths },
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<object>.Ok(new { contractId });
    }

    public async Task<ServiceResult<object>> SendContractAsync(
        Guid contractId,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        await using (var update = new NpgsqlCommand(
            """
            UPDATE udrive.partner_contracts
               SET status = 'Sent', sent_at = now(), updated_at = now()
             WHERE id = @id AND status = 'Draft';
            """,
            connection,
            transaction))
        {
            update.Parameters.AddWithValue("id", contractId);
            if (await update.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                return ServiceResult<object>.Fail(
                    StatusCodes.Status409Conflict, "not_draft",
                    "Only a draft can be sent.");
            }
        }

        // The partner is told. Without this the contract sits in a portal nobody
        // has a reason to open.
        await using (var notify = new NpgsqlCommand(
            """
            INSERT INTO udrive.notifications
                (id, user_id, type, title, body, data_json, created_at, updated_at)
            SELECT gen_random_uuid(), p.user_id, 'PartnerContract',
                   'Your UDrive partner contract is ready',
                   'Open the partner portal to read it and sign. Contract '
                   || c.reference || '.',
                   jsonb_build_object('contractId', c.id::text, 'reference', c.reference),
                   now(), now()
            FROM udrive.partner_contracts c
            JOIN udrive.partners p ON p.id = c.partner_id
            WHERE c.id = @id;
            """,
            connection,
            transaction))
        {
            notify.Parameters.AddWithValue("id", contractId);
            await notify.ExecuteNonQueryAsync(cancellationToken);
        }

        await AuditAsync(connection, transaction, actorId, "PartnerContractSent",
            "PartnerContract", contractId.ToString(), new { contractId }, cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<object>.Ok(new { contractId, status = "Sent" });
    }

    public async Task<ServiceResult<object>> TerminateContractAsync(
        Guid contractId,
        PartnerTerminateRequest request,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Reason))
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status400BadRequest, "reason_required",
                "A termination has to carry a reason.");
        }

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        await using (var update = new NpgsqlCommand(
            """
            UPDATE udrive.partner_contracts
               SET status = 'Terminated', terminated_at = now(),
                   termination_reason = btrim(@reason), updated_at = now()
             WHERE id = @id AND status <> 'Terminated';
            """,
            connection,
            transaction))
        {
            update.Parameters.AddWithValue("id", contractId);
            update.Parameters.AddWithValue("reason", request.Reason);
            if (await update.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                return ServiceResult<object>.Fail(
                    StatusCodes.Status409Conflict, "already_terminated",
                    "That contract is already terminated.");
            }
        }

        // The territory goes back on the market in the same transaction. Leaving
        // the partner Active against a terminated contract is how a territory
        // ends up held by nobody and available to nobody.
        await using (var partner = new NpgsqlCommand(
            """
            UPDATE udrive.partners p
               SET status = 'Ended', ended_at = now(),
                   end_reason = btrim(@reason), updated_at = now()
             WHERE p.id = (SELECT partner_id FROM udrive.partner_contracts WHERE id = @id);
            """,
            connection,
            transaction))
        {
            partner.Parameters.AddWithValue("id", contractId);
            partner.Parameters.AddWithValue("reason", request.Reason);
            await partner.ExecuteNonQueryAsync(cancellationToken);
        }

        await AuditAsync(connection, transaction, actorId, "PartnerContractTerminated",
            "PartnerContract", contractId.ToString(), new { request.Reason }, cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<object>.Ok(new { contractId, status = "Terminated" });
    }

    public async Task<ServiceResult<IReadOnlyList<PartnerContractTemplateDto>>> TemplatesAsync(
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(
            """
            SELECT id, tier_key, version, title, body_md, video_script, is_active, created_at
            FROM udrive.partner_contract_templates
            ORDER BY tier_key, version DESC;
            """,
            connection);

        var rows = new List<PartnerContractTemplateDto>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new PartnerContractTemplateDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetInt32(2),
                reader.GetString(3),
                reader.GetString(4),
                reader.GetString(5),
                reader.GetBoolean(6),
                reader.GetFieldValue<DateTimeOffset>(7)));
        }

        return ServiceResult<IReadOnlyList<PartnerContractTemplateDto>>.Ok(rows);
    }

    /// <summary>Edits a template in place, or writes the next version of it.</summary>
    /// <remarks>
    /// Editing in place is safe here only because contracts carry their own
    /// rendered copy. The version column exists so the admin can keep the old
    /// wording visible next to the new one rather than having to remember it.
    /// </remarks>
    public async Task<ServiceResult<object>> SaveTemplateAsync(
        Guid templateId,
        PartnerContractTemplateRequest request,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.BodyMd) || string.IsNullOrWhiteSpace(request.VideoScript))
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status400BadRequest, "text_required",
                "The agreement text and the video words are both needed.");
        }

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.partner_contract_templates
               SET title = @title, body_md = @body, video_script = @script,
                   is_active = @active, updated_at = now()
             WHERE id = @id;
            """,
            connection);
        command.Parameters.AddWithValue("id", templateId);
        command.Parameters.AddWithValue("title", request.Title);
        command.Parameters.AddWithValue("body", request.BodyMd);
        command.Parameters.AddWithValue("script", request.VideoScript);
        command.Parameters.AddWithValue("active", request.IsActive);

        if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status404NotFound, "not_found", "That template does not exist.");
        }

        await AuditAsync(connection, null, actorId, "PartnerTemplateUpdated",
            "PartnerContractTemplate", templateId.ToString(),
            new { request.Title, request.IsActive }, cancellationToken);

        return ServiceResult<object>.Ok(new { templateId });
    }

    // ══════════════════════════════════════════ periods and statements

    public async Task<ServiceResult<object>> RecomputeAsync(
        Guid contractId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await PartnerMetricsService.RecomputeAsync(connection, contractId, cancellationToken);
        return ServiceResult<object>.Ok(new { contractId, recomputed = true });
    }

    public async Task<ServiceResult<object>> RecordPeriodAsync(
        Guid periodId,
        PartnerPeriodRecordRequest request,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        if (request.Status is not ("Open" or "Met" or "Missed" or "Waived"))
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status400BadRequest, "status_invalid",
                "A month is Open, Met, Missed or Waived.");
        }

        if (request.Status == "Waived" && string.IsNullOrWhiteSpace(request.Note))
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status400BadRequest, "note_required",
                "Waiving a missed month needs a reason written down.");
        }

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.partner_commitment_periods
               SET actual_value = coalesce(@actual, actual_value),
                   status = @status,
                   note = nullif(btrim(@note), ''),
                   recorded_by_user_id = @actor,
                   computed_at = now()
             WHERE id = @id;
            """,
            connection);
        command.Parameters.AddWithValue("id", periodId);
        command.Parameters.AddWithValue("actual", (object?)request.ActualValue ?? DBNull.Value);
        command.Parameters.AddWithValue("status", request.Status);
        command.Parameters.AddWithValue("note", (object?)request.Note ?? string.Empty);
        command.Parameters.AddWithValue("actor", (object?)actorId ?? DBNull.Value);

        if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status404NotFound, "not_found", "That month does not exist.");
        }

        await AuditAsync(connection, null, actorId, "PartnerPeriodRecorded",
            "PartnerCommitmentPeriod", periodId.ToString(),
            new { request.Status, request.ActualValue, request.Note }, cancellationToken);

        return ServiceResult<object>.Ok(new { periodId, request.Status });
    }

    public async Task<ServiceResult<object>> CloseStatementAsync(
        Guid statementId,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        // A month still running cannot be closed. Closing it freezes a figure
        // that has days left to grow, and the partner would be shown a final
        // number that is simply short.
        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.partner_month_statements
               SET status = 'Closed', closed_by_user_id = @actor, updated_at = now()
             WHERE id = @id AND status = 'Open'
               AND period_end < (now() AT TIME ZONE 'utc')::date;
            """,
            connection);
        command.Parameters.AddWithValue("id", statementId);
        command.Parameters.AddWithValue("actor", (object?)actorId ?? DBNull.Value);

        if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status409Conflict, "cannot_close",
                "Only a finished month that is still open can be agreed.");
        }

        await AuditAsync(connection, null, actorId, "PartnerStatementClosed",
            "PartnerMonthStatement", statementId.ToString(), new { statementId }, cancellationToken);

        return ServiceResult<object>.Ok(new { statementId, status = "Closed" });
    }

    public async Task<ServiceResult<object>> MarkStatementPaidAsync(
        Guid statementId,
        PartnerStatementPaidRequest request,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Reference))
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status400BadRequest, "reference_required",
                "Write the payment reference — a bank transfer number, or how it was paid.");
        }

        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.partner_month_statements
               SET status = 'Paid', paid_reference = btrim(@reference), paid_at = now(),
                   note = coalesce(nullif(btrim(@note), ''), note), updated_at = now()
             WHERE id = @id AND status = 'Closed';
            """,
            connection);
        command.Parameters.AddWithValue("id", statementId);
        command.Parameters.AddWithValue("reference", request.Reference);
        command.Parameters.AddWithValue("note", (object?)request.Note ?? string.Empty);

        if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status409Conflict, "not_closed",
                "Agree the month first, then record the payment against it.");
        }

        await AuditAsync(connection, null, actorId, "PartnerStatementPaid",
            "PartnerMonthStatement", statementId.ToString(),
            new { request.Reference }, cancellationToken);

        return ServiceResult<object>.Ok(new { statementId, status = "Paid" });
    }

    // ═════════════════════════════════════════════════════ the evidence

    /// <summary>
    /// The selfie, the video and the three server-side facts — SuperAdmin only.
    /// </summary>
    /// <remarks>
    /// The audit row is written <b>before</b> the data is returned, and in the
    /// same connection. Written afterwards it would be missing for exactly the
    /// request that failed halfway, which is the one anybody would want to look
    /// up.
    /// </remarks>
    public async Task<ServiceResult<PartnerEvidenceDto>> ViewEvidenceAsync(
        Guid contractId,
        Guid? actorId,
        string? ipAddress,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await AuditAsync(connection, null, actorId, "PartnerSignatureEvidenceViewed",
            "PartnerContract", contractId.ToString(),
            new { contractId, viewedFrom = ipAddress }, cancellationToken);

        await using var command = new NpgsqlCommand(
            """
            SELECT e.contract_id, c.reference, u.full_name, e.selfie_url, e.video_url,
                   e.script_shown, e.signed_at_server, e.phone_number, e.ip_address,
                   e.device_info, e.purge_after, e.purged_at
            FROM udrive.partner_signature_evidence e
            JOIN udrive.partner_contracts c ON c.id = e.contract_id
            JOIN udrive.partners p ON p.id = c.partner_id
            JOIN udrive.users u ON u.id = p.user_id
            WHERE e.contract_id = @id;
            """,
            connection);
        command.Parameters.AddWithValue("id", contractId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<PartnerEvidenceDto>.Fail(
                StatusCodes.Status404NotFound, "not_found",
                "There is no signature evidence for that contract.");
        }

        if (!reader.IsDBNull(11))
        {
            return ServiceResult<PartnerEvidenceDto>.Fail(
                StatusCodes.Status410Gone, "purged",
                "This evidence was deleted on "
                + reader.GetFieldValue<DateTimeOffset>(11).ToString("d MMMM yyyy", CultureInfo.InvariantCulture)
                + ".");
        }

        return ServiceResult<PartnerEvidenceDto>.Ok(new PartnerEvidenceDto(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetString(4),
            reader.GetString(5),
            reader.GetFieldValue<DateTimeOffset>(6),
            reader.IsDBNull(7) ? null : reader.GetString(7),
            reader.IsDBNull(8) ? null : reader.GetString(8),
            reader.IsDBNull(9) ? null : reader.GetString(9),
            reader.IsDBNull(10) ? null : reader.GetFieldValue<DateOnly>(10)));
    }

    /// <summary>
    /// Checks that this file really belongs to this contract's evidence, and logs
    /// the view — before the bytes are served.
    /// </summary>
    /// <remarks>
    /// The filename is checked against the row rather than trusted, so a
    /// SuperAdmin cannot reach a file by constructing a path, and a purged
    /// contract's URL stops working rather than falling through to whatever is
    /// still on disk.
    /// </remarks>
    public async Task<ServiceResult<object>> LogEvidenceFileAsync(
        Guid contractId,
        string fileName,
        Guid? actorId,
        string? ipAddress,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        await using var check = new NpgsqlCommand(
            """
            SELECT purged_at IS NULL
              AND (selfie_url LIKE '%/' || @file OR video_url LIKE '%/' || @file)
            FROM udrive.partner_signature_evidence
            WHERE contract_id = @id;
            """,
            connection);
        check.Parameters.AddWithValue("id", contractId);
        check.Parameters.AddWithValue("file", fileName);

        var allowed = await check.ExecuteScalarAsync(cancellationToken);
        if (allowed is not true)
        {
            return ServiceResult<object>.Fail(
                StatusCodes.Status404NotFound, "not_found",
                "That file is not part of this contract's signature record.");
        }

        await AuditAsync(connection, null, actorId, "PartnerSignatureEvidenceFileServed",
            "PartnerContract", contractId.ToString(),
            new { fileName, viewedFrom = ipAddress }, cancellationToken);

        return ServiceResult<object>.Ok(new { contractId, fileName });
    }

    /// <summary>Deletes the photograph and the video, keeping that it happened.</summary>
    public async Task<ServiceResult<object>> PurgeEvidenceAsync(
        Guid contractId,
        LocalFileStorageService storage,
        Guid? actorId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);

        string selfie, video;
        await using (var load = new NpgsqlCommand(
            """
            SELECT selfie_url, video_url FROM udrive.partner_signature_evidence
            WHERE contract_id = @id AND purged_at IS NULL;
            """,
            connection))
        {
            load.Parameters.AddWithValue("id", contractId);
            await using var reader = await load.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<object>.Fail(
                    StatusCodes.Status404NotFound, "not_found",
                    "There is nothing left to delete for that contract.");
            }

            selfie = reader.GetString(0);
            video = reader.GetString(1);
        }

        // The evidence-specific delete, not `DeleteProtectedFile`: that one
        // resolves through `AllowedExtensions`, which has never included video,
        // so it would silently leave the recording on disk and report success.
        storage.DeleteSignatureEvidence(selfie);
        storage.DeleteSignatureEvidence(video);

        // The row stays, with the paths emptied. That a signature was made, when,
        // and from where is part of the contract's history; the photograph is not.
        await using (var update = new NpgsqlCommand(
            """
            UPDATE udrive.partner_signature_evidence
               SET selfie_url = '', video_url = '',
                   purged_at = now(), purged_by_user_id = @actor
             WHERE contract_id = @id;
            """,
            connection))
        {
            update.Parameters.AddWithValue("id", contractId);
            update.Parameters.AddWithValue("actor", (object?)actorId ?? DBNull.Value);
            await update.ExecuteNonQueryAsync(cancellationToken);
        }

        await AuditAsync(connection, null, actorId, "PartnerSignatureEvidencePurged",
            "PartnerContract", contractId.ToString(), new { contractId }, cancellationToken);

        return ServiceResult<object>.Ok(new { contractId, purged = true });
    }

    // ═══════════════════════════════════════════════════ shared loaders

    /// <remarks>
    /// Public and static because the partner portal shows the partner exactly the
    /// rows the admin sees. Two queries would eventually disagree, and the
    /// disagreement would surface as a partner on the telephone insisting their
    /// screen says something else.
    /// </remarks>
    public static async Task<IReadOnlyList<PartnerListItemDto>> LoadPartnersAsync(
        NpgsqlConnection connection,
        Guid? partnerId,
        string? status,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT p.id, p.user_id, u.full_name, u.phone_number,
                   p.tier_key, ti.display_name,
                   p.territory_id, t.name, t.kind,
                   p.status, p.started_at, p.ended_at,
                   c.id, c.reference, c.status,
                   coalesce(c.commission_share_pct, ti.commission_share_pct),
                   coalesce(c.security_deposit, ti.security_deposit),
                   (SELECT count(*) FROM udrive.partner_commitment_periods cp
                     WHERE cp.contract_id = c.id AND cp.status = 'Met'),
                   (SELECT count(*) FROM udrive.partner_commitment_periods cp
                     WHERE cp.contract_id = c.id AND cp.status = 'Missed'),
                   (SELECT coalesce(sum(s.share_amount), 0)
                      FROM udrive.partner_month_statements s
                     WHERE s.contract_id = c.id
                       AND s.period_start = date_trunc('month', now())::date)
            FROM udrive.partners p
            JOIN udrive.users u ON u.id = p.user_id
            JOIN udrive.partner_tiers ti ON ti.tier_key = p.tier_key
            JOIN udrive.territories t ON t.id = p.territory_id
            LEFT JOIN udrive.partner_contracts c
                   ON c.partner_id = p.id AND c.status <> 'Terminated'
            WHERE (@id::uuid IS NULL OR p.id = @id)
              AND (@status::text IS NULL OR p.status = @status)
            ORDER BY (p.status = 'Active') DESC, t.name;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", (object?)partnerId ?? DBNull.Value);
        command.Parameters.AddWithValue(
            "status", string.IsNullOrWhiteSpace(status) ? DBNull.Value : status);

        var rows = new List<PartnerListItemDto>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new PartnerListItemDto(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetString(3),
                reader.GetString(4),
                reader.GetString(5),
                reader.GetGuid(6),
                reader.GetString(7),
                reader.GetString(8),
                reader.GetString(9),
                reader.IsDBNull(10) ? null : reader.GetFieldValue<DateTimeOffset>(10),
                reader.IsDBNull(11) ? null : reader.GetFieldValue<DateTimeOffset>(11),
                reader.IsDBNull(12) ? null : reader.GetGuid(12),
                reader.IsDBNull(13) ? null : reader.GetString(13),
                reader.IsDBNull(14) ? null : reader.GetString(14),
                reader.GetDecimal(15),
                reader.GetDecimal(16),
                (int)reader.GetInt64(17),
                (int)reader.GetInt64(18),
                reader.GetDecimal(19)));
        }

        return rows;
    }

    public static async Task<PartnerContractDto?> LoadContractAsync(
        NpgsqlConnection connection,
        Guid contractId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT id, partner_id, reference, status, rendered_text, video_script,
                   security_deposit, commission_share_pct, term_months,
                   sent_at, signed_at, starts_at, ends_at, terminated_at, termination_reason
            FROM udrive.partner_contracts
            WHERE id = @id;
            """,
            connection);
        command.Parameters.AddWithValue("id", contractId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new PartnerContractDto(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetString(4),
            reader.GetString(5),
            reader.GetDecimal(6),
            reader.GetDecimal(7),
            reader.GetInt32(8),
            reader.IsDBNull(9) ? null : reader.GetFieldValue<DateTimeOffset>(9),
            reader.IsDBNull(10) ? null : reader.GetFieldValue<DateTimeOffset>(10),
            reader.IsDBNull(11) ? null : reader.GetFieldValue<DateTimeOffset>(11),
            reader.IsDBNull(12) ? null : reader.GetFieldValue<DateTimeOffset>(12),
            reader.IsDBNull(13) ? null : reader.GetFieldValue<DateTimeOffset>(13),
            reader.IsDBNull(14) ? null : reader.GetString(14));
    }

    public static async Task<IReadOnlyList<PartnerCommitmentDto>> LoadCommitmentsAsync(
        NpgsqlConnection connection,
        Guid contractId,
        Guid territoryId,
        string territoryKind,
        CancellationToken cancellationToken)
    {
        var snapshot = await PartnerMetricsService.SnapshotAsync(
            connection, territoryId, PartnerMetricsService.MonthStart(DateTimeOffset.UtcNow),
            cancellationToken);

        // The one sentence that stops a Tehsil Head concluding the app is broken.
        var caveat = territoryKind == "Tehsil" && !snapshot.HasAssignedDrivers
            ? "No drivers have been assigned to this tehsil yet, so these counts are "
              + "zero. An admin assigns drivers to a tehsil from the driver's own page."
            : null;

        await using var command = new NpgsqlCommand(
            """
            SELECT c.id, c.metric_key, c.target_value, c.label, c.is_active,
                   cp.actual_value, cp.status
            FROM udrive.partner_commitments c
            LEFT JOIN udrive.partner_commitment_periods cp
                   ON cp.commitment_id = c.id
                  AND cp.period_start = date_trunc('month', now())::date
            WHERE c.contract_id = @contract
            ORDER BY c.sort_order, c.metric_key;
            """,
            connection);
        command.Parameters.AddWithValue("contract", contractId);

        var rows = new List<PartnerCommitmentDto>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var metric = reader.GetString(1);
            var manual = PartnerMetricsService.IsManual(metric);

            // A manual metric shows what was reported; everything else shows the
            // live figure, which may be ahead of the stored row by minutes.
            var current = manual
                ? reader.IsDBNull(5) ? 0m : reader.GetDecimal(5)
                : PartnerMetricsService.MetricValue(snapshot, metric);

            rows.Add(new PartnerCommitmentDto(
                reader.GetGuid(0),
                metric,
                reader.GetDecimal(2),
                reader.GetString(3),
                reader.GetBoolean(4),
                current,
                reader.IsDBNull(6) ? "Open" : reader.GetString(6),
                manual,
                manual ? null : caveat));
        }

        return rows;
    }

    public static async Task<IReadOnlyList<PartnerPeriodDto>> LoadPeriodsAsync(
        NpgsqlConnection connection,
        Guid contractId,
        int months,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT cp.id, cp.commitment_id, cp.metric_key, c.label,
                   cp.period_start, cp.period_end, cp.target_value, cp.actual_value,
                   cp.status, cp.note, cp.computed_at
            FROM udrive.partner_commitment_periods cp
            JOIN udrive.partner_commitments c ON c.id = cp.commitment_id
            WHERE cp.contract_id = @contract
            ORDER BY cp.period_start DESC, c.sort_order
            LIMIT @limit;
            """,
            connection);
        command.Parameters.AddWithValue("contract", contractId);
        command.Parameters.AddWithValue("limit", months * 6);

        var rows = new List<PartnerPeriodDto>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new PartnerPeriodDto(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetFieldValue<DateOnly>(4),
                reader.GetFieldValue<DateOnly>(5),
                reader.GetDecimal(6),
                reader.GetDecimal(7),
                reader.GetString(8),
                reader.IsDBNull(9) ? null : reader.GetString(9),
                reader.GetFieldValue<DateTimeOffset>(10)));
        }

        return rows;
    }

    public static async Task<IReadOnlyList<PartnerStatementDto>> LoadStatementsAsync(
        NpgsqlConnection connection,
        Guid contractId,
        int months,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT id, period_start, period_end, completed_rides, gross_fares,
                   commission_base, share_pct, share_amount, status,
                   paid_reference, paid_at, note, computed_at
            FROM udrive.partner_month_statements
            WHERE contract_id = @contract
            ORDER BY period_start DESC
            LIMIT @limit;
            """,
            connection);
        command.Parameters.AddWithValue("contract", contractId);
        command.Parameters.AddWithValue("limit", months);

        var rows = new List<PartnerStatementDto>();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(new PartnerStatementDto(
                reader.GetGuid(0),
                reader.GetFieldValue<DateOnly>(1),
                reader.GetFieldValue<DateOnly>(2),
                reader.GetInt32(3),
                reader.GetDecimal(4),
                reader.GetDecimal(5),
                reader.GetDecimal(6),
                reader.GetDecimal(7),
                reader.GetString(8),
                reader.IsDBNull(9) ? null : reader.GetString(9),
                reader.IsDBNull(10) ? null : reader.GetFieldValue<DateTimeOffset>(10),
                reader.IsDBNull(11) ? null : reader.GetString(11),
                reader.GetFieldValue<DateTimeOffset>(12)));
        }

        return rows;
    }

    public static async Task<PartnerEvidenceSummaryDto?> LoadEvidenceSummaryAsync(
        NpgsqlConnection connection,
        Guid contractId,
        bool canView,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT signed_at_server, phone_number, ip_address, device_info,
                   purge_after, purged_at
            FROM udrive.partner_signature_evidence
            WHERE contract_id = @id;
            """,
            connection);
        command.Parameters.AddWithValue("id", contractId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return new PartnerEvidenceSummaryDto(
                false, null, null, null, null, null, null, false);
        }

        return new PartnerEvidenceSummaryDto(
            true,
            reader.GetFieldValue<DateTimeOffset>(0),
            reader.IsDBNull(1) ? null : reader.GetString(1),
            reader.IsDBNull(2) ? null : reader.GetString(2),
            reader.IsDBNull(3) ? null : reader.GetString(3),
            reader.IsDBNull(4) ? null : reader.GetFieldValue<DateOnly>(4),
            reader.IsDBNull(5) ? null : reader.GetFieldValue<DateTimeOffset>(5),
            canView && reader.IsDBNull(5));
    }

    public static string PayoutSentence => PayoutNote;

    // ───────────────────────────────────────────────────────────── helpers

    private static string BuildReference() =>
        "UD-PT-"
        + DateTime.UtcNow.ToString("yyyyMM", CultureInfo.InvariantCulture)
        + "-"
        + Guid.NewGuid().ToString("N")[..5].ToUpperInvariant();

    private static string Money(decimal value) =>
        value.ToString("#,##0", CultureInfo.InvariantCulture);

    /// <summary>Drops a trailing `.00` so a target reads as "6", not "6.00".</summary>
    private static string Trim(decimal value) =>
        value == decimal.Truncate(value)
            ? decimal.Truncate(value).ToString(CultureInfo.InvariantCulture)
            : value.ToString("0.##", CultureInfo.InvariantCulture);

    /// <param name="keep">
    /// Placeholders to leave in place. `{{sign_date}}` is filled on the day of
    /// signing, by the screen that shows the words.
    /// </param>
    private static string Fill(
        string template,
        IReadOnlyDictionary<string, string> fields,
        IReadOnlyCollection<string>? keep = null)
    {
        var builder = new StringBuilder(template);
        foreach (var (key, value) in fields)
        {
            if (keep is not null && keep.Contains(key))
            {
                continue;
            }

            builder.Replace("{{" + key + "}}", value);
        }

        return builder.ToString();
    }

    private static async Task AuditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        Guid? actorId,
        string action,
        string entityType,
        string entityId,
        object changes,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.audit_logs
                (id, actor_user_id, action, entity_type, entity_id, changes_json,
                 created_at, updated_at)
            VALUES (gen_random_uuid(), @actor, @action, @type, @entity,
                    cast(@changes as jsonb), now(), now());
            """,
            connection,
            transaction);
        command.Parameters.AddWithValue("actor", (object?)actorId ?? DBNull.Value);
        command.Parameters.AddWithValue("action", action);
        command.Parameters.AddWithValue("type", entityType);
        command.Parameters.AddWithValue("entity", entityId);
        command.Parameters.AddWithValue("changes", JsonSerializer.Serialize(changes));
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
