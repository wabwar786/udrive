using System.Text.Json;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;

namespace UDrive.Api.Services;

public sealed class AdminUserManagementService(string connectionString)
{
    private static readonly string[] PortalRoles = ["SuperAdmin", "Admin", "Manager"];

    public async Task<ServiceResult<CreatedPortalUserDto>> CreateAsync(
        Guid actorUserId,
        CreatePortalUserRequest request,
        string? ipAddress,
        CancellationToken cancellationToken)
    {
        if (!PhoneNumberNormalizer.TryNormalizePakistan(request.PhoneNumber, out var phoneNumber))
        {
            return ServiceResult<CreatedPortalUserDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_phone_number",
                "Enter a valid Pakistani mobile number, for example 03001234567.");
        }

        var role = NormalizeRole(request.Role);
        if (role is null)
        {
            return ServiceResult<CreatedPortalUserDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_portal_role",
                "Portal role must be SuperAdmin, Admin or Manager.");
        }

        var fullName = request.FullName.Trim();
        var email = string.IsNullOrWhiteSpace(request.Email)
            ? null
            : request.Email.Trim().ToLowerInvariant();
        var language = string.Equals(request.PreferredLanguage, "ur", StringComparison.OrdinalIgnoreCase)
            ? "ur"
            : "en";
        var userId = Guid.NewGuid();

        try
        {
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

            await using (var userCommand = new NpgsqlCommand("""
                INSERT INTO udrive.users
                    (id, phone_number, email, full_name, role, status,
                     preferred_language, phone_verified, token_version,
                     created_at, updated_at)
                VALUES
                    (@id, @phone, @email, @name, @role, 'Approved',
                     @language, false, 0, now(), now());
                """, connection, transaction))
            {
                userCommand.Parameters.AddWithValue("id", userId);
                userCommand.Parameters.AddWithValue("phone", phoneNumber);
                userCommand.Parameters.AddWithValue("email", (object?)email ?? DBNull.Value);
                userCommand.Parameters.AddWithValue("name", fullName);
                userCommand.Parameters.AddWithValue("role", role);
                userCommand.Parameters.AddWithValue("language", language);
                await userCommand.ExecuteNonQueryAsync(cancellationToken);
            }

            await using (var roleCommand = new NpgsqlCommand("""
                INSERT INTO udrive.user_roles (user_id, role, created_at)
                VALUES (@id, @role, now());
                """, connection, transaction))
            {
                roleCommand.Parameters.AddWithValue("id", userId);
                roleCommand.Parameters.AddWithValue("role", role);
                await roleCommand.ExecuteNonQueryAsync(cancellationToken);
            }

            await InsertAuditAsync(
                connection,
                transaction,
                actorUserId,
                "CreatePortalUser",
                userId,
                JsonSerializer.Serialize(new { role, phoneNumber, email }),
                ipAddress,
                cancellationToken);

            await transaction.CommitAsync(cancellationToken);
            return ServiceResult<CreatedPortalUserDto>.Created(
                new CreatedPortalUserDto(userId, fullName, phoneNumber, email, role, "Approved"),
                "Portal user created. The user can sign in by requesting an OTP for this mobile number.");
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            return ServiceResult<CreatedPortalUserDto>.Fail(
                StatusCodes.Status409Conflict,
                "user_already_exists",
                "A user with this mobile number or email already exists.");
        }
    }

    public async Task<ServiceResult<bool>> UpdatePortalRoleAsync(
        Guid actorUserId,
        Guid userId,
        UpdatePortalRoleRequest request,
        string? ipAddress,
        CancellationToken cancellationToken)
    {
        var role = string.IsNullOrWhiteSpace(request.Role) ? null : NormalizeRole(request.Role);
        if (!string.IsNullOrWhiteSpace(request.Role) && role is null)
        {
            return ServiceResult<bool>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_portal_role",
                "Portal role must be SuperAdmin, Admin, Manager or empty.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        bool targetExists;
        bool targetIsSuperAdmin;
        await using (var targetCommand = new NpgsqlCommand("""
            SELECT EXISTS(SELECT 1 FROM udrive.users WHERE id = @id),
                   EXISTS(SELECT 1 FROM udrive.user_roles WHERE user_id = @id AND role = 'SuperAdmin');
            """, connection, transaction))
        {
            targetCommand.Parameters.AddWithValue("id", userId);
            await using var reader = await targetCommand.ExecuteReaderAsync(cancellationToken);
            await reader.ReadAsync(cancellationToken);
            targetExists = reader.GetBoolean(0);
            targetIsSuperAdmin = reader.GetBoolean(1);
        }

        if (!targetExists)
        {
            await transaction.RollbackAsync(cancellationToken);
            return ServiceResult<bool>.Fail(
                StatusCodes.Status404NotFound,
                "user_not_found",
                "User not found.");
        }

        if (targetIsSuperAdmin && !string.Equals(role, "SuperAdmin", StringComparison.Ordinal))
        {
            await using var countCommand = new NpgsqlCommand("""
                SELECT count(DISTINCT user_id)
                FROM udrive.user_roles
                WHERE role = 'SuperAdmin' AND user_id <> @id;
                """, connection, transaction);
            countCommand.Parameters.AddWithValue("id", userId);
            var remaining = Convert.ToInt32((long)(await countCommand.ExecuteScalarAsync(cancellationToken) ?? 0L));
            if (remaining == 0)
            {
                await transaction.RollbackAsync(cancellationToken);
                return ServiceResult<bool>.Fail(
                    StatusCodes.Status409Conflict,
                    "last_super_admin",
                    "The last SuperAdmin cannot be demoted or removed.");
            }
        }

        await using (var updateCommand = new NpgsqlCommand("""
            DELETE FROM udrive.user_roles
            WHERE user_id = @id
              AND role IN ('SuperAdmin','Admin','Manager');

            UPDATE udrive.users
            SET role = COALESCE(@role, CASE WHEN role IN ('SuperAdmin','Admin','Manager') THEN 'Customer' ELSE role END),
                token_version = token_version + 1,
                updated_at = now()
            WHERE id = @id;

            UPDATE udrive.refresh_tokens
            SET revoked_at = COALESCE(revoked_at, now())
            WHERE user_id = @id AND revoked_at IS NULL;
            """, connection, transaction))
        {
            updateCommand.Parameters.AddWithValue("id", userId);
            updateCommand.Parameters.AddWithValue("role", (object?)role ?? DBNull.Value);
            await updateCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        if (role is not null)
        {
            await using var insertCommand = new NpgsqlCommand("""
                INSERT INTO udrive.user_roles (user_id, role, created_at)
                VALUES (@id, @role, now())
                ON CONFLICT (user_id, role) DO NOTHING;
                """, connection, transaction);
            insertCommand.Parameters.AddWithValue("id", userId);
            insertCommand.Parameters.AddWithValue("role", role);
            await insertCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await InsertAuditAsync(
            connection,
            transaction,
            actorUserId,
            "UpdatePortalRole",
            userId,
            JsonSerializer.Serialize(new { role }),
            ipAddress,
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<bool>.Ok(true, "Portal role updated. The affected user must sign in again.");
    }

    private static string? NormalizeRole(string role) =>
        PortalRoles.FirstOrDefault(value => string.Equals(value, role.Trim(), StringComparison.OrdinalIgnoreCase));

    private static async Task InsertAuditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorUserId,
        string action,
        Guid entityId,
        string changesJson,
        string? ipAddress,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand("""
            INSERT INTO udrive.audit_logs
                (id, actor_user_id, action, entity_type, entity_id,
                 ip_address, changes_json, created_at, updated_at)
            VALUES
                (@id, @actor, @action, 'User', @entityId,
                 @ip, CAST(@changes AS jsonb), now(), now());
            """, connection, transaction);
        command.Parameters.AddWithValue("id", Guid.NewGuid());
        command.Parameters.AddWithValue("actor", actorUserId);
        command.Parameters.AddWithValue("action", action);
        command.Parameters.AddWithValue("entityId", entityId.ToString());
        command.Parameters.AddWithValue("ip", (object?)ipAddress ?? DBNull.Value);
        command.Parameters.AddWithValue("changes", changesJson);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
