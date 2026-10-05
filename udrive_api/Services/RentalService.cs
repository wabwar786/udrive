using System.Data;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Domain;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Renting a Driver's own vehicle by the day.
/// </summary>
/// <remarks>
/// The platform's part in this is small and stays small. UDrive puts the two
/// people in touch, holds a booking advance so that a booking costs something to
/// break, and records what both sides agreed. It does not hold the security
/// deposit, does not inspect the car, and does not vouch for anybody's papers —
/// and the disclaimer the Customer ticks says exactly that rather than hiding it
/// in terms nobody opens.
///
/// Three things could go badly wrong here and each is guarded in the database
/// rather than in an `if`:
///
///   * the same car rented twice over the same days — an exclusion constraint,
///     with a row lock in front of it;
///   * a rental swallowing a tour departure that already has passengers — the
///     check below refuses it and says which departure and how many seats;
///   * a car out on rent still showing on the city-ride map — migration 061's
///     CHECK, which will not let rent and city both be true.
/// </remarks>
public sealed class RentalService(
    string connectionString,
    LocalFileStorageService? fileStorage = null)
{
    /// <summary>What a Customer pays at booking when no setting says.</summary>
    public const int DefaultAdvancePercent = 20;

    /// <summary>The free-cancellation window when no setting says.</summary>
    public const int DefaultFreeCancelHours = 48;

    /// <summary>How far ahead a calendar is worth drawing.</summary>
    private const int CalendarDays = 120;

    /// <remarks>
    /// A request waiting for the owner's answer holds the days as well: two
    /// customers must not both be told "waiting for the owner" for the same car
    /// on the same dates. The database's exclusion constraint says the same.
    /// </remarks>
    private static readonly string[] LiveRentalStatuses = ["PendingOwner", "Confirmed", "HandedOver"];

    private static readonly string[] ConditionSides = ["front", "back", "left", "right"];

    // ─────────────────────────────────────────────────────────── browsing

    /// <summary>Every vehicle on offer for a date range.</summary>
    /// <remarks>
    /// A photograph is required to appear here at all. Not a rule for its own
    /// sake: a rental list of names and prices is a list nobody books from, and
    /// the one picture this platform could otherwise show is a stock photograph
    /// of the model, which is a different car.
    /// </remarks>
    public async Task<ServiceResult<IReadOnlyList<RentalVehicleDto>>> SearchAsync(
        DateOnly? startDate,
        DateOnly? endDate,
        string? rentalMode,
        string? category,
        CancellationToken cancellationToken)
    {
        if (startDate is not null && endDate is not null && endDate < startDate)
        {
            return ServiceResult<IReadOnlyList<RentalVehicleDto>>.Fail(
                StatusCodes.Status400BadRequest,
                "rental_dates_invalid",
                "The return date cannot be before the pick-up date.");
        }

        const string sql = """
            SELECT v.id, trim(concat_ws(' ', v.make, v.model)), v.category,
                   v.registration_number, v.colour, v.year,
                   v.passenger_capacity, v.luggage_capacity,
                   NULLIF(v.image_url, ''),
                   v.rent_with_driver_daily, v.rent_self_drive_daily,
                   COALESCE(v.rent_security_deposit, 0),
                   COALESCE(v.rent_minimum_days, 1),
                   v.rent_km_per_day, COALESCE(v.rent_fuel_included, false),
                   v.rent_pickup_point,
                   COALESCE(NULLIF(u.full_name, ''), 'Owner'),
                   COALESCE(dp.average_rating, 0),
                   v.has_air_conditioning, v.is_four_by_four,
                   COALESCE(u.email LIKE 'demo.%@udrive.local', false)
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE COALESCE(v.available_for_rent, false) = true
              AND lower(v.status) IN ('verified', 'approved')
              AND lower(dp.verification_status) IN ('approved', 'verified')
              AND u.status = 'Approved'
              -- No photograph, no listing. See the remarks above.
              AND NULLIF(v.image_url, '') IS NOT NULL
              -- At least one rate, and the one the Customer asked for if they
              -- named it. A vehicle offered only with a driver should not come
              -- back from a self-drive search and then refuse at the last step.
              AND (
                    (@mode = '' AND (v.rent_with_driver_daily > 0
                                     OR v.rent_self_drive_daily > 0))
                 OR (@mode = 'WithDriver' AND v.rent_with_driver_daily > 0)
                 OR (@mode = 'SelfDrive' AND v.rent_self_drive_daily > 0)
                  )
              AND (@category = '' OR lower(v.category) = lower(@category))
              -- Already taken over those days, by a rental or by its own work.
              AND (@from::date IS NULL OR NOT EXISTS (
                    SELECT 1 FROM udrive.rental_bookings rb
                    WHERE rb.vehicle_id = v.id
                      AND rb.status = ANY(@liveStatuses)
                      AND daterange(rb.start_date, rb.end_date, '[]')
                          && daterange(@from::date, @to::date, '[]')))
              AND (@from::date IS NULL OR NOT EXISTS (
                    SELECT 1 FROM udrive.rental_blocked_days bd
                    WHERE bd.vehicle_id = v.id
                      AND bd.day BETWEEN @from::date AND @to::date))
              AND (@from::date IS NULL OR NOT EXISTS (
                    SELECT 1 FROM udrive.tour_packages tp
                    WHERE tp.vehicle_id = v.id
                      AND tp.status = 'Active'
                      AND daterange(
                            (tp.departure_at AT TIME ZONE 'Asia/Karachi')::date,
                            (COALESCE(tp.return_at, tp.departure_at)
                               AT TIME ZONE 'Asia/Karachi')::date, '[]')
                          && daterange(@from::date, @to::date, '[]')))
              AND (@from::date IS NULL OR NOT EXISTS (
                    SELECT 1
                    FROM udrive.bookings b
                    JOIN udrive.trip_operations o ON o.booking_id = b.id
                    WHERE b.vehicle_id = v.id
                      AND o.trip_status NOT IN ('TripCompleted', 'Cancelled', 'NoShow')
                      AND daterange(
                            (o.pickup_at AT TIME ZONE 'Asia/Karachi')::date,
                            (COALESCE(o.return_at, o.pickup_at)
                               AT TIME ZONE 'Asia/Karachi')::date, '[]')
                          && daterange(@from::date, @to::date, '[]')))
            ORDER BY COALESCE(v.rent_self_drive_daily, v.rent_with_driver_daily),
                     dp.average_rating DESC
            LIMIT 60;
            """;

        var list = new List<RentalVehicleDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("mode", NormaliseMode(rentalMode) ?? string.Empty);
        command.Parameters.AddWithValue("category", category?.Trim() ?? string.Empty);
        command.Parameters.AddWithValue("liveStatuses", LiveRentalStatuses);
        AddDate(command, "from", startDate);
        AddDate(command, "to", endDate ?? startDate);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(new RentalVehicleDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.IsDBNull(4) ? string.Empty : reader.GetString(4),
                reader.GetInt32(5),
                reader.GetInt32(6),
                reader.GetInt32(7),
                reader.IsDBNull(8) ? null : reader.GetString(8),
                reader.IsDBNull(9) ? null : reader.GetDecimal(9),
                reader.IsDBNull(10) ? null : reader.GetDecimal(10),
                reader.GetDecimal(11),
                reader.GetInt32(12),
                reader.IsDBNull(13) ? null : reader.GetInt32(13),
                reader.GetBoolean(14),
                reader.IsDBNull(15) ? null : reader.GetString(15),
                reader.GetString(16),
                reader.GetDecimal(17),
                reader.GetBoolean(18),
                reader.GetBoolean(19),
                reader.GetBoolean(20)));
        }

        return ServiceResult<IReadOnlyList<RentalVehicleDto>>.Ok(list);
    }

    /// <summary>Which days this vehicle cannot be taken, and why.</summary>
    /// <remarks>
    /// Sent to the Customer's date picker so the unavailable days are closed
    /// before they are chosen. Picking dates and only then being told "not
    /// available" is the worst version of this screen, and the only one that
    /// needs no extra query to build.
    /// </remarks>
    public async Task<ServiceResult<IReadOnlyList<RentalBlockedDayDto>>> BlockedDaysAsync(
        Guid vehicleId,
        DateOnly? from,
        CancellationToken cancellationToken)
    {
        var start = from ?? Today();
        var end = start.AddDays(CalendarDays);

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        var days = await LoadBlockedDaysAsync(
            connection, null, vehicleId, start, end, cancellationToken);
        return ServiceResult<IReadOnlyList<RentalBlockedDayDto>>.Ok(days);
    }

    // ──────────────────────────────────────────────────────────── quoting

    /// <summary>What these dates would cost, and what is needed to take them.</summary>
    public async Task<ServiceResult<RentalQuoteDto>> QuoteAsync(
        Guid? userId,
        Guid vehicleId,
        RentalQuoteRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        return await BuildQuoteAsync(
            connection, null, userId, vehicleId, request, cancellationToken);
    }

    // ───────────────────────────────────────────────────────────── booking

    /// <summary>Takes the vehicle for those days.</summary>
    /// <remarks>
    /// Everything that decides whether this is allowed is re-read inside the
    /// transaction with the vehicle row locked. The quote the Customer looked at
    /// may be minutes old, and in those minutes somebody else may have booked
    /// the same car, the owner may have changed the price, or a passenger may
    /// have bought a seat on a departure that now sits in the way.
    /// </remarks>
    public async Task<ServiceResult<RentalBookingDto>> BookAsync(
        Guid userId,
        CreateRentalBookingRequest request,
        CancellationToken cancellationToken)
    {
        if (await DemoListing.IsDemoVehicleAsync(connectionString, request.VehicleId, cancellationToken))
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict, DemoListing.ErrorCode, DemoListing.Message);
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        // A request the owner never answered still holds its days until it is
        // marked expired, so that happens before the dates are checked.
        await ExpireOverdueAsync(connection, cancellationToken);

        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.ReadCommitted, cancellationToken);

        // The lock, before anything is read. Two customers pressing Book on the
        // same car within the same second is not a hypothetical on a platform
        // with one popular vehicle in a small town.
        await using (var @lock = new NpgsqlCommand(
            "SELECT 1 FROM udrive.vehicles WHERE id = @vehicleId FOR UPDATE;",
            connection, transaction))
        {
            @lock.Parameters.AddWithValue("vehicleId", request.VehicleId);
            if (await @lock.ExecuteScalarAsync(cancellationToken) is null)
            {
                return ServiceResult<RentalBookingDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "vehicle_not_found",
                    "That vehicle was not found.");
            }
        }

        var quote = await BuildQuoteAsync(
            connection,
            transaction,
            userId,
            request.VehicleId,
            new RentalQuoteRequest(request.StartDate, request.EndDate, request.RentalMode),
            cancellationToken);
        if (!quote.Success) return ServiceResult<RentalBookingDto>.Fail(
            quote.StatusCode, quote.ErrorCode ?? "rental_unavailable", quote.Message ?? string.Empty);

        var terms = quote.Data!;

        if (terms.RequiresCustomerDocuments && !terms.CustomerDocumentsOnFile)
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "customer_documents_required",
                "Self-drive needs your CNIC, driving licence and a photograph of "
                + "yourself before the booking can be made.");
        }

        // The disclaimer is the Customer's own statement about who carries the
        // risk, so a booking that does not carry the current one is refused
        // rather than quietly stamped with it.
        if (request.AcceptedDisclaimerVersion != terms.DisclaimerVersion)
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "disclaimer_version_mismatch",
                "The rental terms have been updated. Please read them again "
                + "before booking.");
        }

        var respondBy = await OwnerRespondByAsync(
            connection, transaction, terms.StartDate, cancellationToken);

        var reference = $"RN-{DateTime.UtcNow:yyMM}-{Guid.NewGuid().ToString("N")[..6].ToUpperInvariant()}";

        const string insertSql = """
            INSERT INTO udrive.rental_bookings
                (booking_reference, vehicle_id, driver_profile_id, customer_user_id,
                 start_date, end_date, rental_mode, daily_rate, days, subtotal,
                 security_deposit, advance_amount, balance_due, km_per_day,
                 fuel_included, pickup_point, status, disclaimer_version,
                 disclaimer_accepted_at, owner_respond_by, created_at, updated_at)
            SELECT @reference, v.id, v.driver_profile_id, @customer,
                   @start, @end, @mode, @rate, @days, @subtotal,
                   @deposit, @advance, @balance, v.rent_km_per_day,
                   COALESCE(v.rent_fuel_included, false), v.rent_pickup_point,
                   'PendingOwner', @disclaimer, now(), @respondBy, now(), now()
            FROM udrive.vehicles v
            WHERE v.id = @vehicleId
            RETURNING id;
            """;

        Guid bookingId;
        try
        {
            await using var command = new NpgsqlCommand(insertSql, connection, transaction);
            command.Parameters.AddWithValue("reference", reference);
            command.Parameters.AddWithValue("vehicleId", request.VehicleId);
            command.Parameters.AddWithValue("customer", userId);
            command.Parameters.Add(new NpgsqlParameter("start", NpgsqlDbType.Date) { Value = terms.StartDate });
            command.Parameters.Add(new NpgsqlParameter("end", NpgsqlDbType.Date) { Value = terms.EndDate });
            command.Parameters.AddWithValue("mode", terms.RentalMode);
            command.Parameters.AddWithValue("rate", terms.DailyRate);
            command.Parameters.AddWithValue("days", terms.Days);
            command.Parameters.AddWithValue("subtotal", terms.Subtotal);
            command.Parameters.AddWithValue("deposit", terms.SecurityDeposit);
            command.Parameters.AddWithValue("advance", terms.AdvanceAmount);
            command.Parameters.AddWithValue("balance", terms.BalanceDue);
            command.Parameters.AddWithValue("disclaimer", terms.DisclaimerVersion);
            command.Parameters.AddWithValue("respondBy", respondBy);
            bookingId = (Guid)(await command.ExecuteScalarAsync(cancellationToken))!;
        }
        catch (PostgresException exception)
            when (exception.SqlState == PostgresErrorCodes.ExclusionViolation)
        {
            // The lock covers one application instance. This covers the rest.
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "rental_dates_taken",
                "Somebody booked this vehicle for those days a moment ago. "
                + "Please choose different dates.");
        }

        await transaction.CommitAsync(cancellationToken);

        var created = await LoadBookingAsync(connection, bookingId, userId, false, cancellationToken);
        return ServiceResult<RentalBookingDto>.Created(
            created!,
            "Request sent. The owner will confirm by "
            + $"{respondBy.ToOffset(Karachi):h:mm tt}. If they don't, your advance comes back.");
    }

    /// <summary>Calls a booking off, from either side.</summary>
    /// <remarks>
    /// The two sides are not symmetrical and should not be. A Customer who
    /// cancels inside the free window gets the advance back; inside the last
    /// two days the owner keeps it, because they turned other bookings away. An
    /// owner who cancels refunds in full whenever they do it and it counts
    /// against them — they are the one who made a promise.
    /// </remarks>
    public async Task<ServiceResult<RentalBookingDto>> CancelAsync(
        Guid userId,
        Guid bookingId,
        CancelRentalRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        const string loadSql = """
            SELECT rb.customer_user_id, dp.user_id, rb.status, rb.start_date
            FROM udrive.rental_bookings rb
            JOIN udrive.driver_profiles dp ON dp.id = rb.driver_profile_id
            WHERE rb.id = @id;
            """;

        Guid customerId;
        Guid ownerUserId;
        string status;
        DateOnly startDate;

        await using (var command = new NpgsqlCommand(loadSql, connection))
        {
            command.Parameters.AddWithValue("id", bookingId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<RentalBookingDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "rental_not_found",
                    "That rental booking was not found.");
            }

            customerId = reader.GetGuid(0);
            ownerUserId = reader.GetGuid(1);
            status = reader.GetString(2);
            startDate = DateOnly.FromDateTime(reader.GetDateTime(3));
        }

        var isCustomer = customerId == userId;
        var isOwner = ownerUserId == userId;
        if (!isCustomer && !isOwner)
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status403Forbidden,
                "not_your_rental",
                "This rental booking is not yours.");
        }

        if (status is "PendingOwner" && isOwner)
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "rental_use_respond",
                "This request is waiting for your answer. Reject it instead.");
        }

        if (status is not ("Confirmed" or "PendingOwner"))
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "rental_not_cancellable",
                status is "Cancelled" or "Declined" or "Expired"
                    ? "This booking has already been closed."
                    : "The car has already been handed over, so this booking "
                      + "cannot be cancelled here. Speak to the owner.");
        }

        const string cancelSql = """
            UPDATE udrive.rental_bookings
            SET status = 'Cancelled',
                cancelled_at = now(),
                cancelled_by = @by,
                cancel_reason = @reason,
                updated_at = now()
            WHERE id = @id AND status IN ('Confirmed', 'PendingOwner');
            """;

        await using (var command = new NpgsqlCommand(cancelSql, connection))
        {
            command.Parameters.AddWithValue("id", bookingId);
            command.Parameters.AddWithValue("by", isOwner ? "Owner" : "Customer");
            command.Parameters.Add(new NpgsqlParameter("reason", NpgsqlDbType.Varchar)
            {
                Value = string.IsNullOrWhiteSpace(request.Reason)
                    ? DBNull.Value
                    : request.Reason.Trim(),
            });
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        var freeCancelHours = await SettingAsync(
            connection, null, "rental.free_cancel_hours", DefaultFreeCancelHours, cancellationToken);
        // A request the owner had not yet accepted always refunds: the customer
        // never had a car to turn other bookings away for.
        var refunded = isOwner || status == "PendingOwner" || RefundableNow(startDate, freeCancelHours);

        var dto = await LoadBookingAsync(connection, bookingId, userId, isOwner, cancellationToken);
        return ServiceResult<RentalBookingDto>.Ok(
            dto!,
            refunded
                ? "Cancelled. The advance will be returned."
                : "Cancelled. The advance stays with the owner, because the "
                  + $"booking started within {freeCancelHours} hours.");
    }

    /// <summary>The Customer's own rentals.</summary>
    public Task<ServiceResult<IReadOnlyList<RentalBookingDto>>> MyRentalsAsync(
        Guid userId, CancellationToken cancellationToken) =>
        ListBookingsAsync(userId, false, cancellationToken);

    /// <summary>The Driver's rentals, as the owner of the vehicles.</summary>
    public Task<ServiceResult<IReadOnlyList<RentalBookingDto>>> DriverRentalsAsync(
        Guid userId, CancellationToken cancellationToken) =>
        ListBookingsAsync(userId, true, cancellationToken);

    /// <summary>Owner marks the car handed over, or returned.</summary>
    public async Task<ServiceResult<RentalBookingDto>> SetStatusAsync(
        Guid userId,
        Guid bookingId,
        string status,
        CancellationToken cancellationToken)
    {
        var target = status?.Trim() switch
        {
            "HandedOver" => "HandedOver",
            "Returned" => "Returned",
            "NoShow" => "NoShow",
            _ => null,
        };

        if (target is null)
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status400BadRequest,
                "rental_status_invalid",
                "A rental can be marked handed over, returned, or a no-show.");
        }

        const string sql = """
            UPDATE udrive.rental_bookings rb
            SET status = @target, updated_at = now()
            FROM udrive.driver_profiles dp
            WHERE rb.id = @id
              AND rb.driver_profile_id = dp.id
              AND dp.user_id = @userId
              AND rb.status IN ('Confirmed', 'HandedOver');
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("id", bookingId);
            command.Parameters.AddWithValue("userId", userId);
            command.Parameters.AddWithValue("target", target);
            if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                return ServiceResult<RentalBookingDto>.Fail(
                    StatusCodes.Status409Conflict,
                    "rental_not_updatable",
                    "This rental is not yours, or it is already finished.");
            }
        }

        var dto = await LoadBookingAsync(connection, bookingId, userId, true, cancellationToken);
        return ServiceResult<RentalBookingDto>.Ok(dto!);
    }

    /// <summary>
    /// Where one of the Customer's documents is stored, for the owner of this
    /// booking and nobody else.
    /// </summary>
    /// <remarks>
    /// The whole entitlement is one statement, on purpose. Three things have to
    /// hold at once — the caller owns the vehicle, the rental is self-drive, and
    /// the rental is still live — and writing them as three separate checks is
    /// how one of them eventually gets dropped. A finished or cancelled rental
    /// stops being a reason to hold somebody's CNIC on screen.
    ///
    /// Returns null for every failure, including "no such booking", so the
    /// route cannot be used to find out whose bookings exist.
    /// </remarks>
    public async Task<string?> CustomerDocumentUrlAsync(
        Guid ownerUserId,
        Guid bookingId,
        string kind,
        CancellationToken cancellationToken)
    {
        var column = DocumentColumn(kind);
        if (column is null) return null;

        var sql = $"""
            SELECT cp.{column}
            FROM udrive.rental_bookings rb
            JOIN udrive.driver_profiles dp ON dp.id = rb.driver_profile_id
            JOIN udrive.customer_profiles cp ON cp.user_id = rb.customer_user_id
            WHERE rb.id = @bookingId
              AND dp.user_id = @ownerUserId
              AND rb.rental_mode = 'SelfDrive'
              AND rb.status IN ('PendingOwner', 'Confirmed', 'HandedOver');
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("bookingId", bookingId);
        command.Parameters.AddWithValue("ownerUserId", ownerUserId);
        return await command.ExecuteScalarAsync(cancellationToken) as string;
    }

    /// <remarks>
    /// A fixed map, never the caller's string: a column name cannot be a
    /// parameter, so the only safe shape is one where no caller-supplied text
    /// reaches the statement.
    /// </remarks>
    private static string? DocumentColumn(string? kind) =>
        kind?.Trim().ToLowerInvariant() switch
        {
            "cnic-front" => "cnic_front_url",
            "cnic-back" => "cnic_back_url",
            "driving-licence" => "driving_licence_url",
            "selfie" => "selfie_url",
            _ => null,
        };

    // ─────────────────────────────────────────── the owner's answer

    /// <summary>A WhatsApp message for the owner about one new request.</summary>
    public sealed record OwnerNotice(string To, string Message);

    /// <summary>When the owner must answer a request starting on that day.</summary>
    /// <remarks>
    /// Two hours normally; half an hour when the car is wanted within a few
    /// hours, so a same-day customer is not left waiting for most of the day.
    /// Never later than the start of the rental day itself.
    /// </remarks>
    private static async Task<DateTimeOffset> OwnerRespondByAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        DateOnly startDate,
        CancellationToken cancellationToken)
    {
        var normal = await SettingAsync(connection, transaction, "rental.owner_response_minutes", 120, cancellationToken);
        var shortWindow = await SettingAsync(connection, transaction, "rental.owner_response_short_minutes", 30, cancellationToken);
        var shortNotice = await SettingAsync(connection, transaction, "rental.short_notice_hours", 6, cancellationToken);

        var now = DateTimeOffset.UtcNow;
        var startsAt = new DateTimeOffset(startDate.ToDateTime(new TimeOnly(9, 0)), Karachi);
        var minutes = startsAt - now <= TimeSpan.FromHours(shortNotice) ? shortWindow : normal;
        return now.AddMinutes(Math.Max(5, minutes));
    }

    /// <summary>
    /// Closes every request the owner did not answer in time, and tells each
    /// customer their advance is coming back.
    /// </summary>
    /// <remarks>
    /// Called before anything reads or books rentals, and by the sweep every few
    /// minutes. One statement, so two callers at once cannot both notify.
    /// </remarks>
    internal static async Task<int> ExpireOverdueAsync(
        NpgsqlConnection connection,
        CancellationToken cancellationToken)
    {
        const string sql = """
            WITH expired AS (
                UPDATE udrive.rental_bookings
                SET status = 'Expired',
                    cancelled_at = now(),
                    cancelled_by = 'System',
                    cancel_reason = 'The owner did not answer in time.',
                    updated_at = now()
                WHERE status = 'PendingOwner'
                  AND owner_respond_by IS NOT NULL
                  AND owner_respond_by < now()
                RETURNING id, customer_user_id, booking_reference
            )
            INSERT INTO udrive.notifications
                (id, user_id, type, title, body, data_json, action_path, created_at, updated_at)
            SELECT gen_random_uuid(), e.customer_user_id, 'RentalExpired',
                   'The owner did not answer',
                   'Your rental request ' || e.booking_reference
                     || ' was not confirmed in time. Your advance will be returned. Please choose another car.',
                   jsonb_build_object('rentalBookingId', e.id), '/rentals', now(), now()
            FROM expired e;
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        return await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>The message telling the owner a new request is waiting.</summary>
    public async Task<OwnerNotice?> OwnerNoticeAsync(Guid bookingId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        return await NoticeAsync(connection, bookingId, false, cancellationToken);
    }

    /// <summary>Notes that the owner was told, so the sweep does not tell them again.</summary>
    public async Task RecordOwnerNoticeAsync(Guid bookingId, bool reminder, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            reminder
                ? "UPDATE udrive.rental_bookings SET owner_reminded_at = now() WHERE id = @id;"
                : "UPDATE udrive.rental_bookings SET owner_notified_at = now() WHERE id = @id;",
            connection);
        command.Parameters.AddWithValue("id", bookingId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>
    /// Requests whose answer is due within half an hour and whose owner has not
    /// been reminded yet.
    /// </summary>
    public async Task<IReadOnlyList<(Guid BookingId, OwnerNotice Notice)>> DueRemindersAsync(
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var ids = new List<Guid>();
        await using (var command = new NpgsqlCommand(
            """
            SELECT id FROM udrive.rental_bookings
            WHERE status = 'PendingOwner'
              AND owner_reminded_at IS NULL
              AND owner_respond_by > now()
              AND owner_respond_by <= now() + interval '30 minutes'
              -- A request made with only half an hour to answer has just had its
              -- first message; a reminder five minutes later is noise.
              AND created_at <= now() - interval '10 minutes'
            ORDER BY owner_respond_by
            LIMIT 50;
            """,
            connection))
        {
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken)) ids.Add(reader.GetGuid(0));
        }

        var list = new List<(Guid, OwnerNotice)>();
        foreach (var id in ids)
        {
            var notice = await NoticeAsync(connection, id, true, cancellationToken);
            if (notice is not null) list.Add((id, notice));
        }

        return list;
    }

    private static async Task<OwnerNotice?> NoticeAsync(
        NpgsqlConnection connection,
        Guid bookingId,
        bool reminder,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT owner_u.phone_number,
                   trim(concat_ws(' ', v.make, v.model)), v.registration_number,
                   rb.start_date, rb.end_date, rb.days, rb.rental_mode,
                   rb.subtotal, rb.advance_amount, rb.owner_respond_by, rb.booking_reference
            FROM udrive.rental_bookings rb
            JOIN udrive.vehicles v ON v.id = rb.vehicle_id
            JOIN udrive.driver_profiles dp ON dp.id = rb.driver_profile_id
            JOIN udrive.users owner_u ON owner_u.id = dp.user_id
            WHERE rb.id = @id AND rb.status = 'PendingOwner';
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", bookingId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken) || reader.IsDBNull(0)) return null;

        var phone = reader.GetString(0);
        var car = reader.GetString(1);
        var plate = reader.GetString(2);
        var start = DateOnly.FromDateTime(reader.GetDateTime(3));
        var end = DateOnly.FromDateTime(reader.GetDateTime(4));
        var days = reader.GetInt32(5);
        var mode = reader.GetString(6) == "SelfDrive" ? "Self-drive" : "With driver";
        var total = reader.GetDecimal(7);
        var advance = reader.GetDecimal(8);
        var respondBy = reader.IsDBNull(9) ? (DateTimeOffset?)null : reader.GetFieldValue<DateTimeOffset>(9);
        var reference = reader.GetString(10);
        var by = respondBy is null ? "soon" : respondBy.Value.ToOffset(Karachi).ToString("h:mm tt");

        var message = reminder
            ? $"UDrive reminder: the rental request {reference} for your {car} ({plate}) "
              + $"is still waiting. Please answer by {by}, or it will be cancelled and the customer refunded.\n"
              + "Open the UDrive app → My vehicles → Rent."
            : $"UDrive: new rental request {reference}\n"
              + $"Car: {car} ({plate})\n"
              + $"Dates: {start:dd MMM} – {end:dd MMM} ({days} day{(days == 1 ? "" : "s")})\n"
              + $"Type: {mode}\n"
              + $"Total: Rs {total:N0} · advance paid: Rs {advance:N0}\n"
              + $"Please confirm or reject by {by}.\n"
              + "Open the UDrive app → My vehicles → Rent.";
        return new OwnerNotice(phone, message);
    }

    /// <summary>The owner confirms or rejects a waiting request.</summary>
    /// <remarks>
    /// A with-driver rental names who drives on accept: one of the owner's
    /// approved drivers whose licence is valid to the last day. An owner who
    /// signed up as a UDrive driver is that driver and need not name anyone.
    /// </remarks>
    public async Task<ServiceResult<RentalBookingDto>> RespondAsync(
        Guid userId,
        Guid bookingId,
        RespondRentalRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await ExpireOverdueAsync(connection, cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.ReadCommitted, cancellationToken);

        const string loadSql = """
            SELECT dp.id, rb.status, rb.rental_mode, rb.end_date,
                   COALESCE(dp.profile_kind, 'Driver'), rb.customer_user_id, rb.booking_reference
            FROM udrive.rental_bookings rb
            JOIN udrive.driver_profiles dp ON dp.id = rb.driver_profile_id
            WHERE rb.id = @id AND dp.user_id = @userId
            FOR UPDATE OF rb;
            """;

        Guid profileId;
        string status;
        string mode;
        DateOnly endDate;
        string profileKind;
        Guid customerId;
        string reference;
        await using (var command = new NpgsqlCommand(loadSql, connection, transaction))
        {
            command.Parameters.AddWithValue("id", bookingId);
            command.Parameters.AddWithValue("userId", userId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<RentalBookingDto>.Fail(
                    StatusCodes.Status404NotFound, "rental_not_found", "That rental booking was not found.");
            }

            profileId = reader.GetGuid(0);
            status = reader.GetString(1);
            mode = reader.GetString(2);
            endDate = DateOnly.FromDateTime(reader.GetDateTime(3));
            profileKind = reader.GetString(4);
            customerId = reader.GetGuid(5);
            reference = reader.GetString(6);
        }

        if (status != "PendingOwner")
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "rental_not_pending",
                status == "Expired"
                    ? "The time to answer this request has passed. The customer has been refunded."
                    : "This request has already been answered.");
        }

        Guid? fleetDriverId = null;
        if (request.Accept && mode == "WithDriver")
        {
            if (request.FleetDriverId is { } chosen)
            {
                if (!await ListingService.IsValidDriverAsync(
                        connection, transaction, profileId, chosen, endDate, cancellationToken))
                {
                    return ServiceResult<RentalBookingDto>.Fail(
                        StatusCodes.Status409Conflict,
                        "driver_not_valid",
                        "That driver is not approved, or their licence ends before this rental does.");
                }

                fleetDriverId = chosen;
            }
            else if (profileKind != "Driver")
            {
                return ServiceResult<RentalBookingDto>.Fail(
                    StatusCodes.Status400BadRequest,
                    "driver_required",
                    "Choose who will drive this customer.");
            }
        }

        const string acceptSql = """
            UPDATE udrive.rental_bookings
            SET status = 'Confirmed', owner_responded_at = now(),
                fleet_driver_id = @driver, updated_at = now()
            WHERE id = @id AND status = 'PendingOwner';
            """;
        const string declineSql = """
            UPDATE udrive.rental_bookings
            SET status = 'Declined', owner_responded_at = now(),
                cancelled_at = now(), cancelled_by = 'Owner',
                cancel_reason = @reason, updated_at = now()
            WHERE id = @id AND status = 'PendingOwner';
            """;

        await using (var command = new NpgsqlCommand(request.Accept ? acceptSql : declineSql, connection, transaction))
        {
            command.Parameters.AddWithValue("id", bookingId);
            if (request.Accept)
            {
                command.Parameters.Add(new NpgsqlParameter("driver", NpgsqlDbType.Uuid)
                {
                    Value = (object?)fleetDriverId ?? DBNull.Value,
                });
            }
            else
            {
                var reason = request.Reason?.Trim();
                command.Parameters.Add(new NpgsqlParameter("reason", NpgsqlDbType.Varchar)
                {
                    Value = string.IsNullOrEmpty(reason)
                        ? "The owner could not take this booking."
                        : reason.Length > 500 ? reason[..500] : reason,
                });
            }

            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var notify = new NpgsqlCommand(
            """
            INSERT INTO udrive.notifications
                (id, user_id, type, title, body, data_json, action_path, created_at, updated_at)
            VALUES (gen_random_uuid(), @customer, @type, @title, @body,
                    jsonb_build_object('rentalBookingId', @id), '/rentals', now(), now());
            """,
            connection, transaction))
        {
            notify.Parameters.AddWithValue("customer", customerId);
            notify.Parameters.AddWithValue("id", bookingId);
            notify.Parameters.AddWithValue("type", request.Accept ? "RentalConfirmed" : "RentalDeclined");
            notify.Parameters.AddWithValue("title", request.Accept ? "Your car is confirmed" : "The owner could not take your booking");
            notify.Parameters.AddWithValue("body", request.Accept
                ? $"Rental {reference} is confirmed. The owner's number is now in your booking."
                : $"Rental {reference} was not accepted. Your advance will be returned. Please choose another car.");
            await notify.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        var dto = await LoadBookingAsync(connection, bookingId, userId, true, cancellationToken);
        return ServiceResult<RentalBookingDto>.Ok(
            dto!,
            request.Accept ? "Confirmed. The customer has been told." : "Rejected. The customer's advance will be returned.");
    }

    // ─────────────────────────────────────────── handover and return

    /// <summary>One condition photo, before the car goes out or when it comes back.</summary>
    public async Task<ServiceResult<RentalConditionPhotoDto>> UploadConditionPhotoAsync(
        Guid userId,
        Guid bookingId,
        string phase,
        string side,
        IFormFile? file,
        CancellationToken cancellationToken)
    {
        var cleanPhase = phase?.Trim().ToLowerInvariant();
        var cleanSide = side?.Trim().ToLowerInvariant();
        var column = cleanPhase switch { "handover" => "handover_json", "return" => "return_json", _ => null };
        if (column is null || cleanSide is null || !ConditionSides.Contains(cleanSide))
        {
            return ServiceResult<RentalConditionPhotoDto>.Fail(
                StatusCodes.Status400BadRequest, "photo_kind_invalid", "Unknown photo.");
        }

        if (file is null)
        {
            return ServiceResult<RentalConditionPhotoDto>.Fail(
                StatusCodes.Status400BadRequest, "file_required", "Choose a photo.");
        }

        if (fileStorage is null)
        {
            return ServiceResult<RentalConditionPhotoDto>.Fail(
                StatusCodes.Status503ServiceUnavailable, "storage_unavailable", "Photos cannot be saved right now.");
        }

        var needed = cleanPhase == "handover" ? "Confirmed" : "HandedOver";
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        if (!await OwnsBookingInAsync(connection, userId, bookingId, needed, cancellationToken))
        {
            return ServiceResult<RentalConditionPhotoDto>.Fail(
                StatusCodes.Status409Conflict,
                "rental_not_updatable",
                cleanPhase == "handover"
                    ? "Photos for handover can be added once the booking is confirmed."
                    : "Return photos can be added once the car has been handed over.");
        }

        string url;
        try
        {
            var stored = await fileStorage.SaveAsync(file, "vehicle-images", bookingId, cancellationToken);
            var segments = stored.RelativeUrl.Split('/', StringSplitOptions.RemoveEmptyEntries);
            url = segments.Length >= 2
                ? $"/api/v1/vehicle-images/{segments[^2]}/{segments[^1]}"
                : stored.RelativeUrl;
        }
        catch (InvalidDataException error)
        {
            return ServiceResult<RentalConditionPhotoDto>.Fail(StatusCodes.Status400BadRequest, "file_invalid", error.Message);
        }
        catch (InvalidOperationException error)
        {
            return ServiceResult<RentalConditionPhotoDto>.Fail(StatusCodes.Status503ServiceUnavailable, "storage_unavailable", error.Message);
        }

        // The column name comes from the fixed map above, never the caller.
        var sql = $"""
            UPDATE udrive.rental_bookings
            SET {column} = COALESCE({column}, '{"{}"}'::jsonb)
                    || jsonb_build_object('photos',
                         COALESCE({column} -> 'photos', '{"{}"}'::jsonb)
                         || jsonb_build_object(CAST(@side AS text), CAST(@url AS text))),
                updated_at = now()
            WHERE id = @id;
            """;
        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("id", bookingId);
            command.Parameters.AddWithValue("side", cleanSide);
            command.Parameters.AddWithValue("url", url);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        return ServiceResult<RentalConditionPhotoDto>.Ok(new RentalConditionPhotoDto(cleanPhase!, cleanSide, url));
    }

    /// <summary>The car goes out: four photos, the meter, the tank, and the checks.</summary>
    public async Task<ServiceResult<RentalBookingDto>> HandOverAsync(
        Guid userId,
        Guid bookingId,
        RentalHandoverRequest request,
        CancellationToken cancellationToken)
    {
        var fuel = NormaliseFuel(request.Fuel);
        if (fuel is null || request.OdometerKm <= 0 || request.OdometerKm > 3_000_000)
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status400BadRequest, "meter_invalid", "Enter the odometer reading and the fuel level.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var state = await ConditionStateAsync(connection, userId, bookingId, "handover_json", cancellationToken);
        if (state is null || state.Value.Status != "Confirmed")
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict, "rental_not_updatable",
                "Only a confirmed booking can be handed over.");
        }

        if (state.Value.Photos < 4)
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict, "handover_photos_missing",
                "Take all four photos of the car first.");
        }

        var selfDrive = state.Value.Mode == "SelfDrive";
        if (!request.IdentityChecked)
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict, "identity_not_checked",
                "Check the customer's CNIC against the person in front of you.");
        }

        if (selfDrive && !request.LicenceSeen)
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict, "licence_not_seen",
                "Self-drive: see the customer's original driving licence first.");
        }

        if (selfDrive && state.Value.Deposit > 0 && !request.DepositReceived)
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict, "deposit_not_received",
                "Take the security deposit before handing over the keys.");
        }

        const string sql = """
            UPDATE udrive.rental_bookings
            SET handover_json = COALESCE(handover_json, '{}'::jsonb) || jsonb_build_object(
                    'odometerKm', @km, 'fuel', CAST(@fuel AS text), 'at', to_jsonb(now()),
                    'identityChecked', @identity, 'licenceSeen', @licence, 'depositReceived', @deposit),
                status = 'HandedOver', handed_over_at = now(), updated_at = now()
            WHERE id = @id AND status = 'Confirmed';
            """;
        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("id", bookingId);
            command.Parameters.AddWithValue("km", request.OdometerKm);
            command.Parameters.AddWithValue("fuel", fuel);
            command.Parameters.AddWithValue("identity", request.IdentityChecked);
            command.Parameters.AddWithValue("licence", selfDrive && request.LicenceSeen);
            command.Parameters.AddWithValue("deposit", selfDrive && request.DepositReceived);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        var dto = await LoadBookingAsync(connection, bookingId, userId, true, cancellationToken);
        return ServiceResult<RentalBookingDto>.Ok(dto!, "Handed over. Have a good trip.");
    }

    /// <summary>The car is back: four photos, the meter and the tank.</summary>
    public async Task<ServiceResult<RentalBookingDto>> ReturnAsync(
        Guid userId,
        Guid bookingId,
        RentalReturnRequest request,
        CancellationToken cancellationToken)
    {
        var fuel = NormaliseFuel(request.Fuel);
        if (fuel is null || request.OdometerKm <= 0)
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status400BadRequest, "meter_invalid", "Enter the odometer reading and the fuel level.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var state = await ConditionStateAsync(connection, userId, bookingId, "return_json", cancellationToken);
        if (state is null || state.Value.Status != "HandedOver")
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict, "rental_not_updatable",
                "Only a car that was handed over can be returned.");
        }

        if (state.Value.Photos < 4)
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict, "return_photos_missing",
                "Take all four photos of the car first.");
        }

        if (state.Value.HandoverKm is { } outKm && request.OdometerKm < outKm)
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status400BadRequest, "odometer_below_handover",
                $"The reading cannot be less than at handover ({outKm:N0} km).");
        }

        const string sql = """
            UPDATE udrive.rental_bookings
            SET return_json = COALESCE(return_json, '{}'::jsonb) || jsonb_build_object(
                    'odometerKm', @km, 'fuel', CAST(@fuel AS text), 'at', to_jsonb(now())),
                status = 'Returned', returned_at = now(), updated_at = now()
            WHERE id = @id AND status = 'HandedOver';
            """;
        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("id", bookingId);
            command.Parameters.AddWithValue("km", request.OdometerKm);
            command.Parameters.AddWithValue("fuel", fuel);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        var dto = await LoadBookingAsync(connection, bookingId, userId, true, cancellationToken);
        return ServiceResult<RentalBookingDto>.Ok(dto!, "Returned. Booking complete.");
    }

    private static async Task<bool> OwnsBookingInAsync(
        NpgsqlConnection connection, Guid userId, Guid bookingId, string status, CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT EXISTS (
                SELECT 1 FROM udrive.rental_bookings rb
                JOIN udrive.driver_profiles dp ON dp.id = rb.driver_profile_id
                WHERE rb.id = @id AND dp.user_id = @userId AND rb.status = @status);
            """,
            connection);
        command.Parameters.AddWithValue("id", bookingId);
        command.Parameters.AddWithValue("userId", userId);
        command.Parameters.AddWithValue("status", status);
        return await command.ExecuteScalarAsync(cancellationToken) is true;
    }

    private readonly record struct ConditionState(
        string Status, string Mode, decimal Deposit, int Photos, int? HandoverKm);

    private static async Task<ConditionState?> ConditionStateAsync(
        NpgsqlConnection connection, Guid userId, Guid bookingId, string column, CancellationToken cancellationToken)
    {
        // column is one of two fixed names chosen by the caller in this file.
        var sql = $"""
            SELECT rb.status, rb.rental_mode, rb.security_deposit,
                   (SELECT count(*)::int FROM jsonb_each_text(COALESCE(rb.{column} -> 'photos', '{"{}"}'::jsonb)) p
                     WHERE p.key IN ('front', 'back', 'left', 'right') AND p.value <> ''),
                   (rb.handover_json ->> 'odometerKm')::int
            FROM udrive.rental_bookings rb
            JOIN udrive.driver_profiles dp ON dp.id = rb.driver_profile_id
            WHERE rb.id = @id AND dp.user_id = @userId;
            """;
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", bookingId);
        command.Parameters.AddWithValue("userId", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return null;
        return new ConditionState(
            reader.GetString(0),
            reader.GetString(1),
            reader.GetDecimal(2),
            reader.GetInt32(3),
            reader.IsDBNull(4) ? null : reader.GetInt32(4));
    }

    private static string? NormaliseFuel(string? fuel) => fuel?.Trim().ToLowerInvariant() switch
    {
        "quarter" or "1/4" => "Quarter",
        "half" or "1/2" => "Half",
        "threequarters" or "three_quarters" or "3/4" => "ThreeQuarters",
        "full" => "Full",
        _ => null,
    };

    // ───────────────────────────────────────────────────────── internals

    private async Task<ServiceResult<RentalQuoteDto>> BuildQuoteAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        Guid? userId,
        Guid vehicleId,
        RentalQuoteRequest request,
        CancellationToken cancellationToken)
    {
        var mode = NormaliseMode(request.RentalMode);
        if (mode is null)
        {
            return ServiceResult<RentalQuoteDto>.Fail(
                StatusCodes.Status400BadRequest,
                "rental_mode_invalid",
                "Choose either with a driver, or self-drive.");
        }

        if (request.EndDate < request.StartDate)
        {
            return ServiceResult<RentalQuoteDto>.Fail(
                StatusCodes.Status400BadRequest,
                "rental_dates_invalid",
                "The return date cannot be before the pick-up date.");
        }

        if (request.StartDate < Today())
        {
            return ServiceResult<RentalQuoteDto>.Fail(
                StatusCodes.Status400BadRequest,
                "rental_dates_past",
                "A rental cannot start in the past.");
        }

        const string sql = """
            SELECT COALESCE(v.available_for_rent, false),
                   v.rent_with_driver_daily, v.rent_self_drive_daily,
                   COALESCE(v.rent_security_deposit, 0),
                   COALESCE(v.rent_minimum_days, 1),
                   v.rent_km_per_day, COALESCE(v.rent_fuel_included, false),
                   lower(v.status)
            FROM udrive.vehicles v
            WHERE v.id = @vehicleId;
            """;

        bool availableForRent;
        decimal? withDriver;
        decimal? selfDrive;
        decimal deposit;
        int minimumDays;
        int? kmPerDay;
        bool fuelIncluded;
        string vehicleStatus;

        await using (var command = Command(sql, connection, transaction))
        {
            command.Parameters.AddWithValue("vehicleId", vehicleId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<RentalQuoteDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "vehicle_not_found",
                    "That vehicle was not found.");
            }

            availableForRent = reader.GetBoolean(0);
            withDriver = reader.IsDBNull(1) ? null : reader.GetDecimal(1);
            selfDrive = reader.IsDBNull(2) ? null : reader.GetDecimal(2);
            deposit = reader.GetDecimal(3);
            minimumDays = reader.GetInt32(4);
            kmPerDay = reader.IsDBNull(5) ? null : reader.GetInt32(5);
            fuelIncluded = reader.GetBoolean(6);
            vehicleStatus = reader.GetString(7);
        }

        if (!availableForRent || vehicleStatus is not ("verified" or "approved"))
        {
            return ServiceResult<RentalQuoteDto>.Fail(
                StatusCodes.Status409Conflict,
                "vehicle_not_for_rent",
                "This vehicle is not being offered for rent.");
        }

        var dailyRate = mode == "SelfDrive" ? selfDrive : withDriver;
        if (dailyRate is not > 0)
        {
            return ServiceResult<RentalQuoteDto>.Fail(
                StatusCodes.Status409Conflict,
                "rental_mode_not_offered",
                mode == "SelfDrive"
                    ? "The owner does not offer this vehicle for self-drive."
                    : "The owner does not offer this vehicle with a driver.");
        }

        var days = request.EndDate.DayNumber - request.StartDate.DayNumber + 1;
        if (days < minimumDays)
        {
            return ServiceResult<RentalQuoteDto>.Fail(
                StatusCodes.Status409Conflict,
                "rental_below_minimum_days",
                $"The owner rents this vehicle for at least {minimumDays} "
                + (minimumDays == 1 ? "day." : "days."));
        }

        // A tour departure with passengers on it outranks a rental, and the
        // refusal says which one and how many seats. "Not available" on its own
        // sends a Driver looking for a fault in the app.
        var clash = await PackageClashAsync(
            connection, transaction, vehicleId, request.StartDate, request.EndDate, cancellationToken);
        if (clash is not null)
        {
            return ServiceResult<RentalQuoteDto>.Fail(
                StatusCodes.Status409Conflict,
                "rental_clashes_with_package",
                clash);
        }

        var blocked = await LoadBlockedDaysAsync(
            connection, transaction, vehicleId, request.StartDate, request.EndDate, cancellationToken);
        if (blocked.Count > 0)
        {
            return ServiceResult<RentalQuoteDto>.Fail(
                StatusCodes.Status409Conflict,
                "rental_dates_taken",
                $"This vehicle is already taken on {blocked[0].Date:dd MMM}"
                + (blocked.Count > 1 ? $" and {blocked.Count - 1} other day(s)." : "."));
        }

        var advancePercent = await SettingAsync(
            connection, transaction, "rental.advance_percent", DefaultAdvancePercent, cancellationToken);
        var disclaimerVersion = await SettingAsync(
            connection, transaction, "rental.disclaimer_version", 1, cancellationToken);

        var subtotal = decimal.Round(dailyRate.Value * days, 2);
        var advance = decimal.Round(subtotal * Math.Clamp(advancePercent, 0, 100) / 100m, 0);
        var balance = subtotal - advance;

        var documentsOnFile = mode != "SelfDrive"
            || (userId is not null
                && await HasDocumentsAsync(connection, transaction, userId.Value, cancellationToken));

        return ServiceResult<RentalQuoteDto>.Ok(new RentalQuoteDto(
            vehicleId,
            request.StartDate,
            request.EndDate,
            mode,
            days,
            dailyRate.Value,
            subtotal,
            deposit,
            advance,
            balance,
            kmPerDay is null ? null : kmPerDay * days,
            fuelIncluded,
            disclaimerVersion,
            mode == "SelfDrive",
            documentsOnFile));
    }

    /// <summary>
    /// Every day in the window the vehicle is already spoken for, and by what.
    /// </summary>
    /// <remarks>
    /// Four sources in one query: another rental, the turnaround after it, a
    /// tour departure, and an ordinary trip. Built as whole days because a
    /// rental is agreed in whole days — a car that is out at four in the
    /// afternoon is out that day.
    ///
    /// The turnaround only takes a day when an Admin has set
    /// <c>fleet.turnaround_minutes</c> to a full day or more. At its default of
    /// an hour it costs nothing, because handing one Customer's car back and
    /// another Customer's car out on the same day is ordinary.
    /// </remarks>
    private async Task<IReadOnlyList<RentalBlockedDayDto>> LoadBlockedDaysAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        Guid vehicleId,
        DateOnly from,
        DateOnly to,
        CancellationToken cancellationToken)
    {
        var timing = await FleetTiming.LoadAsync(connection, transaction, cancellationToken);
        var turnaroundDays = timing.TurnaroundMinutes / 1440;

        const string sql = """
            WITH calendar AS (
                SELECT generate_series(@from::date, @to::date, interval '1 day')::date AS day
            ),
            rented AS (
                SELECT rb.start_date, rb.end_date
                FROM udrive.rental_bookings rb
                WHERE rb.vehicle_id = @vehicleId
                  AND rb.status = ANY(@liveStatuses)
            ),
            toured AS (
                SELECT (tp.departure_at AT TIME ZONE 'Asia/Karachi')::date AS start_date,
                       (COALESCE(tp.return_at, tp.departure_at)
                          AT TIME ZONE 'Asia/Karachi')::date AS end_date
                FROM udrive.tour_packages tp
                WHERE tp.vehicle_id = @vehicleId
                  AND tp.status = 'Active'
            ),
            tripped AS (
                SELECT (o.pickup_at AT TIME ZONE 'Asia/Karachi')::date AS start_date,
                       (COALESCE(o.return_at, o.pickup_at)
                          AT TIME ZONE 'Asia/Karachi')::date AS end_date
                FROM udrive.bookings b
                JOIN udrive.trip_operations o ON o.booking_id = b.id
                WHERE b.vehicle_id = @vehicleId
                  AND o.trip_status NOT IN ('TripCompleted', 'Cancelled', 'NoShow')
            ),
            owner_blocked AS (
                SELECT bd.day
                FROM udrive.rental_blocked_days bd
                WHERE bd.vehicle_id = @vehicleId
                  AND bd.day BETWEEN @from::date AND @to::date
            )
            SELECT w.day,
                   CASE
                     WHEN EXISTS (SELECT 1 FROM rented r
                                   WHERE w.day BETWEEN r.start_date AND r.end_date)
                       THEN 'rented'
                     WHEN EXISTS (SELECT 1 FROM rented r
                                   WHERE w.day > r.end_date
                                     AND w.day <= r.end_date + @turnaroundDays)
                       THEN 'turnaround'
                     WHEN EXISTS (SELECT 1 FROM toured t
                                   WHERE w.day BETWEEN t.start_date AND t.end_date)
                       THEN 'tour'
                     WHEN EXISTS (SELECT 1 FROM owner_blocked ob WHERE ob.day = w.day)
                       THEN 'blocked'
                     ELSE 'trip'
                   END AS reason
            FROM calendar w
            WHERE EXISTS (SELECT 1 FROM rented r
                           WHERE w.day BETWEEN r.start_date AND r.end_date + @turnaroundDays)
               OR EXISTS (SELECT 1 FROM toured t
                           WHERE w.day BETWEEN t.start_date AND t.end_date)
               OR EXISTS (SELECT 1 FROM tripped p
                           WHERE w.day BETWEEN p.start_date AND p.end_date)
               OR EXISTS (SELECT 1 FROM owner_blocked ob WHERE ob.day = w.day)
            ORDER BY w.day;
            """;

        var list = new List<RentalBlockedDayDto>();
        await using var command = Command(sql, connection, transaction);
        command.Parameters.AddWithValue("vehicleId", vehicleId);
        command.Parameters.AddWithValue("liveStatuses", LiveRentalStatuses);
        command.Parameters.AddWithValue("turnaroundDays", turnaroundDays);
        command.Parameters.Add(new NpgsqlParameter("from", NpgsqlDbType.Date) { Value = from });
        command.Parameters.Add(new NpgsqlParameter("to", NpgsqlDbType.Date) { Value = to });

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(new RentalBlockedDayDto(
                DateOnly.FromDateTime(reader.GetDateTime(0)),
                reader.GetString(1)));
        }

        return list;
    }

    /// <summary>
    /// A sentence naming the tour departure in the way, or null when none is.
    /// </summary>
    /// <remarks>
    /// Only departures that have sold seats refuse a rental. A departure nobody
    /// has booked is a plan, and a plan should not cost the Driver a paying
    /// rental — it simply stops being offered while the car is away.
    /// </remarks>
    private async Task<string?> PackageClashAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        Guid vehicleId,
        DateOnly from,
        DateOnly to,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT tp.title,
                   (tp.departure_at AT TIME ZONE 'Asia/Karachi')::date,
                   COALESCE(SUM(b.seats_booked), 0)::int
            FROM udrive.tour_packages tp
            JOIN udrive.bookings b ON b.tour_package_id = tp.id
                 AND b.status NOT IN ('Cancelled', 'NoShow', 'Draft')
            WHERE tp.vehicle_id = @vehicleId
              AND tp.status = 'Active'
              AND daterange(
                    (tp.departure_at AT TIME ZONE 'Asia/Karachi')::date,
                    (COALESCE(tp.return_at, tp.departure_at)
                       AT TIME ZONE 'Asia/Karachi')::date, '[]')
                  && daterange(@from::date, @to::date, '[]')
            GROUP BY tp.id, tp.title, tp.departure_at
            HAVING COALESCE(SUM(b.seats_booked), 0) > 0
            ORDER BY tp.departure_at
            LIMIT 1;
            """;

        await using var command = Command(sql, connection, transaction);
        command.Parameters.AddWithValue("vehicleId", vehicleId);
        command.Parameters.Add(new NpgsqlParameter("from", NpgsqlDbType.Date) { Value = from });
        command.Parameters.Add(new NpgsqlParameter("to", NpgsqlDbType.Date) { Value = to });

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return null;

        var title = reader.GetString(0);
        var departure = DateOnly.FromDateTime(reader.GetDateTime(1));
        var seats = reader.GetInt32(2);

        return $"This vehicle is carrying the \"{title}\" departure on "
            + $"{departure:dd MMM} with {seats} seat(s) already sold, so it "
            + "cannot go out on rent across those days.";
    }

    private async Task<ServiceResult<IReadOnlyList<RentalBookingDto>>> ListBookingsAsync(
        Guid userId,
        bool asOwner,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await ExpireOverdueAsync(connection, cancellationToken);

        var sql = BookingSelect(asOwner
            ? "dp.user_id = @userId"
            : "rb.customer_user_id = @userId")
            + " ORDER BY rb.start_date DESC LIMIT 100;";

        var freeCancelHours = await SettingAsync(
            connection, null, "rental.free_cancel_hours", DefaultFreeCancelHours, cancellationToken);

        var list = new List<RentalBookingDto>();
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(ReadBooking(reader, freeCancelHours));
        }

        return ServiceResult<IReadOnlyList<RentalBookingDto>>.Ok(list);
    }

    private async Task<RentalBookingDto?> LoadBookingAsync(
        NpgsqlConnection connection,
        Guid bookingId,
        Guid userId,
        bool asOwner,
        CancellationToken cancellationToken)
    {
        var sql = BookingSelect("rb.id = @id") + " LIMIT 1;";
        var freeCancelHours = await SettingAsync(
            connection, null, "rental.free_cancel_hours", DefaultFreeCancelHours, cancellationToken);

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", bookingId);
        command.Parameters.AddWithValue("userId", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? ReadBooking(reader, freeCancelHours)
            : null;
    }

    /// <remarks>
    /// <c>counterpart</c> is whoever the reader is not: the Customer sees the
    /// owner, the owner sees the Customer. One query, one shape, and neither
    /// side is shown their own name where the other's belongs.
    /// </remarks>
    private static string BookingSelect(string where) => $"""
        SELECT rb.id, rb.booking_reference, rb.vehicle_id,
               trim(concat_ws(' ', v.make, v.model)), v.registration_number,
               NULLIF(v.image_url, ''),
               rb.start_date, rb.end_date, rb.rental_mode, rb.days,
               rb.daily_rate, rb.subtotal, rb.security_deposit,
               rb.advance_amount, rb.balance_due, rb.km_per_day,
               rb.fuel_included, rb.pickup_point, rb.status,
               CASE WHEN rb.customer_user_id = @userId
                    THEN COALESCE(NULLIF(owner_u.full_name, ''), 'Owner')
                    ELSE COALESCE(NULLIF(cust_u.full_name, ''), 'Customer') END,
               CASE WHEN rb.status NOT IN ('Confirmed', 'HandedOver', 'Returned') THEN NULL
                    WHEN rb.customer_user_id = @userId
                    THEN owner_u.phone_number ELSE cust_u.phone_number END,
               rb.created_at, rb.cancelled_at, rb.cancel_reason,
               rb.owner_respond_by,
               fd.full_name, fd.phone_number,
               rb.handover_json::text, rb.return_json::text,
               COALESCE(cp.cnic_front_url IS NOT NULL AND cp.cnic_back_url IS NOT NULL
                        AND cp.driving_licence_url IS NOT NULL AND cp.selfie_url IS NOT NULL, false)
        FROM udrive.rental_bookings rb
        JOIN udrive.vehicles v ON v.id = rb.vehicle_id
        JOIN udrive.driver_profiles dp ON dp.id = rb.driver_profile_id
        JOIN udrive.users owner_u ON owner_u.id = dp.user_id
        JOIN udrive.users cust_u ON cust_u.id = rb.customer_user_id
        LEFT JOIN udrive.fleet_drivers fd ON fd.id = rb.fleet_driver_id
        LEFT JOIN udrive.customer_profiles cp ON cp.user_id = rb.customer_user_id
        WHERE {where}
        """;

    private static RentalBookingDto ReadBooking(NpgsqlDataReader reader, int freeCancelHours)
    {
        var start = DateOnly.FromDateTime(reader.GetDateTime(6));
        var status = reader.GetString(18);
        var showDriver = status is "Confirmed" or "HandedOver" or "Returned";
        var handover = Json(reader, 27);
        var returned = Json(reader, 28);

        return new RentalBookingDto(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetGuid(2),
            reader.GetString(3),
            reader.GetString(4),
            reader.IsDBNull(5) ? null : reader.GetString(5),
            start,
            DateOnly.FromDateTime(reader.GetDateTime(7)),
            reader.GetString(8),
            reader.GetInt32(9),
            reader.GetDecimal(10),
            reader.GetDecimal(11),
            reader.GetDecimal(12),
            reader.GetDecimal(13),
            reader.GetDecimal(14),
            reader.IsDBNull(15) ? null : reader.GetInt32(15),
            reader.GetBoolean(16),
            reader.IsDBNull(17) ? null : reader.GetString(17),
            status,
            reader.GetString(19),
            reader.IsDBNull(20) ? null : reader.GetString(20),
            reader.GetFieldValue<DateTimeOffset>(21),
            reader.IsDBNull(22) ? null : reader.GetFieldValue<DateTimeOffset>(22),
            reader.IsDBNull(23) ? null : reader.GetString(23),
            status == "PendingOwner" || (status == "Confirmed" && RefundableNow(start, freeCancelHours)))
        {
            OwnerRespondBy = status == "PendingOwner" && !reader.IsDBNull(24)
                ? reader.GetFieldValue<DateTimeOffset>(24)
                : null,
            DriverName = showDriver && !reader.IsDBNull(25) ? reader.GetString(25) : null,
            DriverPhone = showDriver && !reader.IsDBNull(26) ? reader.GetString(26) : null,
            HandoverPhotos = Photos(handover),
            ReturnPhotos = Photos(returned),
            Handover = Meter(handover),
            Returned = Meter(returned),
            CustomerDocumentsVerified = reader.GetBoolean(29),
        };
    }

    private static JsonElement? Json(NpgsqlDataReader reader, int ordinal)
    {
        if (reader.IsDBNull(ordinal)) return null;
        using var document = JsonDocument.Parse(reader.GetString(ordinal));
        return document.RootElement.Clone();
    }

    private static RentalConditionPhotosDto Photos(JsonElement? record)
    {
        if (record is not { ValueKind: JsonValueKind.Object } value
            || !value.TryGetProperty("photos", out var photos)
            || photos.ValueKind != JsonValueKind.Object)
        {
            return new RentalConditionPhotosDto(null, null, null, null);
        }

        string? Side(string name) =>
            photos.TryGetProperty(name, out var url) && url.ValueKind == JsonValueKind.String
                ? url.GetString()
                : null;
        return new RentalConditionPhotosDto(Side("front"), Side("back"), Side("left"), Side("right"));
    }

    private static RentalMeterDto? Meter(JsonElement? record)
    {
        if (record is not { ValueKind: JsonValueKind.Object } value
            || !value.TryGetProperty("odometerKm", out var km)
            || km.ValueKind != JsonValueKind.Number)
        {
            return null;
        }

        var fuel = value.TryGetProperty("fuel", out var f) && f.ValueKind == JsonValueKind.String
            ? f.GetString() ?? string.Empty
            : string.Empty;
        DateTimeOffset? at = value.TryGetProperty("at", out var a)
                             && a.ValueKind == JsonValueKind.String
                             && DateTimeOffset.TryParse(a.GetString(), out var parsed)
            ? parsed
            : null;
        return new RentalMeterDto(km.GetInt32(), fuel, at);
    }

    private static async Task<bool> HasDocumentsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var command = Command(
            """
            SELECT cnic_front_url IS NOT NULL
               AND cnic_back_url IS NOT NULL
               AND driving_licence_url IS NOT NULL
               AND selfie_url IS NOT NULL
            FROM udrive.customer_profiles
            WHERE user_id = @userId;
            """,
            connection, transaction);
        command.Parameters.AddWithValue("userId", userId);
        return await command.ExecuteScalarAsync(cancellationToken) is true;
    }

    private static async Task<int> SettingAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        string key,
        int fallback,
        CancellationToken cancellationToken)
    {
        await using var command = Command(
            """
            SELECT COALESCE((SELECT GREATEST(0, (value_json #>> '{}')::int)
                             FROM udrive.system_settings WHERE key = @key), @fallback);
            """,
            connection, transaction);
        command.Parameters.AddWithValue("key", key);
        command.Parameters.AddWithValue("fallback", fallback);
        return await command.ExecuteScalarAsync(cancellationToken) is int value ? value : fallback;
    }

    private static NpgsqlCommand Command(
        string sql, NpgsqlConnection connection, NpgsqlTransaction? transaction) =>
        transaction is null
            ? new NpgsqlCommand(sql, connection)
            : new NpgsqlCommand(sql, connection, transaction);

    /// <summary>
    /// Whether a cancellation now still returns the advance.
    /// </summary>
    /// <remarks>
    /// Measured against the start of the rental day in Pakistan, not against
    /// UTC midnight. A booking starting on the 14th is a car collected on the
    /// morning of the 14th wherever the server happens to be running.
    /// </remarks>
    private static bool RefundableNow(DateOnly startDate, int freeCancelHours)
    {
        var startsAt = new DateTimeOffset(
            startDate.ToDateTime(TimeOnly.MinValue), Karachi);
        return DateTimeOffset.UtcNow <= startsAt.AddHours(-freeCancelHours);
    }

    private static readonly TimeSpan Karachi = TimeSpan.FromHours(5);

    private static DateOnly Today() =>
        DateOnly.FromDateTime(DateTimeOffset.UtcNow.ToOffset(Karachi).DateTime);

    private static string? NormaliseMode(string? mode) => mode?.Trim().ToLowerInvariant() switch
    {
        "withdriver" or "with_driver" or "with driver" => "WithDriver",
        "selfdrive" or "self_drive" or "self drive" => "SelfDrive",
        _ => null,
    };

    private static void AddDate(NpgsqlCommand command, string name, DateOnly? value) =>
        command.Parameters.Add(new NpgsqlParameter(name, NpgsqlDbType.Date)
        {
            Value = (object?)value ?? DBNull.Value,
        });
}
