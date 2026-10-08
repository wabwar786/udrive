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

        // How much of this balance UDrive put there rather than the Driver.
        //
        // Rewards are credited into the commission balance, so a Driver who has
        // earned a mission sees their balance go up with no top-up behind it and
        // no way to tell why. Positive Bonus entries only: a correction an admin
        // had to make is not a reward.
        decimal rewardsCredited;
        await using (var command = new NpgsqlCommand(
            """
            SELECT COALESCE(SUM(amount), 0)
            FROM udrive.driver_wallet_entries
            WHERE wallet_id = @id AND entry_type = 'Bonus' AND amount > 0;
            """,
            connection))
        {
            command.Parameters.AddWithValue("id", wallet.Value.WalletId);
            rewardsCredited =
                Convert.ToDecimal(await command.ExecuteScalarAsync(cancellationToken));
        }

        return ServiceResult<DriverCommissionWalletDto>.Ok(
            new DriverCommissionWalletDto(
                balance,
                minimum,
                percentage,
                balance > minimum,
                topups,
                charges,
                rewardsCredited));
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
                   t.status, t.admin_notes, t.created_at, t.reviewed_at, t.wallet_kind
            FROM udrive.driver_wallet_topups t
            LEFT JOIN udrive.driver_profiles dp ON dp.id = t.driver_profile_id
            -- A hotel top-up names the owner directly.
            JOIN udrive.users u ON u.id = COALESCE(dp.user_id, t.owner_user_id)
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
                reader.IsDBNull(8) ? null : reader.GetFieldValue<DateTimeOffset>(8),
                reader.GetString(9)));
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
            RETURNING driver_profile_id, amount, sender_reference, wallet_kind, owner_user_id;
            """;

        Guid profileId = Guid.Empty;
        decimal amount;
        string? reference;
        Guid? hotelOwner = null;

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

            if (reader.GetString(3) == "Hotel") hotelOwner = reader.GetGuid(4);
            else profileId = reader.GetGuid(0);
            amount = reader.GetDecimal(1);
            reference = reader.IsDBNull(2) ? null : reader.GetString(2);
        }

        // A hotel owner's top-up goes to the hotel wallet.
        if (hotelOwner is { } owner)
        {
            if (approve)
            {
                await HotelWalletService.CreditTopupAsync(
                    connection, transaction, owner, amount, topupId, reference, actorUserId, cancellationToken);
            }

            await transaction.CommitAsync(cancellationToken);
            return ServiceResult<bool>.Ok(true);
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

        if (approve)
        {
            // Back above the line re-arms the warning for the next drop.
            await CheckLowBalanceAsync(connection, transaction, profileId, cancellationToken);
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
    /// <summary>Every commission charge for this Driver, newest first.</summary>
    public async Task<ServiceResult<IReadOnlyList<CommissionEntryDto>>> CommissionHistoryAsync(
        Guid userId,
        int take,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT e.created_at,
                   abs(e.amount),
                   COALESCE(b.booking_reference, e.reference),
                   COALESCE(b.total_amount, rb.subtotal),
                   COALESCE(b.pickup_label, CASE WHEN rb.id IS NOT NULL THEN 'Rent a car' END),
                   b.destination_label,
                   e.entry_type
            FROM udrive.driver_wallet_entries e
            JOIN udrive.driver_wallets w ON w.id = e.wallet_id
            JOIN udrive.driver_profiles dp ON dp.id = w.driver_profile_id
            LEFT JOIN udrive.bookings b ON b.id = e.booking_id
            -- A rent commission has no booking row; its rental is in the key.
            LEFT JOIN udrive.rental_bookings rb
                   ON e.entry_type = 'RentCommission'
                  AND e.idempotency_key = 'rent:' || rb.id::text
            WHERE dp.user_id = @user
              AND e.entry_type IN ('CommissionCharge', 'CancellationCharge', 'RentCommission')
            ORDER BY e.created_at DESC
            LIMIT @take;
            """;

        var list = new List<CommissionEntryDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("user", userId);
        command.Parameters.AddWithValue("take", take);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var charged = reader.GetDecimal(1);
            var fare = reader.IsDBNull(3) ? 0m : reader.GetDecimal(3);

            list.Add(new CommissionEntryDto(
                reader.GetFieldValue<DateTimeOffset>(0),
                charged,
                reader.IsDBNull(2) ? null : reader.GetString(2),
                fare,
                // Derived from what was actually taken, not from today's
                // setting. A driver looking at last month should see the rate
                // they were charged, not the one in force now.
                fare <= 0 ? 0 : Math.Round(charged / fare * 100, 1),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.GetString(6) == "CancellationCharge"));
        }

        return ServiceResult<IReadOnlyList<CommissionEntryDto>>.Ok(list);
    }

    /// <summary>Credits a newly approved Driver their opening balance.</summary>
    /// <remarks>
    /// The amount is an admin setting, because its purpose expires. Early on it
    /// buys a fleet: a driver who has to top up before their first fare has
    /// been asked to pay to find out whether the platform works. Once there are
    /// drivers, that reason is gone.
    ///
    /// Keyed on the driver profile. Re-approving somebody after a suspension,
    /// or an Admin clicking twice, credits nothing further — this is a welcome,
    /// not a monthly payment.
    /// </remarks>
    internal static Task<bool> CreditWelcomeBonusAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid driverProfileId,
        CancellationToken cancellationToken) =>
        CreditWelcomeAsync(connection, transaction, driverProfileId,
            "driver.welcome.bonus", 1000, "welcome:", "Welcome credit on approval", cancellationToken);

    /// <summary>
    /// The welcome credit for tours or rent-a-car, paid once per owner per
    /// kind, when a vehicle is first approved for that kind.
    /// </summary>
    /// <param name="kind">tour or rent.</param>
    internal static Task<bool> CreditListingWelcomeAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid driverProfileId,
        string kind,
        CancellationToken cancellationToken) =>
        kind == "rent"
            ? CreditWelcomeAsync(connection, transaction, driverProfileId,
                "driver.welcome.rent_bonus", 500, "welcome:rent:", "Welcome credit — rent a car approve", cancellationToken)
            : CreditWelcomeAsync(connection, transaction, driverProfileId,
                "driver.welcome.tour_bonus", 500, "welcome:tour:", "Welcome credit — tour approve", cancellationToken);

    private static async Task<bool> CreditWelcomeAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid driverProfileId,
        string settingKey,
        decimal fallback,
        string keyPrefix,
        string description,
        CancellationToken cancellationToken)
    {
        // The wallet row is created first, in a statement of its own.
        //
        // It used to be a CTE in the statement below, and that silently broke
        // everything: Postgres will not let a second CTE update a row that an
        // earlier CTE in the same statement has already inserted or updated, and
        // sibling CTEs all read the same snapshot. So `credited` matched nothing,
        // the balance never moved and no ledger row was written — with no error,
        // which is why it went unnoticed. Proven against the live database:
        // balance 5000.00 before, `INSERT 0 0`, balance 5000.00 after.
        await EnsureWalletForDriverAsync(
            connection, transaction, driverProfileId, cancellationToken);

        const string sql = """
            WITH amount AS (
                SELECT COALESCE((SELECT (value_json #>> '{}')::numeric
                                   FROM udrive.system_settings
                                  WHERE key = @setting), @fallback) AS value
            ), credited AS (
                UPDATE udrive.driver_wallets w
                SET commission_balance = w.commission_balance + amount.value,
                    version = w.version + 1,
                    updated_at = now()
                FROM amount
                WHERE w.driver_profile_id = @driver
                  AND amount.value > 0
                  -- The balance is guarded by the same key as the ledger row.
                  -- Without this only the ledger was idempotent, so a retry
                  -- would have moved the balance again and left it disagreeing
                  -- with its own history.
                  AND NOT EXISTS (
                      SELECT 1 FROM udrive.driver_wallet_entries e
                      WHERE e.idempotency_key = @prefix || @driver::text)
                RETURNING w.id AS wallet_id, amount.value AS credited
            )
            INSERT INTO udrive.driver_wallet_entries
                (id, wallet_id, entry_type, amount, balance_bucket,
                 description, idempotency_key, created_at)
            SELECT gen_random_uuid(), credited.wallet_id, 'CommissionTopup',
                   credited.credited, 'Commission',
                   @description,
                   @prefix || @driver::text, now()
            FROM credited
            ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL
            DO NOTHING
            RETURNING id;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("driver", driverProfileId);
        command.Parameters.AddWithValue("setting", settingKey);
        command.Parameters.AddWithValue("fallback", fallback);
        command.Parameters.AddWithValue("prefix", keyPrefix);
        command.Parameters.AddWithValue("description", description);
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is not null and not DBNull;
    }

    internal static async Task<bool> ChargeCancellationAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid bookingId,
        CancellationToken cancellationToken)
    {
        // Wallet first, in its own statement — see CreditWelcomeBonusAsync for
        // why a CTE here made this whole method a no-op.
        await EnsureWalletForBookingAsync(
            connection, transaction, bookingId, cancellationToken);

        const string sql = """
            WITH booking AS (
                SELECT b.id, b.driver_profile_id, b.total_amount
                FROM udrive.bookings b
                WHERE b.id = @booking AND b.driver_profile_id IS NOT NULL
            ), charged AS (
                UPDATE udrive.driver_wallets w
                SET commission_balance =
                        w.commission_balance
                        - round(booking.total_amount * 0.02, 2),
                    version = w.version + 1,
                    updated_at = now()
                FROM booking
                WHERE w.driver_profile_id = booking.driver_profile_id
                  AND booking.total_amount > 0
                  -- Same key as the ledger row below, so a cancellation that is
                  -- retried — or a status set twice, which the transition table
                  -- allows — cannot deduct 2% a second time.
                  AND NOT EXISTS (
                      SELECT 1 FROM udrive.driver_wallet_entries e
                      WHERE e.idempotency_key = 'cancel:' || @booking)
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
        var charged = result is not null and not DBNull;
        if (charged)
        {
            await CheckLowBalanceForBookingAsync(connection, transaction, bookingId, cancellationToken);
        }

        return charged;
    }

    /// <summary>
    /// Makes sure this driver has a wallet row, as a statement of its own.
    /// </summary>
    /// <remarks>
    /// Separate from the statement that then moves money, and that separation is
    /// the whole point. A CTE cannot insert a row and have a later CTE in the
    /// same statement update it — Postgres simply does not apply the second
    /// change, and returns no error while doing so. Three methods here were
    /// written that way and all three were silently doing nothing: no
    /// commission, no cancellation fee, no welcome credit.
    ///
    /// DO NOTHING rather than DO UPDATE: the only purpose is existence, and
    /// touching `updated_at` for a row that already exists is a write for
    /// nothing.
    /// </remarks>
    private static async Task EnsureWalletForDriverAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid driverProfileId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.driver_wallets
                (id, driver_profile_id, created_at, updated_at)
            VALUES (gen_random_uuid(), @driver, now(), now())
            ON CONFLICT (driver_profile_id) DO NOTHING;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("driver", driverProfileId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>The same, for the driver a booking is assigned to.</summary>
    private static async Task EnsureWalletForBookingAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid bookingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.driver_wallets
                (id, driver_profile_id, created_at, updated_at)
            SELECT gen_random_uuid(), b.driver_profile_id, now(), now()
            FROM udrive.bookings b
            WHERE b.id = @booking AND b.driver_profile_id IS NOT NULL
            ON CONFLICT (driver_profile_id) DO NOTHING;
            """;

        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("booking", bookingId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    internal static async Task<bool> ChargeCommissionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid bookingId,
        CancellationToken cancellationToken)
    {
        // Wallet first — see EnsureWalletForDriverAsync.
        await EnsureWalletForBookingAsync(
            connection, transaction, bookingId, cancellationToken);

        // The rate depends on the kind of work: a tour, a city-to-city ride
        // (pickup and drop in different districts), or an ordinary city ride.
        // Each has its own Admin setting; a kind with no setting falls back to
        // the city rate.
        const string sql = """
            WITH booking AS (
                SELECT b.id, b.driver_profile_id, b.total_amount,
                       CASE WHEN b.tour_package_id IS NOT NULL THEN 'tour'
                            WHEN COALESCE(rr.is_intercity, false) THEN 'intercity'
                            ELSE 'city' END AS kind
                FROM udrive.bookings b
                LEFT JOIN udrive.ride_requests rr ON rr.id = b.ride_request_id
                WHERE b.id = @booking AND b.driver_profile_id IS NOT NULL
            ), city_rate AS (
                SELECT COALESCE(
                    (SELECT (value_json #>> '{}')::numeric
                       FROM udrive.system_settings
                      WHERE key = 'driver.commission.percentage'), 10) AS pct
            ), rate AS (
                SELECT COALESCE(
                    (SELECT (s.value_json #>> '{}')::numeric
                       FROM udrive.system_settings s, booking
                      WHERE s.key = CASE booking.kind
                                WHEN 'tour' THEN 'driver.commission.tour_percentage'
                                WHEN 'intercity' THEN 'driver.commission.intercity_percentage'
                                ELSE 'driver.commission.percentage' END),
                    (SELECT pct FROM city_rate)) AS pct
            ), charged AS (
                UPDATE udrive.driver_wallets w
                SET commission_balance =
                        w.commission_balance
                        - round(booking.total_amount * rate.pct / 100, 2),
                    version = w.version + 1,
                    updated_at = now()
                FROM booking, rate
                WHERE w.driver_profile_id = booking.driver_profile_id
                  AND booking.total_amount > 0
                  AND NOT EXISTS (
                      SELECT 1 FROM udrive.driver_wallet_entries e
                      WHERE e.idempotency_key = 'commission:' || @booking)
                RETURNING w.id AS wallet_id,
                          round(booking.total_amount * rate.pct / 100, 2) AS charge,
                          rate.pct AS pct
            )
            INSERT INTO udrive.driver_wallet_entries
                (id, wallet_id, booking_id, entry_type, amount, balance_bucket,
                 description, idempotency_key, created_at)
            SELECT gen_random_uuid(), charged.wallet_id, @booking,
                   'CommissionCharge', -charged.charge, 'Commission',
                   CASE (SELECT kind FROM booking)
                        WHEN 'tour' THEN 'Tour commission '
                        WHEN 'intercity' THEN 'City-to-city commission '
                        ELSE 'Platform commission ' END
                   || trim(to_char(charged.pct, 'FM990.##')) || '% on trip start',
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
        var charged = result is not null and not DBNull;
        if (charged)
        {
            await CheckLowBalanceForBookingAsync(connection, transaction, bookingId, cancellationToken);
        }

        return charged;
    }

    /// <summary>The commission a rent booking costs its driver, in rupees.</summary>
    /// <remarks>
    /// <c>driver.commission.rent_percentage</c> of the rental subtotal, falling
    /// back to the city rate. Asked before the driver accepts, so the app can
    /// say what will be taken and the server can refuse when the wallet does
    /// not cover it.
    /// </remarks>
    internal static async Task<(decimal Commission, decimal Balance)> RentCommissionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid rentalBookingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT round(rb.subtotal * COALESCE(
                       (SELECT (value_json #>> '{}')::numeric FROM udrive.system_settings
                         WHERE key = 'driver.commission.rent_percentage'),
                       (SELECT (value_json #>> '{}')::numeric FROM udrive.system_settings
                         WHERE key = 'driver.commission.percentage'),
                       10) / 100, 2),
                   COALESCE((SELECT w.commission_balance FROM udrive.driver_wallets w
                              WHERE w.driver_profile_id = rb.driver_profile_id), 0)
            FROM udrive.rental_bookings rb
            WHERE rb.id = @rental;
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("rental", rentalBookingId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? (reader.GetDecimal(0), reader.GetDecimal(1))
            : (0m, 0m);
    }

    /// <summary>Takes the rent commission when the driver accepts a rental.</summary>
    /// <remarks>Keyed on the rental, so a retried accept cannot charge twice.</remarks>
    internal static async Task ChargeRentCommissionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid rentalBookingId,
        decimal commission,
        CancellationToken cancellationToken)
    {
        if (commission <= 0) return;

        Guid driverProfileId;
        string reference;
        await using (var load = new NpgsqlCommand(
            "SELECT driver_profile_id, booking_reference FROM udrive.rental_bookings WHERE id = @rental;",
            connection,
            transaction))
        {
            load.Parameters.AddWithValue("rental", rentalBookingId);
            await using var reader = await load.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken)) return;
            driverProfileId = reader.GetGuid(0);
            reference = reader.GetString(1);
        }

        await EnsureWalletForDriverAsync(connection, transaction, driverProfileId, cancellationToken);
        await MoveCommissionAsync(
            connection, transaction, driverProfileId, -commission, "RentCommission",
            $"Rent commission · {reference}", reference, $"rent:{rentalBookingId}", cancellationToken);
        await CheckLowBalanceAsync(connection, transaction, driverProfileId, cancellationToken);
    }

    /// <summary>Gives the rent commission back when the customer cancels.</summary>
    /// <remarks>
    /// Only what was actually taken, found by its key; nothing when nothing
    /// was charged. Keyed on the rental, so it is returned once.
    /// </remarks>
    internal static async Task RefundRentCommissionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid rentalBookingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT w.driver_profile_id, -e.amount, e.reference
            FROM udrive.driver_wallet_entries e
            JOIN udrive.driver_wallets w ON w.id = e.wallet_id
            WHERE e.idempotency_key = 'rent:' || @rental;
            """;
        Guid driverProfileId;
        decimal amount;
        string? reference;
        await using (var command = new NpgsqlCommand(sql, connection, transaction))
        {
            command.Parameters.AddWithValue("rental", rentalBookingId.ToString());
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken)) return;
            driverProfileId = reader.GetGuid(0);
            amount = reader.GetDecimal(1);
            reference = reader.IsDBNull(2) ? null : reader.GetString(2);
        }

        if (amount <= 0) return;
        await MoveCommissionAsync(
            connection, transaction, driverProfileId, amount, "RentCommissionRefund",
            $"Rent cancelled by customer · {reference} · commission returned", reference,
            $"rentrefund:{rentalBookingId}", cancellationToken);
        await CheckLowBalanceAsync(connection, transaction, driverProfileId, cancellationToken);
    }

    /// <summary>Moves the commission balance and writes its ledger row, once per key.</summary>
    private static async Task MoveCommissionAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid driverProfileId,
        decimal amount,
        string entryType,
        string description,
        string? reference,
        string key,
        CancellationToken cancellationToken)
    {
        const string sql = """
            WITH moved AS (
                UPDATE udrive.driver_wallets w
                SET commission_balance = w.commission_balance + @amount,
                    version = w.version + 1,
                    updated_at = now()
                WHERE w.driver_profile_id = @driver
                  AND NOT EXISTS (
                      SELECT 1 FROM udrive.driver_wallet_entries e
                      WHERE e.idempotency_key = @key)
                RETURNING w.id AS wallet_id
            )
            INSERT INTO udrive.driver_wallet_entries
                (id, wallet_id, entry_type, amount, balance_bucket,
                 description, reference, idempotency_key, created_at)
            SELECT gen_random_uuid(), moved.wallet_id, @type, @amount, 'Commission',
                   @description, @reference, @key, now()
            FROM moved
            ON CONFLICT (idempotency_key) WHERE idempotency_key IS NOT NULL
            DO NOTHING;
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("driver", driverProfileId);
        command.Parameters.AddWithValue("amount", amount);
        command.Parameters.AddWithValue("type", entryType);
        command.Parameters.AddWithValue("description", description);
        command.Parameters.Add(new NpgsqlParameter("reference", NpgsqlDbType.Varchar)
        {
            Value = (object?)reference ?? DBNull.Value,
        });
        command.Parameters.AddWithValue("key", key);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>
    /// Tells the Driver once when their wallet drops below the warning line.
    /// </summary>
    /// <remarks>
    /// One in-app notification per drop, not one per ride: the wallet row
    /// remembers that the warning went out, and the mark is cleared when the
    /// balance is back at or above the line (a top-up), so the next drop warns
    /// again. The line is <c>driver.wallet.low_balance_alert</c> (PKR 50 by
    /// default); zero turns the warning off.
    /// </remarks>
    internal static async Task CheckLowBalanceAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid driverProfileId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            WITH line AS (
                SELECT COALESCE(
                    (SELECT (value_json #>> '{}')::numeric
                       FROM udrive.system_settings
                      WHERE key = 'driver.wallet.low_balance_alert'), 50) AS value
            ), cleared AS (
                UPDATE udrive.driver_wallets w
                SET low_balance_notified_at = NULL
                FROM line
                WHERE w.driver_profile_id = @driver
                  AND w.low_balance_notified_at IS NOT NULL
                  AND w.commission_balance >= line.value
                RETURNING w.id
            ), flagged AS (
                UPDATE udrive.driver_wallets w
                SET low_balance_notified_at = now()
                FROM line
                WHERE w.driver_profile_id = @driver
                  AND w.low_balance_notified_at IS NULL
                  AND line.value > 0
                  AND w.commission_balance < line.value
                RETURNING w.commission_balance AS balance, line.value AS line_value
            )
            INSERT INTO udrive.notifications
                (id, user_id, type, title, body, data_json, created_at, updated_at)
            SELECT gen_random_uuid(), dp.user_id, 'WalletLow', 'Wallet top-up karein',
                   'Aap ka wallet PKR ' || trim(to_char(flagged.balance, 'FM999999990'))
                   || ' hai — ' || trim(to_char(flagged.line_value, 'FM999999990'))
                   || ' se kam. Top-up karein taa ke rides milti rahein.',
                   jsonb_build_object('balance', flagged.balance, 'line', flagged.line_value),
                   now(), now()
            FROM flagged
            JOIN udrive.driver_profiles dp ON dp.id = @driver
            RETURNING user_id, (data_json->>'balance')::numeric, (data_json->>'line')::numeric;
            """;

        Guid? userId = null;
        decimal balance = 0;
        decimal line = 0;
        await using (var command = new NpgsqlCommand(sql, connection, transaction))
        {
            command.Parameters.AddWithValue("driver", driverProfileId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (await reader.ReadAsync(cancellationToken))
            {
                userId = reader.GetGuid(0);
                balance = reader.GetDecimal(1);
                line = reader.GetDecimal(2);
            }
        }

        // Only when the warning was just raised: once per drop below the line.
        if (userId is null) return;
        string? phone;
        await using (var command = new NpgsqlCommand(
            "SELECT phone_number FROM udrive.users WHERE id = @id;", connection, transaction))
        {
            command.Parameters.AddWithValue("id", userId.Value);
            phone = await command.ExecuteScalarAsync(cancellationToken) as string;
        }

        await WhatsAppOutbox.QueueAsync(
            connection, transaction, WhatsAppOutbox.WalletLowDriver, phone,
            new Dictionary<string, string?>
            {
                ["balance"] = WhatsAppOutbox.Money(balance),
                ["line"] = WhatsAppOutbox.Money(line),
            },
            cancellationToken);
    }

    private static async Task CheckLowBalanceForBookingAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid bookingId,
        CancellationToken cancellationToken)
    {
        Guid driverProfileId;
        await using (var command = new NpgsqlCommand(
            "SELECT driver_profile_id FROM udrive.bookings WHERE id = @booking;",
            connection,
            transaction))
        {
            command.Parameters.AddWithValue("booking", bookingId);
            if (await command.ExecuteScalarAsync(cancellationToken) is not Guid id)
            {
                return;
            }

            driverProfileId = id;
        }

        await CheckLowBalanceAsync(connection, transaction, driverProfileId, cancellationToken);
    }
}
