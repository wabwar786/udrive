using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Caching.Memory;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>Admin side of the website: the ad places and what came in from the web.</summary>
public sealed class WebsiteAdminService(string connectionString, IMemoryCache cache)
{
    private const string AdColumns = """
        id, slot, title, body, image_url, link_url, cta_label, starts_on, ends_on, is_active, sort_order, clicks,
        (is_active AND (starts_on IS NULL OR starts_on <= (now() AT TIME ZONE 'Asia/Karachi')::date)
                   AND (ends_on IS NULL OR ends_on >= (now() AT TIME ZONE 'Asia/Karachi')::date)),
        updated_at
        """;

    public async Task<ServiceResult<IReadOnlyList<AdminWebAdDto>>> AdsAsync(CancellationToken ct)
    {
        var list = new List<AdminWebAdDto>();
        await using var c = await OpenAsync(ct);
        await using var cmd = new NpgsqlCommand($"SELECT {AdColumns} FROM udrive.web_ads ORDER BY slot, sort_order, created_at DESC;", c);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) list.Add(Ad(r));
        return ServiceResult<IReadOnlyList<AdminWebAdDto>>.Ok(list);
    }

    public async Task<ServiceResult<AdminWebAdDto>> SaveAdAsync(Guid adminId, Guid? id, SaveWebAdRequest x, CancellationToken ct)
    {
        var slot = (x.Slot ?? "").Trim().ToLowerInvariant();
        if (!WebsiteService.AdSlots.Contains(slot)) return Fail(400, "ad_slot", "Jagah chunein: " + string.Join(", ", WebsiteService.AdSlots) + ".");
        var title = WebsiteService.Clean(x.Title, 120) ?? "";
        if (title.Length < 2) return Fail(400, "ad_title", "Ad ka title likhein.");
        var link = (x.LinkUrl ?? "").Trim();
        if (link.Length > 0 && (!Uri.TryCreate(link, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps))
        {
            return Fail(400, "ad_link", "Link https:// se shuru hona chahiye.");
        }

        var image = (x.ImageUrl ?? "").Trim();
        if (image.Length > 0 && !WebsiteService.SafeImage(image, allowHttps: true)) return Fail(400, "ad_image", "Tasveer upload karein ya https link dein.");
        if (x.StartsOn is { } s && x.EndsOn is { } e && e < s) return Fail(400, "ad_dates", "Khatam hone ki tareekh shuru se pehle nahi ho sakti.");

        await using var c = await OpenAsync(ct);
        await using var cmd = new NpgsqlCommand(id is null
            ? $"""
              INSERT INTO udrive.web_ads (slot, title, body, image_url, link_url, cta_label, starts_on, ends_on, is_active, sort_order, created_by)
              VALUES (@slot, @title, @body, @image, @link, @cta, @starts, @ends, @active, @sort, @admin)
              RETURNING {AdColumns};
              """
            : $"""
              UPDATE udrive.web_ads SET slot = @slot, title = @title, body = @body, image_url = @image, link_url = @link,
                     cta_label = @cta, starts_on = @starts, ends_on = @ends, is_active = @active, sort_order = @sort, updated_at = now()
               WHERE id = @id
              RETURNING {AdColumns};
              """, c);
        cmd.Parameters.AddWithValue("slot", slot);
        cmd.Parameters.AddWithValue("title", title);
        cmd.Parameters.AddWithValue("body", WebsiteService.Clean(x.Body, 300) ?? "");
        cmd.Parameters.Add(new NpgsqlParameter("image", NpgsqlDbType.Text) { Value = image.Length == 0 ? DBNull.Value : image });
        cmd.Parameters.Add(new NpgsqlParameter("link", NpgsqlDbType.Text) { Value = link.Length == 0 ? DBNull.Value : link });
        cmd.Parameters.AddWithValue("cta", WebsiteService.Clean(x.CtaLabel, 40) is { Length: > 0 } cta ? cta : "View");
        cmd.Parameters.Add(new NpgsqlParameter("starts", NpgsqlDbType.Date) { Value = x.StartsOn is { } so ? so : DBNull.Value });
        cmd.Parameters.Add(new NpgsqlParameter("ends", NpgsqlDbType.Date) { Value = x.EndsOn is { } eo ? eo : DBNull.Value });
        cmd.Parameters.AddWithValue("active", x.IsActive);
        cmd.Parameters.AddWithValue("sort", Math.Clamp(x.SortOrder, 0, 999));
        cmd.Parameters.AddWithValue("admin", adminId);
        if (id is { } existing) cmd.Parameters.AddWithValue("id", existing);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        if (!await r.ReadAsync(ct)) return Fail(404, "ad_not_found", "Ad nahi mila.");
        var saved = Ad(r);
        Forget(saved.Slot);
        return id is null ? ServiceResult<AdminWebAdDto>.Created(saved, "Ad ban gaya.") : ServiceResult<AdminWebAdDto>.Ok(saved, "Ad save ho gaya.");
    }

    public async Task<ServiceResult<bool>> DeleteAdAsync(Guid id, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        await using var cmd = new NpgsqlCommand("DELETE FROM udrive.web_ads WHERE id = @id RETURNING slot;", c);
        cmd.Parameters.AddWithValue("id", id);
        var slot = await cmd.ExecuteScalarAsync(ct);
        if (slot is null) return ServiceResult<bool>.Fail(404, "ad_not_found", "Ad nahi mila.");
        Forget(slot.ToString()!);
        return ServiceResult<bool>.Ok(true, "Ad hata diya.");
    }

    public async Task<ServiceResult<AdminWebActivityDto>> ActivityAsync(CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        int today = 0, month = 0, hotelsMonth = 0;
        decimal value = 0;
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT count(*) FILTER (WHERE b.created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Karachi') AT TIME ZONE 'Asia/Karachi')::int,
                   count(*) FILTER (WHERE b.created_at >= date_trunc('month', now() AT TIME ZONE 'Asia/Karachi') AT TIME ZONE 'Asia/Karachi')::int,
                   COALESCE(sum(b.total_amount) FILTER (WHERE b.created_at >= date_trunc('month', now() AT TIME ZONE 'Asia/Karachi') AT TIME ZONE 'Asia/Karachi'
                                                     AND b.status <> 'Cancelled'), 0),
                   (SELECT count(*)::int FROM udrive.hotels h WHERE h.source = 'Web'
                      AND h.created_at >= date_trunc('month', now() AT TIME ZONE 'Asia/Karachi') AT TIME ZONE 'Asia/Karachi')
              FROM udrive.bookings b WHERE b.channel = 'Web';
            """, c))
        await using (var r = await cmd.ExecuteReaderAsync(ct))
        {
            if (await r.ReadAsync(ct))
            {
                today = r.GetInt32(0);
                month = r.GetInt32(1);
                value = r.GetDecimal(2);
                hotelsMonth = r.GetInt32(3);
            }
        }

        var bookings = new List<AdminWebBookingDto>();
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT b.id, COALESCE(b.booking_reference, ''), COALESCE(tp.title, ''), COALESCE(tp.departure_at, b.pickup_at),
                   u.full_name, u.phone_number, b.booking_type, b.seats_booked, b.total_amount, COALESCE(b.advance_amount, 0),
                   b.status, COALESCE(du.full_name, ''), b.created_at
              FROM udrive.bookings b
              JOIN udrive.users u ON u.id = b.customer_user_id
              LEFT JOIN udrive.tour_packages tp ON tp.id = b.tour_package_id
              LEFT JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
              LEFT JOIN udrive.users du ON du.id = dp.user_id
             WHERE b.channel = 'Web'
             ORDER BY b.created_at DESC
             LIMIT 200;
            """, c))
        await using (var r = await cmd.ExecuteReaderAsync(ct))
        {
            while (await r.ReadAsync(ct))
            {
                bookings.Add(new AdminWebBookingDto(r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetFieldValue<DateTimeOffset>(3),
                    r.GetString(4), r.GetString(5), r.GetString(6) == "WholeVehicle" ? "Whole vehicle" : "Per seat",
                    r.GetInt32(7), r.GetDecimal(8), r.GetDecimal(9), r.GetString(10), r.GetString(11), r.GetFieldValue<DateTimeOffset>(12)));
            }
        }

        var hotels = new List<AdminWebHotelDto>();
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT h.id, h.name, h.city, u.full_name, u.phone_number, h.approval_status, h.created_at
              FROM udrive.hotels h JOIN udrive.users u ON u.id = h.owner_user_id
             WHERE h.source = 'Web'
             ORDER BY h.created_at DESC LIMIT 100;
            """, c))
        await using (var r = await cmd.ExecuteReaderAsync(ct))
        {
            while (await r.ReadAsync(ct))
            {
                hotels.Add(new AdminWebHotelDto(r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetString(3), r.GetString(4),
                    r.GetString(5), r.GetFieldValue<DateTimeOffset>(6)));
            }
        }

        return ServiceResult<AdminWebActivityDto>.Ok(new AdminWebActivityDto(today, month, value, hotelsMonth, bookings, hotels));
    }

    private void Forget(string slot)
    {
        cache.Remove($"web:ads:{slot}");
        cache.Remove("web:home");
    }

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken ct)
    {
        var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        return c;
    }

    private static AdminWebAdDto Ad(NpgsqlDataReader r) => new(
        r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetString(3),
        r.IsDBNull(4) ? null : r.GetString(4), r.IsDBNull(5) ? null : r.GetString(5), r.GetString(6),
        r.IsDBNull(7) ? null : r.GetFieldValue<DateOnly>(7), r.IsDBNull(8) ? null : r.GetFieldValue<DateOnly>(8),
        r.GetBoolean(9), r.GetInt32(10), r.GetInt32(11), r.GetBoolean(12), r.GetFieldValue<DateTimeOffset>(13));

    private static ServiceResult<AdminWebAdDto> Fail(int status, string code, string message) =>
        ServiceResult<AdminWebAdDto>.Fail(status, code, message);
}
