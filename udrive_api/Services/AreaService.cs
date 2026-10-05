using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Districts and tehsils: where a vehicle, a driver, a hotel or a business is.
/// </summary>
/// <remarks>
/// Kept in the territory tree from migration 065 so partner territories and
/// verification areas are one list. A district is a 'City' node and a tehsil a
/// 'Tehsil' node under it. Each tehsil carries a centre pin so the app can
/// suggest the nearest one from the phone's position.
/// </remarks>
public sealed class AreaService(string connectionString)
{
    /// <summary>Active districts and their active tehsils, for pickers in the app.</summary>
    public async Task<ServiceResult<IReadOnlyList<AreaDistrictDto>>> PublicAsync(CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand(
            """
            SELECT d.id, d.name, t.id, t.name, t.latitude, t.longitude
            FROM udrive.territories d
            JOIN udrive.territories t ON t.parent_id = d.id AND t.kind = 'Tehsil' AND t.is_active
            WHERE d.kind = 'City' AND d.is_active
            ORDER BY d.name, t.name;
            """, connection);
        var map = new Dictionary<Guid, (string Name, List<AreaTehsilDto> Tehsils)>();
        var order = new List<Guid>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var id = reader.GetGuid(0);
            if (!map.TryGetValue(id, out var entry))
            {
                entry = (reader.GetString(1), new List<AreaTehsilDto>());
                map[id] = entry;
                order.Add(id);
            }

            entry.Tehsils.Add(new AreaTehsilDto(
                reader.GetGuid(2), reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetDouble(4),
                reader.IsDBNull(5) ? null : reader.GetDouble(5),
                true));
        }

        return ServiceResult<IReadOnlyList<AreaDistrictDto>>.Ok(
            order.Select(id => new AreaDistrictDto(id, map[id].Name, true, map[id].Tehsils)).ToList());
    }

    /// <summary>Every district and tehsil, active or not, with how much sits in each.</summary>
    public async Task<ServiceResult<IReadOnlyList<AdminAreaDistrictDto>>> AdminAsync(CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand(
            """
            WITH located AS (
                SELECT COALESCE(v.territory_id, dp.territory_id) AS tehsil
                FROM udrive.vehicles v
                JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                WHERE v.status <> 'Deleted'
            ),
            drivers AS (
                SELECT dp.territory_id AS tehsil
                FROM udrive.driver_profiles dp
                WHERE COALESCE(dp.profile_kind, 'Driver') = 'Driver'
                  AND dp.verification_status <> 'Deleted' AND dp.territory_id IS NOT NULL
            )
            SELECT d.id, d.name, d.is_active,
                   t.id, t.name, t.latitude, t.longitude, t.is_active,
                   (SELECT count(*)::int FROM located l WHERE l.tehsil = t.id),
                   (SELECT count(*)::int FROM drivers r WHERE r.tehsil = t.id)
            FROM udrive.territories d
            LEFT JOIN udrive.territories t ON t.parent_id = d.id AND t.kind = 'Tehsil'
            WHERE d.kind = 'City'
            ORDER BY d.name, t.name;
            """, connection);

        var rows = new List<(Guid Id, string Name, bool Active, AdminAreaTehsilDto? Tehsil)>();
        await using (var reader = await command.ExecuteReaderAsync(ct))
        {
            while (await reader.ReadAsync(ct))
            {
                AdminAreaTehsilDto? tehsil = reader.IsDBNull(3)
                    ? null
                    : new AdminAreaTehsilDto(
                        reader.GetGuid(3), reader.GetString(4),
                        reader.IsDBNull(5) ? null : reader.GetDouble(5),
                        reader.IsDBNull(6) ? null : reader.GetDouble(6),
                        reader.GetBoolean(7), reader.GetInt32(8), reader.GetInt32(9));
                rows.Add((reader.GetGuid(0), reader.GetString(1), reader.GetBoolean(2), tehsil));
            }
        }

        var list = rows
            .GroupBy(r => (r.Id, r.Name, r.Active))
            .Select(g =>
            {
                var tehsils = g.Where(r => r.Tehsil is not null).Select(r => r.Tehsil!).ToList();
                return new AdminAreaDistrictDto(
                    g.Key.Id, g.Key.Name, g.Key.Active,
                    tehsils.Sum(t => t.Vehicles), tehsils.Sum(t => t.Drivers), tehsils);
            })
            .ToList();
        return ServiceResult<IReadOnlyList<AdminAreaDistrictDto>>.Ok(list);
    }

    public async Task<ServiceResult<Guid>> AddDistrictAsync(Guid adminId, SaveDistrictRequest request, CancellationToken ct)
    {
        var name = Clean(request.Name);
        if (name is null) return Fail<Guid>(400, "name_required", "Enter the district name.");

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        try
        {
            await using var command = new NpgsqlCommand(
                """
                INSERT INTO udrive.territories (parent_id, kind, name, is_active, notes)
                VALUES ((SELECT id FROM udrive.territories WHERE kind = 'Region' ORDER BY created_at LIMIT 1),
                        'City', @name, @active, 'District')
                RETURNING id;
                """, connection);
            command.Parameters.AddWithValue("name", name);
            command.Parameters.AddWithValue("active", request.IsActive);
            var id = (Guid)(await command.ExecuteScalarAsync(ct))!;
            await AuditAsync(connection, adminId, "DistrictAdded", id, new { name }, ct);
            return ServiceResult<Guid>.Ok(id);
        }
        catch (PostgresException error) when (error.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            return Fail<Guid>(409, "duplicate", "A district with that name already exists.");
        }
    }

    public async Task<ServiceResult<Guid>> AddTehsilAsync(Guid adminId, SaveTehsilRequest request, CancellationToken ct)
    {
        var name = Clean(request.Name);
        if (name is null) return Fail<Guid>(400, "name_required", "Enter the tehsil name.");
        if (!ValidPin(request.Latitude, request.Longitude))
        {
            return Fail<Guid>(400, "pin_invalid", "Enter both latitude and longitude of the tehsil centre, or neither.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        try
        {
            await using var command = new NpgsqlCommand(
                """
                INSERT INTO udrive.territories (parent_id, kind, name, latitude, longitude, is_active)
                SELECT d.id, 'Tehsil', @name, @lat, @lng, @active
                FROM udrive.territories d WHERE d.id = @district AND d.kind = 'City'
                RETURNING id;
                """, connection);
            command.Parameters.AddWithValue("district", request.DistrictId);
            command.Parameters.AddWithValue("name", name);
            command.Parameters.Add(new NpgsqlParameter("lat", NpgsqlDbType.Double) { Value = (object?)request.Latitude ?? DBNull.Value });
            command.Parameters.Add(new NpgsqlParameter("lng", NpgsqlDbType.Double) { Value = (object?)request.Longitude ?? DBNull.Value });
            command.Parameters.AddWithValue("active", request.IsActive);
            if (await command.ExecuteScalarAsync(ct) is not Guid id)
            {
                return Fail<Guid>(404, "district_not_found", "That district was not found.");
            }

            await AuditAsync(connection, adminId, "TehsilAdded", id, new { name, request.DistrictId }, ct);
            return ServiceResult<Guid>.Ok(id);
        }
        catch (PostgresException error) when (error.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            return Fail<Guid>(409, "duplicate", "That district already has a tehsil with this name.");
        }
    }

    public async Task<ServiceResult<Guid>> UpdateAsync(Guid adminId, Guid id, UpdateAreaRequest request, CancellationToken ct)
    {
        var name = Clean(request.Name);
        if (name is null) return Fail<Guid>(400, "name_required", "Enter a name.");
        if (!ValidPin(request.Latitude, request.Longitude))
        {
            return Fail<Guid>(400, "pin_invalid", "Enter both latitude and longitude, or neither.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        try
        {
            await using var command = new NpgsqlCommand(
                """
                UPDATE udrive.territories
                SET name = @name, is_active = @active,
                    latitude = CASE WHEN kind = 'Tehsil' THEN @lat ELSE latitude END,
                    longitude = CASE WHEN kind = 'Tehsil' THEN @lng ELSE longitude END,
                    updated_at = now()
                WHERE id = @id AND kind IN ('City', 'Tehsil')
                RETURNING id;
                """, connection);
            command.Parameters.AddWithValue("id", id);
            command.Parameters.AddWithValue("name", name);
            command.Parameters.AddWithValue("active", request.IsActive);
            command.Parameters.Add(new NpgsqlParameter("lat", NpgsqlDbType.Double) { Value = (object?)request.Latitude ?? DBNull.Value });
            command.Parameters.Add(new NpgsqlParameter("lng", NpgsqlDbType.Double) { Value = (object?)request.Longitude ?? DBNull.Value });
            if (await command.ExecuteScalarAsync(ct) is not Guid)
            {
                return Fail<Guid>(404, "area_not_found", "That area was not found.");
            }

            await AuditAsync(connection, adminId, "AreaUpdated", id, new { name, request.IsActive, request.Latitude, request.Longitude }, ct);
            return ServiceResult<Guid>.Ok(id);
        }
        catch (PostgresException error) when (error.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            return Fail<Guid>(409, "duplicate", "Another area in the same place already has that name.");
        }
    }

    /// <summary>Whether this id is an active tehsil. Used before saving it on anything.</summary>
    internal static async Task<bool> IsTehsilAsync(
        NpgsqlConnection connection, NpgsqlTransaction? transaction, Guid id, CancellationToken ct)
    {
        await using var command = transaction is null
            ? new NpgsqlCommand(string.Empty, connection)
            : new NpgsqlCommand(string.Empty, connection, transaction);
        command.CommandText = "SELECT EXISTS (SELECT 1 FROM udrive.territories WHERE id = @id AND kind = 'Tehsil' AND is_active);";
        command.Parameters.AddWithValue("id", id);
        return await command.ExecuteScalarAsync(ct) is true;
    }

    private static bool ValidPin(double? lat, double? lng) =>
        (lat is null && lng is null)
        || (lat is >= -90 and <= 90 && lng is >= -180 and <= 180);

    private static string? Clean(string? value)
    {
        var text = value?.Trim();
        return string.IsNullOrEmpty(text) ? null : text.Length > 120 ? text[..120] : text;
    }

    private static async Task AuditAsync(NpgsqlConnection connection, Guid adminId, string action, Guid id, object changes, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.audit_logs
                (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
            VALUES (gen_random_uuid(), @admin, @action, 'Territory', CAST(@id AS text), CAST(@changes AS jsonb), now(), now());
            """, connection);
        command.Parameters.AddWithValue("admin", adminId);
        command.Parameters.AddWithValue("action", action);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("changes", System.Text.Json.JsonSerializer.Serialize(changes));
        await command.ExecuteNonQueryAsync(ct);
    }

    private static ServiceResult<T> Fail<T>(int status, string code, string message) =>
        ServiceResult<T>.Fail(status, code, message);
}
