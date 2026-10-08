using Microsoft.AspNetCore.Http;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The hotel owner's home: who booked, who arrives and leaves today, and how
/// many rooms of each type are free over the next seven days.
/// </summary>
/// <remarks>
/// Hotel bookings are confirmed when the customer books — the owner does not
/// accept them. The owner only marks a guest arrived or gone.
/// </remarks>
public sealed class HotelOwnerDashboardService(string connectionString)
{
    private const int Days = 7;

    public async Task<ServiceResult<HotelOwnerDashboardDto>> DashboardAsync(
        Guid ownerId, Guid? hotelId, CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);

        var hotels = new List<HotelOwnerHotelDto>();
        await using (var command = new NpgsqlCommand(
            """
            SELECT h.id, h.name, COALESCE(NULLIF(h.city, ''), h.district, ''), h.approval_status,
                   NULLIF(h.main_image_url, ''),
                   (SELECT count(*)::int FROM udrive.hotel_rooms r WHERE r.hotel_id = h.id AND r.is_active),
                   (SELECT COALESCE(sum(r.total_rooms), 0)::int FROM udrive.hotel_rooms r
                     WHERE r.hotel_id = h.id AND r.is_active)
            FROM udrive.hotels h
            WHERE h.owner_user_id = @owner
            ORDER BY h.created_at;
            """, connection))
        {
            command.Parameters.AddWithValue("owner", ownerId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                hotels.Add(new HotelOwnerHotelDto(
                    reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4), reader.GetInt32(5), reader.GetInt32(6)));
            }
        }

        var today = DateOnly.FromDateTime(DateTime.UtcNow.AddHours(5));
        var selected = hotels.FirstOrDefault(h => h.Id == hotelId) ?? hotels.FirstOrDefault();
        if (selected is null)
        {
            return ServiceResult<HotelOwnerDashboardDto>.Ok(new HotelOwnerDashboardDto(
                hotels, null, 0, 0, 0, 0, [], [], [], [], today));
        }

        // Rooms free per type per day: the day's inventory (or the type's
        // total), less what live bookings already hold on that night.
        var rooms = new List<HotelOwnerRoomDto>();
        await using (var command = new NpgsqlCommand(
            """
            SELECT r.id, r.room_type, COALESCE(r.base_rate, 0),
                   array_agg(GREATEST(0,
                       COALESCE(i.available_rooms, r.total_rooms)
                       - COALESCE((SELECT sum(b.rooms) FROM udrive.hotel_bookings b
                                    WHERE b.room_id = r.id
                                      AND b.status NOT IN ('Cancelled', 'CheckedOut', 'NoShow')
                                      AND d.day >= b.check_in AND d.day < b.check_out), 0))::int
                       ORDER BY d.day)
            FROM udrive.hotel_rooms r
            CROSS JOIN LATERAL (SELECT (@today::date + g)::date AS day FROM generate_series(0, @days - 1) g) d
            LEFT JOIN udrive.hotel_room_inventory i ON i.room_id = r.id AND i.inventory_date = d.day
            WHERE r.hotel_id = @hotel AND r.is_active
            GROUP BY r.id, r.room_type, r.base_rate, r.created_at
            ORDER BY r.created_at;
            """, connection))
        {
            command.Parameters.AddWithValue("hotel", selected.Id);
            command.Parameters.Add(new NpgsqlParameter("today", NpgsqlDbType.Date) { Value = today });
            command.Parameters.AddWithValue("days", Days);
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                rooms.Add(new HotelOwnerRoomDto(
                    reader.GetGuid(0), reader.GetString(1), reader.GetDecimal(2), reader.GetFieldValue<int[]>(3)));
            }
        }

        var bookings = new List<HotelOwnerBookingDto>();
        await using (var command = new NpgsqlCommand(
            """
            SELECT b.id, COALESCE(b.booking_reference, ''),
                   COALESCE(NULLIF(b.guest_name, ''), NULLIF(u.full_name, ''), 'Guest'),
                   COALESCE(NULLIF(b.guest_phone, ''), u.phone_number),
                   r.room_type, b.rooms, b.guests, b.check_in, b.check_out, b.amount, b.status,
                   b.arrival_time, b.include_transport, b.created_at
            FROM udrive.hotel_bookings b
            JOIN udrive.hotel_rooms r ON r.id = b.room_id
            JOIN udrive.users u ON u.id = b.customer_user_id
            WHERE b.hotel_id = @hotel
              AND b.status NOT IN ('Cancelled', 'NoShow')
              AND b.check_out >= @today
            ORDER BY b.check_in, b.created_at
            LIMIT 200;
            """, connection))
        {
            command.Parameters.AddWithValue("hotel", selected.Id);
            command.Parameters.Add(new NpgsqlParameter("today", NpgsqlDbType.Date) { Value = today });
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                bookings.Add(new HotelOwnerBookingDto(
                    reader.GetGuid(0), reader.GetString(1), reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3),
                    reader.GetString(4), reader.GetInt32(5), reader.GetInt32(6),
                    reader.GetFieldValue<DateOnly>(7), reader.GetFieldValue<DateOnly>(8),
                    reader.GetDecimal(9), reader.GetString(10),
                    reader.IsDBNull(11) ? null : reader.GetFieldValue<TimeOnly>(11).ToString("h:mm tt", System.Globalization.CultureInfo.InvariantCulture),
                    reader.GetBoolean(12),
                    reader.GetFieldValue<DateTimeOffset>(13)));
            }
        }

        decimal month;
        await using (var command = new NpgsqlCommand(
            """
            SELECT COALESCE(sum(b.amount), 0)
            FROM udrive.hotel_bookings b
            WHERE b.hotel_id = @hotel
              AND b.status NOT IN ('Cancelled', 'NoShow')
              AND date_trunc('month', b.check_in) = date_trunc('month', @today::date);
            """, connection))
        {
            command.Parameters.AddWithValue("hotel", selected.Id);
            command.Parameters.Add(new NpgsqlParameter("today", NpgsqlDbType.Date) { Value = today });
            month = Convert.ToDecimal(await command.ExecuteScalarAsync(ct) ?? 0m);
        }

        var since = DateTimeOffset.UtcNow.AddDays(-7);
        var arriving = bookings.Where(b => b.CheckIn == today && b.Status == "Confirmed").ToList();
        var leaving = bookings.Where(b => b.CheckOut == today && b.Status is "Confirmed" or "CheckedIn").ToList();
        var upcoming = bookings.Where(b => b.Status == "Confirmed" && b.CheckIn >= today).ToList();

        return ServiceResult<HotelOwnerDashboardDto>.Ok(new HotelOwnerDashboardDto(
            hotels,
            selected.Id,
            bookings.Count(b => b.CreatedAt >= since),
            rooms.Sum(r => r.FreePerDay.Length > 0 ? r.FreePerDay[0] : 0),
            selected.TotalRooms,
            month,
            upcoming,
            arriving,
            leaving,
            rooms,
            today));
    }

    /// <summary>The guest arrived (CheckedIn) or left (CheckedOut).</summary>
    public async Task<ServiceResult<bool>> SetStatusAsync(
        Guid ownerId, Guid bookingId, string status, CancellationToken ct)
    {
        var (from, to) = status.Trim().ToLowerInvariant() switch
        {
            "checkedin" => ("Confirmed", "CheckedIn"),
            "checkedout" => ("CheckedIn", "CheckedOut"),
            _ => (null as string, null as string),
        };
        if (to is null)
        {
            return ServiceResult<bool>.Fail(
                StatusCodes.Status400BadRequest, "status_invalid", "Status CheckedIn ya CheckedOut ho sakta hai.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        // Leaving without being marked arrived is still leaving.
        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.hotel_bookings b
            SET status = @to, updated_at = now()
            FROM udrive.hotels h
            WHERE b.id = @id AND h.id = b.hotel_id AND h.owner_user_id = @owner
              AND (b.status = @from OR (@to = 'CheckedOut' AND b.status = 'Confirmed'));
            """, connection);
        command.Parameters.AddWithValue("id", bookingId);
        command.Parameters.AddWithValue("owner", ownerId);
        command.Parameters.AddWithValue("from", from!);
        command.Parameters.AddWithValue("to", to);
        return await command.ExecuteNonQueryAsync(ct) == 0
            ? ServiceResult<bool>.Fail(StatusCodes.Status409Conflict, "booking_not_updatable",
                "Yeh booking aap ke hotel ki nahi, ya pehle hi update ho chuki hai.")
            : ServiceResult<bool>.Ok(true, to == "CheckedIn" ? "Guest aa gaye." : "Guest chale gaye — kamra khali.");
    }
}
