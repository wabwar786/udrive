using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Npgsql;
using System.Text.Json;
using System.Text.RegularExpressions;
using UDrive.Api.Common;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// Address autocomplete and reverse geocoding, proxied through our own server.
/// </summary>
/// <remarks>
/// Three reasons this is a server-side proxy rather than a direct call from the
/// app:
///
/// 1. The Google key never reaches the client, so it cannot be lifted out of a
///    web bundle or an APK and spent by someone else.
/// 2. An admin can set or rotate the key from the admin portal without shipping
///    a new build.
/// 3. Browsers block the <c>User-Agent</c> header, which OpenStreetMap's
///    Nominatim requires. A browser calling Nominatim directly fails CORS
///    preflight; a server calling it does not.
///
/// If no Google key is configured the proxy falls back to Nominatim, so search
/// keeps working before the key exists and if Google is ever over quota.
/// </remarks>
[ApiController]
[Route("api/v1/places")]
// Anonymous on purpose (address search happens before sign-in), so the cost
// control is a per-caller rate limit rather than a token. The tile route
// overrides this with its own, larger allowance.
[EnableRateLimiting("places")]
public sealed class PlacesController(
    IConfiguration configuration,
    IHttpClientFactory httpClientFactory) : ControllerBase
{
    private const string GoogleKeySetting = "places.google.apiKey";

    private string ConnectionString => ConnectionStringFactory.Resolve(configuration);

    /// <summary>Reads the admin-configured Google key, or null when unset.</summary>
    private async Task<string?> GoogleKeyAsync(CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = new NpgsqlConnection(ConnectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new NpgsqlCommand(
                "select value_json::text from udrive.system_settings where key = @key",
                connection);
            command.Parameters.AddWithValue("key", GoogleKeySetting);

            var raw = await command.ExecuteScalarAsync(cancellationToken) as string;
            if (string.IsNullOrWhiteSpace(raw)) return null;

            using var document = JsonDocument.Parse(raw);
            var value = document.RootElement.ValueKind == JsonValueKind.String
                ? document.RootElement.GetString()
                : null;

            return string.IsNullOrWhiteSpace(value) ? null : value;
        }
        catch
        {
            return null;
        }
    }

    [HttpGet("autocomplete")]
    public async Task<ActionResult<object>> Autocomplete(
        [FromQuery] string q,
        [FromQuery] double? lat = null,
        [FromQuery] double? lng = null,
        [FromQuery] string country = "pk",
        [FromQuery] string? sessionToken = null,
        CancellationToken cancellationToken = default)
    {
        var query = (q ?? string.Empty).Trim();
        if (query.Length < 2)
        {
            return Ok(ApiResponse<object>.Ok(new { results = Array.Empty<object>() }));
        }

        var client = httpClientFactory.CreateClient("places");
        var key = await GoogleKeyAsync(cancellationToken);

        if (!string.IsNullOrWhiteSpace(key))
        {
            var results = await GoogleSearchAsync(
                client, query, lat, lng, key!, sessionToken ?? string.Empty,
                cancellationToken);
            if (results.Count > 0)
            {
                return Ok(ApiResponse<object>.Ok(new
                {
                    results = await MergeLocalPlacesAsync(
                        query, results, cancellationToken),
                    source = "google"
                }));
            }
        }

        var fallback = await NominatimSearchAsync(client, query, country, cancellationToken);
        return Ok(ApiResponse<object>.Ok(new
        {
            results = await MergeLocalPlacesAsync(
                query, fallback, cancellationToken),
            source = "osm"
        }));
    }

    [HttpGet("reverse")]
    public async Task<ActionResult<object>> Reverse(
        [FromQuery] double lat,
        [FromQuery] double lng,
        CancellationToken cancellationToken = default)
    {
        var client = httpClientFactory.CreateClient("places");
        var key = await GoogleKeyAsync(cancellationToken);

        if (!string.IsNullOrWhiteSpace(key))
        {
            var address = await GoogleReverseAsync(client, lat, lng, key!, cancellationToken);
            if (!string.IsNullOrWhiteSpace(address))
            {
                return Ok(ApiResponse<object>.Ok(new { address, source = "google" }));
            }
        }

        var fallback = await NominatimReverseAsync(client, lat, lng, cancellationToken);
        return Ok(ApiResponse<object>.Ok(new { address = fallback, source = "osm" }));
    }

    /// <summary>
    /// Driving route between two points: distance, duration, the road it takes
    /// and the encoded polyline to draw on the map.
    /// </summary>
    /// <remarks>
    /// Uses the <b>Routes API</b> (<c>routes.googleapis.com/computeRoutes</c>),
    /// not the older Directions API. Google moved Directions and Distance
    /// Matrix to legacy status in March 2025: projects that had not already
    /// enabled them can no longer do so, so a new project like this one has to
    /// use Routes.
    ///
    /// Routes is a POST with a JSON body and requires a field mask — it will
    /// not return anything you did not explicitly ask for. That is a billing
    /// feature as much as an API one: you are charged by which fields you
    /// request, so the mask below asks only for duration, distance, the polyline
    /// and the road description.
    ///
    /// Straight-line distance is not an acceptable fallback in Kashmir: the road
    /// from Muzaffarabad to Kel is roughly three times the direct line, so a
    /// fare or an ETA built on it would be badly wrong. When Routes cannot
    /// answer, this returns no route rather than a misleading number.
    /// </remarks>
    [HttpGet("directions")]
    [ResponseCache(Duration = 120, Location = ResponseCacheLocation.Any)]
    public async Task<ActionResult<object>> Directions(
        [FromQuery] double originLat,
        [FromQuery] double originLng,
        [FromQuery] double destinationLat,
        [FromQuery] double destinationLng,
        [FromQuery] bool alternatives = true,
        CancellationToken cancellationToken = default)
    {
        var key = await GoogleKeyAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(key))
        {
            return Ok(ApiResponse<object>.Ok(new
            {
                routes = Array.Empty<object>(),
                reason = "no_key"
            }));
        }

        var client = httpClientFactory.CreateClient("places");
        var routes = new List<object>();

        try
        {
            var payload = new
            {
                origin = new
                {
                    location = new
                    {
                        latLng = new { latitude = originLat, longitude = originLng }
                    }
                },
                destination = new
                {
                    location = new
                    {
                        latLng = new
                        {
                            latitude = destinationLat,
                            longitude = destinationLng
                        }
                    }
                },
                travelMode = "DRIVE",
                routingPreference = "TRAFFIC_AWARE",
                // Routes returns an OVERVIEW polyline by default: heavily
                // simplified, so a road that curves through the hills is drawn
                // as a near-straight line. HIGH_QUALITY follows the actual
                // carriageway, which is the whole point of drawing it.
                polylineQuality = "HIGH_QUALITY",
                polylineEncoding = "ENCODED_POLYLINE",
                computeAlternativeRoutes = alternatives,
                languageCode = "en",
                regionCode = "PK",
                units = "METRIC"
            };

            using var request = new HttpRequestMessage(
                HttpMethod.Post,
                "https://routes.googleapis.com/directions/v2:computeRoutes")
            {
                Content = new StringContent(
                    JsonSerializer.Serialize(payload),
                    System.Text.Encoding.UTF8,
                    "application/json")
            };

            request.Headers.Add("X-Goog-Api-Key", key);
            // Ask for the minimum that answers "how long, how far, which road".
            request.Headers.Add(
                "X-Goog-FieldMask",
                "routes.duration,routes.distanceMeters," +
                "routes.polyline.encodedPolyline,routes.description");

            using var response = await client.SendAsync(request, cancellationToken);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);

            if (!response.IsSuccessStatusCode)
            {
                // Routes puts the reason in the body; surface it so the cause is
                // visible in logs rather than a bare status code.
                return Ok(ApiResponse<object>.Ok(new
                {
                    routes = Array.Empty<object>(),
                    reason = "upstream_error",
                    detail = body.Length > 500 ? body[..500] : body
                }));
            }

            using var document = JsonDocument.Parse(body);
            if (!document.RootElement.TryGetProperty("routes", out var items))
            {
                return Ok(ApiResponse<object>.Ok(new
                {
                    routes = Array.Empty<object>(),
                    reason = "ZERO_RESULTS"
                }));
            }

            // A route we cannot measure must not be passed on as one of zero
            // length. The customer's fare is distance x rate, so a zero here
            // quotes every vehicle at its minimum fare — and the client sorts
            // by distance, so the unmeasurable route is the one it picks.
            //
            // Filtered before Take(3), not inside the loop: otherwise one
            // unmeasurable route costs a real alternative Google returned.
            var usable = items
                .EnumerateArray()
                .Where(route =>
                    route.TryGetProperty("distanceMeters", out var dm)
                    && dm.GetInt32() > 0)
                .Take(3);

            foreach (var route in usable)
            {
                var distanceMetres = route.GetProperty("distanceMeters").GetInt32();

                // Routes returns duration as a protobuf string like "1234s".
                var seconds = 0;
                if (route.TryGetProperty("duration", out var dur))
                {
                    var raw = dur.GetString() ?? "0s";
                    int.TryParse(raw.TrimEnd('s'), out seconds);
                }

                routes.Add(new
                {
                    summary = route.TryGetProperty("description", out var desc)
                        ? desc.GetString()
                        : string.Empty,
                    distanceMetres,
                    durationSeconds = seconds,
                    polyline =
                        route.TryGetProperty("polyline", out var poly) &&
                        poly.TryGetProperty("encodedPolyline", out var pts)
                            ? pts.GetString()
                            : string.Empty
                });
            }
        }
        catch (Exception ex)
        {
            return Ok(ApiResponse<object>.Ok(new
            {
                routes = Array.Empty<object>(),
                reason = "exception",
                detail = ex.Message
            }));
        }

        // "ok" with nothing in it is not ok. The client shows `reason` under
        // "Could not work out the route", so an empty list with reason "ok"
        // printed the literal word "ok" at the customer.
        return routes.Count == 0
            ? Ok(ApiResponse<object>.Ok(new { routes, reason = "ZERO_RESULTS" }))
            : Ok(ApiResponse<object>.Ok(new { routes, reason = "ok" }));
    }

    /// <summary>
    /// Puts matching Azad Kashmir places at the top of the results.
    /// </summary>
    /// <remarks>
    /// Local places lead rather than trail. Someone typing "kel" in this app
    /// almost certainly means the village in Neelum, not a business elsewhere
    /// with those letters in its name, and making them scroll for it would be
    /// perverse in an app built for Kashmir.
    ///
    /// Duplicates are dropped by name so a place Google already returned does
    /// not appear twice.
    /// </remarks>
    private async Task<List<object>> MergeLocalPlacesAsync(
        string query,
        List<object> remote,
        CancellationToken cancellationToken)
    {
        var local = await LocalPlacesAsync(query, cancellationToken);
        if (local.Count == 0) return remote;

        var localNames = local
            .Select(place => place.name.ToLowerInvariant())
            .ToHashSet();

        var merged = new List<object>();
        merged.AddRange(local.Select(place => (object)new
        {
            title = place.name,
            subtitle = string.IsNullOrWhiteSpace(place.note)
                ? place.district
                : $"{place.district} · {place.note}",
            latitude = place.latitude,
            longitude = place.longitude
        }));

        foreach (var item in remote)
        {
            // The anonymous types from the search helpers all expose `title`.
            var title = item.GetType().GetProperty("title")?.GetValue(item) as string;
            if (title is not null &&
                localNames.Contains(title.ToLowerInvariant()))
            {
                continue;
            }
            merged.Add(item);
        }

        return merged.Take(10).ToList();
    }

    /// <summary>Admin-pinned places matching the query.</summary>
    /// <remarks>
    /// Matching happens in SQL so an admin adding a place takes effect on the
    /// next search, with no cache to wait on and no redeploy.
    ///
    /// `position(... in ...)` rather than a prefix match: someone searching
    /// "kel" expects Arang Kel, and "neelum" expects the valley.
    /// </remarks>
    private async Task<List<(string name, string district, string note,
        double latitude, double longitude)>> LocalPlacesAsync(
        string query,
        CancellationToken cancellationToken)
    {
        var results = new List<(string, string, string, double, double)>();
        var needle = query.Trim().ToLowerInvariant();
        if (needle.Length < 2) return results;

        const string sql = """
            SELECT name, district, note, latitude, longitude
            FROM udrive.custom_places
            WHERE is_active = true
              AND (
                    position(@needle in lower(name)) > 0
                 OR EXISTS (
                        SELECT 1 FROM unnest(aliases) AS alias
                        WHERE position(@needle in alias) > 0
                    )
              )
            ORDER BY
                CASE
                    WHEN lower(btrim(name)) = @needle THEN 0
                    WHEN lower(name) LIKE @prefix THEN 1
                    ELSE 2
                END,
                length(name)
            LIMIT 5;
            """;

        try
        {
            await using var connection = new NpgsqlConnection(ConnectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new NpgsqlCommand(sql, connection);
            command.Parameters.AddWithValue("needle", needle);
            command.Parameters.AddWithValue("prefix", needle + "%");

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                results.Add((
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetDouble(3),
                    reader.GetDouble(4)));
            }
        }
        catch
        {
            // Search must still work if this table is missing or unreachable.
        }

        return results;
    }

    // ------------------------------------------------------------- map tiles

    /// <summary>Cached Map Tiles session token, and when it stops being valid.</summary>
    /// <remarks>
    /// Google issues session tokens valid for two weeks and expects them to be
    /// reused. Creating one per tile request would be both slow and abusive, so
    /// one is held here and refreshed a day before it lapses.
    ///
    /// Static because the token belongs to the key, not to a request. The lock
    /// stops a burst of tile requests on a cold start from creating a dozen
    /// sessions at once.
    /// </remarks>
    private static string? _tileSession;
    private static DateTimeOffset _tileSessionExpiry = DateTimeOffset.MinValue;
    private static readonly SemaphoreSlim TileSessionLock = new(1, 1);

    private async Task<string?> TileSessionAsync(
        HttpClient client,
        string key,
        CancellationToken cancellationToken)
    {
        if (_tileSession is not null && DateTimeOffset.UtcNow < _tileSessionExpiry)
        {
            return _tileSession;
        }

        await TileSessionLock.WaitAsync(cancellationToken);
        try
        {
            // Re-check: another request may have created one while we waited.
            if (_tileSession is not null && DateTimeOffset.UtcNow < _tileSessionExpiry)
            {
                return _tileSession;
            }

            var payload = new
            {
                mapType = "roadmap",
                language = "en-US",
                region = "PK",
                overlay = false,
                // Styled at the source. Restyling tiles in the client would
                // affect the route and markers with them; here only the
                // basemap changes.
                //
                // Light, and close to Google's own default. The map is the one
                // part of the screen a person reads rather than looks at —
                // street names, junctions, which side of the road a pin is on —
                // and a dark basemap costs legibility in the daylight where a
                // ride app is actually used.
                //
                // Points of interest and transit stay off: the map exists to
                // show a route and nearby vehicles, and every extra label
                // competes with the markers that matter.
                styles = new object[]
                {
                    new { elementType = "labels.icon",
                          stylers = new object[] { new { visibility = "off" } } },
                    new { featureType = "poi",
                          stylers = new object[] { new { visibility = "off" } } },
                    new { featureType = "transit",
                          stylers = new object[] { new { visibility = "off" } } },
                    new { featureType = "poi.park",
                          elementType = "geometry",
                          stylers = new[] { new { color = "#E8F3E8" } } },
                    new { featureType = "road",
                          elementType = "labels.text.fill",
                          stylers = new[] { new { color = "#55606B" } } },
                    new { featureType = "water",
                          elementType = "geometry",
                          stylers = new[] { new { color = "#D9E9F2" } } },
                }
            };

            using var request = new HttpRequestMessage(
                HttpMethod.Post,
                $"https://tile.googleapis.com/v1/createSession?key={Uri.EscapeDataString(key)}")
            {
                Content = new StringContent(
                    JsonSerializer.Serialize(payload),
                    System.Text.Encoding.UTF8,
                    "application/json")
            };

            using var response = await client.SendAsync(request, cancellationToken);
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            if (!response.IsSuccessStatusCode) return null;

            using var document = JsonDocument.Parse(body);
            if (!document.RootElement.TryGetProperty("session", out var session))
            {
                return null;
            }

            _tileSession = session.GetString();

            // "expiry" is seconds since the epoch, as a string.
            if (document.RootElement.TryGetProperty("expiry", out var expiry) &&
                long.TryParse(expiry.GetString(), out var epoch))
            {
                _tileSessionExpiry =
                    DateTimeOffset.FromUnixTimeSeconds(epoch).AddDays(-1);
            }
            else
            {
                _tileSessionExpiry = DateTimeOffset.UtcNow.AddDays(7);
            }

            return _tileSession;
        }
        catch
        {
            return null;
        }
        finally
        {
            TileSessionLock.Release();
        }
    }

    /// <summary>
    /// Serves a Google map tile.
    /// </summary>
    /// <remarks>
    /// Proxied rather than fetched directly by the app so the key stays on the
    /// server. A tile URL built in the browser would carry the key in plain
    /// sight of anyone opening devtools.
    ///
    /// Tiles are immutable for practical purposes, so they are cached hard.
    /// After the first visit to an area the browser stops asking.
    /// </remarks>
    /// <remarks>
    /// The <c>v</c> segment is a cache buster, and it exists because of a real
    /// failure: the basemap style was changed from dark to light, and customers
    /// kept seeing the dark one. The URL had not changed, the tiles are cached
    /// for a week, so the browser never asked the server again — one phone
    /// showed a light map and another a dark one, for the same account, at the
    /// same moment.
    ///
    /// Bump <see cref="TileStyleVersion"/> whenever the style changes. Every
    /// tile becomes a new URL, nothing stale can be served, and nobody waits a
    /// week.
    /// </remarks>
    /// <summary>Bumped whenever the basemap style changes.</summary>
    public const int TileStyleVersion = 2;

    [HttpGet("tiles/v{v:int}/{z:int}/{x:int}/{y:int}")]
    [HttpGet("tiles/{z:int}/{x:int}/{y:int}")]
    [EnableRateLimiting("map-tiles")]
    [ResponseCache(Duration = 604800, Location = ResponseCacheLocation.Any)]
    public async Task<IActionResult> Tile(
        int z,
        int x,
        int y,
        CancellationToken cancellationToken = default)
    {
        if (z is < 0 or > 22) return NotFound();

        var key = await GoogleKeyAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(key)) return NotFound();

        var client = httpClientFactory.CreateClient("places");
        var session = await TileSessionAsync(client, key!, cancellationToken);
        if (session is null) return NotFound();

        try
        {
            var url =
                $"https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}" +
                $"?session={Uri.EscapeDataString(session)}" +
                $"&key={Uri.EscapeDataString(key!)}";

            using var response = await client.GetAsync(url, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                // A missing tile is normal at the edges of coverage; do not log
                // it as an error or the log fills with noise.
                return NotFound();
            }

            var bytes = await response.Content.ReadAsByteArrayAsync(cancellationToken);
            var contentType =
                response.Content.Headers.ContentType?.MediaType ?? "image/png";

            Response.Headers.CacheControl = "public, max-age=604800, immutable";
            return File(bytes, contentType);
        }
        catch
        {
            return NotFound();
        }
    }

    // ------------------------------------------------------------------ google

    /// <summary>
    /// Google Places Autocomplete predictions.
    /// </summary>
    /// <remarks>
    /// Autocomplete, not Text Search. Text Search looks for places that fully
    /// match a phrase, so a small town returns one or two results — searching
    /// "Dhirkot" gave a single suggestion where other apps show five.
    /// Autocomplete is built for partial input and returns the breadth people
    /// expect while typing.
    ///
    /// The trade-off is that predictions carry no coordinates: those come from
    /// a Details call when the customer picks one, which is one extra request
    /// per booking rather than per keystroke.
    ///
    /// A session token ties the keystrokes and the eventual Details call into
    /// one billable session instead of several.
    /// </remarks>
    private static async Task<List<object>> GoogleSearchAsync(
        HttpClient client,
        string query,
        double? lat,
        double? lng,
        string key,
        string sessionToken,
        CancellationToken cancellationToken)
    {
        var results = new List<object>();
        try
        {
            var url =
                "https://maps.googleapis.com/maps/api/place/autocomplete/json" +
                $"?input={Uri.EscapeDataString(query)}" +
                "&components=country:pk" +
                "&language=en" +
                $"&sessiontoken={Uri.EscapeDataString(sessionToken)}" +
                $"&key={Uri.EscapeDataString(key)}";

            // Bias towards the customer without excluding anywhere else: they
            // usually want the nearby Bazaar, but must still be able to search
            // another city.
            if (lat.HasValue && lng.HasValue)
            {
                url += $"&location={lat.Value},{lng.Value}&radius=80000";
            }

            using var response = await client.GetAsync(url, cancellationToken);
            if (!response.IsSuccessStatusCode) return results;

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            using var document = JsonDocument.Parse(body);

            if (!document.RootElement.TryGetProperty("predictions", out var items))
            {
                return results;
            }

            foreach (var item in items.EnumerateArray().Take(8))
            {
                var placeId = item.TryGetProperty("place_id", out var id)
                    ? id.GetString()
                    : null;
                if (string.IsNullOrWhiteSpace(placeId)) continue;

                var main = string.Empty;
                var secondary = string.Empty;
                if (item.TryGetProperty("structured_formatting", out var formatting))
                {
                    main = formatting.TryGetProperty("main_text", out var m)
                        ? m.GetString() ?? string.Empty
                        : string.Empty;
                    secondary =
                        formatting.TryGetProperty("secondary_text", out var sec)
                            ? sec.GetString() ?? string.Empty
                            : string.Empty;
                }

                if (main.Length == 0 &&
                    item.TryGetProperty("description", out var description))
                {
                    main = description.GetString() ?? string.Empty;
                }

                results.Add(new
                {
                    title = main,
                    subtitle = secondary,
                    // No coordinates yet — resolved by /places/details when the
                    // customer picks this one.
                    latitude = (double?)null,
                    longitude = (double?)null,
                    placeId
                });
            }
        }
        catch
        {
            // Fall through to Nominatim.
        }

        return results;
    }

    /// <summary>
    /// Coordinates for a prediction the customer chose.
    /// </summary>
    /// <remarks>
    /// Asks for the two fields it needs. Google bills Details by field set, so
    /// requesting the default everything would cost several times as much for
    /// data nothing reads.
    /// </remarks>
    [HttpGet("details")]
    public async Task<ActionResult<object>> Details(
        [FromQuery] string placeId,
        [FromQuery] string? sessionToken = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(placeId))
        {
            return BadRequest(new { success = false, message = "placeId is required." });
        }

        var key = await GoogleKeyAsync(cancellationToken);
        if (string.IsNullOrWhiteSpace(key))
        {
            return Ok(ApiResponse<object>.Ok(new { latitude = (double?)null }));
        }

        var client = httpClientFactory.CreateClient("places");
        try
        {
            var url =
                "https://maps.googleapis.com/maps/api/place/details/json" +
                $"?place_id={Uri.EscapeDataString(placeId)}" +
                "&fields=geometry/location,formatted_address" +
                (string.IsNullOrWhiteSpace(sessionToken)
                    ? string.Empty
                    : $"&sessiontoken={Uri.EscapeDataString(sessionToken)}") +
                $"&key={Uri.EscapeDataString(key!)}";

            using var response = await client.GetAsync(url, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return Ok(ApiResponse<object>.Ok(new { latitude = (double?)null }));
            }

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            using var document = JsonDocument.Parse(body);

            if (document.RootElement.TryGetProperty("result", out var result) &&
                result.TryGetProperty("geometry", out var geometry) &&
                geometry.TryGetProperty("location", out var location))
            {
                return Ok(ApiResponse<object>.Ok(new
                {
                    latitude = location.GetProperty("lat").GetDouble(),
                    longitude = location.GetProperty("lng").GetDouble(),
                    address = result.TryGetProperty("formatted_address", out var a)
                        ? a.GetString()
                        : null
                }));
            }
        }
        catch
        {
            // Reported as "no coordinates", which the app already handles.
        }

        return Ok(ApiResponse<object>.Ok(new { latitude = (double?)null }));
    }

    // --------------------------------------------------------- reverse geocode

    /// <summary>
    /// The name the customer would use for a point on the map.
    /// </summary>
    /// <remarks>
    /// Taking <c>results[0].formatted_address</c> is what produced pickup labels
    /// like <c>MV62+76W, Rd B, Muzaffarabad</c>. That is a plus code — Google's
    /// answer for a spot with no street number — and it is the one string a
    /// customer cannot check, cannot repeat to a driver on the phone, and cannot
    /// recognise as the place they are standing in.
    ///
    /// So this makes three attempts, cheapest first:
    ///
    /// 1. The geocoder's results, ranked. A building, a shop or a numbered
    ///    street address wins over a bare road, which wins over a
    ///    neighbourhood. Anything that is only a plus code is set aside.
    /// 2. If nothing above a bare road came back, the nearest named place
    ///    within 200 m — this is what turns a plus code into "Unity Plaza".
    ///    Only reached in the plus-code case, so the ordinary address costs no
    ///    extra request.
    /// 3. The plus code with its code stripped off the front, which at least
    ///    leaves the road and the town.
    /// </remarks>
    private static async Task<string?> GoogleReverseAsync(
        HttpClient client,
        double lat,
        double lng,
        string key,
        CancellationToken cancellationToken)
    {
        var (named, weak) =
            await GoogleGeocodeReverseAsync(client, lat, lng, key, cancellationToken);

        if (!string.IsNullOrWhiteSpace(named)) return named;

        var landmark =
            await GoogleNearestPlaceAsync(client, lat, lng, key, cancellationToken);
        if (!string.IsNullOrWhiteSpace(landmark)) return landmark;

        return string.IsNullOrWhiteSpace(weak) ? null : weak;
    }

    /// <summary>
    /// Runs the reverse geocode and splits its answer in two: a label good
    /// enough to show as-is, and a fallback that is better than nothing.
    /// </summary>
    private static async Task<(string? Named, string? Weak)> GoogleGeocodeReverseAsync(
        HttpClient client,
        double lat,
        double lng,
        string key,
        CancellationToken cancellationToken)
    {
        try
        {
            var url =
                "https://maps.googleapis.com/maps/api/geocode/json" +
                $"?latlng={lat},{lng}&key={Uri.EscapeDataString(key)}";

            using var response = await client.GetAsync(url, cancellationToken);
            if (!response.IsSuccessStatusCode) return (null, null);

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            using var document = JsonDocument.Parse(body);

            return PickGeocodeResult(document.RootElement);
        }
        catch
        {
            // Fall through.
        }

        return (null, null);
    }

    /// <summary>
    /// Chooses which of the geocoder's results to show. Separated from the
    /// request so it can be checked against real Google payloads.
    /// </summary>
    internal static (string? Named, string? Weak) PickGeocodeResult(JsonElement root)
    {
        if (!root.TryGetProperty("results", out var items) ||
            items.ValueKind != JsonValueKind.Array)
        {
            return (null, null);
        }

        // The best result that can be shown as it stands, and the best of
        // everything including the plus codes. They are tracked separately
        // because a stripped plus code ("Rd B, Muzaffarabad") still says more
        // than the town on its own, and would otherwise lose to it.
        string? named = null;
        var namedRank = -1;
        string? any = null;
        var anyRank = -1;

        // Only the first handful are worth reading. Google orders reverse
        // results from the most specific outwards, so by the time we are past
        // six we are looking at the district and then the country.
        var seen = 0;
        foreach (var item in items.EnumerateArray())
        {
            if (seen++ >= 6) break;

            var address = item.TryGetProperty("formatted_address", out var f)
                ? f.GetString() ?? string.Empty
                : string.Empty;
            if (address.Length == 0) continue;

            var types = new List<string>();
            if (item.TryGetProperty("types", out var typeList) &&
                typeList.ValueKind == JsonValueKind.Array)
            {
                foreach (var type in typeList.EnumerateArray())
                {
                    var value = type.GetString();
                    if (!string.IsNullOrEmpty(value)) types.Add(value);
                }
            }

            var tidy = TidyAddress(address);
            if (tidy.Length == 0) continue;

            var rank = RankPlaceTypes(types);
            if (rank > anyRank)
            {
                anyRank = rank;
                any = tidy;
            }

            // A plus code is never the answer, however specific Google thinks
            // it is. It survives only as the fallback above, with the code
            // itself already stripped off the front by TidyAddress.
            if (types.Contains("plus_code") || StartsWithPlusCode(address)) continue;

            if (rank > namedRank)
            {
                namedRank = rank;
                named = tidy;
            }
        }

        // A bare road or a whole neighbourhood is not a pickup point the
        // customer can stand at, so it goes in the same pile as the plus code:
        // usable, but worth one more lookup to beat.
        return namedRank >= 2 ? (named, any) : (null, any);
    }

    /// <summary>
    /// How much a reverse-geocode result tells the customer. Higher is better.
    /// </summary>
    private static int RankPlaceTypes(IReadOnlyCollection<string> types)
    {
        if (types.Contains("point_of_interest") ||
            types.Contains("establishment") ||
            types.Contains("premise") ||
            types.Contains("subpremise") ||
            types.Contains("transit_station") ||
            types.Contains("airport"))
        {
            return 4;
        }

        if (types.Contains("street_address")) return 3;
        if (types.Contains("intersection")) return 2;
        if (types.Contains("route")) return 1;
        return 0;
    }

    /// <summary>
    /// The nearest named place, used only when the geocoder had nothing but a
    /// plus code or a road name.
    /// </summary>
    /// <remarks>
    /// <c>rankby=distance</c> is what makes this usable: it returns the closest
    /// places rather than the most prominent ones in a radius, so a shop across
    /// the road wins over a landmark two kilometres away. The 200 m cut-off is
    /// applied here, from the geometry Google returns, because a name from
    /// further away would be worse than the road the customer is actually on.
    /// </remarks>
    private static async Task<string?> GoogleNearestPlaceAsync(
        HttpClient client,
        double lat,
        double lng,
        string key,
        CancellationToken cancellationToken)
    {
        try
        {
            var url =
                "https://maps.googleapis.com/maps/api/place/nearbysearch/json" +
                $"?location={lat},{lng}&rankby=distance" +
                $"&key={Uri.EscapeDataString(key)}";

            using var response = await client.GetAsync(url, cancellationToken);
            if (!response.IsSuccessStatusCode) return null;

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            using var document = JsonDocument.Parse(body);

            return PickNearestPlace(document.RootElement, lat, lng);
        }
        catch
        {
            // Fall through.
        }

        return null;
    }

    /// <summary>
    /// Chooses a landmark from a Nearby Search payload. Separated from the
    /// request so the 200 m rule can be checked without calling Google.
    /// </summary>
    internal static string? PickNearestPlace(JsonElement root, double lat, double lng)
    {
        if (!root.TryGetProperty("results", out var items) ||
            items.ValueKind != JsonValueKind.Array)
        {
            return null;
        }

        var seen = 0;
        foreach (var item in items.EnumerateArray())
        {
            if (seen++ >= 5) break;

            var name = item.TryGetProperty("name", out var n)
                ? (n.GetString() ?? string.Empty).Trim()
                : string.Empty;
            if (name.Length == 0 || IsPlusCodeToken(name)) continue;

            if (!item.TryGetProperty("geometry", out var geometry) ||
                !geometry.TryGetProperty("location", out var location) ||
                !location.TryGetProperty("lat", out var placeLat) ||
                !location.TryGetProperty("lng", out var placeLng))
            {
                continue;
            }

            if (MetresBetween(lat, lng, placeLat.GetDouble(), placeLng.GetDouble()) > 200)
            {
                // Sorted by distance, so the first one too far away means every
                // one after it is too.
                break;
            }

            var area = item.TryGetProperty("vicinity", out var v)
                ? (v.GetString() ?? string.Empty).Trim()
                : string.Empty;

            // "Unity Plaza, Blue Area" reads as a place. "Unity Plaza, Unity
            // Plaza" reads as a bug, so the area is dropped when it is already
            // part of the name.
            if (area.Length == 0 ||
                name.Contains(area, StringComparison.OrdinalIgnoreCase) ||
                area.Contains(name, StringComparison.OrdinalIgnoreCase))
            {
                return name;
            }

            return TidyAddress($"{name}, {area}");
        }

        return null;
    }

    private static readonly Regex PlusCodePattern = new(
        @"^[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3}$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static bool IsPlusCodeToken(string value) =>
        PlusCodePattern.IsMatch(value.Trim());

    private static bool StartsWithPlusCode(string address)
    {
        var first = address.Split(',', 2)[0];
        return IsPlusCodeToken(first);
    }

    /// <summary>
    /// Trims a Google address down to what fits on the pickup pill: no plus
    /// code, no country, no postcode, and at most three parts.
    /// </summary>
    private static string TidyAddress(string address)
    {
        var parts = address
            .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Where(part => !IsPlusCodeToken(part))
            .Where(part => !part.Equals("Pakistan", StringComparison.OrdinalIgnoreCase))
            // A bare number at the end is the postcode. A number at the front is
            // a house number, which is worth keeping, so only the tail is cut.
            .ToList();

        while (parts.Count > 1 && parts[^1].All(char.IsDigit))
        {
            parts.RemoveAt(parts.Count - 1);
        }

        return string.Join(", ", parts.Take(3));
    }

    private static double MetresBetween(
        double lat1, double lng1, double lat2, double lng2)
    {
        const double earthRadiusMetres = 6371000;
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLng = (lng2 - lng1) * Math.PI / 180;
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(lat1 * Math.PI / 180) * Math.Cos(lat2 * Math.PI / 180) *
                Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        return earthRadiusMetres * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }

    // --------------------------------------------------------------- nominatim

    /// <summary>
    /// OpenStreetMap fallback. Works with no key at all, which keeps search
    /// alive before a Google key is configured.
    /// </summary>
    private static async Task<List<object>> NominatimSearchAsync(
        HttpClient client,
        string query,
        string country,
        CancellationToken cancellationToken)
    {
        var results = new List<object>();
        try
        {
            var url =
                "https://nominatim.openstreetmap.org/search" +
                $"?q={Uri.EscapeDataString(query)}" +
                "&format=jsonv2&limit=8&addressdetails=1" +
                $"&countrycodes={Uri.EscapeDataString(country)}";

            using var response = await client.GetAsync(url, cancellationToken);
            if (!response.IsSuccessStatusCode) return results;

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            using var document = JsonDocument.Parse(body);

            foreach (var item in document.RootElement.EnumerateArray().Take(8))
            {
                if (!item.TryGetProperty("lat", out var latText) ||
                    !item.TryGetProperty("lon", out var lonText) ||
                    !double.TryParse(latText.GetString(), out var latitude) ||
                    !double.TryParse(lonText.GetString(), out var longitude))
                {
                    continue;
                }

                var display = item.TryGetProperty("display_name", out var d)
                    ? d.GetString() ?? string.Empty
                    : string.Empty;
                var parts = display.Split(',', StringSplitOptions.TrimEntries);

                var title = item.TryGetProperty("name", out var n) &&
                            !string.IsNullOrWhiteSpace(n.GetString())
                    ? n.GetString()!
                    : parts.FirstOrDefault() ?? display;

                results.Add(new
                {
                    title,
                    subtitle = string.Join(", ", parts.Skip(1).Take(3)),
                    latitude,
                    longitude
                });
            }
        }
        catch
        {
            // Empty list is the honest answer.
        }

        return results;
    }

    private static async Task<string> NominatimReverseAsync(
        HttpClient client,
        double lat,
        double lng,
        CancellationToken cancellationToken)
    {
        try
        {
            var url =
                "https://nominatim.openstreetmap.org/reverse" +
                $"?lat={lat}&lon={lng}&format=jsonv2&zoom=16";

            using var response = await client.GetAsync(url, cancellationToken);
            if (!response.IsSuccessStatusCode) return string.Empty;

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            using var document = JsonDocument.Parse(body);

            if (document.RootElement.TryGetProperty("display_name", out var display))
            {
                var parts = (display.GetString() ?? string.Empty)
                    .Split(',', StringSplitOptions.TrimEntries);
                return string.Join(", ", parts.Take(3));
            }
        }
        catch
        {
            // Fall through.
        }

        return string.Empty;
    }
}
