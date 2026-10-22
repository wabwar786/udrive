using System.Globalization;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Caching.Memory;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Domain.Enums;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Everything the public website ("UDrive – Travel &amp; Tour") reads, and the one
/// thing it writes: a tour booking.
/// </summary>
/// <remarks>
/// The website is static files on its own host. It holds no secret and never
/// connects to the database; it only calls <c>/api/v1/web/*</c>.
///
/// Security rules this class keeps:
/// <list type="bullet">
/// <item>Reads are shaped for strangers: a driver's first name and rating only;
/// never a phone, CNIC, registration number, live location or owner detail.
/// Demo and self-test listings are left out.</item>
/// <item>Visibility is the app's own: a tour is listed only when the app's
/// public package query lists it (Active, future, seats not held, vehicle not
/// on hold or rented); a hotel only when approved, active, not on hold and its
/// wallet holds the minimum.</item>
/// <item>A booking needs a signed-in customer (WhatsApp OTP). The amount, the
/// seats and the 20% advance are worked out here from the database; nothing
/// the browser sends about money is used.</item>
/// <item>Answers are cached for a short time so a burst of visitors (or a
/// scraper) does not become a burst of queries.</item>
/// </list>
/// </remarks>
public sealed class WebsiteService(
    string connectionString,
    PackageMarketplaceService packages,
    Phase18TourService tourContent,
    IMemoryCache cache)
{
    public const decimal AdvancePercent = 20m;
    public const int MaxOpenWebBookings = 3;
    private static readonly TimeSpan Pk = TimeSpan.FromHours(5);
    private static readonly TimeSpan Short = TimeSpan.FromSeconds(45);
    private static readonly TimeSpan Medium = TimeSpan.FromMinutes(5);
    public static readonly string[] AdSlots = ["home", "tours", "tour", "hotels", "hotel"];

    // ──────────────────────────────────────────────────────────────── home

    public async Task<ServiceResult<WebHomeDto>> HomeAsync(CancellationToken ct)
    {
        var home = await cache.GetOrCreateAsync("web:home", async e =>
        {
            e.AbsoluteExpirationRelativeToNow = Short;
            var tours = await UpcomingToursAsync(ct);
            var hotels = await HotelsAsync(null, 0, 6, ct);
            var destinations = await DestinationsCachedAsync(ct);
            var ads = await AdsAsync("home", ct);
            return new WebHomeDto(await StatsAsync(tours, ct), tours.Take(8).ToList(), hotels, destinations, ads);
        });
        return ServiceResult<WebHomeDto>.Ok(home!);
    }

    // ─────────────────────────────────────────────────────────────── tours

    /// <param name="days">"1", "2-3" or "4+".</param>
    /// <param name="mode">"seat" or "whole".</param>
    public async Task<ServiceResult<WebPageDto<WebTourCardDto>>> ToursAsync(
        string? destination, string? days, string? mode, DateOnly? date, int page, CancellationToken ct)
    {
        page = Math.Clamp(page, 1, 50);
        const int size = 12;
        IEnumerable<WebTourCardDto> list = await UpcomingToursAsync(ct);

        if (!string.IsNullOrWhiteSpace(destination))
        {
            list = list.Where(t => string.Equals(t.DestinationSlug, destination.Trim(), StringComparison.OrdinalIgnoreCase));
        }

        list = (days ?? "").Trim() switch
        {
            "1" => list.Where(t => t.Days <= 1),
            "2-3" => list.Where(t => t.Days is >= 2 and <= 3),
            "4+" => list.Where(t => t.Days >= 4),
            _ => list,
        };

        list = (mode ?? "").Trim().ToLowerInvariant() switch
        {
            "seat" => list.Where(t => t.PricePerSeat > 0 && t.SeatsLeft > 0),
            "whole" => list.Where(t => t.WholeVehicleAvailable),
            _ => list,
        };

        if (date is { } d)
        {
            list = list.Where(t => DateOnly.FromDateTime(t.DepartureAt.ToOffset(Pk).DateTime) == d);
        }

        var all = list.ToList();
        var items = all.Skip((page - 1) * size).Take(size).ToList();
        return ServiceResult<WebPageDto<WebTourCardDto>>.Ok(new WebPageDto<WebTourCardDto>(items, page, all.Count > page * size));
    }

    public async Task<ServiceResult<WebTourDetailDto>> TourAsync(Guid id, CancellationToken ct)
    {
        // Misses are not cached: random ids must not fill the cache.
        if (!cache.TryGetValue($"web:tour:{id}", out WebTourDetailDto? detail))
        {
            detail = await LoadTourAsync(id, ct);
            if (detail is not null) cache.Set($"web:tour:{id}", detail, TimeSpan.FromSeconds(20));
        }

        return detail is null
            ? ServiceResult<WebTourDetailDto>.Fail(StatusCodes.Status404NotFound, "tour_not_found", "This tour is full, finished or no longer listed.")
            : ServiceResult<WebTourDetailDto>.Ok(detail);
    }

    private async Task<WebTourDetailDto?> LoadTourAsync(Guid id, CancellationToken ct)
    {
        {
            var found = await packages.GetPublicPackageAsync(id, ct);
            if (!found.Success || found.Data is null || found.Data.IsDemo) return null;
            var p = found.Data;

            var slugs = await DestinationSlugsAsync(ct);
            var toursDone = await ToursDoneAsync([p.DriverProfileId], ct);
            var card = Card(p, slugs, toursDone);

            var plan = new List<WebItineraryDayDto>();
            var images = new List<string>();
            var content = await tourContent.GetContentAsync(id, ct);
            if (content.Success && content.Data is not null)
            {
                plan.AddRange(content.Data.Itinerary
                    .OrderBy(x => x.DayNumber)
                    .Select(x => new WebItineraryDayDto(x.DayNumber, Clean(x.Title, 120),
                        Clean(string.Join(" ", new[] { x.Location, x.Activity, x.Notes }.Where(s => !string.IsNullOrWhiteSpace(s))), 600))));
                images.AddRange(content.Data.Images.OrderByDescending(x => x.IsCover).ThenBy(x => x.SortOrder).Select(x => x.ImageUrl).Where(u => SafeImage(u)));
            }

            if (plan.Count == 0)
            {
                plan.AddRange(p.Itinerary.Where(s => !string.IsNullOrWhiteSpace(s)).Select((s, i) => new WebItineraryDayDto(i + 1, $"Day {i + 1}", Clean(s, 600))));
            }

            if (images.Count == 0 && card.ImageUrl is not null) images.Add(card.ImageUrl);

            return new WebTourDetailDto(
                card,
                Clean(p.Description, 2000),
                p.RouteStops.Select(s => Clean(s, 80)!).Where(s => s.Length > 0).ToList(),
                p.Inclusions.Select(s => Clean(s, 120)!).Where(s => s.Length > 0).ToList(),
                p.Exclusions.Select(s => Clean(s, 120)!).Where(s => s.Length > 0).ToList(),
                plan,
                images.Distinct().Take(10).ToList(),
                Clean(p.CancellationPolicy, 600),
                p.PassengerPolicy,
                Clean(p.LuggageAllowance, 200),
                p.FamilyOnly,
                p.WomenOnly,
                AdvancePercent);
        }
    }

    /// <summary>Holds the seats and confirms the booking, with a 20% advance worked out here.</summary>
    /// <remarks>
    /// Same two steps the app takes (hold, then confirm), so seat counting,
    /// the driver's notification and both WhatsApp messages behave exactly as
    /// for an app booking. The advance is recorded on the booking; it is paid
    /// to the driver when he confirms, as with app bookings.
    /// </remarks>
    public async Task<ServiceResult<WebTourBookingDto>> BookTourAsync(
        Guid customerUserId, Guid packageId, WebTourBookingRequest request, CancellationToken ct)
    {
        var mode = (request.Mode ?? "").Trim().ToLowerInvariant() switch
        {
            "seat" or "perseat" => (BookingType?)BookingType.PerSeat,
            "whole" or "wholevehicle" => BookingType.WholeVehicle,
            _ => null,
        };
        if (mode is null) return BookFail(400, "mode_invalid", "Per seat ya whole vehicle chunein.");

        var name = Clean(request.FullName, 160) ?? "";
        if (name.Length < 2) return BookFail(400, "name_required", "Apna naam likhein.");

        var tour = await packages.GetPublicPackageAsync(packageId, ct);
        if (!tour.Success || tour.Data is null || tour.Data.IsDemo)
        {
            return BookFail(404, "tour_not_found", "Yeh tour ab available nahi.");
        }

        // A booking is confirmed before any money moves, so one number must not
        // be able to block a whole week of departures: at most a few upcoming
        // web bookings per customer, and one per departure.
        await using (var c = new NpgsqlConnection(connectionString))
        {
            await c.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand(
                """
                SELECT count(*)::int,
                       count(*) FILTER (WHERE b.tour_package_id = @p)::int
                  FROM udrive.bookings b
                  JOIN udrive.tour_packages tp ON tp.id = b.tour_package_id
                 WHERE b.customer_user_id = @u AND b.channel = 'Web'
                   AND b.status NOT IN ('Cancelled', 'Completed', 'NoShow')
                   AND tp.departure_at > now();
                """, c);
            cmd.Parameters.AddWithValue("u", customerUserId);
            cmd.Parameters.AddWithValue("p", packageId);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            if (await r.ReadAsync(ct))
            {
                if (r.GetInt32(1) > 0) return BookFail(409, "already_booked", "Aap is tour par pehle se booking kar chuke hain. Tabdeeli ke liye driver ya UDrive se WhatsApp par baat karein.");
                if (r.GetInt32(0) >= MaxOpenWebBookings) return BookFail(409, "too_many_bookings", "Aap ki pehle se " + MaxOpenWebBookings + " bookings chal rahi hain. Mazeed ke liye UDrive app istemal karein.");
            }
        }

        var seats = mode == BookingType.WholeVehicle ? tour.Data.TotalSeats : Math.Clamp(request.Seats, 1, 60);
        if (mode == BookingType.PerSeat && tour.Data.PricePerSeat <= 0)
        {
            return BookFail(409, "seat_not_sold", "Is tour par sirf poori gaari book hoti hai.");
        }

        var hold = await packages.AcquireHoldAsync(customerUserId, packageId, new AcquirePackageHoldRequest(mode.Value, seats), ct);
        if (!hold.Success || hold.Data is null)
        {
            return BookFail(hold.StatusCode, hold.ErrorCode ?? "hold_failed", hold.Message ?? "Seats hold nahi ho sakin. Dobara koshish karein.");
        }

        var total = hold.Data.QuotedAmount;
        var advance = Math.Ceiling(total * AdvancePercent / 100m);
        var confirmed = await packages.ConfirmHoldAsync(customerUserId, packageId,
            new ConfirmPackageBookingRequest(hold.Data.HoldId, advance,
                [new PassengerRequest(name, null, "Adult", null, true)]), ct);
        if (!confirmed.Success || confirmed.Data is null)
        {
            return BookFail(confirmed.StatusCode, confirmed.ErrorCode ?? "booking_failed", confirmed.Message ?? "Booking nahi hui. Dobara koshish karein.");
        }

        var b = confirmed.Data;
        await using (var c = new NpgsqlConnection(connectionString))
        {
            await c.OpenAsync(ct);
            await using var mark = new NpgsqlCommand("UPDATE udrive.bookings SET channel = 'Web' WHERE id = @id;", c);
            mark.Parameters.AddWithValue("id", b.Id);
            await mark.ExecuteNonQueryAsync(ct);
        }

        cache.Remove("web:home");
        cache.Remove("web:upcoming");
        cache.Remove($"web:tour:{packageId}");

        return ServiceResult<WebTourBookingDto>.Created(new WebTourBookingDto(
            b.BookingReference,
            tour.Data.Title,
            b.PickupAt,
            tour.Data.PickupPoint,
            mode == BookingType.WholeVehicle ? "Whole vehicle" : "Per seat",
            b.SeatsBooked,
            b.TotalAmount,
            b.AdvanceAmount,
            b.RemainingAmount,
            FirstName(tour.Data.DriverName)), "Booking ho gayi. Driver WhatsApp par confirm karega.");
    }

    // ──────────────────────────────────────────────────────── destinations

    public async Task<ServiceResult<IReadOnlyList<WebDestinationDto>>> DestinationsAsync(CancellationToken ct) =>
        ServiceResult<IReadOnlyList<WebDestinationDto>>.Ok(await DestinationsCachedAsync(ct));

    private async Task<IReadOnlyList<WebDestinationDto>> DestinationsCachedAsync(CancellationToken ct) =>
        (await cache.GetOrCreateAsync("web:destinations", async e =>
        {
            e.AbsoluteExpirationRelativeToNow = Medium;
            var list = new List<WebDestinationDto>();
            await using var c = new NpgsqlConnection(connectionString);
            await c.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand(
                """
                SELECT d.id, d.slug, d.name_en, d.district, d.summary_en, d.best_season, NULLIF(d.cover_image_url, ''),
                       (SELECT count(*)::int FROM udrive.tour_packages tp
                         WHERE tp.destination_id = d.id AND tp.status = 'Active' AND tp.departure_at > now())
                  FROM udrive.destinations d
                 WHERE d.is_active
                 ORDER BY 8 DESC, d.name_en
                 LIMIT 60;
                """, c);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                list.Add(new WebDestinationDto(r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetString(3),
                    Clean(r.GetString(4), 600) ?? "", r.GetString(5), r.IsDBNull(6) || !SafeImage(r.GetString(6), allowHttps: true) ? null : r.GetString(6), r.GetInt32(7)));
            }
            return (IReadOnlyList<WebDestinationDto>)list;
        }))!;

    // ────────────────────────────────────────────────────────────── hotels

    public async Task<ServiceResult<WebPageDto<WebHotelCardDto>>> HotelsPageAsync(string? city, int page, CancellationToken ct)
    {
        page = Math.Clamp(page, 1, 50);
        const int size = 12;
        var items = await HotelsAsync(city, (page - 1) * size, size + 1, ct);
        return ServiceResult<WebPageDto<WebHotelCardDto>>.Ok(
            new WebPageDto<WebHotelCardDto>(items.Take(size).ToList(), page, items.Count > size));
    }

    // The app's own visibility rule (HotelService.SearchAsync), minus demo and
    // self-test owners, which are never shown to the public.
    private const string HotelVisible = """
        lower(h.approval_status) = 'approved' AND h.is_active
        AND NOT EXISTS (SELECT 1 FROM udrive.listing_holds lh WHERE lh.kind = 'hotels' AND lh.entity_id = h.id AND lh.released_at IS NULL)
        AND COALESCE((SELECT hw.balance FROM udrive.hotel_wallets hw WHERE hw.owner_user_id = h.owner_user_id), 0)
            >= COALESCE((SELECT (ss.value_json #>> '{}')::numeric FROM udrive.system_settings ss WHERE ss.key = 'hotel.wallet.minimum_balance'), 0)
        AND NOT EXISTS (SELECT 1 FROM udrive.users o WHERE o.id = h.owner_user_id
                         AND (o.email LIKE 'demo.%@udrive.local' OR o.email LIKE 'selftest.%@udrive.local'))
        """;

    private const string HotelCardColumns = """
        h.id, h.name, COALESCE(NULLIF(h.property_type, ''), 'Hotel'), h.city, h.district, h.rating,
        COALESCE((SELECT min(r.base_rate) FROM udrive.hotel_rooms r WHERE r.hotel_id = h.id AND r.is_active), 0),
        COALESCE((SELECT p.url FROM udrive.hotel_photos p WHERE p.hotel_id = h.id ORDER BY p.sort_order, p.created_at LIMIT 1),
                 NULLIF(h.main_image_url, ''))
        """;

    private async Task<List<WebHotelCardDto>> HotelsAsync(string? city, int offset, int limit, CancellationToken ct)
    {
        var list = new List<WebHotelCardDto>();
        await using var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        await using var cmd = new NpgsqlCommand(
            $"""
            SELECT {HotelCardColumns}
              FROM udrive.hotels h
             WHERE {HotelVisible}
               AND (@city = '' OR h.city ILIKE '%' || @city || '%' OR h.district ILIKE '%' || @city || '%')
             ORDER BY h.rating DESC, h.created_at DESC
             LIMIT @limit OFFSET @offset;
            """, c);
        cmd.Parameters.AddWithValue("city", (Clean(city, 60) ?? "").Replace("%", "").Replace("_", ""));
        cmd.Parameters.AddWithValue("limit", limit);
        cmd.Parameters.AddWithValue("offset", offset);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) list.Add(HotelCard(r));
        return list;
    }

    public async Task<ServiceResult<WebHotelDetailDto>> HotelAsync(Guid id, CancellationToken ct)
    {
        if (!cache.TryGetValue($"web:hotel:{id}", out WebHotelDetailDto? detail))
        {
            detail = await LoadHotelAsync(id, ct);
            if (detail is not null) cache.Set($"web:hotel:{id}", detail, Short);
        }

        return detail is null
            ? ServiceResult<WebHotelDetailDto>.Fail(StatusCodes.Status404NotFound, "hotel_not_found", "This hotel is not listed right now.")
            : ServiceResult<WebHotelDetailDto>.Ok(detail);
    }

    private async Task<WebHotelDetailDto?> LoadHotelAsync(Guid id, CancellationToken ct)
    {
        {
            await using var c = new NpgsqlConnection(connectionString);
            await c.OpenAsync(ct);

            WebHotelCardDto? card = null;
            string description = "", address = "";
            double? lat = null, lng = null;
            string[] amenities = [];
            string? checkIn = null, checkOut = null;
            var transport = false;
            await using (var cmd = new NpgsqlCommand(
                $"""
                SELECT {HotelCardColumns}, h.description, h.address, h.latitude, h.longitude, h.amenities::text,
                       h.check_in_time::text, h.check_out_time::text, h.transport_available
                  FROM udrive.hotels h
                 WHERE h.id = @id AND {HotelVisible};
                """, c))
            {
                cmd.Parameters.AddWithValue("id", id);
                await using var r = await cmd.ExecuteReaderAsync(ct);
                if (await r.ReadAsync(ct))
                {
                    card = HotelCard(r);
                    description = Clean(r.GetString(8), 3000) ?? "";
                    address = Clean(r.GetString(9), 300) ?? "";
                    lat = r.IsDBNull(10) ? null : Math.Round(r.GetDouble(10), 4);
                    lng = r.IsDBNull(11) ? null : Math.Round(r.GetDouble(11), 4);
                    amenities = ParseStrings(r.IsDBNull(12) ? null : r.GetString(12));
                    checkIn = r.IsDBNull(13) ? null : r.GetString(13)[..Math.Min(5, r.GetString(13).Length)];
                    checkOut = r.IsDBNull(14) ? null : r.GetString(14)[..Math.Min(5, r.GetString(14).Length)];
                    transport = r.GetBoolean(15);
                }
            }

            if (card is null) return null;

            var photos = new List<string>();
            await using (var cmd = new NpgsqlCommand(
                "SELECT url FROM udrive.hotel_photos WHERE hotel_id = @id ORDER BY sort_order, created_at LIMIT 12;", c))
            {
                cmd.Parameters.AddWithValue("id", id);
                await using var r = await cmd.ExecuteReaderAsync(ct);
                while (await r.ReadAsync(ct))
                {
                    var url = r.GetString(0);
                    if (SafeImage(url)) photos.Add(url);
                }
            }

            if (photos.Count == 0 && card.ImageUrl is not null) photos.Add(card.ImageUrl);

            var rooms = new List<WebHotelRoomDto>();
            await using (var cmd = new NpgsqlCommand(
                """
                SELECT room_type, description, capacity, base_rate, NULLIF(image_url, '')
                  FROM udrive.hotel_rooms WHERE hotel_id = @id AND is_active ORDER BY base_rate LIMIT 20;
                """, c))
            {
                cmd.Parameters.AddWithValue("id", id);
                await using var r = await cmd.ExecuteReaderAsync(ct);
                while (await r.ReadAsync(ct))
                {
                    var img = r.IsDBNull(4) ? null : r.GetString(4);
                    rooms.Add(new WebHotelRoomDto(Clean(r.GetString(0), 80) ?? "", Clean(r.GetString(1), 400) ?? "",
                        r.GetInt32(2), r.GetDecimal(3), SafeImage(img) ? img : null));
                }
            }

            return new WebHotelDetailDto(card, description, address, lat, lng, amenities, checkIn, checkOut, transport, photos, rooms);
        }
    }

    /// <summary>A hotel by its website address (name + first 8 characters of its id).</summary>
    public async Task<ServiceResult<WebHotelDetailDto>> HotelBySlugAsync(string slug, CancellationToken ct)
    {
        var clean = (slug ?? "").Trim().ToLowerInvariant();
        var dash = clean.LastIndexOf('-');
        var prefix = dash >= 0 ? clean[(dash + 1)..] : "";
        if (prefix.Length != 8 || !prefix.All(Uri.IsHexDigit))
        {
            return ServiceResult<WebHotelDetailDto>.Fail(StatusCodes.Status404NotFound, "hotel_not_found", "This hotel is not listed right now.");
        }

        var ids = new List<Guid>();
        await using (var c = new NpgsqlConnection(connectionString))
        {
            await c.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand(
                "SELECT id FROM udrive.hotels WHERE left(replace(id::text, '-', ''), 8) = @p LIMIT 5;", c);
            cmd.Parameters.AddWithValue("p", prefix);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct)) ids.Add(r.GetGuid(0));
        }

        foreach (var id in ids)
        {
            var hotel = await HotelAsync(id, ct);
            if (hotel.Success && hotel.Data!.Hotel.Slug == clean) return hotel;
        }

        return ServiceResult<WebHotelDetailDto>.Fail(StatusCodes.Status404NotFound, "hotel_not_found", "This hotel is not listed right now.");
    }

    /// <summary>Marks a hotel the signed-in owner just created from the website.</summary>
    public async Task<ServiceResult<bool>> MarkHotelFromWebAsync(Guid ownerId, Guid hotelId, CancellationToken ct)
    {
        await using var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        await using var cmd = new NpgsqlCommand(
            """
            UPDATE udrive.hotels SET source = 'Web'
             WHERE id = @id AND owner_user_id = @u AND created_at > now() - interval '2 days';
            """, c);
        cmd.Parameters.AddWithValue("id", hotelId);
        cmd.Parameters.AddWithValue("u", ownerId);
        var n = await cmd.ExecuteNonQueryAsync(ct);
        return n == 0
            ? ServiceResult<bool>.Fail(StatusCodes.Status404NotFound, "hotel_not_found", "Hotel not found.")
            : ServiceResult<bool>.Ok(true);
    }

    // ─────────────────────────────────────────────────────────────── ads

    public async Task<ServiceResult<IReadOnlyList<WebAdDto>>> AdsForSlotAsync(string slot, CancellationToken ct)
    {
        if (!AdSlots.Contains(slot)) return ServiceResult<IReadOnlyList<WebAdDto>>.Ok([]);
        return ServiceResult<IReadOnlyList<WebAdDto>>.Ok(await AdsAsync(slot, ct));
    }

    private async Task<IReadOnlyList<WebAdDto>> AdsAsync(string slot, CancellationToken ct) =>
        (await cache.GetOrCreateAsync($"web:ads:{slot}", async e =>
        {
            e.AbsoluteExpirationRelativeToNow = Short;
            var list = new List<WebAdDto>();
            await using var c = new NpgsqlConnection(connectionString);
            await c.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand(
                """
                SELECT id, slot, title, body, image_url, link_url, cta_label
                  FROM udrive.web_ads
                 WHERE is_active AND slot = @slot
                   AND (starts_on IS NULL OR starts_on <= (now() AT TIME ZONE 'Asia/Karachi')::date)
                   AND (ends_on IS NULL OR ends_on >= (now() AT TIME ZONE 'Asia/Karachi')::date)
                 ORDER BY sort_order, created_at DESC
                 LIMIT 4;
                """, c);
            cmd.Parameters.AddWithValue("slot", slot);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                var adImage = r.IsDBNull(4) ? null : r.GetString(4);
                list.Add(new WebAdDto(r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetString(3),
                    SafeImage(adImage, allowHttps: true) ? adImage : null, r.IsDBNull(5) ? null : r.GetString(5), r.GetString(6)));
            }
            return (IReadOnlyList<WebAdDto>)list;
        }))!;

    public async Task<ServiceResult<bool>> AdClickAsync(Guid id, CancellationToken ct)
    {
        await using var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        await using var cmd = new NpgsqlCommand("UPDATE udrive.web_ads SET clicks = clicks + 1 WHERE id = @id AND is_active;", c);
        cmd.Parameters.AddWithValue("id", id);
        await cmd.ExecuteNonQueryAsync(ct);
        return ServiceResult<bool>.Ok(true);
    }

    // ──────────────────────────────────────────────────────────── sitemap

    /// <summary>Destinations and hotels for the static build and sitemap.xml.</summary>
    public async Task<ServiceResult<WebSitemapDto>> SitemapAsync(CancellationToken ct)
    {
        var data = await cache.GetOrCreateAsync("web:sitemap", async e =>
        {
            e.AbsoluteExpirationRelativeToNow = Medium;
            return new WebSitemapDto(await DestinationsCachedAsync(ct), await HotelsAsync(null, 0, 500, ct), DateTimeOffset.UtcNow);
        });
        return ServiceResult<WebSitemapDto>.Ok(data!);
    }

    // ─────────────────────────────────────────────────────────── internals

    private async Task<List<WebTourCardDto>> UpcomingToursAsync(CancellationToken ct) =>
        (await cache.GetOrCreateAsync("web:upcoming", async e =>
        {
            e.AbsoluteExpirationRelativeToNow = Short;
            var now = DateTimeOffset.UtcNow;
            var result = await packages.GetPublicPackagesAsync(null, now, null, ct, now.AddDays(90));
            var rows = (result.Data ?? []).Where(p => !p.IsDemo).ToList();
            var slugs = await DestinationSlugsAsync(ct);
            var done = await ToursDoneAsync(rows.Select(p => p.DriverProfileId).Distinct().ToList(), ct);
            return rows.Select(p => Card(p, slugs, done))
                .Where(t => t.SeatsLeft > 0 || t.WholeVehicleAvailable)
                .OrderBy(t => t.DepartureAt)
                .ToList();
        }))!;

    private async Task<WebStatsDto> StatsAsync(IReadOnlyList<WebTourCardDto> tours, CancellationToken ct)
    {
        var todayPk = DateOnly.FromDateTime(DateTimeOffset.UtcNow.ToOffset(Pk).DateTime);
        var today = tours.Count(t => DateOnly.FromDateTime(t.DepartureAt.ToOffset(Pk).DateTime) == todayPk);
        var week = tours.Count(t => t.DepartureAt < DateTimeOffset.UtcNow.AddDays(7));

        await using var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        await using var cmd = new NpgsqlCommand(
            $"""
            SELECT (SELECT count(*)::int FROM udrive.driver_profiles dp JOIN udrive.users u ON u.id = dp.user_id
                     WHERE dp.verification_status = 'Approved' AND u.status <> 'Deleted'
                       AND (u.email IS NULL OR u.email NOT LIKE '%@udrive.local')),
                   (SELECT count(*)::int FROM udrive.hotels h WHERE {HotelVisible});
            """, c);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        var drivers = 0;
        var hotels = 0;
        if (await r.ReadAsync(ct))
        {
            drivers = r.GetInt32(0);
            hotels = r.GetInt32(1);
        }

        return new WebStatsDto(today, week, drivers, hotels);
    }

    // Every destination, not only the active ones listed on the site: a tour
    // can still point at a destination an admin has since hidden.
    private async Task<Dictionary<Guid, string>> DestinationSlugsAsync(CancellationToken ct) =>
        (await cache.GetOrCreateAsync("web:slugs", async e =>
        {
            e.AbsoluteExpirationRelativeToNow = Medium;
            var map = new Dictionary<Guid, string>();
            await using var c = new NpgsqlConnection(connectionString);
            await c.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand("SELECT id, slug FROM udrive.destinations;", c);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct)) map[r.GetGuid(0)] = r.GetString(1);
            return map;
        }))!;

    private async Task<Dictionary<Guid, int>> ToursDoneAsync(IReadOnlyList<Guid> driverProfileIds, CancellationToken ct)
    {
        var map = new Dictionary<Guid, int>();
        if (driverProfileIds.Count == 0) return map;
        await using var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        await using var cmd = new NpgsqlCommand(
            """
            SELECT tp.driver_profile_id, count(DISTINCT tp.id)::int
              FROM udrive.tour_packages tp
              JOIN udrive.package_bookings pb ON pb.tour_package_id = tp.id
             WHERE tp.driver_profile_id = ANY(@ids) AND tp.departure_at < now()
             GROUP BY tp.driver_profile_id;
            """, c);
        cmd.Parameters.AddWithValue("ids", driverProfileIds.ToArray());
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) map[r.GetGuid(0)] = r.GetInt32(1);
        return map;
    }

    private static WebTourCardDto Card(TourPackageLiveDto p, IReadOnlyDictionary<Guid, string> slugs, IReadOnlyDictionary<Guid, int> done)
    {
        var seatsLeft = Math.Max(0, p.AvailableSeats - p.HeldSeats);
        var days = p.ReturnAt is { } back
            ? Math.Max(1, (int)Math.Ceiling((back - p.DepartureAt).TotalHours / 24.0))
            : Math.Max(1, p.Itinerary.Count);
        var image = SafeImage(p.CoverImageUrl) ? p.CoverImageUrl : null;
        return new WebTourCardDto(
            p.Id,
            Clean(p.Title, 200) ?? "",
            p.Destination,
            slugs.TryGetValue(p.DestinationId, out var slug) ? slug : "",
            Clean(p.StartingCity, 120) ?? "",
            Clean(p.PickupPoint, 200),
            p.DepartureAt,
            p.ReturnAt,
            days,
            p.TotalSeats,
            seatsLeft,
            p.PricePerSeat,
            p.WholeVehiclePrice,
            p.WholeVehiclePrice > 0 && seatsLeft == p.TotalSeats,
            Clean(p.Vehicle, 120) ?? "",
            image,
            new WebDriverDto(FirstName(p.DriverName), Initials(p.DriverName), Math.Round(p.DriverRating, 1),
                done.TryGetValue(p.DriverProfileId, out var n) ? n : 0));
    }

    private static WebHotelCardDto HotelCard(NpgsqlDataReader r)
    {
        var id = r.GetGuid(0);
        var name = Clean(r.GetString(1), 160) ?? "";
        var img = r.IsDBNull(7) ? null : r.GetString(7);
        return new WebHotelCardDto(id, Slug(name) + "-" + id.ToString("N")[..8], name, r.GetString(2),
            r.GetString(3), r.GetString(4), Math.Round(r.GetDecimal(5), 1), r.GetDecimal(6), SafeImage(img) ? img : null);
    }

    private static readonly string[] OwnImageRoutes =
    [
        "/api/v1/hotel-images/", "/api/v1/vehicle-images/", "/api/v1/web-images/", "/api/v1/catalog/destination-images/",
    ];

    /// <summary>
    /// Pictures a stranger's browser may load. Owner- and driver-supplied
    /// pictures must be on one of our own public image routes (so nobody can
    /// make every visitor call their server); <paramref name="allowHttps"/> is
    /// only for admin-set pictures (destinations, ads).
    /// </summary>
    internal static bool SafeImage(string? url, bool allowHttps = false)
    {
        if (string.IsNullOrWhiteSpace(url)) return false;
        if (url.Contains("..", StringComparison.Ordinal) || url.Contains('\\') || url.Any(char.IsWhiteSpace)) return false;
        if (url.StartsWith('/'))
        {
            return !url.Contains('%') && OwnImageRoutes.Any(r => url.StartsWith(r, StringComparison.Ordinal));
        }
        return allowHttps && Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps;
    }

    internal static string FirstName(string? fullName)
    {
        var parts = (fullName ?? "").Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0) return "UDrive driver";
        return parts.Length == 1 ? parts[0] : $"{parts[0]} {char.ToUpperInvariant(parts[1][0])}.";
    }

    private static string Initials(string? fullName)
    {
        var parts = (fullName ?? "").Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length switch
        {
            0 => "UD",
            1 => parts[0][..1].ToUpperInvariant(),
            _ => (parts[0][..1] + parts[1][..1]).ToUpperInvariant(),
        };
    }

    internal static string Slug(string text)
    {
        var sb = new StringBuilder();
        foreach (var ch in text.ToLowerInvariant())
        {
            if (ch is >= 'a' and <= 'z' or >= '0' and <= '9') sb.Append(ch);
            else if (sb.Length > 0 && sb[^1] != '-') sb.Append('-');
        }
        var slug = sb.ToString().Trim('-');
        return slug.Length == 0 ? "hotel" : slug[..Math.Min(60, slug.Length)];
    }

    /// <summary>Trims, removes control characters and caps the length.</summary>
    internal static string? Clean(string? text, int max)
    {
        if (text is null) return null;
        var sb = new StringBuilder(Math.Min(text.Length, max));
        foreach (var ch in text)
        {
            if (char.IsControl(ch) && ch != '\n') continue;
            sb.Append(ch);
            if (sb.Length >= max) break;
        }
        return sb.ToString().Trim();
    }

    private static string[] ParseStrings(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            return (JsonSerializer.Deserialize<string[]>(json) ?? [])
                .Select(s => Clean(s, 60) ?? "").Where(s => s.Length > 0).Take(30).ToArray();
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private static ServiceResult<WebTourBookingDto> BookFail(int status, string code, string message) =>
        ServiceResult<WebTourBookingDto>.Fail(status, code, message);
}
