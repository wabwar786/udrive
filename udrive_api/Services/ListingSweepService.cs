using Npgsql;

namespace UDrive.Api.Services;

/// <summary>
/// Every five minutes: closes rental requests the owner did not answer in
/// time, reminds owners whose answer is due soon, and warns drivers (and their
/// owner) once when a licence has thirty days or less left.
/// </summary>
/// <remarks>
/// Modelled on <see cref="SelfTestScheduler"/>. Expiry also happens whenever a
/// rental list is read or a booking is made, so a missed tick never leaves a
/// customer waiting on a request that is already past its deadline.
/// </remarks>
public sealed class ListingSweepService(
    IServiceScopeFactory scopeFactory,
    string connectionString,
    ILogger<ListingSweepService> logger) : BackgroundService
{
    private static readonly TimeSpan Tick = TimeSpan.FromMinutes(5);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Migrations run on start-up; give them a moment before the first pass.
        try
        {
            await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await SweepAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "The listing sweep failed.");
            }

            try
            {
                await Task.Delay(Tick, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private async Task SweepAsync(CancellationToken ct)
    {
        await using (var connection = new NpgsqlConnection(connectionString))
        {
            await connection.OpenAsync(ct);
            var expired = await RentalService.ExpireOverdueAsync(connection, ct);
            if (expired > 0) logger.LogInformation("Expired {Count} unanswered rental request(s).", expired);
        }

        using var scope = scopeFactory.CreateScope();
        var rentals = scope.ServiceProvider.GetRequiredService<RentalService>();
        var whatsApp = scope.ServiceProvider.GetRequiredService<WhatsAppService>();

        foreach (var (bookingId, notice) in await rentals.DueRemindersAsync(ct))
        {
            // Recorded whether or not it went out: one reminder attempt per
            // request, never a message every five minutes.
            await rentals.RecordOwnerNoticeAsync(bookingId, true, ct);
            await SendAsync(whatsApp, notice.To, notice.Message, ct);
        }

        foreach (var warning in await ExpiringLicencesAsync(ct))
        {
            var day = warning.Expiry.ToString("dd MMM yyyy");
            await SendAsync(whatsApp, warning.DriverPhone,
                $"UDrive: your driving licence expires on {day}. Renew it and send the new one in the UDrive app "
                + "(Profile → Driver invites), or you cannot be given bookings after that day.", ct);
            if (!warning.IsOwner && !string.IsNullOrWhiteSpace(warning.OwnerPhone))
            {
                await SendAsync(whatsApp, warning.OwnerPhone,
                    $"UDrive: {warning.DriverName}'s driving licence expires on {day}. "
                    + "After that day they cannot be assigned to your bookings.", ct);
            }
        }
    }

    private sealed record LicenceWarning(
        string DriverName, string DriverPhone, string? OwnerPhone, bool IsOwner, DateOnly Expiry);

    /// <summary>Marks and returns the licences that need their one warning.</summary>
    private async Task<IReadOnlyList<LicenceWarning>> ExpiringLicencesAsync(CancellationToken ct)
    {
        const string sql = """
            WITH due AS (
                UPDATE udrive.fleet_drivers fd
                SET expiry_reminded_at = now(), updated_at = now()
                WHERE fd.status = 'Approved'
                  AND fd.expiry_reminded_at IS NULL
                  AND fd.licence_expiry IS NOT NULL
                  AND fd.licence_expiry BETWEEN (now() AT TIME ZONE 'Asia/Karachi')::date
                                            AND (now() AT TIME ZONE 'Asia/Karachi')::date + 30
                RETURNING fd.full_name, fd.phone_number, fd.is_owner, fd.licence_expiry, fd.owner_profile_id
            )
            SELECT d.full_name, d.phone_number, u.phone_number, d.is_owner, d.licence_expiry
            FROM due d
            JOIN udrive.driver_profiles dp ON dp.id = d.owner_profile_id
            JOIN udrive.users u ON u.id = dp.user_id;
            """;

        var list = new List<LicenceWarning>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            list.Add(new LicenceWarning(
                reader.GetString(0),
                reader.GetString(1),
                reader.IsDBNull(2) ? null : reader.GetString(2),
                reader.GetBoolean(3),
                DateOnly.FromDateTime(reader.GetDateTime(4))));
        }

        return list;
    }

    private async Task SendAsync(WhatsAppService whatsApp, string to, string message, CancellationToken ct)
    {
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(TimeSpan.FromSeconds(12));
            await whatsApp.SendTextAsync(to, message, timeout.Token);
        }
        catch (Exception exception) when (!ct.IsCancellationRequested)
        {
            logger.LogWarning(exception, "A listing sweep WhatsApp message could not be sent.");
        }
    }
}
