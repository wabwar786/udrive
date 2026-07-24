using Npgsql;

namespace UDrive.Api.Services;

public static class ConnectionStringFactory
{
    public static string Resolve(IConfiguration configuration)
    {
        var value = Environment.GetEnvironmentVariable("DATABASE_URL")
                    ?? configuration.GetConnectionString("DefaultConnection")
                    ?? throw new InvalidOperationException("DATABASE_URL or ConnectionStrings:DefaultConnection is required.");

        if (!value.StartsWith("postgres://", StringComparison.OrdinalIgnoreCase) &&
            !value.StartsWith("postgresql://", StringComparison.OrdinalIgnoreCase))
        {
            return value;
        }

        var uri = new Uri(value);
        var credentials = uri.UserInfo.Split(':', 2);
        var builder = new NpgsqlConnectionStringBuilder
        {
            Host = uri.Host,
            Port = uri.IsDefaultPort ? 5432 : uri.Port,
            Username = Uri.UnescapeDataString(credentials[0]),
            Password = credentials.Length > 1 ? Uri.UnescapeDataString(credentials[1]) : string.Empty,
            Database = uri.AbsolutePath.TrimStart('/'),
            SslMode = SslMode.Prefer,
            TrustServerCertificate = true,
            Pooling = true,
            MinimumPoolSize = 0,
            MaximumPoolSize = 100,
            Timeout = 15,
            CommandTimeout = 30,
            KeepAlive = 30
        };

        return builder.ConnectionString;
    }
}
