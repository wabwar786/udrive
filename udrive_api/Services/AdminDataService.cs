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

    /// <summary>
    /// Tables the reset leaves alone.
    /// </summary>
    /// <remarks>
    /// The first four are the ones that keep an operator able to sign in and
    /// keep their configuration: without them a reset locks everybody out of
    /// the portal it was run from.
    ///
    /// destinations and service_vehicle_rates are here for a different reason.
    /// They are reference data, not application records — the 35 destinations
    /// are real places in Azad Jammu and Kashmir and the rate card is what
    /// every fare quote is built from. Deleting them does not clear old
    /// records, it takes the product apart: the tourism catalogue goes empty,
    /// no fare can be quoted, so no ride can be booked and no tour package can
    /// name a destination.
    ///
    /// And nothing put them back. They are seeded by migrations, migration
    /// history lives in public.schema_migrations which this reset does not
    /// touch, so the migrations never re-ran. The only route back was a button
    /// labelled "Add demo data" — which is both the wrong name for real
    /// reference data and, until the seed was fixed, broken anyway.
    ///
    /// Safe to exclude: neither table has an outgoing foreign key, so no
    /// TRUNCATE ... CASCADE elsewhere in the loop can reach them either.
    /// </remarks>
    private static readonly string[] PreservedTables =
    [
        "users", "user_roles", "system_settings", "refresh_tokens",
        "destinations", "service_vehicle_rates"
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

                -- The preserved list goes through a temp table rather than
                -- straight into the loop below, because the loop is a DO block
                -- and a DO block's body is a dollar-quoted string literal:
                -- @preserved inside it would never be substituted, it would
                -- reach PL/pgSQL as the literal text "@preserved". A temp table
                -- the block can read keeps PreservedTables the single source of
                -- truth in C# without building SQL by hand.
                CREATE TEMP TABLE preserved_tables(name text PRIMARY KEY) ON COMMIT DROP;
                INSERT INTO preserved_tables(name) SELECT DISTINCT unnest(@preserved);

                DO $$
                DECLARE item record;
                BEGIN
                    FOR item IN
                        SELECT tablename
                        FROM pg_tables
                        WHERE schemaname = 'udrive'
                          AND tablename NOT IN (SELECT name FROM preserved_tables)
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
                     jsonb_build_object('portalAccountsPreserved', true,
                                        'systemSettingsPreserved', true,
                                        'referenceDataPreserved', true),
                     now(), now());
                """;
            command.Parameters.AddWithValue("roles", PortalRoles);
            command.Parameters.AddWithValue("preserved", PreservedTables);
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
            message = "Old application data deleted. Portal admin accounts, system settings, "
                + "the destination catalogue and the vehicle rate card were preserved.",
            before,
            after = await GetStatusAsync(cancellationToken)
        };
    }

    /// <summary>Restores the reference data, and adds the demo hotels.</summary>
    /// <remarks>
    /// Two things changed here, and the first is the reason this ever needed
    /// changing.
    ///
    /// It used to seed by re-running two MIGRATION files — 023 for the rate
    /// card and 010 for the destinations. A migration is written against the
    /// schema as it stood when it was written, so replaying one against a
    /// schema that has moved on is a bet that keeps getting riskier. It came
    /// due: migration 025 later added service_vehicle_rates.per_km_rate as NOT
    /// NULL with no default, and 023's INSERT does not supply it. The seed
    /// therefore threw 23502 on its first statement every single time it was
    /// pressed. Reference data now has its own script, written against the
    /// current schema, and no migration is ever replayed.
    ///
    /// Second, each script gets its own savepoint. Before, all three ran in one
    /// transaction with no savepoints, so 023 failing rolled back the
    /// destinations and the hotels too — neither of which had anything wrong
    /// with them. An operator pressing this button to get the catalogue back
    /// got a 500 and an unchanged database, and the 500 said only "an
    /// unexpected error occurred". Now one script failing costs only that
    /// script, and the reply names it.
    /// </remarks>
    public async Task<object> AddDemoDataAsync(Guid adminUserId, CancellationToken cancellationToken)
    {
        (string Name, string Sql)[] scripts =
        [
            ("the destination catalogue and vehicle rate card",
                await ReadEmbeddedSqlAsync("reference_data.sql", cancellationToken)),
            ("the demo hotels",
                await ReadEmbeddedSqlAsync("demo_hotels.sql", cancellationToken)),
        ];

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        var applied = new List<string>();
        var failures = new List<string>();

        try
        {
            for (var index = 0; index < scripts.Length; index++)
            {
                var script = scripts[index];
                var savepoint = $"seed_{index}";
                await transaction.SaveAsync(savepoint, cancellationToken);
                try
                {
                    await ExecuteSqlAsync(connection, transaction, script.Sql, cancellationToken);
                    await transaction.ReleaseAsync(savepoint, cancellationToken);
                    applied.Add(script.Name);
                }
                catch (Exception exception)
                {
                    // Back to the savepoint, not out of the transaction: whatever
                    // the earlier scripts wrote stays, and the later ones still run.
                    await transaction.RollbackAsync(savepoint, cancellationToken);
                    failures.Add($"{script.Name} ({exception.Message})");
                    logger.LogError(exception,
                        "Seeding {Script} failed. The other seed scripts were unaffected.",
                        script.Name);
                }
            }

            await using var audit = connection.CreateCommand();
            audit.Transaction = transaction;
            audit.CommandText = """
                INSERT INTO udrive.audit_logs
                    (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
                VALUES
                    (gen_random_uuid(), @admin_id, 'DemoDataSeeded', 'System', 'udrive-demo',
                     jsonb_build_object('applied', @applied, 'failed', @failed),
                     now(), now());
                """;
            audit.Parameters.AddWithValue("admin_id", adminUserId);
            audit.Parameters.AddWithValue("applied", applied.ToArray());
            audit.Parameters.AddWithValue("failed", failures.ToArray());
            await audit.ExecuteNonQueryAsync(cancellationToken);
            await transaction.CommitAsync(cancellationToken);
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            throw;
        }

        if (failures.Count == 0)
        {
            logger.LogInformation("Demo data was seeded by admin {AdminUserId}", adminUserId);
        }

        // The message leads with the problem when there is one, because the
        // portal shows it in the same place either way, and the counts on the
        // page refresh alongside it.
        var message = failures.Count == 0
            ? "Added " + string.Join(" and ", applied) + "."
            : "PARTLY APPLIED. Could not add " + string.Join("; ", failures) + ". "
              + (applied.Count > 0
                  ? "Added " + string.Join(" and ", applied) + "."
                  : "Nothing was added.");

        return new
        {
            message,
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
