using System.Globalization;
using System.Text.RegularExpressions;
using Npgsql;

namespace UDrive.Api.Services;

/// <summary>
/// Queues WhatsApp messages written from the Admin's templates.
/// </summary>
/// <remarks>
/// Called inside the same transaction as the booking, acceptance or wallet
/// change it is about, so a message is queued exactly when that thing really
/// happened. Sending is done later by <see cref="WhatsAppOutboxWorker"/>, so
/// WhatsApp being slow or down never holds up or undoes the booking.
///
/// A template the Admin switched off sends nothing. A missing phone number
/// sends nothing. Any failure here is swallowed behind a savepoint: a message
/// is never worth losing a booking over.
/// </remarks>
public static partial class WhatsAppOutbox
{
    public const string TourBookingCustomer = "tour_booking_customer";
    public const string TourBookingDriver = "tour_booking_driver";
    public const string RentBookingCustomer = "rent_booking_customer";
    public const string RentBookingDriver = "rent_booking_driver";
    public const string WaitlistAcceptedCustomer = "waitlist_accepted_customer";
    public const string WalletLowDriver = "wallet_low_driver";

    private static readonly TimeSpan Karachi = TimeSpan.FromHours(5);
    private static readonly CultureInfo English = CultureInfo.GetCultureInfo("en-US");

    [GeneratedRegex(@"\{([a-z_]+)\}")]
    private static partial Regex Placeholder();

    /// <summary>The placeholders a body uses, in order, without repeats.</summary>
    public static IReadOnlyList<string> PlaceholdersIn(string body) =>
        Placeholder().Matches(body).Select(m => m.Groups[1].Value).Distinct().ToList();

    /// <summary>Fills each {placeholder}; one with no value becomes "—".</summary>
    public static string Render(string body, IReadOnlyDictionary<string, string?> values) =>
        Placeholder().Replace(body, match =>
            values.TryGetValue(match.Groups[1].Value, out var value) && !string.IsNullOrWhiteSpace(value)
                ? value.Trim()
                : "—");

    public static async Task QueueAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        string templateKey,
        string? phone,
        IReadOnlyDictionary<string, string?> values,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(phone)) return;

        // A savepoint, so a problem here rolls back only this message.
        if (transaction is not null) await transaction.SaveAsync("wa_outbox", cancellationToken);
        try
        {
            string? body = null;
            await using (var load = new NpgsqlCommand(
                "SELECT body FROM udrive.message_templates WHERE key = @key AND is_active;",
                connection, transaction))
            {
                load.Parameters.AddWithValue("key", templateKey);
                body = await load.ExecuteScalarAsync(cancellationToken) as string;
            }

            if (string.IsNullOrWhiteSpace(body)) return;

            await using var insert = new NpgsqlCommand(
                """
                INSERT INTO udrive.whatsapp_outbox (template_key, to_phone, body)
                VALUES (@key, @phone, @body);
                """, connection, transaction);
            insert.Parameters.AddWithValue("key", templateKey);
            insert.Parameters.AddWithValue("phone", phone.Trim().Length > 32 ? phone.Trim()[..32] : phone.Trim());
            insert.Parameters.AddWithValue("body", Render(body, values));
            await insert.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (PostgresException) when (transaction is not null)
        {
            await transaction.RollbackAsync("wa_outbox", cancellationToken);
        }
        catch (PostgresException)
        {
            // No transaction to protect; the message is simply not queued.
        }
    }

    // ── formatting shared by every caller, so all messages read the same

    public static string Money(decimal value) => value.ToString("N0", English);

    public static string DateTime(DateTimeOffset value) =>
        value.ToOffset(Karachi).ToString("d MMM, h:mm tt", English);

    public static string Time(DateTimeOffset value) =>
        value.ToOffset(Karachi).ToString("h:mm tt", English);

    public static string Dates(DateOnly start, DateOnly end) =>
        start == end
            ? start.ToString("d MMM", English)
            : $"{start.ToString("d MMM", English)} – {end.ToString("d MMM", English)}";

    public static string Mode(string rentalMode) =>
        rentalMode == "SelfDrive" ? "Self-drive" : "Driver ke saath";
}
