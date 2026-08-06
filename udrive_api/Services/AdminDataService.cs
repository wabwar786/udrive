using System.Reflection;
using Npgsql;

namespace UDrive.Api.Services;

public sealed class AdminDataService(string connectionString, ILogger<AdminDataService> logger)
{
    private static readonly string[] PortalRoles =
    [
        "SuperAdmin", "Admin", "Manager", "Operations", "VerificationOfficer",
        "SupportAgent", "FinanceOfficer", "SafetyOfficer", "TourismManager"
    ];

    public async Task<object> GetStatusAsync(CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT
                (SELECT count(*) FROM udrive.users) AS users,
                (SELECT count(*) FROM udrive.driver_profiles) AS drivers,
                (SELECT count(*) FROM udrive.vehicles) AS vehicles,
                (SELECT count(*) FROM udrive.hotels) AS hotels,
                (SELECT count(*) FROM udrive.hotels WHERE approval_status = 'Pending') AS pending_hotels,
                (SELECT count(*) FROM udrive.bookings) AS ride_bookings,
                (SELECT count(*) FROM udrive.hotel_bookings) AS hotel_bookings,
                (SELECT count(*) FROM udrive.tour_packages) AS tour_packages,
                (SELECT count(*) FROM udrive.destinations) AS destinations,
                (SELECT count(*) FROM udrive.users WHERE email LIKE 'demo.%@udrive.local') AS demo_users;
            """;

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        await reader.ReadAsync(cancellationToken);
        return new
        {
            users = reader.GetInt64(0),
            drivers = reader.GetInt64(1),
            vehicles = reader.GetInt64(2),
            hotels = reader.GetInt64(3),
            pendingHotels = reader.GetInt64(4),
            rideBookings = reader.GetInt64(5),
            hotelBookings = reader.GetInt64(6),
            tourPackages = reader.GetInt64(7),
            destinations = reader.GetInt64(8),
            demoUsers = reader.GetInt64(9)
        };
    }

    public async Task<object> ResetAsync(Guid adminUserId, CancellationToken cancellationToken)
    {
        var before = await GetStatusAsync(cancellationToken);
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            await using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandTimeout = 180;
            command.CommandText = """
                CREATE TEMP TABLE protected_portal_users(id uuid PRIMARY KEY) ON COMMIT DROP;

                INSERT INTO protected_portal_users(id)
                SELECT DISTINCT u.id
                FROM udrive.users u
                LEFT JOIN udrive.user_roles ur ON ur.user_id = u.id
                WHERE u.role = ANY(@roles) OR ur.role = ANY(@roles);

                DO $$
                DECLARE item record;
                BEGIN
                    FOR item IN
                        SELECT tablename
                        FROM pg_tables
                        WHERE schemaname = 'udrive'
                          AND tablename NOT IN ('users', 'user_roles', 'system_settings', 'refresh_tokens')
                        ORDER BY tablename
                    LOOP
                        EXECUTE format('TRUNCATE TABLE udrive.%I CASCADE', item.tablename);
                    END LOOP;
                END $$;

                UPDATE udrive.system_settings
                SET updated_by_user_id = NULL,
                    updated_at = now()
                WHERE updated_by_user_id IS NOT NULL
                  AND updated_by_user_id NOT IN (SELECT id FROM protected_portal_users);

                DELETE FROM udrive.refresh_tokens
                WHERE user_id NOT IN (SELECT id FROM protected_portal_users);

                DELETE FROM udrive.user_roles
                WHERE user_id NOT IN (SELECT id FROM protected_portal_users);

                DELETE FROM udrive.users
                WHERE id NOT IN (SELECT id FROM protected_portal_users);

                INSERT INTO udrive.audit_logs
                    (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
                VALUES
                    (gen_random_uuid(), @admin_id, 'ApplicationDataReset', 'System', 'udrive',
                     jsonb_build_object('portalAccountsPreserved', true, 'systemSettingsPreserved', true),
                     now(), now());
                """;
            command.Parameters.AddWithValue("roles", PortalRoles);
            command.Parameters.AddWithValue("admin_id", adminUserId);
            await command.ExecuteNonQueryAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            throw;
        }

        logger.LogWarning("Application data was reset by admin {AdminUserId}", adminUserId);
        return new
        {
            message = "Old application data deleted. Portal admin accounts and system settings were preserved.",
            before,
            after = await GetStatusAsync(cancellationToken)
        };
    }

    public async Task<object> AddDemoDataAsync(Guid adminUserId, CancellationToken cancellationToken)
    {
        var fleetSql = await ReadEmbeddedSqlAsync("010_demo_fleet_kashmir_catalog.sql", cancellationToken);
        var hotelSql = await ReadEmbeddedSqlAsync("demo_hotels.sql", cancellationToken);

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            await ExecuteSqlAsync(connection, transaction, fleetSql, cancellationToken);
            await ExecuteSqlAsync(connection, transaction, hotelSql, cancellationToken);

            await using var audit = connection.CreateCommand();
            audit.Transaction = transaction;
            audit.CommandText = """
                INSERT INTO udrive.audit_logs
                    (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
                VALUES
                    (gen_random_uuid(), @admin_id, 'DemoDataSeeded', 'System', 'udrive-demo',
                     jsonb_build_object('vehicles', true, 'hotels', true, 'destinations', true, 'tourPackages', true),
                     now(), now());
                """;
            audit.Parameters.AddWithValue("admin_id", adminUserId);
            await audit.ExecuteNonQueryAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            throw;
        }

        logger.LogInformation("Demo data was seeded by admin {AdminUserId}", adminUserId);
        return new
        {
            message = "Demo vehicle, destination, tour and hotel data added successfully.",
            status = await GetStatusAsync(cancellationToken)
        };
    }

    private static async Task ExecuteSqlAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string sql,
        CancellationToken cancellationToken)
    {
        await using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        command.CommandTimeout = 240;
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<string> ReadEmbeddedSqlAsync(string fileName, CancellationToken cancellationToken)
    {
        var assembly = Assembly.GetExecutingAssembly();
        var resourceName = assembly.GetManifestResourceNames()
            .SingleOrDefault(name => name.EndsWith(fileName, StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidOperationException($"Embedded SQL file {fileName} was not found.");

        await using var stream = assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Embedded SQL resource {resourceName} was not found.");
        using var reader = new StreamReader(stream);
        return await reader.ReadToEndAsync(cancellationToken);
    }
}
