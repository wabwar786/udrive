using Npgsql;

namespace UDrive.Api.Services;

public sealed class ProductionMaintenanceService(
    string connectionString,
    ILogger<ProductionMaintenanceService> logger) : BackgroundService
{
    private readonly TimeSpan _interval = TimeSpan.FromHours(
        int.TryParse(Environment.GetEnvironmentVariable("MAINTENANCE_INTERVAL_HOURS"), out var hours) && hours > 0
            ? Math.Min(hours, 24)
            : 6);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromMinutes(2), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await RunAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "Production maintenance cycle failed.");
            }

            await Task.Delay(_interval, stoppingToken);
        }
    }

    private async Task RunAsync(CancellationToken cancellationToken)
    {
        const string sql = """
            DELETE FROM udrive.auth_otp_challenges
            WHERE expires_at < now() - interval '24 hours';

            DELETE FROM udrive.refresh_tokens
            WHERE expires_at < now() - interval '30 days'
               OR (revoked_at IS NOT NULL AND revoked_at < now() - interval '30 days');

            UPDATE udrive.package_seat_holds
            SET status = 'Expired', updated_at = now()
            WHERE status = 'Active' AND expires_at <= now();

            DELETE FROM udrive.trip_tracking_tokens
            WHERE expires_at < now() - interval '7 days'
               OR (revoked_at IS NOT NULL AND revoked_at < now() - interval '7 days');

            DELETE FROM udrive.trip_location_history
            WHERE server_timestamp < now() - interval '30 days';

            DELETE FROM udrive.notifications
            WHERE read_at IS NOT NULL AND created_at < now() - interval '180 days';
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection)
        {
            CommandTimeout = 120
        };
        var affected = await command.ExecuteNonQueryAsync(cancellationToken);
        logger.LogInformation("Production maintenance cycle completed. Affected rows: {AffectedRows}", affected);
    }
}
