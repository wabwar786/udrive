using Npgsql;

namespace UDrive.Api.Services;

/// <summary>
/// Sends the queued WhatsApp messages (<see cref="WhatsAppOutbox"/>) through
/// WA Engine, every few seconds.
/// </summary>
/// <remarks>
/// Rows are claimed with SKIP LOCKED, so two API instances never send the
/// same message. A failed send is retried three times, a few minutes apart;
/// a wrong number is not retried. A message still unsent after six hours is
/// dropped — a booking notice that arrives the next day helps nobody.
/// </remarks>
public sealed class WhatsAppOutboxWorker(
    IServiceScopeFactory scopeFactory,
    string connectionString,
    ILogger<WhatsAppOutboxWorker> logger) : BackgroundService
{
    private static readonly TimeSpan Tick = TimeSpan.FromSeconds(10);
    private const int Batch = 20;
    private const int MaxAttempts = 3;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Migrations run on start-up; give them a moment before the first pass.
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            var sent = 0;
            try
            {
                sent = await SendDueAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "The WhatsApp outbox pass failed.");
            }

            // A full batch means more are waiting: go again straight away.
            if (sent >= Batch) continue;

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

    private async Task<int> SendDueAsync(CancellationToken ct)
    {
        var due = new List<(Guid Id, string Phone, string Body, int Attempts)>();
        await using (var connection = new NpgsqlConnection(connectionString))
        {
            await connection.OpenAsync(ct);
            await using (var stale = new NpgsqlCommand(
                """
                UPDATE udrive.whatsapp_outbox
                SET status = 'Failed', last_error = 'Not sent within 6 hours.'
                WHERE status = 'Pending' AND created_at < now() - interval '6 hours';
                """, connection))
            {
                await stale.ExecuteNonQueryAsync(ct);
            }

            // Claimed by pushing next_attempt_at forward: if this instance
            // dies mid-send, the row comes due again on its own.
            await using var claim = new NpgsqlCommand(
                $"""
                UPDATE udrive.whatsapp_outbox o
                SET attempts = o.attempts + 1, next_attempt_at = now() + interval '5 minutes'
                WHERE o.id IN (
                    SELECT id FROM udrive.whatsapp_outbox
                    WHERE status = 'Pending' AND next_attempt_at <= now()
                    ORDER BY created_at
                    LIMIT {Batch}
                    FOR UPDATE SKIP LOCKED)
                RETURNING o.id, o.to_phone, o.body, o.attempts;
                """, connection);
            await using var reader = await claim.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                due.Add((reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetInt32(3)));
            }
        }

        if (due.Count == 0) return 0;

        using var scope = scopeFactory.CreateScope();
        var whatsApp = scope.ServiceProvider.GetRequiredService<WhatsAppService>();

        foreach (var message in due)
        {
            string? error = null;
            var retry = true;
            try
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
                timeout.CancelAfter(TimeSpan.FromSeconds(15));
                var result = await whatsApp.SendTextAsync(message.Phone, message.Body, timeout.Token);
                if (!result.Success)
                {
                    error = result.Message ?? result.ErrorCode ?? "Send failed.";
                    retry = result.ErrorCode != "invalid_whatsapp_number";
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception)
            {
                error = exception.Message;
            }

            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(ct);
            await using var update = new NpgsqlCommand(
                error is null
                    ? "UPDATE udrive.whatsapp_outbox SET status = 'Sent', sent_at = now(), last_error = NULL WHERE id = @id;"
                    : retry && message.Attempts < MaxAttempts
                        ? "UPDATE udrive.whatsapp_outbox SET last_error = @error, next_attempt_at = now() + make_interval(mins => @wait) WHERE id = @id;"
                        : "UPDATE udrive.whatsapp_outbox SET status = 'Failed', last_error = @error WHERE id = @id;",
                connection);
            update.Parameters.AddWithValue("id", message.Id);
            if (error is not null)
            {
                update.Parameters.AddWithValue("error", error.Length > 300 ? error[..300] : error);
                update.Parameters.AddWithValue("wait", 2 * message.Attempts);
            }

            await update.ExecuteNonQueryAsync(ct);
        }

        return due.Count;
    }
}
