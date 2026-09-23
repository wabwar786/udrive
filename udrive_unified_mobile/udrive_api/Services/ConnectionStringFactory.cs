using Npgsql;

namespace UDrive.Api.Services;

public static class ConnectionStringFactory
{
    public static string Resolve(IConfiguration configuration)
    {
        // An empty DATABASE_URL is not the same as a missing one, and it is the
        // likelier mistake: a Railway variable reference such as
        // ${{Postgres.DATABASE_URL}} resolves to an empty string when the
        // service name is wrong. Without this guard the app starts, hands "" to
        // Npgsql and dies with "The ConnectionString property has not been
        // initialized", which says nothing about where to look.
        var value = FirstNonEmpty(
            Environment.GetEnvironmentVariable("DATABASE_URL"),
            configuration.GetConnectionString("DefaultConnection"));

        if (value is null)
        {
            throw new InvalidOperationException(
                "DATABASE_URL is missing or empty. In Railway open udrive-api -> Variables, set " +
                "DATABASE_URL to a reference to the Postgres service (type ${{ and pick DATABASE_URL " +
                "from the list; typing the service name by hand resolves to an empty value when it " +
                "does not match), then redeploy.");
        }

        // Railway may provide either an Npgsql-style connection string or
        // a PostgreSQL URI. Npgsql-style strings can be used directly.
        if (!value.StartsWith("postgres://", StringComparison.OrdinalIgnoreCase)
            && !value.StartsWith("postgresql://", StringComparison.OrdinalIgnoreCase))
        {
            return value;
        }

        var uri = new Uri(value);
        var credentials = uri.UserInfo.Split(':', 2);

        if (credentials.Length == 0 || string.IsNullOrWhiteSpace(credentials[0]))
        {
            throw new InvalidOperationException(
                "DATABASE_URL does not contain a valid PostgreSQL username.");
        }

        var builder = new NpgsqlConnectionStringBuilder
        {
            Host = uri.Host,
            Port = uri.IsDefaultPort ? 5432 : uri.Port,
            Username = Uri.UnescapeDataString(credentials[0]),
            Password = credentials.Length > 1
                ? Uri.UnescapeDataString(credentials[1])
                : string.Empty,
            Database = uri.AbsolutePath.TrimStart('/'),
            SslMode = SslMode.Prefer,
            Pooling = true,

            // Npgsql 10 property names:
            MinPoolSize = 0,
            MaxPoolSize = 100,

            Timeout = 15,
            CommandTimeout = 30,
            KeepAlive = 30,
            ApplicationName = "udrive-api"
        };

        return builder.ConnectionString;
    }

    private static string? FirstNonEmpty(params string?[] candidates) =>
        candidates.FirstOrDefault(candidate => !string.IsNullOrWhiteSpace(candidate))?.Trim();
}
