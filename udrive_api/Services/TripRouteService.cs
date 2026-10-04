using System.Globalization;
using System.Text;
using System.Text.Json;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The road for the current leg of a live ride — fetched once, stored, and
/// shared by the driver's and the customer's screens.
/// </summary>
/// <remarks>
/// <para><b>Why this exists.</b> Both live screens used to call the Places
/// directions proxy themselves, each again every 150 metres, at the
/// TRAFFIC_AWARE rate that Google bills as Routes <i>Pro</i>. One ride cost
/// thirty to sixty paid calls. Here a leg costs one call, plus a reroute only
/// when the driver has genuinely left the road.</para>
///
/// <para><b>Who can spend money.</b> Only the assigned driver can cause a Google
/// call, through <see cref="EnsureAsync"/>. The customer's screen only ever
/// reads the stored row, so a customer leaving the tracking screen open all
/// afternoon costs nothing.</para>
///
/// <para><b>The guards, in the order they are checked:</b></para>
/// <list type="number">
/// <item>A stored road for this leg is returned as-is unless a reroute is
/// asked for.</item>
/// <item>A reroute is refused for 30 seconds after the last road, and while the
/// driver is still within 40 metres of it — the phone's own check, repeated
/// here so a misbehaving client cannot spend for it.</item>
/// <item>At most <c>routing.max_reroutes_per_leg</c> reroutes per leg.</item>
/// <item>At most <c>routing.google_daily_cap</c> calls per Google quota day
/// across the whole platform.</item>
/// </list>
///
/// <para><b>Billing.</b> <c>TRAFFIC_UNAWARE</c> keeps every call in the Routes
/// <i>Essentials</i> SKU (10,000 free a month). Traffic data on Azad Kashmir's
/// roads is thin enough that the traffic-aware estimate was not buying much.</para>
/// </remarks>
public sealed class TripRouteService(
    string connectionString,
    IHttpClientFactory httpClientFactory,
    ILogger<TripRouteService> logger)
{
    private const string GoogleKeySetting = "places.google.apiKey";
    private const string DailyCapSetting = "routing.google_daily_cap";
    private const string MaxReroutesSetting = "routing.max_reroutes_per_leg";

    private const int DefaultDailyCap = 300;
    private const int DefaultMaxReroutes = 6;

    /// <summary>A reroute closer than this to the stored road is not a reroute.</summary>
    private const double OnRouteMeters = 40;

    /// <summary>Minimum gap between two roads for the same leg.</summary>
    private static readonly TimeSpan RerouteCooldown = TimeSpan.FromSeconds(30);

    /// <summary>
    /// A stored road whose end is further than this from the leg's target was
    /// computed for a different target (the destination was edited) and does
    /// not count.
    /// </summary>
    private const double SameTargetMeters = 60;

    private static readonly string[] ActiveStatuses =
    [
        "DriverAssigned", "DriverAccepted", "DriverEnRoute",
        "DriverArrived", "TripStarted", "Emergency"
    ];

    private sealed record Context(
        string Status,
        string Leg,
        double? TargetLatitude,
        double? TargetLongitude,
        bool IsCustomer,
        bool IsDriver);

    private sealed record StoredRoute(
        Guid Id,
        int DistanceMeters,
        int DurationSeconds,
        string Polyline,
        IReadOnlyList<TripRouteStepDto> Steps,
        DateTimeOffset CreatedAt,
        double TargetLatitude,
        double TargetLongitude);

    // ─────────────────────────────────────────────────────────────── read

    /// <summary>The stored road for the current leg. Never calls Google.</summary>
    public async Task<ServiceResult<TripRouteDto>> GetAsync(
        Guid userId,
        bool privileged,
        Guid bookingId,
        CancellationToken ct)
    {
        await using var cn = new NpgsqlConnection(connectionString);
        await cn.OpenAsync(ct);

        var context = await LoadContextAsync(cn, null, userId, bookingId, ct);
        if (context is null)
        {
            return ServiceResult<TripRouteDto>.Fail(404, "trip_not_found", "Trip not found.");
        }
        if (!privileged && !context.IsCustomer && !context.IsDriver)
        {
            return ServiceResult<TripRouteDto>.Fail(403, "route_forbidden", "You cannot view this trip.");
        }

        var stored = await LatestAsync(cn, null, bookingId, context, ct);
        var maxReroutes = await ReadIntSettingAsync(cn, null, MaxReroutesSetting, DefaultMaxReroutes, ct);
        var used = stored is null ? 0 : await RerouteCountAsync(cn, null, bookingId, context.Leg, ct);

        return ServiceResult<TripRouteDto>.Ok(
            ToDto(context, stored, stored is null ? "no_route_yet" : null, used, maxReroutes));
    }

    // ─────────────────────────────────────────────────────────── compute

    /// <summary>
    /// Returns the road for the current leg, computing it only when the guards
    /// in the class remarks allow. Driver only.
    /// </summary>
    public async Task<ServiceResult<TripRouteDto>> EnsureAsync(
        Guid userId,
        Guid bookingId,
        TripRouteRequest request,
        CancellationToken ct)
    {
        if (!IsCoordinate(request.Latitude, request.Longitude))
        {
            return ServiceResult<TripRouteDto>.Fail(400, "invalid_location", "The driver location is not valid.");
        }

        await using var cn = new NpgsqlConnection(connectionString);
        await cn.OpenAsync(ct);
        await using var tx = await cn.BeginTransactionAsync(ct);

        // One computation per trip at a time. Two taps on "open live ride", or
        // the screen reopening while the first request is still out, would
        // otherwise both find no stored road and both pay for one.
        await using (var lockCommand = new NpgsqlCommand(
            "select pg_advisory_xact_lock(hashtext(@key))", cn, tx))
        {
            lockCommand.Parameters.AddWithValue("key", "trip-route:" + bookingId.ToString("N"));
            await lockCommand.ExecuteNonQueryAsync(ct);
        }

        var context = await LoadContextAsync(cn, tx, userId, bookingId, ct);
        if (context is null)
        {
            return ServiceResult<TripRouteDto>.Fail(404, "trip_not_found", "Trip not found.");
        }
        if (!context.IsDriver)
        {
            return ServiceResult<TripRouteDto>.Fail(403, "route_forbidden", "Only the assigned driver can request the route.");
        }
        if (!ActiveStatuses.Contains(context.Status))
        {
            return ServiceResult<TripRouteDto>.Fail(409, "route_inactive", "This trip is not live.");
        }

        var maxReroutes = await ReadIntSettingAsync(cn, tx, MaxReroutesSetting, DefaultMaxReroutes, ct);

        if (context.TargetLatitude is null || context.TargetLongitude is null)
        {
            await tx.CommitAsync(ct);
            return ServiceResult<TripRouteDto>.Ok(ToDto(context, null, "no_target", 0, maxReroutes));
        }

        var stored = await LatestAsync(cn, tx, bookingId, context, ct);
        var used = stored is null ? 0 : await RerouteCountAsync(cn, tx, bookingId, context.Leg, ct);

        if (stored is not null)
        {
            string? keep = null;
            if (!request.Reroute)
            {
                keep = string.Empty; // returned as asked — no reason to report
            }
            else if (DateTimeOffset.UtcNow - stored.CreatedAt < RerouteCooldown)
            {
                keep = "cooldown";
            }
            else if (DistanceToPolylineMeters(request.Latitude, request.Longitude, stored.Polyline) <= OnRouteMeters)
            {
                keep = "on_route";
            }
            else if (used >= maxReroutes)
            {
                keep = "reroute_limit";
            }

            if (keep is not null)
            {
                await tx.CommitAsync(ct);
                return ServiceResult<TripRouteDto>.Ok(
                    ToDto(context, stored, keep.Length == 0 ? null : keep, used, maxReroutes));
            }
        }

        var dailyCap = await ReadIntSettingAsync(cn, tx, DailyCapSetting, DefaultDailyCap, ct);
        if (await TodayCountAsync(cn, tx, ct) >= dailyCap)
        {
            logger.LogWarning(
                "Live-ride routing daily cap of {Cap} reached; booking {Booking} keeps its last route.",
                dailyCap, bookingId);
            await tx.CommitAsync(ct);
            return ServiceResult<TripRouteDto>.Ok(ToDto(context, stored, "daily_cap", used, maxReroutes));
        }

        var key = await GoogleKeyAsync(cn, tx, ct);
        if (string.IsNullOrWhiteSpace(key))
        {
            await tx.CommitAsync(ct);
            return ServiceResult<TripRouteDto>.Ok(ToDto(context, stored, "no_key", used, maxReroutes));
        }

        var computed = await ComputeAsync(
            key,
            request.Latitude,
            request.Longitude,
            context.TargetLatitude.Value,
            context.TargetLongitude.Value,
            ct);

        if (computed is null)
        {
            await tx.CommitAsync(ct);
            return ServiceResult<TripRouteDto>.Ok(ToDto(context, stored, "upstream_error", used, maxReroutes));
        }

        var isReroute = stored is not null;
        var inserted = await InsertAsync(
            cn, tx, bookingId, context, request, isReroute, computed.Value, ct);
        await tx.CommitAsync(ct);

        return ServiceResult<TripRouteDto>.Ok(
            ToDto(context, inserted, null, used + (isReroute ? 1 : 0), maxReroutes));
    }

    // ──────────────────────────────────────────────────────────── google

    private async Task<(int Distance, int Duration, string Polyline, List<TripRouteStepDto> Steps)?> ComputeAsync(
        string key,
        double originLatitude,
        double originLongitude,
        double targetLatitude,
        double targetLongitude,
        CancellationToken ct)
    {
        var payload = new
        {
            origin = new { location = new { latLng = new { latitude = originLatitude, longitude = originLongitude } } },
            destination = new { location = new { latLng = new { latitude = targetLatitude, longitude = targetLongitude } } },
            travelMode = "DRIVE",
            // Essentials. TRAFFIC_AWARE is what moves a call to Pro.
            routingPreference = "TRAFFIC_UNAWARE",
            // HIGH_QUALITY follows the carriageway through the hills; the
            // overview polyline cuts corners, and the driver's phone measures
            // "have I left the road" against this line.
            polylineQuality = "HIGH_QUALITY",
            polylineEncoding = "ENCODED_POLYLINE",
            computeAlternativeRoutes = false,
            languageCode = "en",
            regionCode = "PK",
            units = "METRIC"
        };

        try
        {
            var client = httpClientFactory.CreateClient("places");
            using var request = new HttpRequestMessage(
                HttpMethod.Post,
                "https://routes.googleapis.com/directions/v2:computeRoutes")
            {
                Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json")
            };
            request.Headers.Add("X-Goog-Api-Key", key);
            // Only what the live screens use: the line, its length and time,
            // and for each turn its maneuver, length and starting point. No
            // instruction text — the app speaks Urdu from its own clips.
            request.Headers.Add(
                "X-Goog-FieldMask",
                "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline," +
                "routes.legs.steps.distanceMeters,routes.legs.steps.startLocation," +
                "routes.legs.steps.navigationInstruction.maneuver");

            using var response = await client.SendAsync(request, ct);
            var body = await response.Content.ReadAsStringAsync(ct);
            if (!response.IsSuccessStatusCode)
            {
                logger.LogWarning(
                    "Routes API returned {Status} for a live-ride route: {Body}",
                    (int)response.StatusCode,
                    body.Length > 400 ? body[..400] : body);
                return null;
            }

            return ParseRoute(body);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException)
        {
            logger.LogWarning(ex, "Routes API call for a live-ride route failed.");
            return null;
        }
    }

    /// <summary>
    /// Reads the first route out of a computeRoutes response. Public for tests.
    /// </summary>
    public static (int Distance, int Duration, string Polyline, List<TripRouteStepDto> Steps)? ParseRoute(string body)
    {
        using var document = JsonDocument.Parse(body);
        if (!document.RootElement.TryGetProperty("routes", out var routes) ||
            routes.ValueKind != JsonValueKind.Array ||
            routes.GetArrayLength() == 0)
        {
            return null;
        }

        var route = routes[0];
        var polyline = route.TryGetProperty("polyline", out var poly) &&
                       poly.TryGetProperty("encodedPolyline", out var encoded)
            ? encoded.GetString() ?? string.Empty
            : string.Empty;
        var distance = route.TryGetProperty("distanceMeters", out var dm) ? dm.GetInt32() : 0;
        if (polyline.Length == 0 || distance <= 0) return null;

        // Protobuf duration: "1234s".
        var duration = 0;
        if (route.TryGetProperty("duration", out var dur))
        {
            int.TryParse(
                (dur.GetString() ?? "0s").TrimEnd('s'),
                NumberStyles.Integer,
                CultureInfo.InvariantCulture,
                out duration);
        }

        var steps = new List<TripRouteStepDto>();
        if (route.TryGetProperty("legs", out var legs) && legs.ValueKind == JsonValueKind.Array)
        {
            foreach (var leg in legs.EnumerateArray())
            {
                if (!leg.TryGetProperty("steps", out var items) || items.ValueKind != JsonValueKind.Array)
                {
                    continue;
                }

                foreach (var step in items.EnumerateArray())
                {
                    if (!step.TryGetProperty("startLocation", out var start) ||
                        !start.TryGetProperty("latLng", out var latLng) ||
                        !latLng.TryGetProperty("latitude", out var lat) ||
                        !latLng.TryGetProperty("longitude", out var lng))
                    {
                        continue;
                    }

                    var maneuver = step.TryGetProperty("navigationInstruction", out var instruction) &&
                                   instruction.TryGetProperty("maneuver", out var m)
                        ? m.GetString() ?? "MANEUVER_UNSPECIFIED"
                        : "MANEUVER_UNSPECIFIED";

                    steps.Add(new TripRouteStepDto(
                        maneuver,
                        step.TryGetProperty("distanceMeters", out var sd) ? sd.GetInt32() : 0,
                        lat.GetDouble(),
                        lng.GetDouble()));
                }
            }
        }

        return (distance, duration, polyline, steps);
    }

    // ──────────────────────────────────────────────────────────────── sql

    private static async Task<Context?> LoadContextAsync(
        NpgsqlConnection cn,
        NpgsqlTransaction? tx,
        Guid userId,
        Guid bookingId,
        CancellationToken ct)
    {
        const string sql = """
            select o.trip_status,
                   (o.started_at is not null or o.trip_status = 'TripStarted'),
                   ST_Y(rr.pickup_location::geometry), ST_X(rr.pickup_location::geometry),
                   ST_Y(rr.destination_location::geometry), ST_X(rr.destination_location::geometry),
                   b.customer_user_id = @user,
                   coalesce(dp.user_id = @user, false)
            from udrive.bookings b
            join udrive.trip_operations o on o.booking_id = b.id
            left join udrive.ride_requests rr on rr.id = b.ride_request_id
            left join udrive.driver_profiles dp on dp.id = b.driver_profile_id
            where b.id = @booking
            """;

        await using var cmd = new NpgsqlCommand(sql, cn, tx);
        cmd.Parameters.AddWithValue("booking", bookingId);
        cmd.Parameters.AddWithValue("user", userId);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        if (!await r.ReadAsync(ct)) return null;

        var started = r.GetBoolean(1);
        double? Read(int i) => r.IsDBNull(i) ? null : r.GetDouble(i);

        return new Context(
            r.GetString(0),
            started ? "destination" : "pickup",
            started ? Read(4) : Read(2),
            started ? Read(5) : Read(3),
            r.GetBoolean(6),
            r.GetBoolean(7));
    }

    private static async Task<StoredRoute?> LatestAsync(
        NpgsqlConnection cn,
        NpgsqlTransaction? tx,
        Guid bookingId,
        Context context,
        CancellationToken ct)
    {
        const string sql = """
            select id, distance_meters, duration_seconds, polyline, steps::text,
                   created_at, target_latitude, target_longitude
            from udrive.trip_routes
            where booking_id = @booking and leg = @leg
            order by created_at desc
            limit 1
            """;

        await using var cmd = new NpgsqlCommand(sql, cn, tx);
        cmd.Parameters.AddWithValue("booking", bookingId);
        cmd.Parameters.AddWithValue("leg", context.Leg);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        if (!await r.ReadAsync(ct)) return null;

        var stored = new StoredRoute(
            r.GetGuid(0),
            r.GetInt32(1),
            r.GetInt32(2),
            r.GetString(3),
            ParseSteps(r.GetString(4)),
            r.GetFieldValue<DateTimeOffset>(5),
            r.GetDouble(6),
            r.GetDouble(7));

        // Computed for a target that has since moved — not this leg's road.
        if (context.TargetLatitude is double lat && context.TargetLongitude is double lng &&
            HaversineMeters(lat, lng, stored.TargetLatitude, stored.TargetLongitude) > SameTargetMeters)
        {
            return null;
        }

        return stored;
    }

    private static async Task<StoredRoute> InsertAsync(
        NpgsqlConnection cn,
        NpgsqlTransaction tx,
        Guid bookingId,
        Context context,
        TripRouteRequest request,
        bool isReroute,
        (int Distance, int Duration, string Polyline, List<TripRouteStepDto> Steps) route,
        CancellationToken ct)
    {
        const string sql = """
            insert into udrive.trip_routes
                (booking_id, leg, reason, origin_latitude, origin_longitude,
                 target_latitude, target_longitude, distance_meters, duration_seconds,
                 polyline, steps)
            values
                (@booking, @leg, @reason, @olat, @olng, @tlat, @tlng, @distance, @duration,
                 @polyline, cast(@steps as jsonb))
            returning id, created_at
            """;

        var stepsJson = JsonSerializer.Serialize(
            route.Steps.Select(s => new { m = s.Maneuver, d = s.DistanceMeters, lat = s.Latitude, lng = s.Longitude }));

        await using var cmd = new NpgsqlCommand(sql, cn, tx);
        cmd.Parameters.AddWithValue("booking", bookingId);
        cmd.Parameters.AddWithValue("leg", context.Leg);
        cmd.Parameters.AddWithValue("reason", isReroute ? "reroute" : "initial");
        cmd.Parameters.AddWithValue("olat", request.Latitude);
        cmd.Parameters.AddWithValue("olng", request.Longitude);
        cmd.Parameters.AddWithValue("tlat", context.TargetLatitude!.Value);
        cmd.Parameters.AddWithValue("tlng", context.TargetLongitude!.Value);
        cmd.Parameters.AddWithValue("distance", route.Distance);
        cmd.Parameters.AddWithValue("duration", route.Duration);
        cmd.Parameters.AddWithValue("polyline", route.Polyline);
        cmd.Parameters.AddWithValue("steps", stepsJson);

        await using var r = await cmd.ExecuteReaderAsync(ct);
        await r.ReadAsync(ct);
        var id = r.GetGuid(0);
        var createdAt = r.GetFieldValue<DateTimeOffset>(1);

        return new StoredRoute(
            id, route.Distance, route.Duration, route.Polyline, route.Steps, createdAt,
            context.TargetLatitude.Value, context.TargetLongitude.Value);
    }

    private static async Task<int> RerouteCountAsync(
        NpgsqlConnection cn, NpgsqlTransaction? tx, Guid bookingId, string leg, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(
            "select count(*) from udrive.trip_routes where booking_id = @booking and leg = @leg and reason = 'reroute'",
            cn, tx);
        cmd.Parameters.AddWithValue("booking", bookingId);
        cmd.Parameters.AddWithValue("leg", leg);
        return Convert.ToInt32(await cmd.ExecuteScalarAsync(ct), CultureInfo.InvariantCulture);
    }

    /// <summary>Paid calls since the start of Google's quota day (midnight US Pacific).</summary>
    private static async Task<int> TodayCountAsync(NpgsqlConnection cn, NpgsqlTransaction tx, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(
            """
            select count(*) from udrive.trip_routes
            where created_at >= (date_trunc('day', now() at time zone 'America/Los_Angeles')
                                 at time zone 'America/Los_Angeles')
            """,
            cn, tx);
        return Convert.ToInt32(await cmd.ExecuteScalarAsync(ct), CultureInfo.InvariantCulture);
    }

    private static async Task<int> ReadIntSettingAsync(
        NpgsqlConnection cn, NpgsqlTransaction? tx, string key, int fallback, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(
            "select value_json::text from udrive.system_settings where key = @key", cn, tx);
        cmd.Parameters.AddWithValue("key", key);
        var raw = await cmd.ExecuteScalarAsync(ct) as string;
        if (string.IsNullOrWhiteSpace(raw)) return fallback;

        try
        {
            using var document = JsonDocument.Parse(raw);
            var root = document.RootElement;
            var value = root.ValueKind switch
            {
                JsonValueKind.Number when root.TryGetInt32(out var n) => n,
                JsonValueKind.String when int.TryParse(root.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var s) => s,
                _ => fallback
            };
            return value < 0 ? fallback : value;
        }
        catch (JsonException)
        {
            return fallback;
        }
    }

    private static async Task<string?> GoogleKeyAsync(NpgsqlConnection cn, NpgsqlTransaction tx, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(
            "select value_json::text from udrive.system_settings where key = @key", cn, tx);
        cmd.Parameters.AddWithValue("key", GoogleKeySetting);
        var raw = await cmd.ExecuteScalarAsync(ct) as string;
        if (string.IsNullOrWhiteSpace(raw)) return null;

        try
        {
            using var document = JsonDocument.Parse(raw);
            return document.RootElement.ValueKind == JsonValueKind.String
                ? document.RootElement.GetString()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    // ──────────────────────────────────────────────────────────── helpers

    private static TripRouteDto ToDto(
        Context context, StoredRoute? stored, string? reason, int used, int allowed) =>
        stored is null
            ? new TripRouteDto(
                null, context.Leg, false, reason, 0, 0, string.Empty, [], null,
                context.TargetLatitude, context.TargetLongitude, used, allowed)
            : new TripRouteDto(
                stored.Id, context.Leg, true, reason, stored.DistanceMeters, stored.DurationSeconds,
                stored.Polyline, stored.Steps, stored.CreatedAt,
                context.TargetLatitude ?? stored.TargetLatitude,
                context.TargetLongitude ?? stored.TargetLongitude,
                used, allowed);

    private static IReadOnlyList<TripRouteStepDto> ParseSteps(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Array) return [];

            var list = new List<TripRouteStepDto>();
            foreach (var item in document.RootElement.EnumerateArray())
            {
                if (!item.TryGetProperty("lat", out var lat) || !item.TryGetProperty("lng", out var lng)) continue;
                list.Add(new TripRouteStepDto(
                    item.TryGetProperty("m", out var m) ? m.GetString() ?? "MANEUVER_UNSPECIFIED" : "MANEUVER_UNSPECIFIED",
                    item.TryGetProperty("d", out var d) ? d.GetInt32() : 0,
                    lat.GetDouble(),
                    lng.GetDouble()));
            }
            return list;
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private static bool IsCoordinate(double latitude, double longitude) =>
        double.IsFinite(latitude) && double.IsFinite(longitude) &&
        latitude is >= -90 and <= 90 && longitude is >= -180 and <= 180 &&
        !(Math.Abs(latitude) < 0.01 && Math.Abs(longitude) < 0.01);

    /// <summary>Shortest distance from a point to an encoded polyline, in metres. Public for tests.</summary>
    public static double DistanceToPolylineMeters(double latitude, double longitude, string encoded)
    {
        var points = DecodePolyline(encoded);
        if (points.Count == 0) return double.MaxValue;
        if (points.Count == 1) return HaversineMeters(latitude, longitude, points[0].Lat, points[0].Lng);

        // Flat projection around the driver: accurate to well under a metre at
        // the few-hundred-metre scale this decision is made on.
        const double metresPerDegree = 111_320;
        var cos = Math.Cos(latitude * Math.PI / 180);
        var best = double.MaxValue;

        for (var i = 0; i < points.Count - 1; i++)
        {
            var ax = (points[i].Lng - longitude) * metresPerDegree * cos;
            var ay = (points[i].Lat - latitude) * metresPerDegree;
            var bx = (points[i + 1].Lng - longitude) * metresPerDegree * cos;
            var by = (points[i + 1].Lat - latitude) * metresPerDegree;

            var dx = bx - ax;
            var dy = by - ay;
            var lengthSquared = dx * dx + dy * dy;
            var t = lengthSquared == 0 ? 0 : Math.Clamp(-(ax * dx + ay * dy) / lengthSquared, 0, 1);
            var px = ax + t * dx;
            var py = ay + t * dy;
            var distance = Math.Sqrt(px * px + py * py);
            if (distance < best) best = distance;
        }

        return best;
    }

    /// <summary>Google's encoded polyline format. Public for tests.</summary>
    public static List<(double Lat, double Lng)> DecodePolyline(string encoded)
    {
        var points = new List<(double Lat, double Lng)>();
        int index = 0, lat = 0, lng = 0;

        while (index < encoded.Length)
        {
            if (!TryReadValue(encoded, ref index, out var dLat)) break;
            if (!TryReadValue(encoded, ref index, out var dLng)) break;
            lat += dLat;
            lng += dLng;
            points.Add((lat / 1e5, lng / 1e5));
        }

        return points;
    }

    private static bool TryReadValue(string encoded, ref int index, out int value)
    {
        int result = 0, shift = 0, b;
        do
        {
            if (index >= encoded.Length)
            {
                value = 0;
                return false;
            }
            b = encoded[index++] - 63;
            result |= (b & 0x1f) << shift;
            shift += 5;
        } while (b >= 0x20 && shift < 32);

        value = (result & 1) != 0 ? ~(result >> 1) : result >> 1;
        return true;
    }

    private static double HaversineMeters(double lat1, double lon1, double lat2, double lon2)
    {
        const double r = 6_371_000;
        var p1 = lat1 * Math.PI / 180;
        var p2 = lat2 * Math.PI / 180;
        var dp = (lat2 - lat1) * Math.PI / 180;
        var dl = (lon2 - lon1) * Math.PI / 180;
        var a = Math.Sin(dp / 2) * Math.Sin(dp / 2) +
                Math.Cos(p1) * Math.Cos(p2) * Math.Sin(dl / 2) * Math.Sin(dl / 2);
        return r * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }
}
