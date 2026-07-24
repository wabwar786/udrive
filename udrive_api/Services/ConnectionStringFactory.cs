using Npgsql;

namespace UDrive.Api.Services;

public static class ConnectionStringFactory
{
    public static string Resolve(IConfiguration configuration)
    {
        var value =
            Environment.GetEnvironmentVariable("DATABASE_URL")
            ?? configuration.GetConnectionString("DefaultConnection")
            ?? throw new InvalidOperationException(
                "DATABASE_URL or ConnectionStrings:DefaultConnection is required.");

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
}
