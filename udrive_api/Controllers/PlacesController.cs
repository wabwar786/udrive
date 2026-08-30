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
