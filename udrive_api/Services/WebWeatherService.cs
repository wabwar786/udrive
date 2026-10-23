using System.Globalization;
using System.Text.Json;
using Microsoft.Extensions.Caching.Memory;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>Weather for the public website.</summary>
/// <remarks>
/// Reads only what <see cref="WeatherWorker"/> already stored (hourly, from
/// Open-Meteo) — the website never calls a weather service itself, so there is
/// no key, no extra cost and nothing a visitor can make the server fetch.
/// Also returns the road advisories the team marked active.
/// </remarks>
public sealed class WebWeatherService(string connectionString, IMemoryCache cache)
{
    /// <summary>The worker's tourist spots: clean name and district for the website.</summary>
    private static readonly Dictionary<string, (string Name, string District)> Spots = new()
    {
        ["spot:keran"] = ("Keran", "Neelum"),
        ["spot:sharda"] = ("Sharda", "Neelum"),
        ["spot:arangkel"] = ("Arang Kel", "Neelum"),
        ["spot:taobat"] = ("Taobat", "Neelum"),
        ["spot:leepa"] = ("Leepa", "Hattian Bala"),
        ["spot:banjosa"] = ("Banjosa Lake", "Poonch"),
        ["spot:tolipir"] = ("Toli Pir", "Poonch"),
        ["spot:pirchinasi"] = ("Pir Chinasi", "Muzaffarabad"),
    };

    public async Task<ServiceResult<WebWeatherDto>> GetAsync(CancellationToken ct)
    {
        var data = await cache.GetOrCreateAsync("web:weather", async e =>
        {
            e.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10);
            return await LoadAsync(ct);
        });
        return ServiceResult<WebWeatherDto>.Ok(data!);
    }

    private async Task<WebWeatherDto> LoadAsync(CancellationToken ct)
    {
        var places = new List<WebWeatherPlaceDto>();
        DateTimeOffset? updated = null;
        await using var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT w.place_key, w.name, w.payload::text, w.fetched_at, COALESCE(d.name, ''), w.latitude, w.longitude
              FROM udrive.weather_readings w
              LEFT JOIN udrive.territories t ON w.place_key = 't:' || t.id::text
              LEFT JOIN udrive.territories d ON d.id = t.parent_id
             WHERE w.fetched_at > now() - interval '6 hours'
             ORDER BY w.name;
            """, c))
        await using (var r = await cmd.ExecuteReaderAsync(ct))
        {
            while (await r.ReadAsync(ct))
            {
                var key = r.GetString(0);
                var fetched = r.GetFieldValue<DateTimeOffset>(3);
                if (updated is null || fetched > updated) updated = fetched;
                var spot = Spots.TryGetValue(key, out var s);
                var name = spot ? s.Name : Plain(r.GetString(1), 80);
                var district = spot ? s.District : Plain(r.GetString(4), 80);
                if (name.Length == 0) continue;
                var parsed = Parse(r.GetString(2));
                if (parsed is null) continue;
                var (now, days) = parsed.Value;
                places.Add(new WebWeatherPlaceDto(spot ? key : $"t-{name.ToLowerInvariant().Replace(' ', '-')}", name, district,
                    spot ? "Spot" : "Tehsil", now, days, Advise(now, days))
                {
                    Latitude = Math.Round(r.GetDouble(5), 4),
                    Longitude = Math.Round(r.GetDouble(6), 4),
                });
            }
        }

        var roads = new List<WebRoadUpdateDto>();
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT a.title_en, a.details_en, a.severity, r.name, a.source_name, a.starts_at
              FROM udrive.route_advisories a
              LEFT JOIN udrive.routes r ON r.id = a.route_id
             WHERE a.is_active AND a.starts_at <= now() AND (a.ends_at IS NULL OR a.ends_at > now())
             ORDER BY a.starts_at DESC LIMIT 6;
            """, c))
        await using (var r = await cmd.ExecuteReaderAsync(ct))
        {
            while (await r.ReadAsync(ct))
            {
                roads.Add(new WebRoadUpdateDto(Plain(r.GetString(0), 200), Plain(r.GetString(1), 600),
                    r.GetString(2), r.IsDBNull(3) ? null : Plain(r.GetString(3), 120), Plain(r.GetString(4), 120) is { Length: > 0 } src ? src : "UDrive",
                    r.GetFieldValue<DateTimeOffset>(5)));
            }
        }

        return new WebWeatherDto(updated, places, roads);
    }

    internal static (WebWeatherNowDto Now, IReadOnlyList<WebWeatherDayDto> Days)? Parse(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            var cur = root.GetProperty("current");
            var now = new WebWeatherNowDto(Round(cur.GetProperty("temperature_2m").GetDouble()), cur.GetProperty("weather_code").GetInt32(),
                Round(cur.GetProperty("wind_speed_10m").GetDouble()));
            var d = root.GetProperty("daily");
            var dates = d.GetProperty("time").EnumerateArray().Select(x => x.GetString() ?? "").ToList();
            double At(string name, int i) => d.TryGetProperty(name, out var a) && a.GetArrayLength() > i && a[i].ValueKind == JsonValueKind.Number ? a[i].GetDouble() : 0;
            var days = new List<WebWeatherDayDto>();
            for (var i = 0; i < dates.Count && i < 4; i++)
            {
                if (!DateOnly.TryParseExact(dates[i], "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date)) continue;
                var rain = Round(At("precipitation_sum", i));
                var snow = Round(At("snowfall_sum", i));
                int? chance = d.TryGetProperty("precipitation_probability_max", out var pp) && pp.GetArrayLength() > i && pp[i].ValueKind == JsonValueKind.Number ? pp[i].GetInt32() : null;
                days.Add(new WebWeatherDayDto(date, DayCode((int)At("weather_code", i), rain, snow), Round(At("temperature_2m_max", i)), Round(At("temperature_2m_min", i)),
                    rain, snow, Round(At("wind_speed_10m_max", i)), chance));
            }
            return (now, days);
        }
        catch (Exception exception) when (exception is JsonException or KeyNotFoundException or InvalidOperationException)
        {
            return null;
        }
    }

    /// <summary>
    /// Open-Meteo gives a day the "worst" code of any hour, so one hour of
    /// 0.1 mm drizzle makes a sunny day show as drizzle. Below half a
    /// millimetre the day shows as what it mostly is — partly cloudy.
    /// </summary>
    internal static int DayCode(int code, double rain, double snow)
    {
        var wet = code is >= 51 and <= 67 or >= 80 and <= 82;
        var snowy = code is >= 71 and <= 77 or 85 or 86;
        if (wet && rain < 0.5) return 2;
        if (snowy && snow < 0.5 && rain < 0.5) return 3;
        return code;
    }

    /// <summary>
    /// The label. Red: real snow (1 cm or more) in the next two days. Amber:
    /// thunderstorm, rain of 2 mm or more, wind 35 km/h+, or nights below −3°.
    /// "Landslide risk" only for heavy rain (10 mm+). Otherwise green.
    /// </summary>
    internal static WebWeatherAdviceDto Advise(WebWeatherNowDto now, IReadOnlyList<WebWeatherDayDto> days)
    {
        var soon = days.Take(2).ToList();
        var snowNow = now.Code is >= 71 and <= 77 or 85 or 86;
        if (soon.Any(x => x.Snow >= 1) || (snowNow && soon.FirstOrDefault()?.Snow > 0)) return new("bad", "Snow — 4×4 jeep only");
        var storm = soon.FirstOrDefault(x => x.Code >= 95 && x.Rain >= 1);
        if (storm is not null) return new("warn", $"Thunderstorm {Day(storm.Date)} — start early");
        var heavy = soon.FirstOrDefault(x => x.Rain >= 10);
        if (heavy is not null) return new("warn", $"Heavy rain {Day(heavy.Date)} — landslide risk");
        var rainy = soon.FirstOrDefault(x => x.Rain >= 2);
        if (rainy is not null) return new("warn", $"Rain {Day(rainy.Date)} — carry a jacket");
        var windy = soon.FirstOrDefault(x => x.WindMax >= 35);
        if (windy is not null || now.Wind >= 35) return new("warn", $"Windy — {Math.Round(Math.Max(now.Wind, windy?.WindMax ?? 0))} km/h");
        if (soon.Any(x => x.Min <= -3)) return new("warn", $"Very cold nights — {soon.Min(x => x.Min):0}°");
        return new("ok", "Good to go");
    }

    private static string Day(DateOnly d)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow.AddHours(5));
        return d == today ? "today" : d == today.AddDays(1) ? "tomorrow" : d.ToString("dddd", CultureInfo.InvariantCulture);
    }

    private static double Round(double v) => Math.Round(v, 1);

    /// <summary>Admin-typed text for strangers: no tags, no control characters, limited length.</summary>
    private static string Plain(string? text, int max) =>
        System.Text.RegularExpressions.Regex.Replace(WebsiteService.Clean(text, max * 2) ?? "", "<[^>]*>|[<>]", "") is var t && t.Length > max ? t[..max] : t;
}
