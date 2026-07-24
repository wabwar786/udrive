using Npgsql;

namespace UDrive.Api.Services;

public sealed record AuthUserRecord(
    Guid Id,
    string PhoneNumber,
    string FullName,
    string? Email,
    string PreferredLanguage,
    string AccountStatus,
    int TokenVersion,
    Guid? DriverProfileId,
    string? DriverVerificationStatus);

public sealed record OtpChallengeRecord(
    Guid Id,
    string CodeHash,
    DateTimeOffset ExpiresAt,
    int Attempts,
    int MaxAttempts);

public sealed record RefreshTokenRecord(
    Guid Id,
    Guid UserId,
    DateTimeOffset ExpiresAt,
    DateTimeOffset? RevokedAt);

public sealed class AuthSqlStore(string connectionString)
{
    public async Task<DateTimeOffset?> GetLastOtpRequestAsync(
        string phoneNumber,
        string purpose,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT created_at
            FROM udrive.auth_otp_challenges
            WHERE phone_number = @phone AND purpose = @purpose
            ORDER BY created_at DESC
            LIMIT 1;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("phone", phoneNumber);
        command.Parameters.AddWithValue("purpose", purpose);
        var value = await command.ExecuteScalarAsync(cancellationToken);
        return value is DateTimeOffset timestamp ? timestamp : null;
    }

    public async Task<Guid> CreateOtpChallengeAsync(
        string phoneNumber,
        string purpose,
        string codeHash,
        DateTimeOffset expiresAt,
        string? requestedIp,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.auth_otp_challenges
                (id, phone_number, purpose, code_hash, expires_at, attempts,
                 max_attempts, requested_ip, created_at)
            VALUES
                (@id, @phone, @purpose, @hash, @expires, 0, 5, @ip, now());
            """;

        var id = Guid.NewGuid();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("phone", phoneNumber);
        command.Parameters.AddWithValue("purpose", purpose);
        command.Parameters.AddWithValue("hash", codeHash);
        command.Parameters.AddWithValue("expires", expiresAt);
        command.Parameters.AddWithValue("ip", (object?)requestedIp ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
        return id;
    }

    public async Task<OtpChallengeRecord?> GetLatestActiveOtpAsync(
        string phoneNumber,
        string purpose,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT id, code_hash, expires_at, attempts, max_attempts
            FROM udrive.auth_otp_challenges
            WHERE phone_number = @phone
              AND purpose = @purpose
              AND consumed_at IS NULL
            ORDER BY created_at DESC
            LIMIT 1;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("phone", phoneNumber);
        command.Parameters.AddWithValue("purpose", purpose);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new OtpChallengeRecord(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetFieldValue<DateTimeOffset>(2),
            reader.GetInt32(3),
            reader.GetInt32(4));
    }

    public async Task IncrementOtpAttemptsAsync(Guid id, CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.auth_otp_challenges
            SET attempts = attempts + 1
            WHERE id = @id AND consumed_at IS NULL;
            """;
        await ExecuteAsync(sql, cancellationToken, ("id", id));
    }

    public async Task ConsumeOtpAsync(Guid id, CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.auth_otp_challenges
            SET consumed_at = now()
            WHERE id = @id AND consumed_at IS NULL;
            """;
        await ExecuteAsync(sql, cancellationToken, ("id", id));
    }

    public async Task<AuthUserRecord> UpsertVerifiedCustomerAsync(
        string phoneNumber,
        string fullName,
        string language,
        CancellationToken cancellationToken)
    {
        const string userSql = """
            INSERT INTO udrive.users
                (id, phone_number, full_name, role, status, preferred_language,
                 phone_verified, token_version, last_login_at, created_at, updated_at)
            VALUES
                (@id, @phone, @name, 'Customer', 'Approved', @language,
                 true, 0, now(), now(), now())
            ON CONFLICT (phone_number) DO UPDATE SET
                phone_verified = true,
                full_name = CASE
                    WHEN udrive.users.full_name IS NULL OR udrive.users.full_name = ''
                    THEN EXCLUDED.full_name ELSE udrive.users.full_name END,
                preferred_language = EXCLUDED.preferred_language,
                last_login_at = now(),
                updated_at = now()
            RETURNING id;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        var proposedId = Guid.NewGuid();
        await using var userCommand = new NpgsqlCommand(userSql, connection, transaction);
        userCommand.Parameters.AddWithValue("id", proposedId);
        userCommand.Parameters.AddWithValue("phone", phoneNumber);
        userCommand.Parameters.AddWithValue("name", fullName);
        userCommand.Parameters.AddWithValue("language", language);
        var userId = (Guid)(await userCommand.ExecuteScalarAsync(cancellationToken)
            ?? throw new InvalidOperationException("The user could not be created."));

        await using (var profileCommand = new NpgsqlCommand("""
            INSERT INTO udrive.customer_profiles (id, user_id, created_at, updated_at)
            VALUES (@id, @userId, now(), now())
            ON CONFLICT (user_id) DO NOTHING;
            """, connection, transaction))
        {
            profileCommand.Parameters.AddWithValue("id", Guid.NewGuid());
            profileCommand.Parameters.AddWithValue("userId", userId);
            await profileCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var roleCommand = new NpgsqlCommand("""
            INSERT INTO udrive.user_roles (user_id, role, created_at)
            VALUES (@userId, 'Customer', now())
            ON CONFLICT (user_id, role) DO NOTHING;
            """, connection, transaction))
        {
            roleCommand.Parameters.AddWithValue("userId", userId);
            await roleCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return await GetUserByIdAsync(userId, cancellationToken)
            ?? throw new InvalidOperationException("The user could not be loaded after login.");
    }

    public Task<AuthUserRecord?> GetUserByIdAsync(Guid userId, CancellationToken cancellationToken) =>
        GetUserAsync("u.id = @value", userId, cancellationToken);

    public Task<AuthUserRecord?> GetUserByPhoneAsync(string phoneNumber, CancellationToken cancellationToken) =>
        GetUserAsync("u.phone_number = @value", phoneNumber, cancellationToken);

    public async Task<IReadOnlyList<string>> GetRolesAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT role
            FROM udrive.user_roles
            WHERE user_id = @userId
            ORDER BY role;
            """;

        var roles = new List<string>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            roles.Add(reader.GetString(0));
        }
        return roles;
    }

    public async Task InsertRefreshTokenAsync(
        Guid id,
        Guid userId,
        string tokenHash,
        string? deviceId,
        string? deviceName,
        DateTimeOffset expiresAt,
        string? ipAddress,
        string? userAgent,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.refresh_tokens
                (id, user_id, token_hash, device_id, device_name, expires_at,
                 ip_address, user_agent, created_at, last_used_at)
            VALUES
                (@id, @userId, @hash, @deviceId, @deviceName, @expiresAt,
                 @ip, @agent, now(), now());
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("userId", userId);
        command.Parameters.AddWithValue("hash", tokenHash);
        command.Parameters.AddWithValue("deviceId", (object?)deviceId ?? DBNull.Value);
        command.Parameters.AddWithValue("deviceName", (object?)deviceName ?? DBNull.Value);
        command.Parameters.AddWithValue("expiresAt", expiresAt);
        command.Parameters.AddWithValue("ip", (object?)ipAddress ?? DBNull.Value);
        command.Parameters.AddWithValue("agent", (object?)userAgent ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<RefreshTokenRecord?> GetRefreshTokenAsync(
        string tokenHash,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT id, user_id, expires_at, revoked_at
            FROM udrive.refresh_tokens
            WHERE token_hash = @hash
            LIMIT 1;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("hash", tokenHash);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new RefreshTokenRecord(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetFieldValue<DateTimeOffset>(2),
            reader.IsDBNull(3) ? null : reader.GetFieldValue<DateTimeOffset>(3));
    }

    public async Task RevokeAndReplaceRefreshTokenAsync(
        Guid oldTokenId,
        Guid replacementTokenId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.refresh_tokens
            SET revoked_at = now(), replaced_by_token_id = @replacement, last_used_at = now()
            WHERE id = @id AND revoked_at IS NULL;
            """;
        await ExecuteAsync(
            sql,
            cancellationToken,
            ("replacement", replacementTokenId),
            ("id", oldTokenId));
    }

    public async Task RevokeRefreshTokenAsync(string tokenHash, CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.refresh_tokens
            SET revoked_at = COALESCE(revoked_at, now()), last_used_at = now()
            WHERE token_hash = @hash;
            """;
        await ExecuteAsync(sql, cancellationToken, ("hash", tokenHash));
    }

    public async Task RevokeAllRefreshTokensAsync(Guid userId, CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.refresh_tokens
            SET revoked_at = COALESCE(revoked_at, now()), last_used_at = now()
            WHERE user_id = @userId;
            """;
        await ExecuteAsync(sql, cancellationToken, ("userId", userId));
    }

    private async Task<AuthUserRecord?> GetUserAsync(
        string predicate,
        object value,
        CancellationToken cancellationToken)
    {
        var sql = $"""
            SELECT
                u.id, u.phone_number, u.full_name, u.email,
                u.preferred_language, u.status, u.token_version,
                dp.id, dp.verification_status
            FROM udrive.users u
            LEFT JOIN udrive.driver_profiles dp ON dp.user_id = u.id
            WHERE {predicate}
            LIMIT 1;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("value", value);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new AuthUserRecord(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.IsDBNull(3) ? null : reader.GetString(3),
            reader.GetString(4),
            reader.GetString(5),
            reader.GetInt32(6),
            reader.IsDBNull(7) ? null : reader.GetGuid(7),
            reader.IsDBNull(8) ? null : reader.GetString(8));
    }

    private async Task ExecuteAsync(
        string sql,
        CancellationToken cancellationToken,
        params (string Name, object Value)[] parameters)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        foreach (var parameter in parameters)
        {
            command.Parameters.AddWithValue(parameter.Name, parameter.Value);
        }
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
