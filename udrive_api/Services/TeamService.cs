using System.Text.Json;
using Microsoft.Extensions.Caching.Memory;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Security;

namespace UDrive.Api.Services;

public sealed record TeamPermissionDto(string Module, bool View, bool Edit, bool Approve, bool Delete);

public sealed record TeamAreaDto(Guid Id, string Name, string Kind, string? DistrictName);

public sealed record TeamUserDto(
    Guid Id,
    string FullName,
    string PhoneNumber,
    string? Username,
    string Status,
    bool Editable,
    string Template,
    bool AllAreas,
    IReadOnlyList<TeamAreaDto> Areas,
    IReadOnlyList<TeamPermissionDto> Permissions,
    IReadOnlyList<string> Roles,
    DateTimeOffset? LastLoginAt,
    DateTimeOffset CreatedAt);

public sealed record TeamModuleDto(string Key, string Label, string Group, IReadOnlyList<string> Actions, IReadOnlyList<string> PortalRoutes);

public sealed record TeamTemplateDto(string Key, string Label, IReadOnlyList<TeamPermissionDto> Permissions);

public sealed record TeamCatalogDto(IReadOnlyList<TeamModuleDto> Modules, IReadOnlyList<TeamTemplateDto> Templates);

public sealed record SaveTeamUserRequest(
    string FullName,
    string PhoneNumber,
    string? Username,
    string? Password,
    bool IsActive,
    string? Template,
    bool AllAreas,
    IReadOnlyList<Guid>? AreaIds,
    IReadOnlyList<TeamPermissionDto>? Permissions);

public sealed record TeamStatusRequest(bool IsActive);

/// <summary>What the signed-in portal user may open, for hiding menus and buttons.</summary>
public sealed record TeamMeDto(
    bool FullAccess,
    IReadOnlyList<TeamPermissionDto> Permissions,
    bool AllAreas,
    IReadOnlyList<TeamAreaDto> Areas);

/// <summary>Operations → Team: portal users with chosen modules and areas.</summary>
/// <remarks>
/// A team user has the role Staff and nothing broader. What they may do lives
/// in staff_permissions and staff_areas, checked on every request by
/// <see cref="TeamAccessMiddleware"/>. A team user who may manage the team can
/// only hand out what they hold themselves, and only inside their own areas.
/// </remarks>
public sealed class TeamService(string connectionString, AuthService auth, IMemoryCache cache)
{
    public TeamCatalogDto Catalog() => new(
        TeamAccess.Modules.Select(m => new TeamModuleDto(m.Key, m.Label, m.Group, m.Actions, m.PortalRoutes)).ToList(),
        TeamAccess.Templates.Select(t => new TeamTemplateDto(
            t.Key, t.Value.Label,
            t.Value.Grants.Select(g => new TeamPermissionDto(
                g.Key, g.Value.Contains("view"), g.Value.Contains("edit"), g.Value.Contains("approve"), g.Value.Contains("delete"))).ToList()))
            .ToList());

    public async Task<ServiceResult<TeamMeDto>> MeAsync(Guid userId, bool teamUser, CancellationToken ct)
    {
        if (!teamUser) return ServiceResult<TeamMeDto>.Ok(new TeamMeDto(true, [], true, []));
        await using var connection = await OpenAsync(ct);
        var grant = await TeamAccess.LoadGrantAsync(connection, userId, ct);
        return ServiceResult<TeamMeDto>.Ok(new TeamMeDto(
            false,
            grant.Modules.Select(kv => new TeamPermissionDto(kv.Key, kv.Value.View, kv.Value.Edit, kv.Value.Approve, kv.Value.Delete)).ToList(),
            grant.AllAreas,
            await AreaRowsAsync(connection, grant.Areas, ct)));
    }

    public async Task<ServiceResult<IReadOnlyList<TeamUserDto>>> ListAsync(CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        var ids = new List<Guid>();
        await using (var command = new NpgsqlCommand(
            """
            SELECT DISTINCT u.id, (SELECT bool_or(r2.role = 'SuperAdmin') FROM udrive.user_roles r2 WHERE r2.user_id = u.id), u.created_at
            FROM udrive.users u
            JOIN udrive.user_roles r ON r.user_id = u.id
            WHERE r.role IN ('Staff', 'SuperAdmin', 'Admin', 'Manager', 'Operations', 'VerificationOfficer',
                             'SupportAgent', 'FinanceOfficer', 'SafetyOfficer', 'TourismManager')
              AND u.status <> 'Deleted'
            ORDER BY 2 DESC, u.created_at;
            """, connection))
        {
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct)) ids.Add(reader.GetGuid(0));
        }

        var list = new List<TeamUserDto>();
        foreach (var id in ids)
        {
            var user = await LoadAsync(connection, id, ct);
            if (user is not null) list.Add(user);
        }

        return ServiceResult<IReadOnlyList<TeamUserDto>>.Ok(list);
    }

    public async Task<ServiceResult<TeamUserDto>> GetAsync(Guid id, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        var user = await LoadAsync(connection, id, ct);
        return user is null ? Fail<TeamUserDto>(404, "not_found", "That team user was not found.") : ServiceResult<TeamUserDto>.Ok(user);
    }

    public async Task<ServiceResult<TeamUserDto>> SaveAsync(
        Guid actorId, bool actorIsTeamUser, Guid? id, SaveTeamUserRequest request, CancellationToken ct)
    {
        var name = request.FullName?.Trim() ?? string.Empty;
        if (name.Length < 2) return Fail<TeamUserDto>(400, "name_required", "Enter the full name.");
        if (!PhoneNumberNormalizer.TryNormalizePakistan(request.PhoneNumber, out var phone))
        {
            return Fail<TeamUserDto>(400, "invalid_phone_number", "Enter a valid Pakistani mobile number, for example 03001234567.");
        }

        var permissions = CleanPermissions(request.Permissions);
        if (permissions is null) return Fail<TeamUserDto>(400, "permission_invalid", "One of the permissions is not a known module or action.");
        var areaIds = (request.AreaIds ?? []).Distinct().Take(200).ToArray();
        if (!request.AllAreas && areaIds.Length == 0 && permissions.Any(p => p.Module.StartsWith("verification.", StringComparison.Ordinal)))
        {
            return Fail<TeamUserDto>(400, "areas_required", "Choose at least one district or tehsil, or All areas.");
        }

        if (id is null && string.IsNullOrWhiteSpace(request.Password))
        {
            return Fail<TeamUserDto>(400, "password_required", "Set a password for the new user.");
        }

        var username = string.IsNullOrWhiteSpace(request.Username)
            ? "0" + phone[^10..]
            : request.Username.Trim();

        await using var connection = await OpenAsync(ct);

        // A team user who manages the team hands out only what they hold.
        if (actorIsTeamUser)
        {
            var mine = await TeamAccess.LoadGrantAsync(connection, actorId, ct);
            foreach (var p in permissions)
            {
                mine.Modules.TryGetValue(p.Module, out var held);
                if ((p.View && held?.View != true) || (p.Edit && held?.Edit != true)
                    || (p.Approve && held?.Approve != true) || (p.Delete && held?.Delete != true))
                {
                    return Fail<TeamUserDto>(403, "permission_not_held",
                        "You can only give permissions you have yourself.");
                }
            }

            if (!mine.AllAreas && (request.AllAreas || !await AreasWithinAsync(connection, areaIds, mine.Areas, ct)))
            {
                return Fail<TeamUserDto>(403, "area_not_held", "You can only give areas you have yourself.");
            }
        }

        if (areaIds.Length > 0 && !await AreasExistAsync(connection, areaIds, ct))
        {
            return Fail<TeamUserDto>(400, "area_invalid", "One of the areas was not found.");
        }

        Guid userId;
        await using (var transaction = await connection.BeginTransactionAsync(ct))
        {
            try
            {
                if (id is null)
                {
                    // An existing account (for example a customer) can be made a team
                    // user; a SuperAdmin or Admin cannot be turned into one.
                    await using (var find = new NpgsqlCommand(
                        """
                        SELECT u.id, EXISTS (SELECT 1 FROM udrive.user_roles r WHERE r.user_id = u.id
                                             AND r.role IN ('SuperAdmin', 'Admin', 'Manager', 'Operations', 'VerificationOfficer',
                                                            'SupportAgent', 'FinanceOfficer', 'SafetyOfficer', 'TourismManager'))
                        FROM udrive.users u WHERE u.phone_number = @phone;
                        """, connection, transaction))
                    {
                        find.Parameters.AddWithValue("phone", phone);
                        await using var reader = await find.ExecuteReaderAsync(ct);
                        if (await reader.ReadAsync(ct))
                        {
                            if (reader.GetBoolean(1))
                            {
                                return Fail<TeamUserDto>(409, "already_portal_user",
                                    "This number already has full portal access.");
                            }

                            userId = reader.GetGuid(0);
                        }
                        else
                        {
                            userId = Guid.Empty;
                        }
                    }

                    if (userId == Guid.Empty)
                    {
                        userId = Guid.NewGuid();
                        await using var insert = new NpgsqlCommand(
                            """
                            INSERT INTO udrive.users (id, phone_number, full_name, role, status, preferred_language,
                                                      phone_verified, token_version, created_at, updated_at)
                            VALUES (@id, @phone, @name, 'Staff', 'Approved', 'en', false, 0, now(), now());
                            """, connection, transaction);
                        insert.Parameters.AddWithValue("id", userId);
                        insert.Parameters.AddWithValue("phone", phone);
                        insert.Parameters.AddWithValue("name", name);
                        await insert.ExecuteNonQueryAsync(ct);
                    }

                    await using var role = new NpgsqlCommand(
                        "INSERT INTO udrive.user_roles (user_id, role, created_at) VALUES (@id, 'Staff', now()) ON CONFLICT DO NOTHING;",
                        connection, transaction);
                    role.Parameters.AddWithValue("id", userId);
                    await role.ExecuteNonQueryAsync(ct);
                }
                else
                {
                    userId = id.Value;
                    if (!await IsTeamUserAsync(connection, transaction, userId, ct))
                    {
                        return Fail<TeamUserDto>(409, "not_team_user",
                            "Only team users can be edited here. Full-access portal users keep their role.");
                    }
                }

                await using (var update = new NpgsqlCommand(
                    """
                    UPDATE udrive.users
                    SET full_name = @name, phone_number = @phone,
                        status = CASE WHEN @active THEN 'Approved' ELSE 'Suspended' END,
                        token_version = token_version + CASE WHEN status = 'Approved' AND NOT @active THEN 1 ELSE 0 END,
                        updated_at = now()
                    WHERE id = @id;

                    INSERT INTO udrive.staff_profiles (user_id, template, all_areas, created_by, updated_by)
                    VALUES (@id, @template, @allAreas, @actor, @actor)
                    ON CONFLICT (user_id) DO UPDATE SET
                        template = EXCLUDED.template, all_areas = EXCLUDED.all_areas,
                        updated_by = EXCLUDED.updated_by, updated_at = now();

                    DELETE FROM udrive.staff_permissions WHERE user_id = @id;
                    DELETE FROM udrive.staff_areas WHERE user_id = @id;
                    """, connection, transaction))
                {
                    update.Parameters.AddWithValue("id", userId);
                    update.Parameters.AddWithValue("name", name);
                    update.Parameters.AddWithValue("phone", phone);
                    update.Parameters.AddWithValue("active", request.IsActive);
                    update.Parameters.AddWithValue("template", TeamAccess.Templates.ContainsKey(request.Template ?? "") ? request.Template! : "custom");
                    update.Parameters.AddWithValue("allAreas", request.AllAreas);
                    update.Parameters.AddWithValue("actor", actorId);
                    await update.ExecuteNonQueryAsync(ct);
                }

                foreach (var p in permissions.Where(p => p.View || p.Edit || p.Approve || p.Delete))
                {
                    await using var insert = new NpgsqlCommand(
                        """
                        INSERT INTO udrive.staff_permissions (user_id, module, can_view, can_edit, can_approve, can_delete)
                        VALUES (@id, @module, @view, @edit, @approve, @delete);
                        """, connection, transaction);
                    insert.Parameters.AddWithValue("id", userId);
                    insert.Parameters.AddWithValue("module", p.Module);
                    // Anything a person may change, they may also see.
                    insert.Parameters.AddWithValue("view", p.View || p.Edit || p.Approve || p.Delete);
                    insert.Parameters.AddWithValue("edit", p.Edit);
                    insert.Parameters.AddWithValue("approve", p.Approve);
                    insert.Parameters.AddWithValue("delete", p.Delete);
                    await insert.ExecuteNonQueryAsync(ct);
                }

                if (!request.AllAreas && areaIds.Length > 0)
                {
                    await using var insert = new NpgsqlCommand(
                        "INSERT INTO udrive.staff_areas (user_id, territory_id) SELECT @id, unnest(@areas);",
                        connection, transaction);
                    insert.Parameters.AddWithValue("id", userId);
                    insert.Parameters.Add(new NpgsqlParameter("areas", NpgsqlDbType.Array | NpgsqlDbType.Uuid) { Value = areaIds });
                    await insert.ExecuteNonQueryAsync(ct);
                }

                await using (var audit = new NpgsqlCommand(
                    """
                    INSERT INTO udrive.audit_logs (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
                    VALUES (gen_random_uuid(), @actor, @action, 'TeamUser', CAST(@id AS text), CAST(@changes AS jsonb), now(), now());
                    """, connection, transaction))
                {
                    audit.Parameters.AddWithValue("actor", actorId);
                    audit.Parameters.AddWithValue("action", id is null ? "TeamUserCreated" : "TeamUserUpdated");
                    audit.Parameters.AddWithValue("id", userId);
                    audit.Parameters.AddWithValue("changes", JsonSerializer.Serialize(new
                    {
                        name, phone, request.IsActive, request.Template, request.AllAreas, areas = areaIds,
                        permissions = permissions.Select(p => new { p.Module, p.View, p.Edit, p.Approve, p.Delete }),
                    }));
                    await audit.ExecuteNonQueryAsync(ct);
                }

                await transaction.CommitAsync(ct);
            }
            catch (PostgresException error) when (error.SqlState == PostgresErrorCodes.UniqueViolation)
            {
                await transaction.RollbackAsync(CancellationToken.None);
                return Fail<TeamUserDto>(409, "phone_taken", "Another account already uses this mobile number.");
            }
        }

        TeamAccess.Forget(cache, userId);

        if (!string.IsNullOrWhiteSpace(request.Password) || id is null)
        {
            var credentials = await auth.SetPortalCredentialsAsync(
                new Models.SetPortalCredentialsRequest(phone, username, request.Password ?? string.Empty), ct);
            if (!credentials.Success)
            {
                return Fail<TeamUserDto>(credentials.StatusCode, credentials.ErrorCode ?? "credentials_failed",
                    "Saved, but the sign-in was not set: " + credentials.Message);
            }
        }

        var saved = await LoadAsync(connection, userId, ct);
        return ServiceResult<TeamUserDto>.Ok(saved!,
            id is null ? $"Created. {name} signs in with username {username} and the password you set." : "Saved.");
    }

    public async Task<ServiceResult<TeamUserDto>> SetStatusAsync(Guid actorId, Guid id, bool active, CancellationToken ct)
    {
        if (id == actorId) return Fail<TeamUserDto>(400, "self", "You cannot disable yourself.");
        await using var connection = await OpenAsync(ct);
        if (!await IsTeamUserAsync(connection, null, id, ct))
        {
            return Fail<TeamUserDto>(409, "not_team_user", "Only team users can be disabled here.");
        }

        await using (var command = new NpgsqlCommand(
            """
            UPDATE udrive.users
            SET status = CASE WHEN @active THEN 'Approved' ELSE 'Suspended' END,
                token_version = token_version + CASE WHEN @active THEN 0 ELSE 1 END,
                updated_at = now()
            WHERE id = @id;
            """, connection))
        {
            command.Parameters.AddWithValue("id", id);
            command.Parameters.AddWithValue("active", active);
            await command.ExecuteNonQueryAsync(ct);
        }

        TeamAccess.Forget(cache, id);
        return ServiceResult<TeamUserDto>.Ok((await LoadAsync(connection, id, ct))!,
            active ? "Active again. They can sign in." : "Disabled and signed out everywhere.");
    }

    // ─────────────────────────────────────────────────────── helpers

    private static IReadOnlyList<TeamPermissionDto>? CleanPermissions(IReadOnlyList<TeamPermissionDto>? input)
    {
        var list = new List<TeamPermissionDto>();
        foreach (var p in input ?? [])
        {
            var module = TeamAccess.Modules.FirstOrDefault(m => m.Key == p.Module);
            if (module is null) return null;
            list.Add(new TeamPermissionDto(
                p.Module,
                p.View && module.Actions.Contains("view"),
                p.Edit && module.Actions.Contains("edit"),
                p.Approve && module.Actions.Contains("approve"),
                p.Delete && module.Actions.Contains("delete")));
        }

        return list.GroupBy(p => p.Module).Select(g => g.Last()).ToList();
    }

    private static async Task<bool> IsTeamUserAsync(NpgsqlConnection connection, NpgsqlTransaction? transaction, Guid id, CancellationToken ct)
    {
        await using var command = transaction is null
            ? new NpgsqlCommand(string.Empty, connection)
            : new NpgsqlCommand(string.Empty, connection, transaction);
        command.CommandText = """
            SELECT EXISTS (SELECT 1 FROM udrive.user_roles WHERE user_id = @id AND role = 'Staff')
               AND NOT EXISTS (SELECT 1 FROM udrive.user_roles WHERE user_id = @id
                               AND role IN ('SuperAdmin', 'Admin', 'Manager', 'Operations', 'VerificationOfficer',
                                            'SupportAgent', 'FinanceOfficer', 'SafetyOfficer', 'TourismManager'));
            """;
        command.Parameters.AddWithValue("id", id);
        return await command.ExecuteScalarAsync(ct) is true;
    }

    private static async Task<bool> AreasExistAsync(NpgsqlConnection connection, Guid[] ids, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            "SELECT count(*)::int FROM udrive.territories WHERE id = ANY(@ids) AND kind IN ('City', 'Tehsil');", connection);
        command.Parameters.Add(new NpgsqlParameter("ids", NpgsqlDbType.Array | NpgsqlDbType.Uuid) { Value = ids });
        return await command.ExecuteScalarAsync(ct) is int n && n == ids.Length;
    }

    /// <summary>Every requested area is one of the actor's areas or a tehsil inside one of their districts.</summary>
    private static async Task<bool> AreasWithinAsync(NpgsqlConnection connection, Guid[] ids, IReadOnlyList<Guid> mine, CancellationToken ct)
    {
        if (ids.Length == 0) return true;
        await using var command = new NpgsqlCommand(
            """
            SELECT bool_and(t.id = ANY(@mine) OR t.parent_id = ANY(@mine))
            FROM udrive.territories t WHERE t.id = ANY(@ids);
            """, connection);
        command.Parameters.Add(new NpgsqlParameter("ids", NpgsqlDbType.Array | NpgsqlDbType.Uuid) { Value = ids });
        command.Parameters.Add(new NpgsqlParameter("mine", NpgsqlDbType.Array | NpgsqlDbType.Uuid) { Value = mine.ToArray() });
        return await command.ExecuteScalarAsync(ct) is true;
    }

    private static async Task<IReadOnlyList<TeamAreaDto>> AreaRowsAsync(NpgsqlConnection connection, IReadOnlyList<Guid> ids, CancellationToken ct)
    {
        if (ids.Count == 0) return [];
        await using var command = new NpgsqlCommand(
            """
            SELECT t.id, t.name, CASE WHEN t.kind = 'Tehsil' THEN 'Tehsil' ELSE 'District' END, d.name
            FROM udrive.territories t LEFT JOIN udrive.territories d ON d.id = t.parent_id AND t.kind = 'Tehsil'
            WHERE t.id = ANY(@ids)
            ORDER BY COALESCE(d.name, t.name), t.kind, t.name;
            """, connection);
        command.Parameters.Add(new NpgsqlParameter("ids", NpgsqlDbType.Array | NpgsqlDbType.Uuid) { Value = ids.ToArray() });
        var list = new List<TeamAreaDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            list.Add(new TeamAreaDto(reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.IsDBNull(3) ? null : reader.GetString(3)));
        }

        return list;
    }

    private static async Task<TeamUserDto?> LoadAsync(NpgsqlConnection connection, Guid id, CancellationToken ct)
    {
        string name, phone, status;
        string? username;
        DateTimeOffset? lastLogin;
        DateTimeOffset created;
        string template;
        bool allAreas;
        var roles = new List<string>();
        await using (var command = new NpgsqlCommand(
            """
            SELECT u.full_name, u.phone_number, u.username, u.status, u.last_login_at, u.created_at,
                   COALESCE(sp.template, 'custom'), COALESCE(sp.all_areas, false),
                   ARRAY(SELECT r.role FROM udrive.user_roles r WHERE r.user_id = u.id ORDER BY r.role)
            FROM udrive.users u
            LEFT JOIN udrive.staff_profiles sp ON sp.user_id = u.id
            WHERE u.id = @id;
            """, connection))
        {
            command.Parameters.AddWithValue("id", id);
            await using var reader = await command.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct)) return null;
            name = reader.IsDBNull(0) ? string.Empty : reader.GetString(0);
            phone = reader.IsDBNull(1) ? string.Empty : reader.GetString(1);
            username = reader.IsDBNull(2) ? null : reader.GetString(2);
            status = reader.GetString(3);
            lastLogin = reader.IsDBNull(4) ? null : reader.GetFieldValue<DateTimeOffset>(4);
            created = reader.GetFieldValue<DateTimeOffset>(5);
            template = reader.GetString(6);
            allAreas = reader.GetBoolean(7);
            roles.AddRange(reader.GetFieldValue<string[]>(8));
        }

        var editable = roles.Contains(TeamAccess.StaffRole)
            && !roles.Any(r => r is "SuperAdmin" or "Admin" or "Manager" or "Operations" or "VerificationOfficer"
                or "SupportAgent" or "FinanceOfficer" or "SafetyOfficer" or "TourismManager");
        var grant = await TeamAccess.LoadGrantAsync(connection, id, ct);
        return new TeamUserDto(
            id, name, phone, username, status, editable, template,
            editable ? allAreas : true,
            await AreaRowsAsync(connection, grant.Areas, ct),
            grant.Modules.Select(kv => new TeamPermissionDto(kv.Key, kv.Value.View, kv.Value.Edit, kv.Value.Approve, kv.Value.Delete)).ToList(),
            roles, lastLogin, created);
    }

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken ct)
    {
        var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        return connection;
    }

    private static ServiceResult<T> Fail<T>(int status, string code, string message) => ServiceResult<T>.Fail(status, code, message);
}
