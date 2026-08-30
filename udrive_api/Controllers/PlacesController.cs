using Microsoft.AspNetCore.Mvc;
using Npgsql;
using System.Text.Json;
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
            var results = await GoogleSearchAsync(client, query, lat, lng, key!, cancellationToken);
            if (results.Count > 0)
            {
                return Ok(ApiResponse<object>.Ok(new { results, source = "google" }));
            }
        }

        var fallback = await NominatimSearchAsync(client, query, country, cancellationToken);
        return Ok(ApiResponse<object>.Ok(new { results = fallback, source = "osm" }));
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

            foreach (var route in items.EnumerateArray().Take(3))
            {
                var distanceMetres =
                    route.TryGetProperty("distanceMeters", out var dm)
                        ? dm.GetInt32()
                        : 0;

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

        return Ok(ApiResponse<object>.Ok(new { routes, reason = "ok" }));
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
                // Google hosts the styling, so the map matches the app without
                // shipping a style document with every tile request.
                overlay = false
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
    [HttpGet("tiles/{z:int}/{x:int}/{y:int}")]
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
    /// Text Search rather than Autocomplete: it returns coordinates in the same
    /// response, so one call answers what would otherwise take two (predict,
    /// then fetch place details) and costs half as much.
    /// </summary>
    private static async Task<List<object>> GoogleSearchAsync(
        HttpClient client,
        string query,
        double? lat,
        double? lng,
        string key,
        CancellationToken cancellationToken)
    {
        var results = new List<object>();
        try
        {
            var url =
                "https://maps.googleapis.com/maps/api/place/textsearch/json" +
                $"?query={Uri.EscapeDataString(query)}" +
                "&region=pk" +
                $"&key={Uri.EscapeDataString(key)}";

            if (lat.HasValue && lng.HasValue)
            {
                url += $"&location={lat.Value},{lng.Value}&radius=50000";
            }

            using var response = await client.GetAsync(url, cancellationToken);
            if (!response.IsSuccessStatusCode) return results;

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            using var document = JsonDocument.Parse(body);

            if (!document.RootElement.TryGetProperty("results", out var items))
            {
                return results;
            }

            foreach (var item in items.EnumerateArray().Take(8))
            {
                if (!item.TryGetProperty("geometry", out var geometry) ||
                    !geometry.TryGetProperty("location", out var location))
                {
                    continue;
                }

                results.Add(new
                {
                    title = item.TryGetProperty("name", out var name)
                        ? name.GetString()
                        : string.Empty,
                    subtitle = item.TryGetProperty("formatted_address", out var address)
                        ? address.GetString()
                        : string.Empty,
                    latitude = location.GetProperty("lat").GetDouble(),
                    longitude = location.GetProperty("lng").GetDouble()
                });
            }
        }
        catch
        {
            // Fall through to Nominatim.
        }

        return results;
    }

    private static async Task<string?> GoogleReverseAsync(
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
            if (!response.IsSuccessStatusCode) return null;

            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            using var document = JsonDocument.Parse(body);

            if (document.RootElement.TryGetProperty("results", out var items) &&
                items.GetArrayLength() > 0 &&
                items[0].TryGetProperty("formatted_address", out var formatted))
            {
                return formatted.GetString();
            }
        }
        catch
        {
            // Fall through.
        }

        return null;
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
