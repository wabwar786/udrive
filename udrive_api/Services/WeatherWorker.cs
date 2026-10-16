using System.Globalization;
using System.Text.Json;
using Npgsql;

namespace UDrive.Api.Services;

/// <summary>
/// Fetches the forecast for every tehsil and the main tour spots once an hour,
/// from Open-Meteo (free, no key), into <c>weather_readings</c>.
/// </summary>
/// <remarks>
/// One request covers every place (Open-Meteo takes a list of coordinates).
/// A failed fetch keeps the last good reading, and the Ops board shows when
/// it was fetched, so a stale forecast is never mistaken for a fresh one.
/// </remarks>
public sealed class WeatherWorker(string connectionString, IHttpClientFactory httpFactory, ILogger<WeatherWorker> logger) : BackgroundService
{
    public const string HttpClientName = "open-meteo";

    /// <summary>Tour spots that are not tehsil centres but get snowed in first.</summary>
    private static readonly (string Key, string Name, double Lat, double Lng)[] Spots =
    [
        ("spot:keran", "Neelum — Keran", 34.6480, 73.9530),
        ("spot:sharda", "Neelum — Sharda", 34.7930, 74.1880),
        ("spot:arangkel", "Arang Kel", 34.8080, 74.3460),
        ("spot:taobat", "Taobat", 34.8590, 74.5980),
        ("spot:leepa", "Leepa valley", 34.3180, 73.9090),
        ("spot:banjosa", "Banjosa lake", 33.7900, 73.8170),
        ("spot:tolipir", "Toli Pir", 33.8770, 73.9310),
        ("spot:pirchinasi", "Pir Chinasi", 34.3870, 73.5490),
    ];

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try { await Task.Delay(TimeSpan.FromSeconds(60), stoppingToken); }
        catch (OperationCanceledException) { return; }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await RunOnceAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Weather fetch failed; the last reading stays until the next hour.");
            }

            try { await Task.Delay(TimeSpan.FromHours(1), stoppingToken); }
            catch (OperationCanceledException) { return; }
        }
    }

    public async Task RunOnceAsync(CancellationToken ct)
    {
        var places = new List<(string Key, string Name, double Lat, double Lng)>();
        await using (var c = new NpgsqlConnection(connectionString))
        {
            await c.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand(
                """
                SELECT 't:' || id::text, name, latitude, longitude FROM udrive.territories
                 WHERE kind = 'Tehsil' AND is_active AND latitude IS NOT NULL AND longitude IS NOT NULL
                 ORDER BY name LIMIT 80;
                """, c);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct)) places.Add((r.GetString(0), r.GetString(1), r.GetDouble(2), r.GetDouble(3)));
        }
        places.AddRange(Spots);
        if (places.Count == 0) return;

        var inv = CultureInfo.InvariantCulture;
        var url = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + string.Join(",", places.Select(p => p.Lat.ToString("0.####", inv)))
            + "&longitude=" + string.Join(",", places.Select(p => p.Lng.ToString("0.####", inv)))
            + "&current=temperature_2m,weather_code,wind_speed_10m"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,snowfall_sum,wind_speed_10m_max"
            + "&timezone=Asia%2FKarachi&forecast_days=4";

        var client = httpFactory.CreateClient(HttpClientName);
        using var response = await client.GetAsync(url, ct);
        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(json);

        // One place answers with an object, several with an array, in the same order.
        var items = doc.RootElement.ValueKind == JsonValueKind.Array
            ? doc.RootElement.EnumerateArray().ToList()
            : [doc.RootElement];

        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync(ct);
        for (var i = 0; i < items.Count && i < places.Count; i++)
        {
            var p = places[i];
            await using var up = new NpgsqlCommand(
                """
                INSERT INTO udrive.weather_readings (place_key, name, latitude, longitude, payload, fetched_at)
                VALUES (@k, @n, @lat, @lng, @payload::jsonb, now())
                ON CONFLICT (place_key) DO UPDATE SET
                    name = EXCLUDED.name, latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude,
                    payload = EXCLUDED.payload, fetched_at = now();
                """, conn);
            up.Parameters.AddWithValue("k", p.Key);
            up.Parameters.AddWithValue("n", p.Name);
            up.Parameters.AddWithValue("lat", p.Lat);
            up.Parameters.AddWithValue("lng", p.Lng);
            up.Parameters.AddWithValue("payload", items[i].GetRawText());
            await up.ExecuteNonQueryAsync(ct);
        }

        // A tehsil that was removed should not keep showing old weather.
        await using var prune = new NpgsqlCommand(
            "DELETE FROM udrive.weather_readings WHERE fetched_at < now() - interval '3 days';", conn);
        await prune.ExecuteNonQueryAsync(ct);
    }
}
