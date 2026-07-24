using System.Reflection;
using Npgsql;
using UDrive.Api.Services;

namespace UDrive.Api.Infrastructure.Persistence;

public sealed class SqlMigrationRunner(IConfiguration configuration, ILogger<SqlMigrationRunner> logger)
{
    public async Task ApplyPendingAsync(CancellationToken cancellationToken = default)
    {
        var connectionString = ConnectionStringFactory.Resolve(configuration);
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        await using (var setup = connection.CreateCommand())
        {
            setup.CommandText = """
                CREATE TABLE IF NOT EXISTS public.schema_migrations (
                    migration_id text PRIMARY KEY,
                    applied_at timestamptz NOT NULL DEFAULT now()
                );
                """;
            await setup.ExecuteNonQueryAsync(cancellationToken);
        }

        var assembly = Assembly.GetExecutingAssembly();
        var resources = assembly.GetManifestResourceNames()
            .Where(name => name.Contains("Infrastructure.Persistence.Migrations", StringComparison.Ordinal) && name.EndsWith(".sql", StringComparison.OrdinalIgnoreCase))
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();

        foreach (var resourceName in resources)
        {
            var migrationId = resourceName.Split('.').Reverse().Skip(1).First();

            await using var exists = connection.CreateCommand();
            exists.CommandText = "SELECT EXISTS(SELECT 1 FROM public.schema_migrations WHERE migration_id = @id);";
            exists.Parameters.AddWithValue("id", migrationId);
            if ((bool)(await exists.ExecuteScalarAsync(cancellationToken) ?? false))
            {
                continue;
            }

            await using var stream = assembly.GetManifestResourceStream(resourceName)
                ?? throw new InvalidOperationException($"Missing embedded migration {resourceName}");
            using var reader = new StreamReader(stream);
            var sql = await reader.ReadToEndAsync(cancellationToken);

            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
            try
            {
                await using var command = connection.CreateCommand();
                command.Transaction = transaction;
                command.CommandText = sql;
                command.CommandTimeout = 120;
                await command.ExecuteNonQueryAsync(cancellationToken);

                await using var record = connection.CreateCommand();
                record.Transaction = transaction;
                record.CommandText = "INSERT INTO public.schema_migrations (migration_id) VALUES (@id);";
                record.Parameters.AddWithValue("id", migrationId);
                await record.ExecuteNonQueryAsync(cancellationToken);

                await transaction.CommitAsync(cancellationToken);
                logger.LogInformation("Applied database migration {MigrationId}", migrationId);
            }
            catch
            {
                await transaction.RollbackAsync(cancellationToken);
                throw;
            }
        }
    }
}
