using System.Globalization;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The Ops board ("Aaj ke kaam"): today's numbers, the cards that say what to
/// do, and the few actions an admin can take from them.
/// </summary>
/// <remarks>
/// Nothing on the board acts by itself. A card suggests; the admin presses the
/// button. A fare change is a temporary percent (±20, ending at midnight), a
/// WhatsApp is shown in full and edited before it is queued, and every action
/// is written to <c>ops_actions</c> / <c>ops_messages</c> so the board can show
/// who did what.
///
/// "Today" is the Pakistan day (UTC+5). "Kal" compares today so far with the
/// same hours yesterday, not with all of yesterday.
/// </remarks>
public sealed class OpsBoardService(string connectionString)
{
    public static readonly string[] VehicleClasses = ["Car", "Bike", "Rickshaw", "Hiace", "Coster"];
    private static readonly TimeSpan Pk = TimeSpan.FromHours(5);
    private static readonly CultureInfo En = CultureInfo.GetCultureInfo("en-US");
    private const string ActiveTrip = "('DriverAccepted','DriverEnRoute','DriverArrived','TripStarted','Emergency')";
    private const string OpenRequest = "('Open','SearchingDrivers','ReceivingOffers')";

    // ───────────────────────────────────────────────────────────────── board

    public async Task<ServiceResult<OpsBoardDto>> BoardAsync(Guid? district, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        var now = DateTimeOffset.UtcNow;
        var t0 = TodayStart(now);
        var ctx = new Ctx(c, district, t0, now, ct);

        var areas = await AreasAsync(ctx);
        var kpis = await KpisAsync(ctx);
        var weather = await WeatherAsync(ctx);
        var roads = await RoadReportsAsync(ctx);
        var cards = new List<OpsCardDto>();
        cards.AddRange(RushCards(areas, await DominantClassAsync(ctx)));
        cards.AddRange(await RateCardsAsync(ctx, areas));
        cards.AddRange(RoadCards(roads));
        cards.AddRange(WeatherCards(weather.Rows));
        cards.AddRange(await DemandCardsAsync(ctx, areas));
        var pending = await PendingCardAsync(ctx);
        if (pending is not null) cards.Add(pending);

        var hidden = await HiddenCardsAsync(ctx);
        cards = cards.Where(card => !hidden.Contains(card.Key))
            .OrderBy(card => card.Severity switch { "err" => 0, "warn" => 1, "info" => 2, _ => 3 })
            .ToList();

        var board = new OpsBoardDto(
            Time(now),
            kpis,
            cards,
            areas.Select(a => a.Row).ToList(),
            await LiveRidesAsync(ctx, roads),
            await AccountsAsync(ctx),
            await HoursAsync(ctx),
            weather.Rows,
            weather.FetchedAt,
            await FareAdjustmentsAsync(ctx),
            roads,
            await LogAsync(ctx));
        return ServiceResult<OpsBoardDto>.Ok(board);
    }

    // ───────────────────────────────────────────────────────────────── KPIs

    private async Task<IReadOnlyList<OpsKpiDto>> KpisAsync(Ctx x)
    {
        var area = AreaSql("{col}");
        string A(string col) => area.Replace("{col}", col);
        var sql = $"""
            SELECT
              (SELECT count(*) FROM udrive.trip_operations o JOIN udrive.bookings b ON b.id=o.booking_id
                WHERE o.trip_status IN ('DriverAccepted','DriverEnRoute','DriverArrived') AND {A("b.territory_id")})::int,
              (SELECT count(*) FROM udrive.trip_operations o JOIN udrive.bookings b ON b.id=o.booking_id
                WHERE o.trip_status IN ('TripStarted','Emergency') AND {A("b.territory_id")})::int,
              (SELECT count(*) FROM udrive.users WHERE role='Customer' AND created_at >= @t0)::int,
              (SELECT count(*) FROM udrive.users WHERE role='Customer' AND created_at >= @y0 AND created_at < @ynow)::int,
              (SELECT count(*) FROM udrive.driver_profiles WHERE created_at >= @t0)::int,
              (SELECT count(*) FROM udrive.driver_profiles WHERE created_at >= @y0 AND created_at < @ynow)::int,
              (SELECT count(*) FROM udrive.driver_profiles WHERE verification_status IN ('Submitted','PendingReview','UnderReview'))::int,
              (SELECT count(*) FROM udrive.audit_logs WHERE action IN ('AccountDeletedBySelf','AccountDeletedByAdmin') AND created_at >= @t0)::int,
              (SELECT count(*) FROM udrive.audit_logs WHERE action IN ('AccountDeletedBySelf','AccountDeletedByAdmin') AND created_at >= @y0 AND created_at < @ynow)::int,
              (SELECT count(*) FROM udrive.driver_presence_locations p WHERE p.server_timestamp > now() - interval '5 minutes'
                 AND {A("udrive.nearest_tehsil(ST_Y(p.location::geometry), ST_X(p.location::geometry))")})::int,
              (SELECT count(DISTINCT s.driver_profile_id) FROM udrive.driver_online_sessions s
                WHERE s.started_at <= @ynow AND COALESCE(s.ended_at, s.last_heartbeat_at) >= @ynow - interval '5 minutes')::int,
              (SELECT count(*) FROM udrive.ride_requests WHERE created_at >= @t0 AND {A("territory_id")})::int,
              (SELECT count(*) FROM udrive.ride_requests WHERE created_at >= @y0 AND created_at < @ynow AND {A("territory_id")})::int,
              (SELECT count(*) FROM udrive.trip_operations o JOIN udrive.bookings b ON b.id=o.booking_id
                WHERE o.completed_at >= @t0 AND {A("b.territory_id")})::int,
              (SELECT count(*) FROM udrive.ride_requests r WHERE r.created_at >= @t0 AND r.status='Expired' AND {A("r.territory_id")}
                 AND NOT EXISTS (SELECT 1 FROM udrive.driver_offers o WHERE o.ride_request_id=r.id))::int,
              (SELECT count(*) FROM udrive.ride_requests r WHERE r.created_at >= @y0 AND r.created_at < @ynow AND r.status='Expired' AND {A("r.territory_id")}
                 AND NOT EXISTS (SELECT 1 FROM udrive.driver_offers o WHERE o.ride_request_id=r.id))::int,
              (SELECT count(*) FROM udrive.ride_requests WHERE updated_at >= @t0 AND status='Cancelled' AND {A("territory_id")})::int,
              (SELECT count(*) FROM udrive.trip_operations o JOIN udrive.bookings b ON b.id=o.booking_id
                WHERE o.cancelled_at >= @t0 AND {A("b.territory_id")})::int,
              (SELECT count(*) FROM udrive.hotel_bookings WHERE created_at >= @t0)::int,
              (SELECT count(*) FROM udrive.hotel_bookings WHERE created_at >= @t0 AND owner_notified_at IS NOT NULL)::int,
              (SELECT count(*) FROM udrive.rental_bookings WHERE created_at >= @t0)::int,
              (SELECT count(*) FROM udrive.package_bookings WHERE created_at >= @t0)::int,
              COALESCE((SELECT sum(abs(amount)) FROM udrive.driver_wallet_entries
                 WHERE created_at >= @t0 AND entry_type IN ('Commission','RentCommission')),0)
              + COALESCE((SELECT sum(abs(amount)) FROM udrive.hotel_wallet_entries
                 WHERE created_at >= @t0 AND entry_type = 'Commission'),0),
              COALESCE((SELECT sum(abs(amount)) FROM udrive.driver_wallet_entries
                 WHERE created_at >= @y0 AND created_at < @ynow AND entry_type IN ('Commission','RentCommission')),0)
              + COALESCE((SELECT sum(abs(amount)) FROM udrive.hotel_wallet_entries
                 WHERE created_at >= @y0 AND created_at < @ynow AND entry_type = 'Commission'),0),
              (SELECT count(*) FROM udrive.driver_wallet_topups WHERE status='Pending')::int;
            """;
        await using var cmd = x.Cmd(sql);
        await using var r = await cmd.ExecuteReaderAsync(x.Ct);
        await r.ReadAsync(x.Ct);
        int I(int i) => r.GetInt32(i);
        var pickup = I(0); var moving = I(1);
        var cust = I(2); var custY = I(3);
        var drv = I(4); var drvY = I(5); var drvPending = I(6);
        var del = I(7); var delY = I(8);
        var online = I(9); var onlineY = I(10);
        var req = I(11); var reqY = I(12);
        var done = I(13);
        var noOffer = I(14); var noOfferY = I(15);
        var cancelReq = I(16); var cancelTrip = I(17);
        var hotel = I(18); var hotelSent = I(19);
        var rent = I(20); var tour = I(21);
        var comm = r.GetDecimal(22); var commY = r.GetDecimal(23);
        var topups = I(24);

        return
        [
            new("live", "Rides abhi chal rahi", (pickup + moving).ToString(En), $"{pickup} pickup par · {moving} safar mein", "hl"),
            Kpi("customers", "Naye customers", cust, custY, null, higherIsGood: true),
            Kpi("drivers", "Naye drivers (registration)", drv, drvY, drvPending > 0 ? $"{drvPending} approval pending" : null, higherIsGood: true),
            Kpi("deleted", "Account delete", del, delY, del > 0 ? "wajah neeche" : null, higherIsGood: false),
            Kpi("online", "Drivers online abhi", online, onlineY, "is waqt kal se", higherIsGood: true),
            Kpi("requests", "Ride requests aaj", req, reqY, null, higherIsGood: true),
            new("completed", "Rides mukammal", done.ToString(En), req > 0 ? $"{done * 100 / req}% requests se" : null, "flat"),
            Kpi("nooffer", "Bina driver ke (koi offer nahi)", noOffer, noOfferY, noOffer > noOfferY ? "rush ka nishan" : null, higherIsGood: false),
            new("cancel", "Cancel (request / ride)", $"{cancelReq} / {cancelTrip}", null, cancelReq + cancelTrip > 0 ? "down" : "flat"),
            new("hotel", "Hotel bookings", hotel.ToString(En), hotel > 0 ? $"WhatsApp: {hotelSent}/{hotel} gaye" : null, hotelSent < hotel ? "down" : "flat"),
            new("rent", "Rent / Tour bookings", $"{rent} / {tour}", null, "flat"),
            new("commission", "Commission aaj", "Rs " + comm.ToString("N0", En),
                DeltaNote((double)comm, (double)commY) + (topups > 0 ? $" · top-ups {topups} pending" : ""), comm >= commY ? "up" : "down"),
        ];
    }

    private static OpsKpiDto Kpi(string key, string label, int today, int yday, string? extra, bool higherIsGood)
    {
        var trend = today == yday ? "flat" : (today > yday) == higherIsGood ? "up" : "down";
        var note = today == yday ? "kal jitne" : (today > yday ? "↑ " : "↓ ") + Math.Abs(today - yday).ToString(En) + " kal se";
        if (extra is not null) note += " · " + extra;
        return new OpsKpiDto(key, label, today.ToString(En), note, trend);
    }

    private static string DeltaNote(double today, double yday)
    {
        if (yday <= 0) return today > 0 ? "kal kuch nahi tha" : "kal jitna";
        var pct = (today - yday) / yday * 100;
        return (pct >= 0 ? "↑ " : "↓ ") + Math.Abs(Math.Round(pct)).ToString(En) + "% kal se";
    }

    // ───────────────────────────────────────────────────────────────── areas

    private sealed record Area(OpsAreaRowDto Row, int Today, int LastWeek, double? Gap, int Offers, int RoadDrivers);

    private async Task<List<Area>> AreasAsync(Ctx x)
    {
        var sql = $"""
            WITH t AS (
                SELECT t.id, t.name, COALESCE(d.name, '') AS district
                  FROM udrive.territories t LEFT JOIN udrive.territories d ON d.id = t.parent_id
                 WHERE t.kind = 'Tehsil' AND t.is_active AND {AreaSql("t.id")}),
            req AS (SELECT territory_id, count(*) n FROM udrive.ride_requests
                     WHERE created_at > now() - interval '30 minutes' GROUP BY 1),
            noff AS (SELECT r.territory_id, count(*) n FROM udrive.ride_requests r
                      WHERE r.created_at > now() - interval '60 minutes' AND r.created_at < now() - interval '5 minutes'
                        AND (r.status IN {OpenRequest} OR r.status = 'Expired')
                        AND NOT EXISTS (SELECT 1 FROM udrive.driver_offers o WHERE o.ride_request_id = r.id)
                      GROUP BY 1),
            drv AS (SELECT udrive.nearest_tehsil(ST_Y(p.location::geometry), ST_X(p.location::geometry)) AS tid, count(*) n
                      FROM udrive.driver_presence_locations p
                     WHERE p.server_timestamp > now() - interval '5 minutes' GROUP BY 1),
            gap AS (SELECT r.territory_id, avg(o.amount / r.customer_offer - 1) g, count(*) n
                      FROM udrive.driver_offers o JOIN udrive.ride_requests r ON r.id = o.ride_request_id
                     WHERE o.created_at > now() - interval '3 hours' AND r.customer_offer > 0 GROUP BY 1),
            road AS (SELECT territory_id, count(DISTINCT driver_profile_id) n FROM udrive.road_reports
                      WHERE status = 'Open' AND created_at > now() - interval '3 hours' GROUP BY 1),
            today AS (SELECT territory_id, count(*) n FROM udrive.ride_requests WHERE created_at >= @t0 GROUP BY 1),
            lastweek AS (SELECT territory_id, count(*) n FROM udrive.ride_requests
                          WHERE created_at >= @t0 - interval '7 days' AND created_at < now() - interval '7 days' GROUP BY 1)
            SELECT t.id, t.name, t.district, COALESCE(req.n,0)::int, COALESCE(drv.n,0)::int, COALESCE(noff.n,0)::int,
                   gap.g::float8, COALESCE(gap.n,0)::int, COALESCE(road.n,0)::int, COALESCE(today.n,0)::int, COALESCE(lastweek.n,0)::int
              FROM t
              LEFT JOIN req ON req.territory_id = t.id
              LEFT JOIN drv ON drv.tid = t.id
              LEFT JOIN noff ON noff.territory_id = t.id
              LEFT JOIN gap ON gap.territory_id = t.id
              LEFT JOIN road ON road.territory_id = t.id
              LEFT JOIN today ON today.territory_id = t.id
              LEFT JOIN lastweek ON lastweek.territory_id = t.id
             ORDER BY COALESCE(req.n,0) DESC, COALESCE(today.n,0) DESC, COALESCE(drv.n,0) DESC, t.name;
            """;
        var list = new List<Area>();
        await using var cmd = x.Cmd(sql);
        await using var r = await cmd.ExecuteReaderAsync(x.Ct);
        while (await r.ReadAsync(x.Ct))
        {
            var req = r.GetInt32(3); var drivers = r.GetInt32(4); var noOffer = r.GetInt32(5);
            double? gap = r.IsDBNull(6) ? null : r.GetDouble(6);
            var offers = r.GetInt32(7); var road = r.GetInt32(8);
            var state =
                road >= 2 ? "Road band"
                : IsRush(req, drivers, noOffer) ? "Rush"
                : gap is >= 0.25 && offers >= 3 ? "Rate"
                : req == 0 && drivers <= 1 && r.GetInt32(9) == 0 ? "Khamosh"
                : "Theek";
            var gapText = gap is null ? "—" : (gap >= 0 ? "+" : "") + Math.Round(gap.Value * 100).ToString(En) + "%";
            list.Add(new Area(
                new OpsAreaRowDto(r.GetGuid(0), r.GetString(1), r.GetString(2), req, drivers, noOffer, gapText, state),
                r.GetInt32(9), r.GetInt32(10), gap, offers, road));
        }
        return list;
    }

    private static bool IsRush(int requests30, int drivers, int noOffer) =>
        requests30 >= 5 && (drivers == 0 || (double)requests30 / drivers >= 3 || noOffer >= 3);

    private async Task<Dictionary<Guid, string>> DominantClassAsync(Ctx x)
    {
        var map = new Dictionary<Guid, (string Cls, int N)>();
        await using var cmd = x.Cmd("""
            SELECT territory_id, udrive.vehicle_class(vehicle_category), count(*)::int
              FROM udrive.ride_requests
             WHERE created_at > now() - interval '30 minutes' AND territory_id IS NOT NULL
             GROUP BY 1, 2;
            """);
        await using var r = await cmd.ExecuteReaderAsync(x.Ct);
        while (await r.ReadAsync(x.Ct))
        {
            var id = r.GetGuid(0); var n = r.GetInt32(2);
            if (!map.TryGetValue(id, out var best) || n > best.N) map[id] = (r.GetString(1), n);
        }
        return map.ToDictionary(p => p.Key, p => p.Value.Cls);
    }

    // ───────────────────────────────────────────────────────────────── cards

    private IEnumerable<OpsCardDto> RushCards(List<Area> areas, Dictionary<Guid, string> classes)
    {
        foreach (var a in areas.Where(a => a.Row.State == "Rush"))
        {
            var row = a.Row;
            var cls = classes.TryGetValue(row.TerritoryId, out var c) ? c : "Car";
            var ratio = row.DriversOnline == 0 ? 99 : (double)row.Requests30 / row.DriversOnline;
            var pct = ratio >= 5 ? 20 : ratio >= 4 ? 15 : 10;
            yield return new OpsCardDto(
                $"rush:{row.TerritoryId:N}:{cls}:{DayKey()}", "rush", "err",
                $"🔥 Rush — {row.Tehsil}",
                $"Pichle 30 min: {row.Requests30} requests, {row.DriversOnline} drivers online, {row.NoOffer} requests bina offer ke. "
                + $"{cls} fare +{pct}% karein (had ±20%), aur qareeb ke offline drivers ko bulayein.",
                $"requests/driver = {(row.DriversOnline == 0 ? "∞" : ratio.ToString("0.0", En))} (normal 1.5 tak) · bina offer {row.NoOffer} · offer vs fare {row.OfferGap}",
                "abhi",
                [
                    Btn("fare", $"{cls} rate +{pct}% (aaj ke liye)", ("territoryId", row.TerritoryId.ToString()), ("vehicleClass", cls), ("percent", pct.ToString(En))),
                    Btn("message", "Drivers ko WhatsApp →", ("audience", "offline_drivers"), ("territoryId", row.TerritoryId.ToString()), ("vehicleClass", cls)),
                    Btn("dismiss", "Chhoro"),
                ]);
        }
    }

    private async Task<IEnumerable<OpsCardDto>> RateCardsAsync(Ctx x, List<Area> areas)
    {
        var names = areas.ToDictionary(a => a.Row.TerritoryId, a => a.Row.Tehsil);
        var cards = new List<OpsCardDto>();
        await using var cmd = x.Cmd("""
            SELECT r.territory_id, udrive.vehicle_class(r.vehicle_category),
                   count(DISTINCT r.id)::int,
                   count(DISTINCT r.id) FILTER (WHERE r.selected_offer_id IS NOT NULL OR r.status = 'Confirmed')::int,
                   avg(o.amount / NULLIF(r.customer_offer, 0) - 1)::float8,
                   count(o.id)::int
              FROM udrive.ride_requests r
              LEFT JOIN udrive.driver_offers o ON o.ride_request_id = r.id
             WHERE r.created_at > now() - interval '3 hours' AND r.territory_id IS NOT NULL
             GROUP BY 1, 2
            HAVING count(DISTINCT r.id) >= 5;
            """);
        await using var r = await cmd.ExecuteReaderAsync(x.Ct);
        while (await r.ReadAsync(x.Ct))
        {
            var tid = r.GetGuid(0);
            if (!names.TryGetValue(tid, out var tehsil)) continue;
            var cls = r.GetString(1); var requests = r.GetInt32(2); var matched = r.GetInt32(3);
            double? gap = r.IsDBNull(4) ? null : r.GetDouble(4);
            var offers = r.GetInt32(5);
            var acceptRate = (double)matched / requests;
            var highOffers = gap is >= 0.25 && offers >= 3;
            if (!highOffers && acceptRate >= 0.35) continue;
            var pct = highOffers ? Math.Clamp((int)(Math.Round(gap!.Value * 100 * 0.6 / 5) * 5), 5, 20) : 10;
            cards.Add(new OpsCardDto(
                $"rate:{tid:N}:{cls}:{DayKey()}", "rate", "warn",
                $"💸 Rate ghalat — {tehsil}, {cls}",
                highOffers
                    ? $"Drivers {cls} ke offers customer ke fare se {Math.Round(gap!.Value * 100)}% upar bhej rahe hain. Fare +{pct}% karein (aaj ke liye)."
                    : $"Pichle 3 ghante: {requests} me se sirf {matched} {cls} requests ko driver mila. Fare +{pct}% kar ke dekhein.",
                $"accept rate {Math.Round(acceptRate * 100)}% · offers {offers} · offer vs fare {(gap is null ? "—" : Math.Round(gap.Value * 100) + "%")}",
                "pichle 3 ghante",
                [
                    Btn("fare", $"{cls} rate +{pct}% (aaj ke liye)", ("territoryId", tid.ToString()), ("vehicleClass", cls), ("percent", pct.ToString(En))),
                    Btn("link", "Pricing page", ("href", "/pricing")),
                    Btn("dismiss", "Chhoro"),
                ]));
        }
        return cards;
    }

    private IEnumerable<OpsCardDto> RoadCards(IReadOnlyList<OpsRoadReportDto> reports)
    {
        // Clusters: reports within 1.5 km of each other in the last 3 hours.
        var used = new HashSet<Guid>();
        foreach (var seed in reports)
        {
            if (used.Contains(seed.Id)) continue;
            var group = reports.Where(o => !used.Contains(o.Id) && Km(seed.Latitude, seed.Longitude, o.Latitude, o.Longitude) <= 1.5).ToList();
            foreach (var g in group) used.Add(g.Id);
            var drivers = group.Select(g => g.Driver).Distinct().Count();
            if (drivers < 2) continue;
            var kinds = string.Join(", ", group.Select(g => KindLabel(g.Kind)).Distinct());
            var notes = string.Join(" · ", group.Select(g => g.Note).Where(n => n.Length > 0).Distinct().Take(3));
            yield return new OpsCardDto(
                $"road:{seed.Latitude:0.00}:{seed.Longitude:0.00}:{DayKey()}", "road", "err",
                $"⛔ Road band — {seed.Tehsil}",
                $"{drivers} drivers ne bataya: {kinds}.{(notes.Length > 0 ? " \"" + notes + "\"" : "")} Advisory lagayein aur raste wali rides ke customers ko batayein.",
                $"{drivers} alag drivers, 1.5 km ke andar, {group.Count} reports · aakhri {seed.Ago} · map: {seed.Latitude:0.0000}, {seed.Longitude:0.0000}",
                seed.Ago,
                [
                    Btn("advisory", "Advisory lagayein", ("title", $"Road band — {seed.Tehsil}"), ("details", $"{kinds}. {notes}".Trim())),
                    Btn("message", "Chalti rides ke customers ko WhatsApp →", ("audience", "live_customers"), ("territoryId", TidOf(seed))),
                    Btn("falseReport", "Ghalat report", ("reportIds", string.Join(",", group.Select(g => g.Id)))),
                ]);
        }
    }

    private Dictionary<string, Guid> _reportTerritory = new();
    private string TidOf(OpsRoadReportDto r) => _reportTerritory.TryGetValue(r.Id.ToString(), out var t) ? t.ToString() : "";

    private static IEnumerable<OpsCardDto> WeatherCards(IReadOnlyList<OpsWeatherRowDto> rows)
    {
        foreach (var w in rows.Where(w => w.RiskTone is "err" or "warn"))
        {
            var bad = w.Days.Take(3).Select((d, i) => (d, i)).FirstOrDefault(p => Risky(p.d));
            var when = bad.i switch { 0 => "aaj", 1 => "kal", _ => "parson" };
            var d = bad.d ?? w.Days.FirstOrDefault();
            if (d is null) continue;
            var detail = d.Snow > 0 ? $"barf {d.Snow:0.#} cm" : d.Rain >= 10 ? $"barish {d.Rain:0} mm" : d.Wind >= 40 ? $"hawa {d.Wind:0} km/h" : "dhund";
            var tid = w.PlaceKey.StartsWith("t:", StringComparison.Ordinal) ? w.PlaceKey[2..] : "";
            var buttons = new List<OpsCardButtonDto>
            {
                Btn("advisory", "Advisory lagayein", ("title", $"Mausam — {w.Name} ({when})"), ("details", $"{w.Risk}: {detail}")),
            };
            if (tid.Length > 0) buttons.Add(Btn("message", "Aane wale customers ko WhatsApp →", ("audience", "upcoming_customers"), ("territoryId", tid), ("detail", detail)));
            buttons.Add(Btn("dismiss", "Chhoro"));
            yield return new OpsCardDto(
                $"weather:{w.PlaceKey}:{d.Date}", "weather", w.RiskTone == "err" ? "warn" : "info",
                $"{(d.Snow > 0 ? "🌨️" : "🌧️")} Mausam — {when} {w.Name}",
                $"{w.Risk}: {detail}." + (w.Affects is null ? "" : $" Asar: {w.Affects}."),
                $"Open-Meteo forecast · {d.Date} · max {d.Max:0}° / min {d.Min:0}°",
                "forecast",
                buttons);
        }
    }

    private async Task<IEnumerable<OpsCardDto>> DemandCardsAsync(Ctx x, List<Area> areas)
    {
        await Task.CompletedTask;
        return areas.Where(a => a.Today >= 10 && a.Today >= a.LastWeek * 1.3)
            .Select(a => new OpsCardDto(
                $"demand:{a.Row.TerritoryId:N}:{DayKey()}", "demand", "ok",
                $"🟢 Demand zyada — {a.Row.Tehsil}",
                $"Aaj ab tak {a.Today} requests, pichle hafte isi din isi waqt tak {a.LastWeek}. Wahan ke drivers/owners ko online rehne ko kahein.",
                $"aaj {a.Today} vs pichla hafta {a.LastWeek} ({DeltaNote(a.Today, a.LastWeek)})",
                "aaj",
                [
                    Btn("message", "Wahan ke owners ko WhatsApp →", ("audience", "area_owners"), ("territoryId", a.Row.TerritoryId.ToString())),
                    Btn("dismiss", "Chhoro"),
                ]));
    }

    private async Task<OpsCardDto?> PendingCardAsync(Ctx x)
    {
        await using var cmd = x.Cmd("""
            SELECT
              (SELECT count(*) FROM udrive.driver_profiles WHERE verification_status IN ('Submitted','PendingReview','UnderReview')
                  AND COALESCE(submitted_at, updated_at) < now() - interval '2 hours')::int,
              (SELECT count(*) FROM udrive.hotels WHERE approval_status = 'Pending'
                  AND COALESCE(submitted_at, created_at) < now() - interval '2 hours')::int,
              (SELECT count(*) FROM udrive.driver_wallet_topups WHERE status = 'Pending' AND created_at < now() - interval '2 hours')::int,
              (SELECT count(*) FROM udrive.dispute_cases WHERE status IN ('Open','Escalated') AND created_at < now() - interval '2 hours')::int;
            """);
        await using var r = await cmd.ExecuteReaderAsync(x.Ct);
        await r.ReadAsync(x.Ct);
        int drivers = r.GetInt32(0), hotels = r.GetInt32(1), topups = r.GetInt32(2), disputes = r.GetInt32(3);
        if (drivers + hotels + topups + disputes == 0) return null;
        var parts = new List<string>();
        if (drivers > 0) parts.Add($"{drivers} driver approvals");
        if (hotels > 0) parts.Add($"{hotels} hotel");
        if (topups > 0) parts.Add($"{topups} wallet top-ups");
        if (disputes > 0) parts.Add($"{disputes} disputes");
        return new OpsCardDto(
            $"pending:{DayKey()}:{drivers}:{hotels}:{topups}:{disputes}", "pending", "warn",
            "⏳ Pending kaam",
            string.Join(" · ", parts) + " — 2 ghante se zyada ruke hue.",
            "jitni dair ruke rahenge, utne log intezar mein",
            "2 ghante se zyada",
            [
                Btn("link", "Verification kholein", ("href", "/verification")),
                Btn("link", "Top-ups", ("href", "/wallet-topups")),
                Btn("link", "Disputes", ("href", "/disputes")),
            ]);
    }

    private async Task<HashSet<string>> HiddenCardsAsync(Ctx x)
    {
        var set = new HashSet<string>();
        await using var cmd = x.Cmd("SELECT DISTINCT card_key FROM udrive.ops_actions WHERE hide_until > now();");
        await using var r = await cmd.ExecuteReaderAsync(x.Ct);
        while (await r.ReadAsync(x.Ct)) set.Add(r.GetString(0));
        return set;
    }

    // ───────────────────────────────────────────────────────────────── lists

    private async Task<IReadOnlyList<OpsLiveRideDto>> LiveRidesAsync(Ctx x, IReadOnlyList<OpsRoadReportDto> roads)
    {
        var roadTehsils = _reportTerritory.Values.ToHashSet();
        var list = new List<OpsLiveRideDto>();
        await using var cmd = x.Cmd($"""
            SELECT b.id, COALESCE(b.booking_reference, ''), COALESCE(v.category, ''),
                   COALESCE(b.pickup_label, '') || ' → ' || COALESCE(b.destination_label, ''),
                   o.trip_status, o.started_at, l.server_timestamp, b.territory_id
              FROM udrive.trip_operations o
              JOIN udrive.bookings b ON b.id = o.booking_id
              LEFT JOIN udrive.vehicles v ON v.id = b.vehicle_id
              LEFT JOIN udrive.driver_latest_locations l ON l.booking_id = b.id
             WHERE o.trip_status IN {ActiveTrip} AND {AreaSql("b.territory_id")}
             ORDER BY o.last_activity_at DESC
             LIMIT 40;
            """);
        await using var r = await cmd.ExecuteReaderAsync(x.Ct);
        while (await r.ReadAsync(x.Ct))
        {
            var status = r.GetString(4);
            DateTimeOffset? seen = r.IsDBNull(6) ? null : r.GetFieldValue<DateTimeOffset>(6);
            var stale = seen is null ? (double?)null : (DateTimeOffset.UtcNow - seen.Value).TotalMinutes;
            Guid? tid = r.IsDBNull(7) ? null : r.GetGuid(7);
            string flag, tone;
            if (status == "Emergency") { flag = "SOS"; tone = "err"; }
            else if (stale is null || stale > 3) { flag = stale is null ? "GPS abhi tak nahi" : $"GPS {Math.Round(stale.Value)} min se band"; tone = "err"; }
            else if (tid is not null && roadTehsils.Contains(tid.Value)) { flag = "Road band area mein"; tone = "warn"; }
            else
            {
                tone = "ok";
                flag = status switch
                {
                    "TripStarted" when !r.IsDBNull(5) => $"Safar mein · {Math.Max(1, Math.Round((DateTimeOffset.UtcNow - r.GetFieldValue<DateTimeOffset>(5)).TotalMinutes))} min",
                    "TripStarted" => "Safar mein",
                    "DriverArrived" => "Driver pickup par",
                    _ => "Driver aa raha hai",
                };
            }
            list.Add(new OpsLiveRideDto(r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetString(3), status, flag, tone));
        }
        return list;
    }

    private async Task<OpsAccountsDto> AccountsAsync(Ctx x)
    {
        int cust, drv, owners, hotelOwners, del, active;
        await using (var cmd = x.Cmd("""
            SELECT
              (SELECT count(*) FROM udrive.users WHERE role='Customer' AND created_at >= @t0)::int,
              (SELECT count(*) FROM udrive.driver_profiles WHERE created_at >= @t0 AND COALESCE(profile_kind,'Driver') = 'Driver')::int,
              (SELECT count(*) FROM udrive.driver_profiles WHERE created_at >= @t0 AND COALESCE(profile_kind,'Driver') <> 'Driver')::int,
              (SELECT count(*) FROM udrive.hotel_owner_profiles WHERE created_at >= @t0)::int,
              (SELECT count(*) FROM udrive.audit_logs WHERE action IN ('AccountDeletedBySelf','AccountDeletedByAdmin') AND created_at >= @t0)::int,
              (SELECT count(DISTINCT install_id) FROM udrive.app_sessions WHERE last_seen_at >= @t0)::int;
            """))
        {
            await using var r = await cmd.ExecuteReaderAsync(x.Ct);
            await r.ReadAsync(x.Ct);
            cust = r.GetInt32(0); drv = r.GetInt32(1); owners = r.GetInt32(2); hotelOwners = r.GetInt32(3); del = r.GetInt32(4); active = r.GetInt32(5);
        }
        var reasons = new List<string>();
        await using (var cmd = x.Cmd("""
            SELECT COALESCE(NULLIF(changes_json->>'reason', ''), 'wajah nahi likhi')
              FROM udrive.audit_logs
             WHERE action IN ('AccountDeletedBySelf','AccountDeletedByAdmin') AND created_at >= @t0
             ORDER BY created_at DESC LIMIT 10;
            """))
        {
            await using var r = await cmd.ExecuteReaderAsync(x.Ct);
            while (await r.ReadAsync(x.Ct)) reasons.Add(r.GetString(0));
        }
        var versions = new List<string>();
        await using (var cmd = x.Cmd("""
            WITH v AS (SELECT COALESCE(NULLIF(app_version, ''), '?') AS ver, count(*) n
                         FROM udrive.app_devices WHERE last_seen_at > now() - interval '7 days' GROUP BY 1)
            SELECT ver, (n * 100.0 / NULLIF(sum(n) OVER (), 0))::float8 FROM v ORDER BY n DESC LIMIT 4;
            """))
        {
            await using var r = await cmd.ExecuteReaderAsync(x.Ct);
            while (await r.ReadAsync(x.Ct)) versions.Add($"{r.GetString(0)}: {Math.Round(r.GetDouble(1))}%");
        }
        return new OpsAccountsDto(cust, drv, owners, hotelOwners, del, reasons, active, versions);
    }

    private async Task<IReadOnlyList<OpsHourDto>> HoursAsync(Ctx x)
    {
        var today = new int[24]; var usual = new double[24];
        await using var cmd = x.Cmd($"""
            SELECT extract(hour FROM created_at AT TIME ZONE 'Asia/Karachi')::int,
                   count(*) FILTER (WHERE created_at >= @t0)::int,
                   (count(*) FILTER (WHERE created_at < @t0) / 7.0)::float8
              FROM udrive.ride_requests
             WHERE created_at >= @t0 - interval '7 days' AND {AreaSql("territory_id")}
             GROUP BY 1;
            """);
        await using var r = await cmd.ExecuteReaderAsync(x.Ct);
        while (await r.ReadAsync(x.Ct))
        {
            var h = Math.Clamp(r.GetInt32(0), 0, 23);
            today[h] = r.GetInt32(1); usual[h] = Math.Round(r.GetDouble(2), 1);
        }
        return Enumerable.Range(0, 24).Select(h => new OpsHourDto(h, today[h], usual[h])).ToList();
    }

    private async Task<(IReadOnlyList<OpsWeatherRowDto> Rows, string? FetchedAt)> WeatherAsync(Ctx x)
    {
        var rows = new List<OpsWeatherRowDto>();
        DateTimeOffset? fetched = null;
        var affects = new Dictionary<string, int>();
        await using (var cmd = x.Cmd("""
            SELECT 't:' || b.territory_id::text, count(*)::int FROM udrive.bookings b
             WHERE b.pickup_at BETWEEN now() AND now() + interval '72 hours' AND b.status <> 'Cancelled' AND b.territory_id IS NOT NULL
             GROUP BY 1;
            """))
        {
            await using var r = await cmd.ExecuteReaderAsync(x.Ct);
            while (await r.ReadAsync(x.Ct)) affects[r.GetString(0)] = r.GetInt32(1);
        }
        await using (var cmd = x.Cmd($"""
            SELECT w.place_key, w.name, w.payload::text, w.fetched_at
              FROM udrive.weather_readings w
              LEFT JOIN udrive.territories t ON w.place_key = 't:' || t.id::text
             WHERE w.place_key NOT LIKE 't:%' OR {AreaSql("t.id")}
             ORDER BY (w.place_key LIKE 't:%') DESC, w.name;
            """))
        {
            await using var r = await cmd.ExecuteReaderAsync(x.Ct);
            while (await r.ReadAsync(x.Ct))
            {
                var at = r.GetFieldValue<DateTimeOffset>(3);
                if (fetched is null || at > fetched) fetched = at;
                var parsed = WeatherPayload.Parse(r.GetString(2));
                if (parsed is null) continue;
                var (risk, tone) = RiskOf(parsed.Days);
                var key = r.GetString(0);
                rows.Add(new OpsWeatherRowDto(key, r.GetString(1), parsed.NowTemp, parsed.NowCode, parsed.Days, risk, tone,
                    affects.TryGetValue(key, out var n) && n > 0 ? $"agle 3 din {n} bookings is ilaqe mein" : null));
            }
        }
        // Risky places first, then the rest.
        rows = rows.OrderBy(w => w.RiskTone switch { "err" => 0, "warn" => 1, _ => 2 }).ThenBy(w => w.Name).ToList();
        return (rows, fetched is null ? null : Time(fetched.Value));
    }

    private static bool Risky(OpsWeatherDayDto d) => d.Snow > 0 || d.Rain >= 10 || d.Wind >= 40 || d.Code is 45 or 48;

    public static (string Risk, string Tone) RiskOf(IReadOnlyList<OpsWeatherDayDto> days)
    {
        var next = days.Take(3).ToList();
        if (next.Any(d => d.Snow >= 10)) return ("Raasta band ho sakta hai (barf)", "err");
        if (next.Any(d => d.Snow > 0)) return ("Barf · 4×4 zaroori", "err");
        if (next.Count(d => d.Rain >= 10) >= 2) return ("Landslide khatra", "warn");
        if (next.Any(d => d.Rain >= 10)) return ("Tez barish", "warn");
        if (next.Any(d => d.Wind >= 40)) return ("Tez hawa", "warn");
        if (next.Any(d => d.Code is 45 or 48)) return ("Dhund", "warn");
        return ("Theek", "ok");
    }

    private async Task<IReadOnlyList<OpsFareAdjustmentDto>> FareAdjustmentsAsync(Ctx x)
    {
        var list = new List<OpsFareAdjustmentDto>();
        await using var cmd = x.Cmd($"""
            SELECT a.id, t.name, a.vehicle_class, a.percent, a.ends_at, a.reason
              FROM udrive.ops_fare_adjustments a JOIN udrive.territories t ON t.id = a.territory_id
             WHERE a.ended_early_at IS NULL AND now() BETWEEN a.starts_at AND a.ends_at AND {AreaSql("t.id")}
             ORDER BY a.created_at DESC;
            """);
        await using var r = await cmd.ExecuteReaderAsync(x.Ct);
        while (await r.ReadAsync(x.Ct))
        {
            list.Add(new OpsFareAdjustmentDto(r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetDecimal(3),
                Time(r.GetFieldValue<DateTimeOffset>(4)), r.GetString(5)));
        }
        return list;
    }

    private async Task<IReadOnlyList<OpsRoadReportDto>> RoadReportsAsync(Ctx x)
    {
        var list = new List<OpsRoadReportDto>();
        _reportTerritory = new();
        await using var cmd = x.Cmd($"""
            SELECT rr.id, COALESCE(t.name, '—'), rr.kind, rr.note, rr.latitude, rr.longitude, rr.created_at,
                   COALESCE(NULLIF(u.full_name, ''), 'Driver'), rr.territory_id
              FROM udrive.road_reports rr
              JOIN udrive.driver_profiles dp ON dp.id = rr.driver_profile_id
              JOIN udrive.users u ON u.id = dp.user_id
              LEFT JOIN udrive.territories t ON t.id = rr.territory_id
             WHERE rr.status = 'Open' AND rr.created_at > now() - interval '3 hours' AND {AreaSql("rr.territory_id")}
             ORDER BY rr.created_at DESC
             LIMIT 50;
            """);
        await using var r = await cmd.ExecuteReaderAsync(x.Ct);
        while (await r.ReadAsync(x.Ct))
        {
            var id = r.GetGuid(0);
            if (!r.IsDBNull(8)) _reportTerritory[id.ToString()] = r.GetGuid(8);
            list.Add(new OpsRoadReportDto(id, r.GetString(1), r.GetString(2), r.GetString(3), r.GetDouble(4), r.GetDouble(5),
                Ago(r.GetFieldValue<DateTimeOffset>(6)), r.GetString(7)));
        }
        return list;
    }

    private async Task<IReadOnlyList<OpsLogDto>> LogAsync(Ctx x)
    {
        var list = new List<OpsLogDto>();
        await using var cmd = x.Cmd("""
            SELECT at, card, decision, actor, detail FROM (
                SELECT a.created_at AS at, a.title AS card, a.decision, COALESCE(u.username, u.full_name, '') AS actor, a.detail
                  FROM udrive.ops_actions a LEFT JOIN udrive.users u ON u.id = a.actor_user_id
                 WHERE a.created_at >= @t0
                UNION ALL
                SELECT m.created_at, COALESCE(m.card_key, ''), 'WhatsApp ' || m.recipients || ' ko (' || m.audience || ')',
                       COALESCE(u.username, u.full_name, ''), left(m.body, 120)
                  FROM udrive.ops_messages m LEFT JOIN udrive.users u ON u.id = m.actor_user_id
                 WHERE m.created_at >= @t0
                UNION ALL
                SELECT f.created_at, f.vehicle_class || ' · ' || t.name,
                       'Fare ' || CASE WHEN f.percent >= 0 THEN '+' ELSE '' END || (f.percent::float8)::text || '%' || CASE WHEN f.ended_early_at IS NOT NULL THEN ' (khatam kiya)' ELSE '' END,
                       COALESCE(u.username, u.full_name, ''), f.reason
                  FROM udrive.ops_fare_adjustments f
                  JOIN udrive.territories t ON t.id = f.territory_id
                  LEFT JOIN udrive.users u ON u.id = f.created_by
                 WHERE f.created_at >= @t0
            ) x ORDER BY at DESC LIMIT 60;
            """);
        await using var r = await cmd.ExecuteReaderAsync(x.Ct);
        while (await r.ReadAsync(x.Ct))
        {
            list.Add(new OpsLogDto(Time(r.GetFieldValue<DateTimeOffset>(0)), r.GetString(1), r.GetString(2), r.GetString(3), r.GetString(4)));
        }
        return list;
    }

    // ───────────────────────────────────────────────────────────────── actions

    public async Task<ServiceResult<OpsFareAdjustmentDto>> SetFareAdjustmentAsync(Guid actor, OpsFareAdjustmentRequest x, CancellationToken ct)
    {
        var cls = VehicleClasses.FirstOrDefault(c => string.Equals(c, x.VehicleClass?.Trim(), StringComparison.OrdinalIgnoreCase));
        if (cls is null) return Fail<OpsFareAdjustmentDto>(400, "class_invalid", "Gaari ki qisam ghalat hai.");
        if (x.Percent is < -20 or > 20 || x.Percent == 0) return Fail<OpsFareAdjustmentDto>(400, "percent_invalid", "Fare -20% se +20% tak badal sakta hai.");

        await using var c = await OpenAsync(ct);
        string? tehsil;
        await using (var cmd = new NpgsqlCommand("SELECT name FROM udrive.territories WHERE id = @t AND kind = 'Tehsil';", c))
        {
            cmd.Parameters.AddWithValue("t", x.TerritoryId);
            tehsil = await cmd.ExecuteScalarAsync(ct) as string;
        }
        if (tehsil is null) return Fail<OpsFareAdjustmentDto>(404, "tehsil_not_found", "Tehsil nahi mili.");

        var ends = TodayStart(DateTimeOffset.UtcNow).AddDays(1);
        var reason = Clip(x.Reason, 200);
        Guid id;
        await using (var cmd = new NpgsqlCommand(
            """
            UPDATE udrive.ops_fare_adjustments SET ended_early_at = now()
             WHERE territory_id = @t AND vehicle_class = @cls AND ended_early_at IS NULL AND ends_at > now();
            """, c))
        {
            cmd.Parameters.AddWithValue("t", x.TerritoryId);
            cmd.Parameters.AddWithValue("cls", cls);
            await cmd.ExecuteNonQueryAsync(ct);
        }
        await using (var cmd = new NpgsqlCommand(
            """
            INSERT INTO udrive.ops_fare_adjustments (territory_id, vehicle_class, percent, reason, card_key, ends_at, created_by)
            VALUES (@t, @cls, @p, @reason, @card, @ends, @actor) RETURNING id;
            """, c))
        {
            cmd.Parameters.AddWithValue("t", x.TerritoryId);
            cmd.Parameters.AddWithValue("cls", cls);
            cmd.Parameters.AddWithValue("p", x.Percent);
            cmd.Parameters.AddWithValue("reason", reason);
            cmd.Parameters.Add(new NpgsqlParameter("card", NpgsqlDbType.Text) { Value = (object?)Clip(x.CardKey, 200) ?? DBNull.Value });
            cmd.Parameters.AddWithValue("ends", ends);
            cmd.Parameters.AddWithValue("actor", actor);
            id = (Guid)(await cmd.ExecuteScalarAsync(ct))!;
        }
        if (!string.IsNullOrWhiteSpace(x.CardKey))
        {
            await RecordAsync(c, actor, x.CardKey!, "fare", $"{cls} · {tehsil}", "Done", $"Fare {(x.Percent > 0 ? "+" : "")}{x.Percent}% aaj ke liye", TimeSpan.FromHours(3), ct);
        }
        return ServiceResult<OpsFareAdjustmentDto>.Ok(new OpsFareAdjustmentDto(id, tehsil, cls, x.Percent, Time(ends), reason),
            $"{tehsil} mein {cls} fare {(x.Percent > 0 ? "+" : "")}{x.Percent}% raat 12 baje tak.");
    }

    public async Task<ServiceResult<bool>> EndFareAdjustmentAsync(Guid actor, Guid id, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        await using var cmd = new NpgsqlCommand(
            "UPDATE udrive.ops_fare_adjustments SET ended_early_at = now() WHERE id = @id AND ended_early_at IS NULL RETURNING id;", c);
        cmd.Parameters.AddWithValue("id", id);
        return await cmd.ExecuteScalarAsync(ct) is Guid
            ? ServiceResult<bool>.Ok(true, "Fare wapis normal.")
            : Fail<bool>(404, "not_found", "Yeh tabdeeli pehle hi khatam hai.");
    }

    public async Task<ServiceResult<bool>> DecideAsync(Guid actor, OpsDecisionRequest x, CancellationToken ct)
    {
        var decision = x.Decision switch { "Done" => "Done", "Dismissed" => "Dismissed", _ => null };
        if (decision is null || string.IsNullOrWhiteSpace(x.CardKey)) return Fail<bool>(400, "decision_invalid", "Faisla samajh nahi aaya.");
        await using var c = await OpenAsync(ct);
        await RecordAsync(c, actor, x.CardKey, Clip(x.CardKind, 40), Clip(x.Title, 200), decision, Clip(x.Detail, 500),
            decision == "Dismissed" ? TimeSpan.FromHours(6) : TimeSpan.FromHours(3), ct);
        return ServiceResult<bool>.Ok(true, decision == "Dismissed" ? "Card 6 ghante ke liye chhupa diya." : "Ho gaya.");
    }

    public async Task<ServiceResult<bool>> ReviewRoadReportsAsync(Guid actor, IReadOnlyList<Guid> ids, bool valid, CancellationToken ct)
    {
        if (ids.Count == 0) return Fail<bool>(400, "ids_required", "Report chunein.");
        await using var c = await OpenAsync(ct);
        await using var cmd = new NpgsqlCommand(
            "UPDATE udrive.road_reports SET status = @s, reviewed_by = @a, reviewed_at = now() WHERE id = ANY(@ids) AND status = 'Open';", c);
        cmd.Parameters.AddWithValue("s", valid ? "Confirmed" : "False");
        cmd.Parameters.AddWithValue("a", actor);
        cmd.Parameters.AddWithValue("ids", ids.ToArray());
        var n = await cmd.ExecuteNonQueryAsync(ct);
        await RecordAsync(c, actor, $"road-review:{string.Join(",", ids.Take(3))}", "road", "Road report", valid ? "Done" : "FalseReport",
            $"{n} reports {(valid ? "theek" : "ghalat")}", null, ct);
        return ServiceResult<bool>.Ok(true, valid ? "Report theek maan li." : "Report ghalat — card hat jayega.");
    }

    public async Task<ServiceResult<bool>> AdvisoryAsync(Guid actor, OpsAdvisoryRequest x, CancellationToken ct)
    {
        var title = Clip(x.Title, 150);
        if (title.Length < 3) return Fail<bool>(400, "title_required", "Advisory ka unwan likhein.");
        var details = Clip(x.Details, 1000);
        var hours = Math.Clamp(x.Hours, 1, 72);
        await using var c = await OpenAsync(ct);
        await using (var cmd = new NpgsqlCommand(
            """
            INSERT INTO udrive.route_advisories
                (id, route_id, severity, title_en, title_ur, details_en, details_ur, source_name, starts_at, ends_at, is_active, created_at, updated_at)
            VALUES (gen_random_uuid(), NULL, 'Caution', @t, @t, @d, @d, 'UDrive Ops board', now(), now() + make_interval(hours => @h), true, now(), now());
            """, c))
        {
            cmd.Parameters.AddWithValue("t", title);
            cmd.Parameters.AddWithValue("d", details);
            cmd.Parameters.AddWithValue("h", hours);
            await cmd.ExecuteNonQueryAsync(ct);
        }
        if (!string.IsNullOrWhiteSpace(x.CardKey))
            await RecordAsync(c, actor, x.CardKey!, "advisory", title, "Done", $"Advisory {hours} ghante", TimeSpan.FromHours(6), ct);
        return ServiceResult<bool>.Ok(true, $"Advisory {hours} ghante ke liye lag gayi (Road advisories page).");
    }

    // ───────────────────────────────────────────────────────────────── WhatsApp

    public async Task<ServiceResult<OpsMessagePreviewDto>> PreviewAsync(OpsAudienceRequest x, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        var (label, recipients, tehsil) = await RecipientsAsync(c, x, ct);
        if (label is null) return Fail<OpsMessagePreviewDto>(400, "audience_invalid", "Kis ko bhejna hai, yeh samajh nahi aaya.");
        var body = DefaultBody(x.Audience, tehsil ?? "aap ke ilaqe", x.Body);
        return ServiceResult<OpsMessagePreviewDto>.Ok(new OpsMessagePreviewDto(x.Audience, label, body, recipients.Count,
            recipients.Select(r => new OpsRecipientDto(r.Name, Mask(r.Phone))).ToList()));
    }

    /// <summary>
    /// Queues the message the admin read and approved. The list is worked out
    /// again here — a recipient list is never taken from the browser.
    /// </summary>
    public async Task<ServiceResult<int>> SendAsync(Guid actor, OpsAudienceRequest x, CancellationToken ct)
    {
        var body = Clip(x.Body, 1000);
        if (body.Length < 10) return Fail<int>(400, "body_required", "Message likhein.");
        await using var c = await OpenAsync(ct);
        var (label, recipients, _) = await RecipientsAsync(c, x, ct);
        if (label is null) return Fail<int>(400, "audience_invalid", "Kis ko bhejna hai, yeh samajh nahi aaya.");
        if (recipients.Count == 0) return Fail<int>(409, "no_recipients", "Is waqt is list mein koi nahi.");

        await using var tx = await c.BeginTransactionAsync(ct);
        foreach (var r in recipients)
        {
            await using var cmd = new NpgsqlCommand(
                "INSERT INTO udrive.whatsapp_outbox (template_key, to_phone, body) VALUES ('ops_board', @p, @b);", c, tx);
            cmd.Parameters.AddWithValue("p", r.Phone.Length > 32 ? r.Phone[..32] : r.Phone);
            cmd.Parameters.AddWithValue("b", body.Replace("{naam}", FirstName(r.Name)));
            await cmd.ExecuteNonQueryAsync(ct);
        }
        await using (var log = new NpgsqlCommand(
            "INSERT INTO udrive.ops_messages (card_key, audience, recipients, body, actor_user_id) VALUES (@k, @a, @n, @b, @actor);", c, tx))
        {
            log.Parameters.Add(new NpgsqlParameter("k", NpgsqlDbType.Text) { Value = (object?)Clip(x.CardKey, 200) ?? DBNull.Value });
            log.Parameters.AddWithValue("a", label);
            log.Parameters.AddWithValue("n", recipients.Count);
            log.Parameters.AddWithValue("b", body);
            log.Parameters.AddWithValue("actor", actor);
            await log.ExecuteNonQueryAsync(ct);
        }
        await tx.CommitAsync(ct);
        return ServiceResult<int>.Ok(recipients.Count, $"{recipients.Count} logon ko WhatsApp queue ho gaya.");
    }

    private sealed record Recipient(string Name, string Phone);

    private static async Task<(string? Label, List<Recipient> Recipients, string? Tehsil)> RecipientsAsync(
        NpgsqlConnection c, OpsAudienceRequest x, CancellationToken ct)
    {
        if (x.TerritoryId is null) return (null, [], null);
        string? tehsil;
        await using (var cmd = new NpgsqlCommand("SELECT name FROM udrive.territories WHERE id = @t;", c))
        {
            cmd.Parameters.AddWithValue("t", x.TerritoryId.Value);
            tehsil = await cmd.ExecuteScalarAsync(ct) as string;
        }
        if (tehsil is null) return (null, [], null);
        var cls = VehicleClasses.FirstOrDefault(v => string.Equals(v, x.VehicleClass?.Trim(), StringComparison.OrdinalIgnoreCase)) ?? "";

        var (label, sql) = x.Audience switch
        {
            "offline_drivers" => ($"{tehsil}: offline {(cls == "" ? "" : cls + " ")}drivers (pichle 7 din active)", """
                SELECT DISTINCT ON (u.id) COALESCE(u.full_name, ''), u.phone_number
                  FROM udrive.driver_profiles dp
                  JOIN udrive.users u ON u.id = dp.user_id
                  JOIN udrive.vehicles v ON v.driver_profile_id = dp.id AND v.status NOT IN ('Deleted', 'Rejected')
                  LEFT JOIN udrive.driver_presence_locations p ON p.driver_profile_id = dp.id
                 WHERE dp.verification_status = 'Approved' AND u.status <> 'Deleted'
                   AND (@cls = '' OR udrive.vehicle_class(v.category) = @cls)
                   AND (p.server_timestamp IS NULL OR p.server_timestamp < now() - interval '5 minutes')
                   AND (dp.territory_id = @t OR v.territory_id = @t
                        OR (p.server_timestamp > now() - interval '7 days'
                            AND udrive.nearest_tehsil(ST_Y(p.location::geometry), ST_X(p.location::geometry)) = @t))
                 ORDER BY u.id LIMIT 100;
                """),
            "live_customers" => ($"{tehsil}: chalti rides ke customers", $"""
                SELECT DISTINCT ON (u.id) COALESCE(u.full_name, ''), u.phone_number
                  FROM udrive.trip_operations o
                  JOIN udrive.bookings b ON b.id = o.booking_id
                  JOIN udrive.users u ON u.id = b.customer_user_id
                 WHERE o.trip_status IN {ActiveTrip} AND b.territory_id = @t AND u.status <> 'Deleted' AND @cls = @cls
                 ORDER BY u.id LIMIT 100;
                """),
            "area_owners" => ($"{tehsil}: drivers / vehicle owners", """
                SELECT DISTINCT ON (u.id) COALESCE(u.full_name, ''), u.phone_number
                  FROM udrive.driver_profiles dp
                  JOIN udrive.users u ON u.id = dp.user_id
                  JOIN udrive.vehicles v ON v.driver_profile_id = dp.id AND v.status NOT IN ('Deleted', 'Rejected')
                 WHERE dp.verification_status = 'Approved' AND u.status <> 'Deleted'
                   AND (v.territory_id = @t OR dp.territory_id = @t)
                   AND (@cls = '' OR udrive.vehicle_class(v.category) = @cls)
                 ORDER BY u.id LIMIT 100;
                """),
            "upcoming_customers" => ($"{tehsil}: agle 3 din ke customers", """
                SELECT DISTINCT ON (u.id) COALESCE(u.full_name, ''), u.phone_number
                  FROM udrive.bookings b
                  JOIN udrive.users u ON u.id = b.customer_user_id
                 WHERE b.territory_id = @t AND b.status <> 'Cancelled' AND u.status <> 'Deleted'
                   AND b.pickup_at BETWEEN now() AND now() + interval '72 hours' AND @cls = @cls
                 ORDER BY u.id LIMIT 100;
                """),
            _ => ((string?)null, ""),
        };
        if (label is null) return (null, [], tehsil);

        var list = new List<Recipient>();
        await using (var cmd = new NpgsqlCommand(sql, c))
        {
            cmd.Parameters.AddWithValue("t", x.TerritoryId.Value);
            cmd.Parameters.AddWithValue("cls", cls);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                var phone = r.IsDBNull(1) ? "" : r.GetString(1).Trim();
                if (phone.Length < 10 || phone.StartsWith("deleted:", StringComparison.Ordinal)) continue;
                list.Add(new Recipient(r.GetString(0), phone));
            }
        }
        return (label, list, tehsil);
    }

    private static string DefaultBody(string audience, string tehsil, string? extra) => audience switch
    {
        "offline_drivers" =>
            $"Assalam o Alaikum {{naam}},\n{tehsil} mein is waqt rides ki demand zyada hai — customers intezar mein hain.\nApp kholein aur Online ho jayein.\n— UDrive",
        "live_customers" =>
            $"Assalam o Alaikum {{naam}},\n{tehsil} ki taraf raste mein rukawat ki ittila mili hai. Aap ka driver behtar rasta dekh raha hai. Madad ke liye app mein Support se rabta karein.\n— UDrive",
        "area_owners" =>
            $"Assalam o Alaikum {{naam}},\n{tehsil} mein rides aur tours ki demand barh rahi hai. App kholein, Online rahein aur apni gaari tour/rent ke liye on rakhein.\n— UDrive",
        "upcoming_customers" =>
            $"Assalam o Alaikum {{naam}},\n{tehsil} mein agle dinon mausam kharab hone ka andaza hai{(string.IsNullOrWhiteSpace(extra) ? "" : $" ({extra})")}. Safar se pehle halaat dekh lein; zaroorat ho to app se booking badal sakte hain.\n— UDrive",
        _ => "",
    };

    // ───────────────────────────────────────────────────────────────── driver app

    public async Task<ServiceResult<bool>> ReportRoadAsync(Guid userId, RoadReportRequest x, CancellationToken ct)
    {
        if (x.Latitude is < 23 or > 38 || x.Longitude is < 60 or > 78) return Fail<bool>(400, "location_invalid", "Location nahi mili.");
        var kind = x.Kind?.Trim() switch
        {
            "Landslide" => "Landslide", "Snow" => "Snow", "Accident" => "Accident", "Works" => "Works", _ => "Blocked",
        };
        await using var c = await OpenAsync(ct);
        Guid? driver;
        await using (var cmd = new NpgsqlCommand("SELECT id FROM udrive.driver_profiles WHERE user_id = @u;", c))
        {
            cmd.Parameters.AddWithValue("u", userId);
            driver = await cmd.ExecuteScalarAsync(ct) as Guid?;
        }
        if (driver is null) return Fail<bool>(403, "not_driver", "Sirf drivers road report kar sakte hain.");
        await using (var cmd = new NpgsqlCommand(
            "SELECT 1 FROM udrive.road_reports WHERE driver_profile_id = @d AND created_at > now() - interval '10 minutes';", c))
        {
            cmd.Parameters.AddWithValue("d", driver.Value);
            if (await cmd.ExecuteScalarAsync(ct) is not null)
                return Fail<bool>(429, "too_soon", "Aap ki report mil chuki hai. 10 minute baad dobara bhej sakte hain.");
        }
        await using (var cmd = new NpgsqlCommand(
            """
            INSERT INTO udrive.road_reports (driver_profile_id, latitude, longitude, kind, note, territory_id)
            VALUES (@d, @lat, @lng, @kind, @note, udrive.nearest_tehsil(@lat, @lng));
            """, c))
        {
            cmd.Parameters.AddWithValue("d", driver.Value);
            cmd.Parameters.AddWithValue("lat", x.Latitude);
            cmd.Parameters.AddWithValue("lng", x.Longitude);
            cmd.Parameters.AddWithValue("kind", kind);
            cmd.Parameters.AddWithValue("note", Clip(x.Note, 200));
            await cmd.ExecuteNonQueryAsync(ct);
        }
        return ServiceResult<bool>.Ok(true, "Shukriya — admin ko bata diya.");
    }

    // ───────────────────────────────────────────────────────────────── FareEngine hook

    /// <summary>
    /// Today's admin percent for this pickup's tehsil and vehicle class, or 0.
    /// Never throws: a quote must not fail because of the Ops board.
    /// </summary>
    public static async Task<decimal> FarePercentAsync(
        NpgsqlConnection c, double lat, double lng, string vehicleCategory, CancellationToken ct)
    {
        try
        {
            await using var cmd = new NpgsqlCommand(
                """
                SELECT percent FROM udrive.ops_fare_adjustments
                 WHERE ended_early_at IS NULL AND now() BETWEEN starts_at AND ends_at
                   AND vehicle_class = udrive.vehicle_class(@cat)
                   AND territory_id = udrive.nearest_tehsil(@lat, @lng)
                 ORDER BY created_at DESC LIMIT 1;
                """, c);
            cmd.Parameters.AddWithValue("cat", vehicleCategory ?? "");
            cmd.Parameters.AddWithValue("lat", lat);
            cmd.Parameters.AddWithValue("lng", lng);
            var value = await cmd.ExecuteScalarAsync(ct);
            return value is decimal d ? Math.Clamp(d, -20m, 20m) : value is null ? 0m : Math.Clamp(Convert.ToDecimal(value, En), -20m, 20m);
        }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            return 0m;
        }
    }

    // ───────────────────────────────────────────────────────────────── helpers

    private sealed record Ctx(NpgsqlConnection C, Guid? District, DateTimeOffset T0, DateTimeOffset Now, CancellationToken Ct)
    {
        public NpgsqlCommand Cmd(string sql)
        {
            var cmd = new NpgsqlCommand(sql, C);
            cmd.Parameters.AddWithValue("t0", T0.ToUniversalTime());
            cmd.Parameters.AddWithValue("y0", T0.AddDays(-1).ToUniversalTime());
            cmd.Parameters.AddWithValue("ynow", Now.AddDays(-1).ToUniversalTime());
            cmd.Parameters.AddWithValue("all", District is null);
            cmd.Parameters.AddWithValue("district", District ?? Guid.Empty);
            return cmd;
        }
    }

    /// <summary>A territory column inside the chosen district (or everywhere).</summary>
    private static string AreaSql(string column) =>
        $"(@all OR {column} IN (SELECT id FROM udrive.territories WHERE id = @district OR parent_id = @district))";

    private async Task RecordAsync(NpgsqlConnection c, Guid actor, string key, string kind, string title, string decision, string detail, TimeSpan? hide, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(
            """
            INSERT INTO udrive.ops_actions (card_key, card_kind, title, decision, detail, hide_until, actor_user_id)
            VALUES (@k, @kind, @title, @d, @detail, @hide, @a);
            """, c);
        cmd.Parameters.AddWithValue("k", Clip(key, 200));
        cmd.Parameters.AddWithValue("kind", kind);
        cmd.Parameters.AddWithValue("title", title);
        cmd.Parameters.AddWithValue("d", decision);
        cmd.Parameters.AddWithValue("detail", detail);
        cmd.Parameters.Add(new NpgsqlParameter("hide", NpgsqlDbType.TimestampTz) { Value = hide is null ? DBNull.Value : DateTimeOffset.UtcNow.Add(hide.Value) });
        cmd.Parameters.AddWithValue("a", actor);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken ct)
    {
        var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        return c;
    }

    private static OpsCardButtonDto Btn(string kind, string label, params (string Key, string Value)[] args) =>
        new(kind, label, args.ToDictionary(a => a.Key, a => a.Value));

    public static DateTimeOffset TodayStart(DateTimeOffset now)
    {
        var pk = now.ToOffset(Pk);
        return new DateTimeOffset(pk.Year, pk.Month, pk.Day, 0, 0, 0, Pk).ToUniversalTime();
    }

    private static string DayKey() => DateTimeOffset.UtcNow.ToOffset(Pk).ToString("yyyyMMdd", En);
    private static string Time(DateTimeOffset t) => t.ToOffset(Pk).ToString("h:mm tt", En);

    private static string Ago(DateTimeOffset t)
    {
        var m = (DateTimeOffset.UtcNow - t).TotalMinutes;
        return m < 1 ? "abhi" : m < 60 ? $"{Math.Round(m)} min pehle" : $"{Math.Round(m / 60, 1)} ghante pehle";
    }

    private static string KindLabel(string kind) => kind switch
    {
        "Landslide" => "landslide", "Snow" => "barf", "Accident" => "accident", "Works" => "kaam chal raha", _ => "road band",
    };

    private static double Km(double lat1, double lng1, double lat2, double lng2)
    {
        const double R = 6371;
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLng = (lng2 - lng1) * Math.PI / 180;
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(lat1 * Math.PI / 180) * Math.Cos(lat2 * Math.PI / 180) * Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        return 2 * R * Math.Asin(Math.Sqrt(a));
    }

    private static string FirstName(string name)
    {
        var n = name.Trim();
        if (n.Length == 0 || n.StartsWith("uDrive User", StringComparison.OrdinalIgnoreCase)) return "";
        return n.Split(' ', StringSplitOptions.RemoveEmptyEntries)[0];
    }

    private static string Mask(string phone) =>
        phone.Length <= 6 ? phone : phone[..4] + new string('•', phone.Length - 7) + phone[^3..];

    private static string Clip(string? value, int max)
    {
        var v = (value ?? "").Trim();
        return v.Length > max ? v[..max] : v;
    }

    private static ServiceResult<T> Fail<T>(int status, string code, string message) => ServiceResult<T>.Fail(status, code, message);
}

/// <summary>The stored Open-Meteo answer, reduced to what the board shows.</summary>
public sealed record WeatherPayload(double? NowTemp, int? NowCode, IReadOnlyList<OpsWeatherDayDto> Days)
{
    public static WeatherPayload? Parse(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            double? temp = null; int? code = null;
            if (root.TryGetProperty("current", out var cur))
            {
                if (cur.TryGetProperty("temperature_2m", out var t) && t.ValueKind == JsonValueKind.Number) temp = t.GetDouble();
                if (cur.TryGetProperty("weather_code", out var w) && w.ValueKind == JsonValueKind.Number) code = w.GetInt32();
            }
            var days = new List<OpsWeatherDayDto>();
            if (root.TryGetProperty("daily", out var d) && d.TryGetProperty("time", out var time))
            {
                double N(string key, int i) =>
                    d.TryGetProperty(key, out var arr) && arr.ValueKind == JsonValueKind.Array && i < arr.GetArrayLength()
                    && arr[i].ValueKind == JsonValueKind.Number ? arr[i].GetDouble() : 0;
                for (var i = 0; i < time.GetArrayLength() && i < 4; i++)
                {
                    days.Add(new OpsWeatherDayDto(time[i].GetString() ?? "", (int)N("weather_code", i), N("temperature_2m_max", i),
                        N("temperature_2m_min", i), N("precipitation_sum", i), N("snowfall_sum", i), N("wind_speed_10m_max", i)));
                }
            }
            return new WeatherPayload(temp, code, days);
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
