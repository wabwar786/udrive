using System.Data;
using Microsoft.AspNetCore.Http;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The Tour &amp; Rent home in Driver mode: who booked, who is waiting, and
/// how full each departure is.
/// </summary>
/// <remarks>
/// Tour seats and rent-a-car days book straight through; there is nothing
/// for the driver to accept. Once a vehicle (or every seat) is taken, new
/// customers can only send a waiting-list request. The driver accepts one
/// when a place frees up — a booked customer cancels, or does not turn up —
/// and the accepted customer then has a limited time to pay the advance.
/// </remarks>
public sealed class TourRentDriverService(string connectionString)
{
    /// <summary>Minutes an accepted customer has to pay, when no setting says.</summary>
    public const int DefaultAcceptHoldMinutes = 120;

    private static readonly TimeSpan Karachi = TimeSpan.FromHours(5);

    // ─────────────────────────────────────────────────────────── home

    public async Task<ServiceResult<TourRentHomeDto>> HomeAsync(
        Guid driverUserId,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var vehicles = new List<string>();
        await using (var command = new NpgsqlCommand(
            """
            SELECT trim(concat_ws(' ', v.make, v.model))
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            WHERE dp.user_id = @user
              AND (COALESCE(v.available_for_tour, false) OR COALESCE(v.available_for_rent, false))
              AND lower(v.status) NOT IN ('deleted', 'rejected')
            ORDER BY v.created_at;
            """, connection))
        {
            command.Parameters.AddWithValue("user", driverUserId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken)) vehicles.Add(reader.GetString(0));
        }

        int ridesVehicles;
        decimal wallet;
        await using (var command = new NpgsqlCommand(
            """
            SELECT
                (SELECT count(*)::int FROM udrive.vehicles v
                  JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                  WHERE dp.user_id = @user
                    AND (COALESCE(v.available_for_city, false) OR COALESCE(v.available_for_intercity, false))
                    AND lower(v.status) NOT IN ('deleted', 'rejected')),
                COALESCE((SELECT sum(w.commission_balance) FROM udrive.driver_wallets w
                  JOIN udrive.driver_profiles dp ON dp.id = w.driver_profile_id
                  WHERE dp.user_id = @user), 0);
            """, connection))
        {
            command.Parameters.AddWithValue("user", driverUserId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            await reader.ReadAsync(cancellationToken);
            ridesVehicles = reader.GetInt32(0);
            wallet = reader.GetDecimal(1);
        }

        var bookings = new List<TourRentBookingDto>();

        // Tour bookings on this driver's departures that have not happened yet.
        await using (var command = new NpgsqlCommand(
            """
            SELECT b.id, COALESCE(NULLIF(cu.full_name, ''), 'Customer'), cu.phone_number,
                   tp.title, trim(concat_ws(' ', v.make, v.model)),
                   b.pickup_at, b.return_at, b.total_amount,
                   b.booking_type = 'WholeVehicle', b.seats_booked, b.status, b.created_at
            FROM udrive.bookings b
            JOIN udrive.tour_packages tp ON tp.id = b.tour_package_id
            JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
            JOIN udrive.vehicles v ON v.id = tp.vehicle_id
            JOIN udrive.users cu ON cu.id = b.customer_user_id
            WHERE dp.user_id = @user
              AND b.status NOT IN ('Cancelled', 'Completed', 'NoShow')
              AND COALESCE(b.return_at, b.pickup_at) >= now() - interval '1 day'
            ORDER BY b.pickup_at, b.created_at
            LIMIT 100;
            """, connection))
        {
            command.Parameters.AddWithValue("user", driverUserId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                bookings.Add(new TourRentBookingDto(
                    reader.GetGuid(0),
                    "tour",
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.GetFieldValue<DateTimeOffset>(5),
                    reader.IsDBNull(6) ? null : reader.GetFieldValue<DateTimeOffset>(6),
                    reader.GetDecimal(7),
                    reader.GetBoolean(8),
                    reader.GetInt32(9),
                    null,
                    reader.GetString(10),
                    reader.GetFieldValue<DateTimeOffset>(11)));
            }
        }

        // Rentals of this driver's cars that are still ahead or under way.
        await using (var command = new NpgsqlCommand(
            """
            SELECT rb.id, COALESCE(NULLIF(cu.full_name, ''), 'Customer'), cu.phone_number,
                   trim(concat_ws(' ', v.make, v.model)), rb.start_date, rb.end_date,
                   rb.subtotal, rb.days, rb.rental_mode, rb.status, rb.created_at
            FROM udrive.rental_bookings rb
            JOIN udrive.driver_profiles dp ON dp.id = rb.driver_profile_id
            JOIN udrive.vehicles v ON v.id = rb.vehicle_id
            JOIN udrive.users cu ON cu.id = rb.customer_user_id
            WHERE dp.user_id = @user
              AND rb.status IN ('PendingOwner', 'Confirmed', 'HandedOver')
              AND rb.end_date >= (now() AT TIME ZONE 'Asia/Karachi')::date
            ORDER BY rb.start_date, rb.created_at
            LIMIT 100;
            """, connection))
        {
            command.Parameters.AddWithValue("user", driverUserId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var start = DateOnly.FromDateTime(reader.GetDateTime(4));
                var end = DateOnly.FromDateTime(reader.GetDateTime(5));
                var status = reader.GetString(9);
                bookings.Add(new TourRentBookingDto(
                    reader.GetGuid(0),
                    "rent",
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(3),
                    DayStart(start),
                    DayStart(end),
                    reader.GetDecimal(6),
                    true,
                    reader.GetInt32(7),
                    reader.GetString(8),
                    status,
                    reader.GetFieldValue<DateTimeOffset>(10)));
            }
        }

        bookings.Sort((a, b) => a.StartsAt.CompareTo(b.StartsAt));

        var waitlist = new List<TourRentWaitlistDto>();

        // Tour waiting list: is there room for this request right now?
        await using (var command = new NpgsqlCommand(
            """
            WITH held AS (
                SELECT h.tour_package_id, sum(h.seats_held)::int AS seats
                FROM udrive.package_seat_holds h
                WHERE h.status = 'Active' AND h.expires_at > now()
                GROUP BY h.tour_package_id
            )
            SELECT w.id, COALESCE(NULLIF(cu.full_name, ''), 'Customer'), cu.phone_number,
                   tp.title, tp.departure_at,
                   CASE WHEN w.booking_type = 'WholeVehicle' THEN tp.whole_vehicle_price
                        ELSE tp.price_per_seat * w.seats_requested END,
                   w.booking_type = 'WholeVehicle', w.seats_requested,
                   tp.total_seats, tp.available_seats, COALESCE(held.seats, 0),
                   CASE WHEN w.status = 'Notified' AND w.accept_expires_at <= now()
                        THEN 'Expired' ELSE w.status END,
                   w.accept_expires_at, w.created_at
            FROM udrive.package_waitlist w
            JOIN udrive.tour_packages tp ON tp.id = w.tour_package_id
            JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
            JOIN udrive.users cu ON cu.id = w.customer_user_id
            LEFT JOIN held ON held.tour_package_id = tp.id
            WHERE dp.user_id = @user
              AND w.status IN ('Waiting', 'Notified')
              AND tp.departure_at > now()
            ORDER BY tp.departure_at, w.created_at;
            """, connection))
        {
            command.Parameters.AddWithValue("user", driverUserId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var whole = reader.GetBoolean(6);
                var requested = reader.GetInt32(7);
                var total = reader.GetInt32(8);
                var available = reader.GetInt32(9);
                var held = reader.GetInt32(10);
                var status = reader.GetString(11);
                var bookable = Math.Max(0, available - held);
                var free = status == "Waiting"
                           && (whole ? available == total && held == 0 : bookable >= requested);
                waitlist.Add(new TourRentWaitlistDto(
                    reader.GetGuid(0),
                    "tour",
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.GetString(3),
                    reader.GetFieldValue<DateTimeOffset>(4),
                    null,
                    reader.GetDecimal(5),
                    whole,
                    requested,
                    total,
                    total - available,
                    free,
                    status == "Notified" ? "Accepted" : status,
                    reader.IsDBNull(12) ? null : reader.GetFieldValue<DateTimeOffset>(12),
                    reader.GetFieldValue<DateTimeOffset>(13)));
            }
        }

        // Rent waiting list: is the car free on those days now?
        await using (var command = new NpgsqlCommand(
            """
            SELECT w.id, COALESCE(NULLIF(cu.full_name, ''), 'Customer'), cu.phone_number,
                   trim(concat_ws(' ', v.make, v.model)), w.start_date, w.end_date,
                   (w.end_date - w.start_date + 1)
                     * COALESCE(CASE WHEN w.rental_mode = 'SelfDrive' THEN v.rent_self_drive_daily
                                     ELSE v.rent_with_driver_daily END, 0),
                   NOT EXISTS (
                       SELECT 1 FROM udrive.rental_bookings rb
                       WHERE rb.vehicle_id = w.vehicle_id
                         AND rb.status IN ('PendingOwner', 'Confirmed', 'HandedOver')
                         AND daterange(rb.start_date, rb.end_date, '[]')
                             && daterange(w.start_date, w.end_date, '[]'))
                   AND NOT EXISTS (
                       SELECT 1 FROM udrive.rental_waitlist o
                       WHERE o.vehicle_id = w.vehicle_id AND o.id <> w.id
                         AND o.status = 'Accepted' AND o.accept_expires_at > now()
                         AND daterange(o.start_date, o.end_date, '[]')
                             && daterange(w.start_date, w.end_date, '[]')),
                   CASE WHEN w.status = 'Accepted' AND w.accept_expires_at <= now()
                        THEN 'Expired' ELSE w.status END,
                   w.accept_expires_at, w.created_at
            FROM udrive.rental_waitlist w
            JOIN udrive.driver_profiles dp ON dp.id = w.driver_profile_id
            JOIN udrive.vehicles v ON v.id = w.vehicle_id
            JOIN udrive.users cu ON cu.id = w.customer_user_id
            WHERE dp.user_id = @user
              AND w.status IN ('Waiting', 'Accepted')
              AND w.end_date >= (now() AT TIME ZONE 'Asia/Karachi')::date
            ORDER BY w.start_date, w.created_at;
            """, connection))
        {
            command.Parameters.AddWithValue("user", driverUserId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var status = reader.GetString(8);
                waitlist.Add(new TourRentWaitlistDto(
                    reader.GetGuid(0),
                    "rent",
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.GetString(3),
                    DayStart(DateOnly.FromDateTime(reader.GetDateTime(4))),
                    DayStart(DateOnly.FromDateTime(reader.GetDateTime(5))),
                    reader.GetDecimal(6),
                    true,
                    0,
                    0,
                    0,
                    status == "Waiting" && reader.GetBoolean(7),
                    status,
                    reader.IsDBNull(9) ? null : reader.GetFieldValue<DateTimeOffset>(9),
                    reader.GetFieldValue<DateTimeOffset>(10)));
            }
        }

        // Free places first, so the one the driver can act on is on top.
        waitlist = waitlist
            .OrderByDescending(w => w.Free)
            .ThenBy(w => w.StartsAt)
            .ToList();

        var departures = new List<TourRentDepartureDto>();
        await using (var command = new NpgsqlCommand(
            """
            SELECT tp.id, tp.title, tp.departure_at, tp.total_seats,
                   tp.total_seats - tp.available_seats,
                   (SELECT count(*)::int FROM udrive.bookings b
                     WHERE b.tour_package_id = tp.id
                       AND b.status NOT IN ('Cancelled', 'NoShow'))
            FROM udrive.tour_packages tp
            JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
            WHERE dp.user_id = @user
              AND tp.status = 'Active'
              AND tp.departure_at > now()
            ORDER BY tp.departure_at
            LIMIT 20;
            """, connection))
        {
            command.Parameters.AddWithValue("user", driverUserId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                departures.Add(new TourRentDepartureDto(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.GetFieldValue<DateTimeOffset>(2),
                    reader.GetInt32(3),
                    reader.GetInt32(4),
                    reader.GetInt32(5)));
            }
        }

        // "Is hafte": this week's work (Monday to Sunday, Pakistan time).
        decimal week;
        await using (var command = new NpgsqlCommand(
            """
            WITH wk AS (
                SELECT date_trunc('week', now() AT TIME ZONE 'Asia/Karachi')::date AS d0
            )
            SELECT
                COALESCE((SELECT sum(b.total_amount)
                          FROM udrive.bookings b
                          JOIN udrive.tour_packages tp ON tp.id = b.tour_package_id
                          JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id, wk
                          WHERE dp.user_id = @user
                            AND b.status NOT IN ('Cancelled', 'NoShow')
                            AND (b.pickup_at AT TIME ZONE 'Asia/Karachi')::date
                                BETWEEN wk.d0 AND wk.d0 + 6), 0)
              + COALESCE((SELECT sum(rb.subtotal)
                          FROM udrive.rental_bookings rb
                          JOIN udrive.driver_profiles dp ON dp.id = rb.driver_profile_id, wk
                          WHERE dp.user_id = @user
                            AND rb.status IN ('Confirmed', 'HandedOver', 'Returned')
                            AND rb.start_date BETWEEN wk.d0 AND wk.d0 + 6), 0);
            """, connection))
        {
            command.Parameters.AddWithValue("user", driverUserId);
            week = Convert.ToDecimal(await command.ExecuteScalarAsync(cancellationToken) ?? 0m);
        }

        var since = DateTimeOffset.UtcNow.AddDays(-7);
        return ServiceResult<TourRentHomeDto>.Ok(new TourRentHomeDto(
            vehicles,
            ridesVehicles,
            wallet,
            bookings.Count(b => b.CreatedAt >= since),
            waitlist.Count,
            week,
            bookings,
            waitlist,
            departures));
    }

    // ───────────────────────────────────────────── accept / decline

    /// <summary>
    /// The driver gives a freed place to a waiting customer. The place is
    /// held for them, and they are told to pay the advance in time.
    /// </summary>
    public async Task<ServiceResult<TourRentWaitlistResultDto>> AcceptAsync(
        Guid driverUserId,
        string kind,
        Guid id,
        CancellationToken cancellationToken) =>
        kind switch
        {
            "tour" => await AcceptTourAsync(driverUserId, id, cancellationToken),
            "rent" => await AcceptRentAsync(driverUserId, id, cancellationToken),
            _ => UnknownKind(),
        };

    /// <summary>The driver turns a waiting request down; the customer is told.</summary>
    public async Task<ServiceResult<TourRentWaitlistResultDto>> DeclineAsync(
        Guid driverUserId,
        string kind,
        Guid id,
        CancellationToken cancellationToken)
    {
        if (kind is not ("tour" or "rent")) return UnknownKind();

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        var sql = kind == "tour"
            ? """
              UPDATE udrive.package_waitlist w
              SET status = 'Declined', responded_at = now(), updated_at = now()
              FROM udrive.tour_packages tp, udrive.driver_profiles dp
              WHERE w.id = @id AND tp.id = w.tour_package_id AND dp.id = tp.driver_profile_id
                AND dp.user_id = @user AND w.status = 'Waiting'
              RETURNING w.customer_user_id, tp.title;
              """
            : """
              UPDATE udrive.rental_waitlist w
              SET status = 'Declined', responded_at = now(), updated_at = now()
              FROM udrive.driver_profiles dp, udrive.vehicles v
              WHERE w.id = @id AND dp.id = w.driver_profile_id AND v.id = w.vehicle_id
                AND dp.user_id = @user AND w.status = 'Waiting'
              RETURNING w.customer_user_id, trim(concat_ws(' ', v.make, v.model));
              """;

        Guid customer;
        string title;
        await using (var command = new NpgsqlCommand(sql, connection, transaction))
        {
            command.Parameters.AddWithValue("id", id);
            command.Parameters.AddWithValue("user", driverUserId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<TourRentWaitlistResultDto>.Fail(
                    StatusCodes.Status409Conflict,
                    "waitlist_not_open",
                    "Yeh request ab khuli nahi hai.");
            }

            customer = reader.GetGuid(0);
            title = reader.GetString(1);
        }

        await NotifyAsync(
            connection, transaction, customer,
            kind == "tour" ? "TourWaitlistDeclined" : "RentalWaitlistDeclined",
            "Request accept nahi ho saki",
            $"{title}: driver is waqt aap ki request accept nahi kar saka. Doosri tour ya gaari dekhein.",
            kind == "tour" ? "/tours" : "/rentals",
            id,
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<TourRentWaitlistResultDto>.Ok(
            new TourRentWaitlistResultDto(id, kind, "Declined", null),
            "Request decline ho gayi. Customer ko bata diya gaya.");
    }

    private async Task<ServiceResult<TourRentWaitlistResultDto>> AcceptTourAsync(
        Guid driverUserId,
        Guid id,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.Serializable, cancellationToken);

        Guid packageId;
        Guid customer;
        string bookingType;
        int requested;
        string status;
        await using (var command = new NpgsqlCommand(
            """
            SELECT w.tour_package_id, w.customer_user_id, w.booking_type,
                   w.seats_requested, w.status
            FROM udrive.package_waitlist w
            JOIN udrive.tour_packages tp ON tp.id = w.tour_package_id
            JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
            WHERE w.id = @id AND dp.user_id = @user;
            """, connection, transaction))
        {
            command.Parameters.AddWithValue("id", id);
            command.Parameters.AddWithValue("user", driverUserId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<TourRentWaitlistResultDto>.Fail(
                    StatusCodes.Status404NotFound, "waitlist_not_found", "Yeh request nahi mili.");
            }

            packageId = reader.GetGuid(0);
            customer = reader.GetGuid(1);
            bookingType = reader.GetString(2);
            requested = reader.GetInt32(3);
            status = reader.GetString(4);
        }

        if (status != "Waiting")
        {
            return ServiceResult<TourRentWaitlistResultDto>.Fail(
                StatusCodes.Status409Conflict, "waitlist_not_open", "Yeh request pehle hi jawab di ja chuki hai.");
        }

        string title;
        int total;
        int available;
        decimal seatPrice;
        decimal wholePrice;
        DateTimeOffset departure;
        await using (var command = new NpgsqlCommand(
            """
            SELECT title, total_seats, available_seats, price_per_seat,
                   whole_vehicle_price, departure_at, status
            FROM udrive.tour_packages WHERE id = @id FOR UPDATE;
            """, connection, transaction))
        {
            command.Parameters.AddWithValue("id", packageId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            await reader.ReadAsync(cancellationToken);
            title = reader.GetString(0);
            total = reader.GetInt32(1);
            available = reader.GetInt32(2);
            seatPrice = reader.GetDecimal(3);
            wholePrice = reader.GetDecimal(4);
            departure = reader.GetFieldValue<DateTimeOffset>(5);
            if (reader.GetString(6) != "Active" || departure <= DateTimeOffset.UtcNow)
            {
                return ServiceResult<TourRentWaitlistResultDto>.Fail(
                    StatusCodes.Status409Conflict, "package_not_bookable", "Yeh tour ab booking ke liye khula nahi.");
            }
        }

        await using (var expire = new NpgsqlCommand(
            "UPDATE udrive.package_seat_holds SET status='Expired', updated_at=now() WHERE tour_package_id=@id AND status='Active' AND expires_at<=now();",
            connection, transaction))
        {
            expire.Parameters.AddWithValue("id", packageId);
            await expire.ExecuteNonQueryAsync(cancellationToken);
        }

        int held;
        await using (var command = new NpgsqlCommand(
            "SELECT COALESCE(sum(seats_held), 0)::int FROM udrive.package_seat_holds WHERE tour_package_id=@id AND status='Active' AND expires_at>now();",
            connection, transaction))
        {
            command.Parameters.AddWithValue("id", packageId);
            held = Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken));
        }

        var whole = bookingType == "WholeVehicle";
        var seats = whole ? total : requested;
        var free = whole ? available == total && held == 0 : available - held >= seats;
        if (!free)
        {
            return ServiceResult<TourRentWaitlistResultDto>.Fail(
                StatusCodes.Status409Conflict,
                "no_room_yet",
                whole
                    ? "Gaari abhi khali nahi — pehle booked customer cancel ho ya 'nahi aaya' mark karein."
                    : $"Abhi sirf {Math.Max(0, available - held)} seat khali hai, request {seats} ki hai.");
        }

        var minutes = await AcceptHoldMinutesAsync(connection, transaction, cancellationToken);
        var expiresAt = DateTimeOffset.UtcNow.AddMinutes(minutes);
        if (expiresAt > departure) expiresAt = departure;

        var holdId = Guid.NewGuid();
        await using (var command = new NpgsqlCommand(
            """
            UPDATE udrive.package_seat_holds SET status='Cancelled', updated_at=now()
            WHERE tour_package_id=@package AND customer_user_id=@customer AND status='Active';

            INSERT INTO udrive.package_seat_holds
                (id, tour_package_id, customer_user_id, booking_type, seats_held,
                 quoted_amount, status, expires_at, created_at, updated_at)
            VALUES (@hold, @package, @customer, @type, @seats, @amount, 'Active', @expires, now(), now());

            UPDATE udrive.package_waitlist
            SET status='Notified', hold_id=@hold, accept_expires_at=@expires,
                notified_at=now(), responded_at=now(), updated_at=now()
            WHERE id=@id;
            """, connection, transaction))
        {
            command.Parameters.AddWithValue("hold", holdId);
            command.Parameters.AddWithValue("package", packageId);
            command.Parameters.AddWithValue("customer", customer);
            command.Parameters.AddWithValue("type", bookingType);
            command.Parameters.AddWithValue("seats", seats);
            command.Parameters.AddWithValue("amount", whole ? wholePrice : seatPrice * seats);
            command.Parameters.AddWithValue("expires", expiresAt);
            command.Parameters.AddWithValue("id", id);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await NotifyAsync(
            connection, transaction, customer, "TourWaitlistAccepted",
            "Aap ki request accept ho gayi",
            $"{title}: driver ne aap ki request accept kar li. {expiresAt.ToOffset(Karachi):h:mm tt} tak "
            + "advance de kar booking pakki karein, warna jagah kisi aur ko di ja sakti hai.",
            "/tours",
            id,
            cancellationToken);

        await WhatsAppOutbox.QueueAsync(
            connection, transaction, WhatsAppOutbox.WaitlistAcceptedCustomer,
            await PhoneAsync(connection, transaction, customer, cancellationToken),
            new Dictionary<string, string?>
            {
                ["what"] = $"{title} · {departure.ToOffset(Karachi):d MMM}",
                ["until"] = WhatsAppOutbox.Time(expiresAt),
                ["where"] = "Tours",
            },
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<TourRentWaitlistResultDto>.Ok(
            new TourRentWaitlistResultDto(id, "tour", "Accepted", expiresAt),
            "Accept ho gaya. Customer ko notification chali gayi.");
    }

    private async Task<ServiceResult<TourRentWaitlistResultDto>> AcceptRentAsync(
        Guid driverUserId,
        Guid id,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await RentalService.ExpireOverdueAsync(connection, cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        Guid vehicleId;
        Guid customer;
        DateOnly start;
        DateOnly end;
        string status;
        string car;
        await using (var command = new NpgsqlCommand(
            """
            SELECT w.vehicle_id, w.customer_user_id, w.start_date, w.end_date, w.status,
                   trim(concat_ws(' ', v.make, v.model))
            FROM udrive.rental_waitlist w
            JOIN udrive.driver_profiles dp ON dp.id = w.driver_profile_id
            JOIN udrive.vehicles v ON v.id = w.vehicle_id
            WHERE w.id = @id AND dp.user_id = @user;
            """, connection, transaction))
        {
            command.Parameters.AddWithValue("id", id);
            command.Parameters.AddWithValue("user", driverUserId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<TourRentWaitlistResultDto>.Fail(
                    StatusCodes.Status404NotFound, "waitlist_not_found", "Yeh request nahi mili.");
            }

            vehicleId = reader.GetGuid(0);
            customer = reader.GetGuid(1);
            start = DateOnly.FromDateTime(reader.GetDateTime(2));
            end = DateOnly.FromDateTime(reader.GetDateTime(3));
            status = reader.GetString(4);
            car = reader.GetString(5);
        }

        if (status != "Waiting")
        {
            return ServiceResult<TourRentWaitlistResultDto>.Fail(
                StatusCodes.Status409Conflict, "waitlist_not_open", "Yeh request pehle hi jawab di ja chuki hai.");
        }

        await using (var @lock = new NpgsqlCommand(
            "SELECT 1 FROM udrive.vehicles WHERE id = @id FOR UPDATE;", connection, transaction))
        {
            @lock.Parameters.AddWithValue("id", vehicleId);
            await @lock.ExecuteScalarAsync(cancellationToken);
        }

        bool free;
        await using (var command = new NpgsqlCommand(
            """
            SELECT NOT EXISTS (
                       SELECT 1 FROM udrive.rental_bookings rb
                       WHERE rb.vehicle_id = @vehicle
                         AND rb.status IN ('PendingOwner', 'Confirmed', 'HandedOver')
                         AND daterange(rb.start_date, rb.end_date, '[]')
                             && daterange(@start, @end, '[]'))
               AND NOT EXISTS (
                       SELECT 1 FROM udrive.rental_waitlist o
                       WHERE o.vehicle_id = @vehicle AND o.id <> @id
                         AND o.status = 'Accepted' AND o.accept_expires_at > now()
                         AND daterange(o.start_date, o.end_date, '[]')
                             && daterange(@start, @end, '[]'));
            """, connection, transaction))
        {
            command.Parameters.AddWithValue("vehicle", vehicleId);
            command.Parameters.AddWithValue("id", id);
            command.Parameters.Add(new NpgsqlParameter("start", NpgsqlDbType.Date) { Value = start });
            command.Parameters.Add(new NpgsqlParameter("end", NpgsqlDbType.Date) { Value = end });
            free = await command.ExecuteScalarAsync(cancellationToken) is true;
        }

        if (!free)
        {
            return ServiceResult<TourRentWaitlistResultDto>.Fail(
                StatusCodes.Status409Conflict,
                "no_room_yet",
                "Gaari in dinon mein abhi booked hai — pehle booked customer cancel ho ya 'nahi aaya' mark karein.");
        }

        var minutes = await AcceptHoldMinutesAsync(connection, transaction, cancellationToken);
        var expiresAt = DateTimeOffset.UtcNow.AddMinutes(minutes);
        await using (var command = new NpgsqlCommand(
            """
            UPDATE udrive.rental_waitlist
            SET status = 'Accepted', accept_expires_at = @expires,
                responded_at = now(), updated_at = now()
            WHERE id = @id;
            """, connection, transaction))
        {
            command.Parameters.AddWithValue("id", id);
            command.Parameters.AddWithValue("expires", expiresAt);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await NotifyAsync(
            connection, transaction, customer, "RentalWaitlistAccepted",
            "Gaari mil gayi — booking pakki karein",
            $"{car} ({start:dd MMM} – {end:dd MMM}): driver ne aap ki request accept kar li. "
            + $"{expiresAt.ToOffset(Karachi):h:mm tt} tak advance de kar book karein.",
            "/rentals",
            id,
            cancellationToken);

        await WhatsAppOutbox.QueueAsync(
            connection, transaction, WhatsAppOutbox.WaitlistAcceptedCustomer,
            await PhoneAsync(connection, transaction, customer, cancellationToken),
            new Dictionary<string, string?>
            {
                ["what"] = $"{car} · {WhatsAppOutbox.Dates(start, end)}",
                ["until"] = WhatsAppOutbox.Time(expiresAt),
                ["where"] = "Rent a car",
            },
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<TourRentWaitlistResultDto>.Ok(
            new TourRentWaitlistResultDto(id, "rent", "Accepted", expiresAt),
            "Accept ho gaya. Customer ko notification chali gayi.");
    }

    // ───────────────────────────────────────────────────── helpers

    private static async Task<int> AcceptHoldMinutesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT (value_json #>> '{}')
            FROM udrive.system_settings WHERE key = 'waitlist.accept_hold_minutes';
            """, connection, transaction);
        var raw = await command.ExecuteScalarAsync(cancellationToken);
        return raw is not null && int.TryParse(raw.ToString(), out var minutes) && minutes >= 10
            ? Math.Min(minutes, 24 * 60)
            : DefaultAcceptHoldMinutes;
    }

    private static async Task NotifyAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid userId,
        string type,
        string title,
        string body,
        string actionPath,
        Guid waitlistId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.notifications
                (id, user_id, type, title, body, data_json, action_path, created_at, updated_at)
            VALUES (gen_random_uuid(), @user, @type, @title, @body,
                    jsonb_build_object('waitlistId', @id), @path, now(), now());
            """, connection, transaction);
        command.Parameters.AddWithValue("user", userId);
        command.Parameters.AddWithValue("type", type);
        command.Parameters.AddWithValue("title", title);
        command.Parameters.AddWithValue("body", body);
        command.Parameters.AddWithValue("id", waitlistId);
        command.Parameters.AddWithValue("path", actionPath);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<string?> PhoneAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid userId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            "SELECT phone_number FROM udrive.users WHERE id = @id;", connection, transaction);
        command.Parameters.AddWithValue("id", userId);
        return await command.ExecuteScalarAsync(cancellationToken) as string;
    }

    private static DateTimeOffset DayStart(DateOnly day) =>
        new(day.ToDateTime(TimeOnly.MinValue), Karachi);

    private static ServiceResult<TourRentWaitlistResultDto> UnknownKind() =>
        ServiceResult<TourRentWaitlistResultDto>.Fail(
            StatusCodes.Status400BadRequest, "kind_invalid", "Kind must be tour or rent.");
}
