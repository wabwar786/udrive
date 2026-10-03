using System.Data;
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
public sealed class RentalService(string connectionString)
{
    /// <summary>What a Customer pays at booking when no setting says.</summary>
    public const int DefaultAdvancePercent = 20;

    /// <summary>The free-cancellation window when no setting says.</summary>
    public const int DefaultFreeCancelHours = 48;

    /// <summary>How far ahead a calendar is worth drawing.</summary>
    private const int CalendarDays = 120;

    private static readonly string[] LiveRentalStatuses = ["Confirmed", "HandedOver"];

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
                   v.has_air_conditioning, v.is_four_by_four
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
                reader.GetBoolean(19)));
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
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
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

        var reference = $"RN-{DateTime.UtcNow:yyMM}-{Guid.NewGuid().ToString("N")[..6].ToUpperInvariant()}";

        const string insertSql = """
            INSERT INTO udrive.rental_bookings
                (booking_reference, vehicle_id, driver_profile_id, customer_user_id,
                 start_date, end_date, rental_mode, daily_rate, days, subtotal,
                 security_deposit, advance_amount, balance_due, km_per_day,
                 fuel_included, pickup_point, status, disclaimer_version,
                 disclaimer_accepted_at, created_at, updated_at)
            SELECT @reference, v.id, v.driver_profile_id, @customer,
                   @start, @end, @mode, @rate, @days, @subtotal,
                   @deposit, @advance, @balance, v.rent_km_per_day,
                   COALESCE(v.rent_fuel_included, false), v.rent_pickup_point,
                   'Confirmed', @disclaimer, now(), now(), now()
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
        return ServiceResult<RentalBookingDto>.Created(created!);
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

        if (status is not "Confirmed")
        {
            return ServiceResult<RentalBookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "rental_not_cancellable",
                status is "Cancelled"
                    ? "This booking has already been cancelled."
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
            WHERE id = @id AND status = 'Confirmed';
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
        var refunded = isOwner || RefundableNow(startDate, freeCancelHours);

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
              AND rb.status IN ('Confirmed', 'HandedOver');
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
                     ELSE 'trip'
                   END AS reason
            FROM calendar w
            WHERE EXISTS (SELECT 1 FROM rented r
                           WHERE w.day BETWEEN r.start_date AND r.end_date + @turnaroundDays)
               OR EXISTS (SELECT 1 FROM toured t
                           WHERE w.day BETWEEN t.start_date AND t.end_date)
               OR EXISTS (SELECT 1 FROM tripped p
                           WHERE w.day BETWEEN p.start_date AND p.end_date)
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
               CASE WHEN rb.customer_user_id = @userId
                    THEN owner_u.phone_number ELSE cust_u.phone_number END,
               rb.created_at, rb.cancelled_at, rb.cancel_reason
        FROM udrive.rental_bookings rb
        JOIN udrive.vehicles v ON v.id = rb.vehicle_id
        JOIN udrive.driver_profiles dp ON dp.id = rb.driver_profile_id
        JOIN udrive.users owner_u ON owner_u.id = dp.user_id
        JOIN udrive.users cust_u ON cust_u.id = rb.customer_user_id
        WHERE {where}
        """;

    private static RentalBookingDto ReadBooking(NpgsqlDataReader reader, int freeCancelHours)
    {
        var start = DateOnly.FromDateTime(reader.GetDateTime(6));
        var status = reader.GetString(18);

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
            status == "Confirmed" && RefundableNow(start, freeCancelHours));
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
