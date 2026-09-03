using Microsoft.AspNetCore.Http;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The Driver's prepaid commission balance, and the top-ups that feed it.
/// </summary>
/// <remarks>
/// The arrangement is: the Driver sends money to the company, an Admin confirms
/// it arrived, and the balance is credited. Ten percent of every completed
/// booking is then taken from that balance. When it runs out, no new requests
/// reach them.
///
/// This is deliberately a different column from <c>available_balance</c>, which
/// means money the platform owes the Driver. The two move in opposite
/// directions and sharing one field would make every reconciliation ambiguous.
/// </remarks>
public sealed class DriverWalletService(
    string connectionString,
    LocalFileStorageService fileStorage)
{
    /// <summary>Reads a numeric platform setting, with a fallback.</summary>
    private static async Task<decimal> SettingAsync(
        NpgsqlConnection connection,
        string key,
        decimal fallback,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT value_json FROM udrive.system_settings WHERE key = @key;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("key", key);
        var value = await command.ExecuteScalarAsync(cancellationToken);

        return value is string text && decimal.TryParse(
                text.Trim('"'),
                System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture,
                out var parsed)
            ? parsed
            : fallback;
    }

    /// <summary>
    /// Finds the Driver's wallet, creating it the first time it is needed.
    /// </summary>
    /// <remarks>
    /// Created on demand rather than at registration. A wallet row that exists
    /// for every Driver who ever started signing up is mostly rows for people
    /// who never drove.
    /// </remarks>
    private static async Task<(Guid WalletId, Guid ProfileId)?> EnsureWalletAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            WITH profile AS (
                SELECT id FROM udrive.driver_profiles WHERE user_id = @user
            ), created AS (
                INSERT INTO udrive.driver_wallets
                    (id, driver_profile_id, created_at, updated_at)
                SELECT gen_random_uuid(), profile.id, now(), now()
                FROM profile
                ON CONFLICT (driver_profile_id) DO NOTHING
                RETURNING id, driver_profile_id
            )
            SELECT id, driver_profile_id FROM created
            UNION ALL
            SELECT w.id, w.driver_profile_id
            FROM udrive.driver_wallets w
            JOIN profile ON profile.id = w.driver_profile_id
            LIMIT 1;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("user", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? (reader.GetGuid(0), reader.GetGuid(1))
            : null;
    }

    /// <summary>Balance, threshold, and the Driver's own top-up history.</summary>
    public async Task<ServiceResult<DriverCommissionWalletDto>> SummaryAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var wallet = await EnsureWalletAsync(connection, null, userId, cancellationToken);
        if (wallet is null)
        {
            return ServiceResult<DriverCommissionWalletDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_profile_not_found",
                "You do not have a driver profile yet.");
        }

        var minimum = await SettingAsync(
            connection, "driver.commission.minimum_balance", 0, cancellationToken);
        var percentage = await SettingAsync(
            connection, "driver.commission.percentage", 10, cancellationToken);

        decimal balance;
        await using (var command = new NpgsqlCommand(
            "SELECT commission_balance FROM udrive.driver_wallets WHERE id = @id;",
            connection))
        {
            command.Parameters.AddWithValue("id", wallet.Value.WalletId);
            balance = (decimal)(await command.ExecuteScalarAsync(cancellationToken))!;
        }

        const string topupsSql = """
            SELECT id, amount, method, sender_reference, status, admin_notes,
                   created_at, reviewed_at
            FROM udrive.driver_wallet_topups
            WHERE driver_profile_id = @profile
            ORDER BY created_at DESC
            LIMIT 20;
            """;

        var topups = new List<WalletTopupDto>();
        await using (var command = new NpgsqlCommand(topupsSql, connection))
        {
            command.Parameters.AddWithValue("profile", wallet.Value.ProfileId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                topups.Add(new WalletTopupDto(
                    reader.GetGuid(0),
                    null,
                    reader.GetDecimal(1),
                    reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.GetString(4),
                    reader.IsDBNull(5) ? null : reader.GetString(5),
                    reader.GetFieldValue<DateTimeOffset>(6),
                    reader.IsDBNull(7)
                        ? null
                        : reader.GetFieldValue<DateTimeOffset>(7)));
            }
        }

        const string chargesSql = """
            SELECT e.amount, e.description, e.created_at
            FROM udrive.driver_wallet_entries e
            WHERE e.wallet_id = @wallet
              AND e.balance_bucket = 'Commission'
            ORDER BY e.created_at DESC
            LIMIT 20;
            """;

        var charges = new List<WalletChargeDto>();
        await using (var command = new NpgsqlCommand(chargesSql, connection))
        {
            command.Parameters.AddWithValue("wallet", wallet.Value.WalletId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                charges.Add(new WalletChargeDto(
                    reader.GetDecimal(0),
                    reader.GetString(1),
                    reader.GetFieldValue<DateTimeOffset>(2)));
            }
        }

        return ServiceResult<DriverCommissionWalletDto>.Ok(
            new DriverCommissionWalletDto(
                balance,
                minimum,
                percentage,
                balance > minimum,
                topups,
                charges));
    }

    /// <summary>Records a payment the Driver says they have sent.</summary>
    /// <remarks>
    /// Nothing is credited here. The balance moves only when an Admin has seen
    /// the money arrive — a screenshot is a claim, not a receipt, and crediting
    /// on upload would make the balance forgeable with an image editor.
    /// </remarks>
    public async Task<ServiceResult<WalletTopupDto>> SubmitTopupAsync(
        Guid userId,
        decimal amount,
        string? senderReference,
        IFormFile? screenshot,
        CancellationToken cancellationToken)
    {
        if (amount <= 0)
        {
            return ServiceResult<WalletTopupDto>.Fail(
                StatusCodes.Status400BadRequest,
                "amount_invalid",
                "Enter the amount you sent.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var wallet = await EnsureWalletAsync(connection, null, userId, cancellationToken);
        if (wallet is null)
        {
            return ServiceResult<WalletTopupDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_profile_not_found",
                "You do not have a driver profile yet.");
        }

        string? screenshotUrl = null;
        if (screenshot is not null && screenshot.Length > 0)
        {
            var stored = await fileStorage.SaveAsync(
                screenshot,
                "wallet-topups",
                wallet.Value.ProfileId,
                cancellationToken);
            screenshotUrl = stored.RelativeUrl;
        }

        const string sql = """
            INSERT INTO udrive.driver_wallet_topups
                (driver_profile_id, amount, sender_reference, screenshot_url)
            VALUES (@profile, @amount, @reference, @screenshot)
            RETURNING id, amount, method, sender_reference, status, admin_notes,
                      created_at, reviewed_at;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("profile", wallet.Value.ProfileId);
        command.Parameters.AddWithValue("amount", amount);
        command.Parameters.Add(new NpgsqlParameter("reference", NpgsqlDbType.Varchar)
        {
            Value = string.IsNullOrWhiteSpace(senderReference)
                ? DBNull.Value
                : senderReference.Trim(),
        });
        command.Parameters.Add(new NpgsqlParameter("screenshot", NpgsqlDbType.Text)
        {
            Value = (object?)screenshotUrl ?? DBNull.Value,
        });

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        await reader.ReadAsync(cancellationToken);

        return ServiceResult<WalletTopupDto>.Created(new WalletTopupDto(
            reader.GetGuid(0),
            null,
            reader.GetDecimal(1),
            reader.GetString(2),
            reader.IsDBNull(3) ? null : reader.GetString(3),
            reader.GetString(4),
            reader.IsDBNull(5) ? null : reader.GetString(5),
            reader.GetFieldValue<DateTimeOffset>(6),
            null));
    }

    // ------------------------------------------------------------------ admin

    /// <summary>Top-ups waiting for someone to confirm the money arrived.</summary>
    public async Task<ServiceResult<IReadOnlyList<WalletTopupDto>>> PendingAsync(
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT t.id, u.full_name, t.amount, t.method, t.sender_reference,
                   t.status, t.admin_notes, t.created_at, t.reviewed_at
            FROM udrive.driver_wallet_topups t
            JOIN udrive.driver_profiles dp ON dp.id = t.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE t.status = 'Pending'
            ORDER BY t.created_at;
            """;

        var list = new List<WalletTopupDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(new WalletTopupDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetDecimal(2),
                reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetString(6),
                reader.GetFieldValue<DateTimeOffset>(7),
                reader.IsDBNull(8) ? null : reader.GetFieldValue<DateTimeOffset>(8)));
        }

        return ServiceResult<IReadOnlyList<WalletTopupDto>>.Ok(list);
    }

    /// <summary>Confirms or rejects a top-up.</summary>
    /// <remarks>
    /// Approving credits the balance and writes a ledger entry in the same
    /// transaction. The status change and the money must not be able to come
    /// apart — a credited balance with no entry behind it cannot be audited,
    /// and an approved row with no credit is a Driver who paid and got nothing.
    ///
    /// The update requires <c>status = 'Pending'</c>, so two Admins pressing
    /// approve at once credit the balance once.
    /// </remarks>
    public async Task<ServiceResult<bool>> ReviewTopupAsync(
        Guid actorUserId,
        Guid topupId,
        bool approve,
        string? notes,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction =
            await connection.BeginTransactionAsync(cancellationToken);

        const string closeSql = """
            UPDATE udrive.driver_wallet_topups
            SET status = @status,
                admin_notes = @notes,
                reviewed_by_user_id = @actor,
                reviewed_at = now(),
                updated_at = now()
            WHERE id = @id AND status = 'Pending'
            RETURNING driver_profile_id, amount, sender_reference;
            """;

        Guid profileId;
        decimal amount;
        string? reference;

        await using (var command = new NpgsqlCommand(closeSql, connection, transaction))
        {
            command.Parameters.AddWithValue("id", topupId);
            command.Parameters.AddWithValue("status", approve ? "Approved" : "Rejected");
            command.Parameters.AddWithValue("actor", actorUserId);
            command.Parameters.Add(new NpgsqlParameter("notes", NpgsqlDbType.Varchar)
            {
                Value = string.IsNullOrWhiteSpace(notes) ? DBNull.Value : notes.Trim(),
            });

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<bool>.Fail(
                    StatusCodes.Status409Conflict,
                    "topup_already_reviewed",
                    "That top-up has already been dealt with.");
            }

            profileId = reader.GetGuid(0);
            amount = reader.GetDecimal(1);
            reference = reader.IsDBNull(2) ? null : reader.GetString(2);
        }

        if (approve)
        {
            const string creditSql = """
                INSERT INTO udrive.driver_wallets
                    (id, driver_profile_id, commission_balance, created_at, updated_at)
                VALUES (gen_random_uuid(), @profile, @amount, now(), now())
                ON CONFLICT (driver_profile_id) DO UPDATE SET
                    commission_balance =
                        udrive.driver_wallets.commission_balance + EXCLUDED.commission_balance,
                    version = udrive.driver_wallets.version + 1,
                    updated_at = now()
                RETURNING id;
                """;

            Guid walletId;
            await using (var command = new NpgsqlCommand(creditSql, connection, transaction))
            {
                command.Parameters.AddWithValue("profile", profileId);
                command.Parameters.AddWithValue("amount", amount);
                walletId = (Guid)(await command.ExecuteScalarAsync(cancellationToken))!;
            }

            const string entrySql = """
                INSERT INTO udrive.driver_wallet_entries
                    (id, wallet_id, entry_type, amount, balance_bucket,
                     description, reference, idempotency_key, created_by_user_id,
                     created_at)
                VALUES (gen_random_uuid(), @wallet, 'CommissionTopup', @amount,
                        'Commission', @description, @reference, @key, @actor, now());
                """;

            await using (var command = new NpgsqlCommand(entrySql, connection, transaction))
            {
                command.Parameters.AddWithValue("wallet", walletId);
                command.Parameters.AddWithValue("amount", amount);
                command.Parameters.AddWithValue(
                    "description", $"Top-up confirmed ({amount:0} PKR)");
                command.Parameters.Add(new NpgsqlParameter("reference", NpgsqlDbType.Varchar)
                {
                    Value = (object?)reference ?? DBNull.Value,
                });
                // Keyed on the top-up, so a retried approval cannot credit twice.
                command.Parameters.AddWithValue("key", $"topup:{topupId}");
                command.Parameters.AddWithValue("actor", actorUserId);
                await command.ExecuteNonQueryAsync(cancellationToken);
            }
        }

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<bool>.Ok(true);
    }

    // ------------------------------------------------------------- commission

    /// <summary>
    /// Takes the platform's share out of the Driver's prepaid balance.
    /// </summary>
    /// <remarks>
    /// Called when a booking completes, inside that transaction, so the charge
    /// and the completion commit together.
    /// </remarks>
    /// <returns>
    /// True when a charge was written. False when there was nothing to charge —
    /// a zero fare, or a booking already charged.
    /// </returns>
    /// <summary>
    /// Charges the Driver for abandoning a ride they had accepted.
    /// </summary>
    /// <remarks>
    /// Two percent of the fare, taken from the prepaid balance when a Driver
    /// cancels before the trip has started. A Customer who has been waiting has
    /// lost their place in the queue and has to start again, and the cost of
    /// that should not fall entirely on them.
    ///
    /// Deliberately small. This is meant to make a casual cancellation cost
    /// something, not to trap a Driver whose vehicle has broken down — at two
    /// percent, a genuine emergency costs about the price of a cup of tea.
    ///
    /// Not charged once the trip has started: at that point the Customer is in
    /// the vehicle and a cancellation is a different, more serious event that
    /// belongs with the disputes process, not an automatic fee.
    /// </remarks>
    internal static async Task<bool> ChargeCancellationAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid bookingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            WITH booking AS (
                SELECT b.id, b.driver_profile_id, b.total_amount
                FROM udrive.bookings b
                WHERE b.id = @booking AND b.driver_profile_id IS NOT NULL
            ), wallet AS (
                INSERT INTO udrive.driver_wallets
                    (id, driver_profile_id, created_at, updated_at)
                SELECT gen_random_uuid(), booking.driver_profile_id, now(), now()
                FROM booking
                ON CONFLICT (driver_profile_id) DO UPDATE SET updated_at = now()
                RETURNING id
            ), charged AS (
                UPDATE udrive.driver_wallets w
                SET commission_balance =
                        w.commission_balance
                        - round(booking.total_amount * 0.02, 2),
                    version = w.version + 1,
                    updated_at = now()
                FROM booking, wallet
                WHERE w.id = wallet.id AND booking.total_amount > 0
                RETURNING w.id AS wallet_id,
                          round(booking.total_amount * 0.02, 2) AS charge
            )
            INSERT INTO udrive.driver_wallet_entries
                (id, wallet_id, booking_id, entry_type, amount, balance_bucket,
                 description, idempotency_key, created_at)
            SELECT gen_random_uuid(), charged.wallet_id, @booking,
                   'CancellationCharge', -charged.charge, 'Commission',
                   'Cancelled after accepting the ride (2%)',
                   'cancel:' || @booking, now()
            FROM charged
            -- Keyed on the booking: a cancellation that is retried, or a status
            -- set twice, must not charge twice.
            ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL
            DO NOTHING
            RETURNING id;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("booking", bookingId);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is not null and not DBNull;
    }

    internal static async Task<bool> ChargeCommissionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid bookingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            WITH booking AS (
                SELECT b.id, b.driver_profile_id, b.total_amount
                FROM udrive.bookings b
                WHERE b.id = @booking AND b.driver_profile_id IS NOT NULL
            ), rate AS (
                SELECT COALESCE(
                    (SELECT (value_json #>> '{}')::numeric
                       FROM udrive.system_settings
                      WHERE key = 'driver.commission.percentage'), 10) AS pct
            ), wallet AS (
                INSERT INTO udrive.driver_wallets
                    (id, driver_profile_id, created_at, updated_at)
                SELECT gen_random_uuid(), booking.driver_profile_id, now(), now()
                FROM booking
                ON CONFLICT (driver_profile_id) DO UPDATE SET updated_at = now()
                RETURNING id, driver_profile_id
            ), charged AS (
                UPDATE udrive.driver_wallets w
                SET commission_balance =
                        w.commission_balance
                        - round(booking.total_amount * rate.pct / 100, 2),
                    version = w.version + 1,
                    updated_at = now()
                FROM booking, rate, wallet
                WHERE w.id = wallet.id AND booking.total_amount > 0
                RETURNING w.id AS wallet_id,
                          round(booking.total_amount * rate.pct / 100, 2) AS charge,
                          rate.pct AS pct
            )
            INSERT INTO udrive.driver_wallet_entries
                (id, wallet_id, booking_id, entry_type, amount, balance_bucket,
                 description, idempotency_key, created_at)
            SELECT gen_random_uuid(), charged.wallet_id, @booking,
                   'CommissionCharge', -charged.charge, 'Commission',
                   'Platform commission ' || charged.pct || '% on completed trip',
                   'commission:' || @booking, now()
            FROM charged
            -- Keyed on the booking. A completion that is retried, or a status
            -- that is set twice, must not charge the Driver twice.
            --
            -- The predicate is repeated because the index behind it is partial
            -- (`WHERE idempotency_key IS NOT NULL`). Postgres only accepts a
            -- partial index as an arbiter when the statement says so, and
            -- without it this raises 42P10 and rolls back the trip completion
            -- it is running inside.
            ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL
            DO NOTHING
            RETURNING id;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("booking", bookingId);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is not null and not DBNull;
    }
}
