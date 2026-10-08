using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The hotel owner's prepaid wallet: welcome credit, top-ups, and the
/// commission taken when a hotel booking is confirmed.
/// </summary>
/// <remarks>
/// One wallet per owner, for all their hotels. Every change writes a ledger
/// row keyed by an idempotency key, and moves the balance in the same
/// statement only when that row was new — a retry never moves money twice.
/// A hotel whose owner's balance is below <c>hotel.wallet.minimum_balance</c>
/// is hidden from new customers (HotelService search, detail and booking).
/// </remarks>
public sealed class HotelWalletService(string connectionString, LocalFileStorageService storage)
{
    // ─────────────────────────────────────────────────────── owner

    public async Task<ServiceResult<HotelWalletDto>> WalletAsync(Guid ownerId, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        if (!await OwnsHotelAsync(connection, ownerId, ct))
        {
            return ServiceResult<HotelWalletDto>.Fail(404, "no_hotel", "Pehle hotel add karein.");
        }

        decimal balance = 0;
        await using (var command = new NpgsqlCommand(
            "SELECT balance FROM udrive.hotel_wallets WHERE owner_user_id = @u;", connection))
        {
            command.Parameters.AddWithValue("u", ownerId);
            if (await command.ExecuteScalarAsync(ct) is { } found and not DBNull) balance = Convert.ToDecimal(found, System.Globalization.CultureInfo.InvariantCulture);
        }

        var percentage = await SettingAsync(connection, null, "hotel.commission.percentage", 0, ct);
        var minimum = await SettingAsync(connection, null, "hotel.wallet.minimum_balance", 0, ct);
        var alert = await SettingAsync(connection, null, "hotel.wallet.low_balance_alert", 500, ct);
        string? number = null, name = null;
        await using (var command = new NpgsqlCommand(
            """
            SELECT key, value_json #>> '{}' FROM udrive.system_settings
            WHERE key IN ('payments.easypaisa.number', 'payments.easypaisa.name');
            """, connection))
        {
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                var value = reader.IsDBNull(1) ? null : reader.GetString(1);
                if (reader.GetString(0).EndsWith("number", StringComparison.Ordinal)) number = value;
                else name = value;
            }
        }

        var entries = new List<HotelWalletEntryDto>();
        await using (var command = new NpgsqlCommand(
            """
            SELECT id, entry_type, amount, balance_after, description, created_at
            FROM udrive.hotel_wallet_entries WHERE owner_user_id = @u
            ORDER BY created_at DESC LIMIT 40;
            """, connection))
        {
            command.Parameters.AddWithValue("u", ownerId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                entries.Add(new HotelWalletEntryDto(reader.GetGuid(0), reader.GetString(1), reader.GetDecimal(2),
                    reader.GetDecimal(3), reader.GetString(4), reader.GetFieldValue<DateTimeOffset>(5)));
            }
        }

        var topups = new List<WalletTopupDto>();
        await using (var command = new NpgsqlCommand(
            """
            SELECT id, amount, method, sender_reference, status, admin_notes, created_at, reviewed_at
            FROM udrive.driver_wallet_topups
            WHERE wallet_kind = 'Hotel' AND owner_user_id = @u
            ORDER BY created_at DESC LIMIT 20;
            """, connection))
        {
            command.Parameters.AddWithValue("u", ownerId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                topups.Add(new WalletTopupDto(
                    reader.GetGuid(0), null, reader.GetDecimal(1), reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3), reader.GetString(4),
                    reader.IsDBNull(5) ? null : reader.GetString(5), reader.GetFieldValue<DateTimeOffset>(6),
                    reader.IsDBNull(7) ? null : reader.GetFieldValue<DateTimeOffset>(7), "Hotel"));
            }
        }

        return ServiceResult<HotelWalletDto>.Ok(new HotelWalletDto(
            balance, percentage, minimum, alert, balance >= minimum, number, name, entries, topups));
    }

    /// <summary>Records money the owner says they sent. Nothing is credited until an Admin approves.</summary>
    public async Task<ServiceResult<WalletTopupDto>> SubmitTopupAsync(
        Guid ownerId, decimal amount, string? reference, IFormFile? screenshot, CancellationToken ct)
    {
        if (amount <= 0 || amount > 1_000_000) return ServiceResult<WalletTopupDto>.Fail(400, "amount_invalid", "Jitni raqam bheji woh likhein.");
        await using var connection = await OpenAsync(ct);
        if (!await OwnsHotelAsync(connection, ownerId, ct))
        {
            return ServiceResult<WalletTopupDto>.Fail(404, "no_hotel", "Pehle hotel add karein.");
        }

        string? url = null;
        if (screenshot is { Length: > 0 })
        {
            try
            {
                url = (await storage.SaveAsync(screenshot, "wallet-topups", ownerId, ct)).RelativeUrl;
            }
            catch (InvalidDataException exception)
            {
                return ServiceResult<WalletTopupDto>.Fail(400, "file_invalid", exception.Message);
            }
        }

        await using var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.driver_wallet_topups (wallet_kind, owner_user_id, amount, sender_reference, screenshot_url)
            VALUES ('Hotel', @u, @amount, @reference, @screenshot)
            RETURNING id, amount, method, sender_reference, status, admin_notes, created_at;
            """, connection);
        command.Parameters.AddWithValue("u", ownerId);
        command.Parameters.AddWithValue("amount", decimal.Round(amount, 2));
        command.Parameters.Add(new NpgsqlParameter("reference", NpgsqlDbType.Varchar)
        {
            Value = string.IsNullOrWhiteSpace(reference) ? DBNull.Value : reference.Trim()[..Math.Min(120, reference.Trim().Length)],
        });
        command.Parameters.Add(new NpgsqlParameter("screenshot", NpgsqlDbType.Text) { Value = (object?)url ?? DBNull.Value });
        await using var reader = await command.ExecuteReaderAsync(ct);
        await reader.ReadAsync(ct);
        return ServiceResult<WalletTopupDto>.Created(new WalletTopupDto(
            reader.GetGuid(0), null, reader.GetDecimal(1), reader.GetString(2),
            reader.IsDBNull(3) ? null : reader.GetString(3), reader.GetString(4),
            reader.IsDBNull(5) ? null : reader.GetString(5), reader.GetFieldValue<DateTimeOffset>(6), null, "Hotel"),
            "Top-up bhej diya. Admin approve kare to balance mein aa jayega.");
    }

    // ─────────────────────────────────────────────────────── money moves

    /// <summary>Welcome credit, once per owner, when their first hotel is approved.</summary>
    internal static async Task<bool> CreditWelcomeAsync(
        NpgsqlConnection connection, NpgsqlTransaction? tx, Guid ownerId, Guid hotelId, CancellationToken ct)
    {
        var amount = await SettingAsync(connection, tx, "hotel.welcome.bonus", 500, ct);
        if (amount <= 0) return false;
        return await MoveAsync(connection, tx, ownerId, "Welcome", amount, hotelId, null,
            "Welcome credit — hotel approve", null, $"hotel-welcome:{ownerId}", null, ct);
    }

    /// <summary>An Admin confirmed a hotel top-up.</summary>
    internal static async Task CreditTopupAsync(
        NpgsqlConnection connection, NpgsqlTransaction tx, Guid ownerId, decimal amount,
        Guid topupId, string? reference, Guid actor, CancellationToken ct)
    {
        await MoveAsync(connection, tx, ownerId, "Topup", amount, null, null,
            $"Top-up confirmed ({amount:0} PKR)", reference, $"hotel-topup:{topupId}", actor, ct);
        await CheckLowAsync(connection, tx, ownerId, ct);
    }

    /// <summary>The commission on a confirmed hotel booking, from the owner's wallet.</summary>
    /// <returns>The amount taken (0 when commission is off).</returns>
    internal static async Task<decimal> ChargeBookingAsync(
        NpgsqlConnection connection, NpgsqlTransaction tx, Guid bookingId, CancellationToken ct)
    {
        Guid owner, hotel;
        decimal total;
        string reference;
        await using (var command = new NpgsqlCommand(
            """
            SELECT h.owner_user_id, h.id, b.amount, COALESCE(b.booking_reference, '')
            FROM udrive.hotel_bookings b JOIN udrive.hotels h ON h.id = b.hotel_id
            WHERE b.id = @id;
            """, connection, tx))
        {
            command.Parameters.AddWithValue("id", bookingId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct)) return 0;
            owner = reader.GetGuid(0);
            hotel = reader.GetGuid(1);
            total = reader.GetDecimal(2);
            reference = reader.GetString(3);
        }

        var percentage = await SettingAsync(connection, tx, "hotel.commission.percentage", 0, ct);
        var charge = decimal.Round(total * percentage / 100m, 0);
        if (charge <= 0) return 0;
        var moved = await MoveAsync(connection, tx, owner, "Commission", -charge, hotel, bookingId,
            $"Commission — booking {reference} ({percentage:0.#}% of Rs {total:N0})", reference,
            $"hotel-commission:{bookingId}", null, ct);
        if (moved) await CheckLowAsync(connection, tx, owner, ct);
        return moved ? charge : 0;
    }

    /// <summary>Writes one ledger row and moves the balance with it, once per key.</summary>
    private static async Task<bool> MoveAsync(
        NpgsqlConnection connection, NpgsqlTransaction? tx, Guid ownerId, string type, decimal amount,
        Guid? hotelId, Guid? bookingId, string description, string? reference, string key, Guid? actor, CancellationToken ct)
    {
        // The wallet row first, in its own statement (a CTE cannot insert a
        // row and have a sibling CTE update it).
        await using (var ensure = new NpgsqlCommand(
            "INSERT INTO udrive.hotel_wallets (owner_user_id) VALUES (@u) ON CONFLICT (owner_user_id) DO NOTHING;",
            connection, tx))
        {
            ensure.Parameters.AddWithValue("u", ownerId);
            await ensure.ExecuteNonQueryAsync(ct);
        }

        await using var command = new NpgsqlCommand(
            """
            WITH fresh AS (
                SELECT NOT EXISTS (SELECT 1 FROM udrive.hotel_wallet_entries WHERE idempotency_key = @key) AS ok
            ), moved AS (
                UPDATE udrive.hotel_wallets w
                SET balance = w.balance + @amount, version = w.version + 1, updated_at = now()
                FROM fresh
                WHERE w.owner_user_id = @u AND fresh.ok
                RETURNING w.balance
            )
            INSERT INTO udrive.hotel_wallet_entries
                (owner_user_id, entry_type, amount, balance_after, hotel_id, hotel_booking_id,
                 description, reference, idempotency_key, created_by_user_id)
            SELECT @u, @type, @amount, moved.balance, @hotel, @booking, @description, @reference, @key, @actor
            FROM moved
            ON CONFLICT (idempotency_key) DO NOTHING
            RETURNING id;
            """, connection, tx);
        command.Parameters.AddWithValue("u", ownerId);
        command.Parameters.AddWithValue("type", type);
        command.Parameters.AddWithValue("amount", amount);
        command.Parameters.Add(new NpgsqlParameter("hotel", NpgsqlDbType.Uuid) { Value = (object?)hotelId ?? DBNull.Value });
        command.Parameters.Add(new NpgsqlParameter("booking", NpgsqlDbType.Uuid) { Value = (object?)bookingId ?? DBNull.Value });
        command.Parameters.AddWithValue("description", description.Length > 300 ? description[..300] : description);
        command.Parameters.Add(new NpgsqlParameter("reference", NpgsqlDbType.Varchar) { Value = (object?)reference ?? DBNull.Value });
        command.Parameters.AddWithValue("key", key);
        command.Parameters.Add(new NpgsqlParameter("actor", NpgsqlDbType.Uuid) { Value = (object?)actor ?? DBNull.Value });
        return await command.ExecuteScalarAsync(ct) is Guid;
    }

    /// <summary>Below the alert line: tell the owner once per drop. Back above: re-arm.</summary>
    private static async Task CheckLowAsync(NpgsqlConnection connection, NpgsqlTransaction? tx, Guid ownerId, CancellationToken ct)
    {
        var line = await SettingAsync(connection, tx, "hotel.wallet.low_balance_alert", 500, ct);
        decimal? dropped = null;
        string? phone = null;
        await using (var command = new NpgsqlCommand(
            """
            WITH changed AS (
                UPDATE udrive.hotel_wallets w
                SET low_balance_notified_at = CASE WHEN w.balance < @line THEN now() ELSE NULL END
                WHERE w.owner_user_id = @u
                  AND ((w.balance < @line AND w.low_balance_notified_at IS NULL)
                       OR (w.balance >= @line AND w.low_balance_notified_at IS NOT NULL))
                RETURNING w.balance, w.low_balance_notified_at IS NOT NULL AS low
            )
            SELECT c.balance, u.phone_number FROM changed c, udrive.users u WHERE u.id = @u AND c.low;
            """, connection, tx))
        {
            command.Parameters.AddWithValue("u", ownerId);
            command.Parameters.AddWithValue("line", line);
            await using var reader = await command.ExecuteReaderAsync(ct);
            if (await reader.ReadAsync(ct))
            {
                dropped = reader.GetDecimal(0);
                phone = reader.IsDBNull(1) ? null : reader.GetString(1);
            }
        }

        if (dropped is not { } balance) return;
        await using (var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.notifications (id, user_id, type, title, body, data_json, action_path, created_at, updated_at)
            VALUES (gen_random_uuid(), @u, 'hotel_wallet_low', 'Hotel wallet kam hai',
                    @body, '{}'::jsonb, '/hotel/wallet', now(), now());
            """, connection, tx))
        {
            command.Parameters.AddWithValue("u", ownerId);
            command.Parameters.AddWithValue("body", $"Wallet mein Rs {balance:N0} reh gaye. Top-up karein, warna hotel naye customers ko nazar nahi aayega.");
            await command.ExecuteNonQueryAsync(ct);
        }

        await WhatsAppOutbox.QueueAsync(connection, tx, "wallet_low_hotel", phone,
            new Dictionary<string, string?>
            {
                ["balance"] = WhatsAppOutbox.Money(balance),
                ["line"] = "PKR " + WhatsAppOutbox.Money(line),
            }, ct);
    }

    private static async Task<decimal> SettingAsync(
        NpgsqlConnection connection, NpgsqlTransaction? tx, string key, decimal fallback, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            "SELECT value_json #>> '{}' FROM udrive.system_settings WHERE key = @key;", connection, tx);
        command.Parameters.AddWithValue("key", key);
        var raw = (await command.ExecuteScalarAsync(ct))?.ToString();
        return decimal.TryParse(raw, System.Globalization.NumberStyles.Number, System.Globalization.CultureInfo.InvariantCulture, out var value)
            ? value
            : fallback;
    }

    private static async Task<bool> OwnsHotelAsync(NpgsqlConnection connection, Guid ownerId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            "SELECT EXISTS (SELECT 1 FROM udrive.hotels WHERE owner_user_id = @u);", connection);
        command.Parameters.AddWithValue("u", ownerId);
        return await command.ExecuteScalarAsync(ct) is true;
    }

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken ct)
    {
        var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        return connection;
    }
}
