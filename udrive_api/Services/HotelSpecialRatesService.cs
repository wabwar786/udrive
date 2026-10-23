using Microsoft.AspNetCore.Http;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Hotel "special dates": a different rate (fixed, or ± a percent of the base
/// rate) and optionally fewer rooms open, for a range of days.
/// </summary>
/// <remarks>
/// The ranges live in <c>hotel_special_rates</c>. Search and booking already
/// read a date's rate and open rooms from <c>hotel_room_inventory</c>, so every
/// change rebuilds that hotel's future inventory rows from its ranges (oldest
/// first, so a newer range wins where two overlap). Nothing else writes
/// <c>hotel_room_inventory</c>, which is what makes a full rebuild safe; it
/// also runs after a room's base rate changes, so percent ranges follow it.
///
/// Every statement is scoped to the signed-in owner's own hotel.
/// </remarks>
public sealed class HotelSpecialRatesService(string connectionString)
{
    private static readonly TimeSpan Pk = TimeSpan.FromHours(5);

    public async Task<ServiceResult<IReadOnlyList<SpecialRateDto>>> ListAsync(Guid ownerId, Guid hotelId, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        if (!await OwnsAsync(c, ownerId, hotelId, ct)) return NotFound<IReadOnlyList<SpecialRateDto>>();
        return ServiceResult<IReadOnlyList<SpecialRateDto>>.Ok(await ReadAsync(c, hotelId, ct));
    }

    public async Task<ServiceResult<IReadOnlyList<SpecialRateDto>>> AddAsync(Guid ownerId, Guid hotelId, SaveSpecialRateRequest x, CancellationToken ct)
    {
        var today = Today();
        if (x.StartsOn < today) return Fail(400, "dates_past", "Shuru ki tareekh aaj ya baad ki honi chahiye.");
        if (x.EndsOn < x.StartsOn) return Fail(400, "dates_invalid", "Khatam ki tareekh shuru se pehle nahi ho sakti.");
        if (x.EndsOn.DayNumber - x.StartsOn.DayNumber > 120) return Fail(400, "dates_too_long", "Aik dafa mein zyada se zyada 120 din.");
        if (x.StartsOn.DayNumber - today.DayNumber > 365) return Fail(400, "dates_too_far", "Sirf agle 12 mahine ke liye.");
        if ((x.Rate is null) == (x.Percent is null)) return Fail(400, "rate_required", "Ya to naya rate likhein ya % (dono nahi).");
        if (x.Rate is { } rate && (rate < 1 || rate > 1_000_000)) return Fail(400, "rate_invalid", "Rate 1 se 1,000,000 tak.");
        if (x.Percent is { } pct && (pct < -50 || pct > 200 || pct == 0)) return Fail(400, "percent_invalid", "% -50 se +200 tak (0 nahi).");
        if (x.RoomsOpen is { } open && (open < 0 || open > 500)) return Fail(400, "rooms_invalid", "Rooms 0 se 500 tak.");

        await using var c = await OpenAsync(ct);
        if (!await OwnsAsync(c, ownerId, hotelId, ct)) return NotFound<IReadOnlyList<SpecialRateDto>>();

        if (x.RoomId is { } roomId)
        {
            await using var cmd = new NpgsqlCommand(
                "SELECT total_rooms FROM udrive.hotel_rooms WHERE id = @r AND hotel_id = @h AND is_active;", c);
            cmd.Parameters.AddWithValue("r", roomId);
            cmd.Parameters.AddWithValue("h", hotelId);
            var total = await cmd.ExecuteScalarAsync(ct);
            if (total is null) return Fail(404, "room_not_found", "Room nahi mila.");
            if (x.RoomsOpen is { } openRooms && openRooms > Convert.ToInt32(total)) return Fail(400, "rooms_invalid", "Is room type ke itne rooms nahi.");
        }

        await using (var count = new NpgsqlCommand(
            "SELECT count(*)::int FROM udrive.hotel_special_rates WHERE hotel_id = @h AND ends_on >= @today;", c))
        {
            count.Parameters.AddWithValue("h", hotelId);
            count.Parameters.AddWithValue("today", today);
            if (Convert.ToInt32(await count.ExecuteScalarAsync(ct)) >= 40) return Fail(409, "too_many", "Zyada se zyada 40 special dates. Purani hatayein.");
        }

        await using var tx = await c.BeginTransactionAsync(ct);
        await using (var ins = new NpgsqlCommand(
            """
            INSERT INTO udrive.hotel_special_rates (hotel_id, room_id, starts_on, ends_on, rate, percent, rooms_open)
            VALUES (@h, @r, @s, @e, @rate, @pct, @open);
            """, c, tx))
        {
            ins.Parameters.AddWithValue("h", hotelId);
            ins.Parameters.Add(new NpgsqlParameter("r", NpgsqlDbType.Uuid) { Value = (object?)x.RoomId ?? DBNull.Value });
            ins.Parameters.AddWithValue("s", x.StartsOn);
            ins.Parameters.AddWithValue("e", x.EndsOn);
            ins.Parameters.Add(new NpgsqlParameter("rate", NpgsqlDbType.Numeric) { Value = (object?)x.Rate ?? DBNull.Value });
            ins.Parameters.Add(new NpgsqlParameter("pct", NpgsqlDbType.Integer) { Value = (object?)x.Percent ?? DBNull.Value });
            ins.Parameters.Add(new NpgsqlParameter("open", NpgsqlDbType.Integer) { Value = (object?)x.RoomsOpen ?? DBNull.Value });
            await ins.ExecuteNonQueryAsync(ct);
        }
        await RebuildAsync(c, tx, hotelId, ct);
        await tx.CommitAsync(ct);
        return ServiceResult<IReadOnlyList<SpecialRateDto>>.Ok(await ReadAsync(c, hotelId, ct), "Special dates save ho gayi.");
    }

    public async Task<ServiceResult<IReadOnlyList<SpecialRateDto>>> RemoveAsync(Guid ownerId, Guid hotelId, Guid rateId, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        if (!await OwnsAsync(c, ownerId, hotelId, ct)) return NotFound<IReadOnlyList<SpecialRateDto>>();
        await using var tx = await c.BeginTransactionAsync(ct);
        await using (var del = new NpgsqlCommand("DELETE FROM udrive.hotel_special_rates WHERE id = @id AND hotel_id = @h;", c, tx))
        {
            del.Parameters.AddWithValue("id", rateId);
            del.Parameters.AddWithValue("h", hotelId);
            if (await del.ExecuteNonQueryAsync(ct) == 0) return Fail(404, "not_found", "Nahi mila.");
        }
        await RebuildAsync(c, tx, hotelId, ct);
        await tx.CommitAsync(ct);
        return ServiceResult<IReadOnlyList<SpecialRateDto>>.Ok(await ReadAsync(c, hotelId, ct), "Hata diya.");
    }

    /// <summary>Re-applies the ranges after a base rate changed. Owner-scoped.</summary>
    public async Task RebuildForOwnerAsync(Guid ownerId, Guid hotelId, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        if (!await OwnsAsync(c, ownerId, hotelId, ct)) return;
        await using var tx = await c.BeginTransactionAsync(ct);
        await RebuildAsync(c, tx, hotelId, ct);
        await tx.CommitAsync(ct);
    }

    private static async Task RebuildAsync(NpgsqlConnection c, NpgsqlTransaction tx, Guid hotelId, CancellationToken ct)
    {
        await using (var clear = new NpgsqlCommand(
            """
            DELETE FROM udrive.hotel_room_inventory i
             USING udrive.hotel_rooms r
             WHERE i.room_id = r.id AND r.hotel_id = @h AND i.inventory_date >= @today;
            """, c, tx))
        {
            clear.Parameters.AddWithValue("h", hotelId);
            clear.Parameters.AddWithValue("today", Today());
            await clear.ExecuteNonQueryAsync(ct);
        }

        // Oldest first: a newer range overwrites an older one on shared days.
        await using var apply = new NpgsqlCommand(
            """
            INSERT INTO udrive.hotel_room_inventory (room_id, inventory_date, available_rooms, rate)
            SELECT DISTINCT ON (r.id, d::date)
                   r.id, d::date,
                   LEAST(COALESCE(s.rooms_open, r.total_rooms), r.total_rooms),
                   COALESCE(s.rate, round(r.base_rate * (100 + s.percent) / 100.0, 0))
              FROM udrive.hotel_special_rates s
              JOIN udrive.hotel_rooms r ON r.hotel_id = s.hotel_id AND r.is_active AND (s.room_id IS NULL OR s.room_id = r.id)
              CROSS JOIN LATERAL generate_series(GREATEST(s.starts_on, @today), s.ends_on, interval '1 day') d
             WHERE s.hotel_id = @h AND s.ends_on >= @today
             ORDER BY r.id, d::date, s.created_at DESC
            ON CONFLICT (room_id, inventory_date) DO UPDATE
               SET available_rooms = EXCLUDED.available_rooms, rate = EXCLUDED.rate;
            """, c, tx);
        apply.Parameters.AddWithValue("h", hotelId);
        apply.Parameters.AddWithValue("today", Today());
        await apply.ExecuteNonQueryAsync(ct);
    }

    private static async Task<IReadOnlyList<SpecialRateDto>> ReadAsync(NpgsqlConnection c, Guid hotelId, CancellationToken ct)
    {
        var list = new List<SpecialRateDto>();
        await using var cmd = new NpgsqlCommand(
            """
            SELECT s.id, s.room_id, COALESCE(r.room_type, 'All rooms'), s.starts_on, s.ends_on, s.rate, s.percent, s.rooms_open
              FROM udrive.hotel_special_rates s
              LEFT JOIN udrive.hotel_rooms r ON r.id = s.room_id
             WHERE s.hotel_id = @h AND s.ends_on >= @today
             ORDER BY s.starts_on, s.created_at;
            """, c);
        cmd.Parameters.AddWithValue("h", hotelId);
        cmd.Parameters.AddWithValue("today", Today());
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
        {
            list.Add(new SpecialRateDto(r.GetGuid(0), r.IsDBNull(1) ? null : r.GetGuid(1), r.GetString(2),
                r.GetFieldValue<DateOnly>(3), r.GetFieldValue<DateOnly>(4),
                r.IsDBNull(5) ? null : r.GetDecimal(5), r.IsDBNull(6) ? null : r.GetInt32(6), r.IsDBNull(7) ? null : r.GetInt32(7)));
        }
        return list;
    }

    private static async Task<bool> OwnsAsync(NpgsqlConnection c, Guid ownerId, Guid hotelId, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand("SELECT 1 FROM udrive.hotels WHERE id = @h AND owner_user_id = @u;", c);
        cmd.Parameters.AddWithValue("h", hotelId);
        cmd.Parameters.AddWithValue("u", ownerId);
        return await cmd.ExecuteScalarAsync(ct) is not null;
    }

    private static DateOnly Today() => DateOnly.FromDateTime(DateTime.UtcNow.Add(Pk));

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken ct)
    {
        var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        return c;
    }

    private static ServiceResult<IReadOnlyList<SpecialRateDto>> Fail(int status, string code, string message) =>
        ServiceResult<IReadOnlyList<SpecialRateDto>>.Fail(status, code, message);

    private static ServiceResult<T> NotFound<T>() =>
        ServiceResult<T>.Fail(StatusCodes.Status404NotFound, "hotel_not_found", "Hotel nahi mila.");
}
