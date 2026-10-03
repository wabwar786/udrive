using Microsoft.AspNetCore.Http;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// What an Admin can see and change about renting.
/// </summary>
/// <remarks>
/// Read-only apart from two things: cancelling a booking, and the settings.
/// That is deliberate. An Admin editing somebody's rental — the dates, the
/// rate, the deposit — would be editing an agreement between two other people
/// after they made it, and neither of them would know.
///
/// The Customer's identity documents are **not** here. The Admin sees whether
/// each one was provided and nothing more. Looking at them would make the
/// platform a party to the check, which is exactly what the disclaimer the
/// Customer ticked says it is not; and the check that matters is the owner
/// holding the CNIC next to the face in front of them, which no screenshot in
/// an office can reproduce.
/// </remarks>
public sealed class AdminRentalService(string connectionString)
{
    private static readonly string[] LiveStatuses = ["Confirmed", "HandedOver"];

    /// <summary>The four numbers at the top of the page.</summary>
    public async Task<ServiceResult<AdminRentalSummaryDto>> SummaryAsync(
        CancellationToken cancellationToken)
    {
        const string sql = """
            WITH today AS (SELECT (now() AT TIME ZONE 'Asia/Karachi')::date AS d)
            SELECT
              (SELECT count(*) FROM udrive.rental_bookings rb, today
                WHERE rb.status = ANY(@live)
                  AND today.d BETWEEN rb.start_date AND rb.end_date),
              (SELECT count(*) FROM udrive.rental_bookings rb, today
                WHERE rb.status = ANY(@live)
                  AND rb.rental_mode = 'SelfDrive'
                  AND today.d BETWEEN rb.start_date AND rb.end_date),
              (SELECT count(*) FROM udrive.rental_bookings rb, today
                WHERE rb.status = ANY(@live)
                  AND rb.start_date BETWEEN today.d AND today.d + 7),
              (SELECT count(*) FROM udrive.rental_bookings rb, today
                WHERE rb.status = 'Confirmed' AND rb.start_date = today.d),
              -- Only the advance. The balance and the deposit never reach the
              -- platform, so counting them as revenue would be a fiction.
              (SELECT COALESCE(sum(rb.advance_amount), 0)
                 FROM udrive.rental_bookings rb
                WHERE rb.status <> 'Cancelled'
                  AND date_trunc('month', rb.created_at AT TIME ZONE 'Asia/Karachi')
                      = date_trunc('month', now() AT TIME ZONE 'Asia/Karachi')),
              (SELECT count(*) FROM udrive.rental_bookings rb
                WHERE rb.cancelled_by = 'Owner'
                  AND rb.cancelled_at > now() - interval '30 days'),
              (SELECT count(*) FROM udrive.rental_bookings rb
                WHERE rb.cancelled_by = 'Customer'
                  AND rb.cancelled_at > now() - interval '30 days');
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("live", LiveStatuses);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<AdminRentalSummaryDto>.Ok(
                new AdminRentalSummaryDto(0, 0, 0, 0, 0, 0, 0));
        }

        var out_ = (int)reader.GetInt64(0);
        var selfDrive = (int)reader.GetInt64(1);

        return ServiceResult<AdminRentalSummaryDto>.Ok(new AdminRentalSummaryDto(
            out_,
            selfDrive,
            out_ - selfDrive,
            (int)reader.GetInt64(2),
            (int)reader.GetInt64(3),
            reader.GetDecimal(4),
            (int)reader.GetInt64(5) + (int)reader.GetInt64(6)));
    }

    /// <summary>The bookings table, filtered.</summary>
    /// <param name="scope">
    /// <c>live</c>, <c>upcoming</c>, <c>finished</c>, <c>cancelled</c> or
    /// <c>all</c>. Named rather than a raw status list because "live" means two
    /// statuses and a date comparison, which a filter box cannot express and an
    /// Admin should not have to.
    /// </param>
    public async Task<ServiceResult<IReadOnlyList<AdminRentalRowDto>>> ListAsync(
        string? scope,
        string? search,
        DateOnly? from,
        DateOnly? to,
        CancellationToken cancellationToken)
    {
        var predicate = (scope?.Trim().ToLowerInvariant()) switch
        {
            "upcoming" => "rb.status = 'Confirmed' AND rb.start_date > (now() AT TIME ZONE 'Asia/Karachi')::date",
            "finished" => "rb.status IN ('Returned', 'NoShow')",
            "cancelled" => "rb.status = 'Cancelled'",
            "all" => "true",
            _ => "rb.status = ANY(@live) AND (now() AT TIME ZONE 'Asia/Karachi')::date "
                 + "BETWEEN rb.start_date AND rb.end_date",
        };

        var sql = $"""
            SELECT rb.id, rb.booking_reference, rb.rental_mode,
                   trim(concat_ws(' ', v.make, v.model)), v.registration_number,
                   COALESCE(NULLIF(cust.full_name, ''), 'Customer'), cust.phone_number,
                   COALESCE(NULLIF(owner.full_name, ''), 'Owner'), owner.phone_number,
                   rb.start_date, rb.end_date, rb.days,
                   rb.advance_amount, rb.balance_due, rb.security_deposit,
                   rb.status, rb.cancelled_by, rb.created_at
            FROM udrive.rental_bookings rb
            JOIN udrive.vehicles v ON v.id = rb.vehicle_id
            JOIN udrive.driver_profiles dp ON dp.id = rb.driver_profile_id
            JOIN udrive.users owner ON owner.id = dp.user_id
            JOIN udrive.users cust ON cust.id = rb.customer_user_id
            WHERE {predicate}
              AND (@from::date IS NULL OR rb.end_date >= @from::date)
              AND (@to::date IS NULL OR rb.start_date <= @to::date)
              AND (@search = '' OR concat_ws(' ',
                      rb.booking_reference, v.registration_number,
                      v.make, v.model, cust.full_name, cust.phone_number,
                      owner.full_name, owner.phone_number)
                   ILIKE '%' || @search || '%')
            ORDER BY rb.start_date DESC, rb.created_at DESC
            LIMIT 300;
            """;

        var list = new List<AdminRentalRowDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("live", LiveStatuses);
        command.Parameters.AddWithValue("search", search?.Trim() ?? string.Empty);
        AddDate(command, "from", from);
        AddDate(command, "to", to);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(new AdminRentalRowDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetString(4),
                reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetString(6),
                reader.GetString(7),
                reader.IsDBNull(8) ? null : reader.GetString(8),
                DateOnly.FromDateTime(reader.GetDateTime(9)),
                DateOnly.FromDateTime(reader.GetDateTime(10)),
                reader.GetInt32(11),
                reader.GetDecimal(12),
                reader.GetDecimal(13),
                reader.GetDecimal(14),
                reader.GetString(15),
                reader.IsDBNull(16) ? null : reader.GetString(16),
                reader.GetFieldValue<DateTimeOffset>(17)));
        }

        return ServiceResult<IReadOnlyList<AdminRentalRowDto>>.Ok(list);
    }

    /// <summary>One booking, with the acceptance record and the document ticks.</summary>
    public async Task<ServiceResult<AdminRentalDetailDto>> DetailAsync(
        Guid bookingId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT rb.id, rb.booking_reference, rb.rental_mode,
                   trim(concat_ws(' ', v.make, v.model)), v.registration_number,
                   COALESCE(NULLIF(cust.full_name, ''), 'Customer'), cust.phone_number,
                   COALESCE(NULLIF(owner.full_name, ''), 'Owner'), owner.phone_number,
                   rb.start_date, rb.end_date, rb.days, rb.daily_rate, rb.subtotal,
                   rb.advance_amount, rb.balance_due, rb.security_deposit,
                   rb.km_per_day, rb.fuel_included, rb.pickup_point,
                   rb.status, rb.cancelled_by, rb.cancelled_at, rb.cancel_reason,
                   rb.disclaimer_version, rb.disclaimer_accepted_at, rb.created_at,
                   cp.cnic_front_url IS NOT NULL, cp.cnic_back_url IS NOT NULL,
                   cp.driving_licence_url IS NOT NULL, cp.selfie_url IS NOT NULL
            FROM udrive.rental_bookings rb
            JOIN udrive.vehicles v ON v.id = rb.vehicle_id
            JOIN udrive.driver_profiles dp ON dp.id = rb.driver_profile_id
            JOIN udrive.users owner ON owner.id = dp.user_id
            JOIN udrive.users cust ON cust.id = rb.customer_user_id
            LEFT JOIN udrive.customer_profiles cp ON cp.user_id = rb.customer_user_id
            WHERE rb.id = @id;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", bookingId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<AdminRentalDetailDto>.Fail(
                StatusCodes.Status404NotFound,
                "rental_not_found",
                "That rental booking was not found.");
        }

        return ServiceResult<AdminRentalDetailDto>.Ok(new AdminRentalDetailDto(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetString(4),
            reader.GetString(5),
            reader.IsDBNull(6) ? null : reader.GetString(6),
            reader.GetString(7),
            reader.IsDBNull(8) ? null : reader.GetString(8),
            DateOnly.FromDateTime(reader.GetDateTime(9)),
            DateOnly.FromDateTime(reader.GetDateTime(10)),
            reader.GetInt32(11),
            reader.GetDecimal(12),
            reader.GetDecimal(13),
            reader.GetDecimal(14),
            reader.GetDecimal(15),
            reader.GetDecimal(16),
            reader.IsDBNull(17) ? null : reader.GetInt32(17),
            reader.GetBoolean(18),
            reader.IsDBNull(19) ? null : reader.GetString(19),
            reader.GetString(20),
            reader.IsDBNull(21) ? null : reader.GetString(21),
            reader.IsDBNull(22) ? null : reader.GetFieldValue<DateTimeOffset>(22),
            reader.IsDBNull(23) ? null : reader.GetString(23),
            reader.GetInt32(24),
            reader.GetFieldValue<DateTimeOffset>(25),
            reader.GetFieldValue<DateTimeOffset>(26),
            reader.GetBoolean(27),
            reader.GetBoolean(28),
            reader.GetBoolean(29),
            reader.GetBoolean(30)));
    }

    /// <summary>Every vehicle an owner has put up for rent, and why it is or is not listed.</summary>
    /// <remarks>
    /// The one question this table exists to answer is the support call: "my
    /// car is set to rent and it is not showing". The answer is almost always
    /// the photograph, and it is visible here in one column.
    /// </remarks>
    public async Task<ServiceResult<IReadOnlyList<AdminRentalVehicleDto>>> FleetAsync(
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT v.id, trim(concat_ws(' ', v.make, v.model)),
                   v.registration_number,
                   COALESCE(NULLIF(u.full_name, ''), 'Owner'), u.phone_number,
                   v.rent_with_driver_daily, v.rent_self_drive_daily,
                   COALESCE(v.rent_security_deposit, 0),
                   COALESCE(v.rent_minimum_days, 1),
                   NULLIF(v.image_url, '') IS NOT NULL,
                   lower(v.status) IN ('verified', 'approved'),
                   (SELECT count(*) FROM udrive.rental_bookings rb
                     WHERE rb.vehicle_id = v.id AND rb.status <> 'Cancelled')
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE COALESCE(v.available_for_rent, false) = true
            ORDER BY u.full_name, v.registration_number;
            """;

        var list = new List<AdminRentalVehicleDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var hasPhoto = reader.GetBoolean(9);
            var verified = reader.GetBoolean(10);
            var withDriver = reader.IsDBNull(5) ? (decimal?)null : reader.GetDecimal(5);
            var selfDrive = reader.IsDBNull(6) ? (decimal?)null : reader.GetDecimal(6);
            var hasRate = withDriver is > 0 || selfDrive is > 0;

            list.Add(new AdminRentalVehicleDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                withDriver,
                selfDrive,
                reader.GetDecimal(7),
                reader.GetInt32(8),
                hasPhoto,
                (int)reader.GetInt64(11),
                hasPhoto && hasRate && verified,
                // Why it is hidden, in the words a support agent can repeat
                // down the phone.
                !verified
                    ? "The vehicle is not verified yet."
                    : !hasRate
                        ? "No daily rate has been set."
                        : !hasPhoto
                            ? "No photograph of this vehicle."
                            : null));
        }

        return ServiceResult<IReadOnlyList<AdminRentalVehicleDto>>.Ok(list);
    }

    // ───────────────────────────────────────────────────────── cancelling

    /// <summary>An Admin calls a booking off, on behalf of neither side.</summary>
    /// <remarks>
    /// Recorded as <c>Admin</c>, which matters: "Owner cancelled" counts
    /// against the owner, and marking a dispute settlement that way would be a
    /// lie told by the platform about one of its own drivers.
    ///
    /// The advance always goes back. An Admin stepping in means something went
    /// wrong that neither side should pay for, and if the owner is genuinely
    /// owed something, that is a conversation — not a silent forfeiture.
    /// </remarks>
    public async Task<ServiceResult<AdminRentalDetailDto>> CancelAsync(
        Guid adminUserId,
        Guid bookingId,
        string? reason,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(reason))
        {
            return ServiceResult<AdminRentalDetailDto>.Fail(
                StatusCodes.Status400BadRequest,
                "cancel_reason_required",
                "Say why. Both sides will see this, and a cancellation with no "
                + "reason is the one every support call starts with.");
        }

        const string sql = """
            UPDATE udrive.rental_bookings
            SET status = 'Cancelled',
                cancelled_at = now(),
                cancelled_by = 'Admin',
                cancel_reason = @reason,
                updated_at = now()
            WHERE id = @id AND status IN ('Confirmed', 'HandedOver');
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("id", bookingId);
            command.Parameters.AddWithValue("reason", reason.Trim());
            if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                return ServiceResult<AdminRentalDetailDto>.Fail(
                    StatusCodes.Status409Conflict,
                    "rental_not_cancellable",
                    "That booking is already finished or cancelled.");
            }
        }

        await AuditAsync(connection, adminUserId, bookingId, reason.Trim(), cancellationToken);
        return await DetailAsync(bookingId, cancellationToken);
    }

    // ────────────────────────────────────────────────────────── settings

    public async Task<ServiceResult<AdminRentalSettingsDto>> SettingsAsync(
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        return ServiceResult<AdminRentalSettingsDto>.Ok(
            await ReadSettingsAsync(connection, cancellationToken));
    }

    /// <summary>Saves the rental settings, raising the version when the text changes.</summary>
    /// <remarks>
    /// The version moves by itself. Leaving it to the Admin means the day
    /// somebody edits the wording and forgets the number, every booking made
    /// afterwards points at a version whose text no longer exists — and the
    /// acceptance record, which is the whole point of storing a version, quietly
    /// becomes worthless.
    /// </remarks>
    public async Task<ServiceResult<AdminRentalSettingsDto>> SaveSettingsAsync(
        AdminRentalSettingsRequest request,
        CancellationToken cancellationToken)
    {
        if (request.AdvancePercent is < 0 or > 100)
        {
            return ServiceResult<AdminRentalSettingsDto>.Fail(
                StatusCodes.Status400BadRequest,
                "advance_percent_invalid",
                "The advance is a percentage between 0 and 100.");
        }

        if (request.FreeCancelHours < 0)
        {
            return ServiceResult<AdminRentalSettingsDto>.Fail(
                StatusCodes.Status400BadRequest,
                "free_cancel_hours_invalid",
                "The free-cancellation window cannot be negative.");
        }

        if (request.MaximumDeposit < 0)
        {
            return ServiceResult<AdminRentalSettingsDto>.Fail(
                StatusCodes.Status400BadRequest,
                "maximum_deposit_invalid",
                "The deposit ceiling cannot be negative. Use 0 for no limit.");
        }

        if (string.IsNullOrWhiteSpace(request.DisclaimerTextEn))
        {
            return ServiceResult<AdminRentalSettingsDto>.Fail(
                StatusCodes.Status400BadRequest,
                "disclaimer_text_required",
                "The English terms cannot be empty — a Customer has to be "
                + "agreeing to something.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var current = await ReadSettingsAsync(connection, cancellationToken);
        var textChanged =
            !string.Equals(current.DisclaimerTextEn, request.DisclaimerTextEn.Trim(), StringComparison.Ordinal)
            || !string.Equals(current.DisclaimerTextUr, (request.DisclaimerTextUr ?? string.Empty).Trim(), StringComparison.Ordinal);
        var version = textChanged ? current.DisclaimerVersion + 1 : current.DisclaimerVersion;

        await WriteAsync(connection, "rental.advance_percent", request.AdvancePercent, cancellationToken);
        await WriteAsync(connection, "rental.free_cancel_hours", request.FreeCancelHours, cancellationToken);
        await WriteAsync(connection, "rental.maximum_deposit", request.MaximumDeposit, cancellationToken);
        await WriteTextAsync(connection, "rental.disclaimer_text_en", request.DisclaimerTextEn.Trim(), cancellationToken);
        await WriteTextAsync(connection, "rental.disclaimer_text_ur", (request.DisclaimerTextUr ?? string.Empty).Trim(), cancellationToken);
        await WriteAsync(connection, "rental.disclaimer_version", version, cancellationToken);

        var saved = await ReadSettingsAsync(connection, cancellationToken);
        return ServiceResult<AdminRentalSettingsDto>.Ok(
            saved,
            textChanged
                ? $"Saved. The terms changed, so they are now version {version} — "
                  + "bookings made before this keep the version they accepted."
                : "Saved.");
    }

    // ───────────────────────────────────────────────────────── internals

    private static async Task<AdminRentalSettingsDto> ReadSettingsAsync(
        NpgsqlConnection connection,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT key, value_json #>> '{}'
            FROM udrive.system_settings
            WHERE key IN ('rental.advance_percent', 'rental.free_cancel_hours',
                          'rental.maximum_deposit', 'rental.disclaimer_version',
                          'rental.disclaimer_text_en', 'rental.disclaimer_text_ur');
            """;

        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            values[reader.GetString(0)] = reader.IsDBNull(1) ? string.Empty : reader.GetString(1);
        }

        int Number(string key, int fallback) =>
            values.TryGetValue(key, out var raw) && int.TryParse(raw, out var value)
                ? value
                : fallback;

        return new AdminRentalSettingsDto(
            Number("rental.advance_percent", RentalService.DefaultAdvancePercent),
            Number("rental.free_cancel_hours", RentalService.DefaultFreeCancelHours),
            Number("rental.maximum_deposit", 0),
            Number("rental.disclaimer_version", 1),
            values.GetValueOrDefault("rental.disclaimer_text_en", string.Empty),
            values.GetValueOrDefault("rental.disclaimer_text_ur", string.Empty));
    }

    private static Task WriteAsync(
        NpgsqlConnection connection, string key, int value, CancellationToken cancellationToken) =>
        UpsertAsync(connection, key, value.ToString(), isText: false, cancellationToken);

    private static Task WriteTextAsync(
        NpgsqlConnection connection, string key, string value, CancellationToken cancellationToken) =>
        UpsertAsync(connection, key, value, isText: true, cancellationToken);

    private static async Task UpsertAsync(
        NpgsqlConnection connection,
        string key,
        string value,
        bool isText,
        CancellationToken cancellationToken)
    {
        // Public by design: the app reads all six from the public settings
        // route, which is what lets the wording change without a release.
        var sql = $"""
            INSERT INTO udrive.system_settings
                (key, value_json, description, is_public, created_at, updated_at)
            VALUES (@key, {(isText ? "to_jsonb(@value::text)" : "to_jsonb(@value::int)")},
                    'Set from the admin portal.', true, now(), now())
            ON CONFLICT (key) DO UPDATE
            SET value_json = EXCLUDED.value_json,
                is_public = true,
                updated_at = now();
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("key", key);
        command.Parameters.Add(new NpgsqlParameter("value", NpgsqlDbType.Text) { Value = value });
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <remarks>
    /// Best-effort. A missing audit row must not undo a cancellation the
    /// Customer has already been told about.
    /// </remarks>
    private static async Task AuditAsync(
        NpgsqlConnection connection,
        Guid adminUserId,
        Guid bookingId,
        string reason,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var command = new NpgsqlCommand(
                """
                INSERT INTO udrive.audit_logs
                    (id, actor_user_id, action, entity_type, entity_id,
                     changes_json, created_at, updated_at)
                VALUES (gen_random_uuid(), @actor, 'rental.cancelled',
                        'RentalBooking', @entity, @payload::jsonb, now(), now());
                """,
                connection);
            command.Parameters.AddWithValue("actor", adminUserId);
            command.Parameters.AddWithValue("entity", bookingId.ToString());
            command.Parameters.Add(new NpgsqlParameter("payload", NpgsqlDbType.Text)
            {
                Value = System.Text.Json.JsonSerializer.Serialize(new { reason }),
            });
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (PostgresException)
        {
            // The audit table's shape differs across deployments. Losing the
            // line is survivable; losing the cancellation is not.
        }
    }

    private static void AddDate(NpgsqlCommand command, string name, DateOnly? value) =>
        command.Parameters.Add(new NpgsqlParameter(name, NpgsqlDbType.Date)
        {
            Value = (object?)value ?? DBNull.Value,
        });
}
