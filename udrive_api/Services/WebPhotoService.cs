using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Channels;
using Microsoft.Extensions.Caching.Memory;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>Destination photos for the website: the public list and the admin side.</summary>
public sealed partial class WebPhotoService(string connectionString, IMemoryCache cache, WebPhotoWorker worker)
{
    public const int PerPlace = 6;

    public async Task<ServiceResult<IReadOnlyList<WebPhotoDto>>> PublicAsync(CancellationToken ct)
    {
        var list = await cache.GetOrCreateAsync("web:photos", async e =>
        {
            e.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10);
            var rows = new List<WebPhotoDto>();
            await using var c = new NpgsqlConnection(connectionString);
            await c.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand(
                """
                SELECT id, slug, url, page_url, author, license, license_url, season, source FROM (
                  SELECT p.*, d.slug,
                         row_number() OVER (PARTITION BY p.destination_id ORDER BY (p.source = 'Own') DESC, p.width DESC, p.created_at) AS n
                    FROM udrive.web_photos p
                    JOIN udrive.destinations d ON d.id = p.destination_id
                   WHERE NOT p.hidden AND d.is_active AND lower(d.district) = ANY(@ajk)) x
                 WHERE n <= @per
                 ORDER BY slug, n;
                """, c);
            cmd.Parameters.AddWithValue("ajk", WebsiteService.AjkDistricts);
            cmd.Parameters.AddWithValue("per", PerPlace);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                var url = r.GetString(2);
                if (!SafeUrl(url)) continue;
                rows.Add(new WebPhotoDto(r.GetGuid(0), r.GetString(1), url, r.IsDBNull(3) ? null : r.GetString(3), r.GetString(4), r.GetString(5),
                    r.IsDBNull(6) ? null : r.GetString(6), r.GetString(7), r.GetString(8) == "Own"));
            }
            return (IReadOnlyList<WebPhotoDto>)rows;
        });
        return ServiceResult<IReadOnlyList<WebPhotoDto>>.Ok(list!);
    }

    public async Task<ServiceResult<AdminWebPhotosDto>> AdminAsync(CancellationToken ct)
    {
        await using var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        var places = new List<AdminWebPlaceDto>();
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT d.id, d.slug, d.name_en, d.district, d.location IS NOT NULL, d.web_kind, d.drive_hours,
                   (SELECT count(*)::int FROM udrive.web_photos p WHERE p.destination_id = d.id AND NOT p.hidden)
              FROM udrive.destinations d
             WHERE d.is_active AND lower(d.district) = ANY(@ajk)
             ORDER BY d.district, d.name_en;
            """, c))
        {
            cmd.Parameters.AddWithValue("ajk", WebsiteService.AjkDistricts);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
                places.Add(new AdminWebPlaceDto(r.GetGuid(0), r.GetString(1), WebsiteService.PlaceName(r.GetString(2)), WebsiteService.DistrictName(r.GetString(3)),
                    r.GetBoolean(4), r.IsDBNull(5) ? null : r.GetString(5), r.IsDBNull(6) ? null : r.GetDecimal(6), r.GetInt32(7)));
        }
        var photos = new List<AdminWebPhotoDto>();
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT p.id, p.destination_id, d.name_en, p.source, p.url, p.page_url, p.author, p.license, p.season, p.taken_month, p.hidden, p.created_at
              FROM udrive.web_photos p JOIN udrive.destinations d ON d.id = p.destination_id
             ORDER BY d.name_en, (p.source = 'Own') DESC, p.hidden, p.width DESC
             LIMIT 600;
            """, c))
        await using (var r = await cmd.ExecuteReaderAsync(ct))
        {
            while (await r.ReadAsync(ct))
                photos.Add(new AdminWebPhotoDto(r.GetGuid(0), r.GetGuid(1), WebsiteService.PlaceName(r.GetString(2)), r.GetString(3), r.GetString(4),
                    r.IsDBNull(5) ? null : r.GetString(5), r.GetString(6), r.GetString(7), r.GetString(8), r.IsDBNull(9) ? null : r.GetInt16(9),
                    r.GetBoolean(10), r.GetFieldValue<DateTimeOffset>(11)));
        }
        return ServiceResult<AdminWebPhotosDto>.Ok(new AdminWebPhotosDto(places, photos, worker.LastRun, worker.Running));
    }

    public async Task<ServiceResult<AdminWebPhotosDto>> SetHiddenAsync(Guid id, bool hidden, CancellationToken ct)
    {
        await using (var c = new NpgsqlConnection(connectionString))
        {
            await c.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand("UPDATE udrive.web_photos SET hidden = @h, updated_at = now() WHERE id = @id;", c);
            cmd.Parameters.AddWithValue("h", hidden);
            cmd.Parameters.AddWithValue("id", id);
            if (await cmd.ExecuteNonQueryAsync(ct) == 0) return ServiceResult<AdminWebPhotosDto>.Fail(404, "photo_not_found", "Tasveer nahi mili.");
        }
        Forget();
        return await AdminAsync(ct);
    }

    /// <summary>An upload by the team (first through POST /admin/web/ads/image, which stores the file).</summary>
    public async Task<ServiceResult<AdminWebPhotosDto>> AddOwnAsync(AddWebPhotoRequest x, CancellationToken ct)
    {
        var url = (x.Url ?? "").Trim();
        if (!url.StartsWith("/api/v1/web-images/", StringComparison.Ordinal) || !SafeUrl(url))
            return ServiceResult<AdminWebPhotosDto>.Fail(400, "photo_url", "Pehle tasveer upload karein.");
        var season = (x.Season ?? "any").Trim().ToLowerInvariant();
        if (season is not ("snow" or "winter" or "spring" or "summer" or "autumn" or "any")) season = "any";
        await using (var c = new NpgsqlConnection(connectionString))
        {
            await c.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand(
                """
                INSERT INTO udrive.web_photos (destination_id, source, source_ref, url, author, license, season, width, height)
                SELECT d.id, 'Own', @ref, @url, 'UDrive', '', @season, 1600, 900 FROM udrive.destinations d WHERE d.id = @d
                ON CONFLICT DO NOTHING;
                """, c);
            cmd.Parameters.AddWithValue("ref", Guid.NewGuid().ToString("N")[..20]);
            cmd.Parameters.AddWithValue("url", url);
            cmd.Parameters.AddWithValue("season", season);
            cmd.Parameters.AddWithValue("d", x.DestinationId);
            if (await cmd.ExecuteNonQueryAsync(ct) == 0) return ServiceResult<AdminWebPhotosDto>.Fail(404, "destination_not_found", "Jagah nahi mili.");
        }
        Forget();
        return await AdminAsync(ct);
    }

    public async Task<ServiceResult<AdminWebPhotosDto>> SavePlaceAsync(Guid id, SaveWebPlaceRequest x, CancellationToken ct)
    {
        var kind = string.IsNullOrWhiteSpace(x.Kind) ? null : x.Kind.Trim().ToLowerInvariant();
        if (kind is not (null or "lake" or "meadow" or "river")) return ServiceResult<AdminWebPhotosDto>.Fail(400, "kind_invalid", "Lake, Meadow ya Rivers & towns chunein.");
        if (x.DriveHours is { } h && (h <= 0 || h > 24)) return ServiceResult<AdminWebPhotosDto>.Fail(400, "hours_invalid", "Ghante 0.5 se 24 tak.");
        await using (var c = new NpgsqlConnection(connectionString))
        {
            await c.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand("UPDATE udrive.destinations SET web_kind = @k, drive_hours = @h, updated_at = now() WHERE id = @id;", c);
            cmd.Parameters.Add(new NpgsqlParameter("k", NpgsqlDbType.Varchar) { Value = (object?)kind ?? DBNull.Value });
            cmd.Parameters.Add(new NpgsqlParameter("h", NpgsqlDbType.Numeric) { Value = x.DriveHours is { } v ? Math.Round(v, 1) : DBNull.Value });
            cmd.Parameters.AddWithValue("id", id);
            if (await cmd.ExecuteNonQueryAsync(ct) == 0) return ServiceResult<AdminWebPhotosDto>.Fail(404, "destination_not_found", "Jagah nahi mili.");
        }
        cache.Remove("web:destinations");
        cache.Remove("web:home");
        return await AdminAsync(ct);
    }

    public ServiceResult<bool> FindNow()
    {
        var started = worker.RequestRun();
        return ServiceResult<bool>.Ok(started, started ? "Tasveerein dhoondi ja rahi hain — chand minute mein list refresh karein." : "Pehle se chal raha hai.");
    }

    private void Forget() => cache.Remove("web:photos");

    internal static bool SafeUrl(string url) =>
        url.Length <= 600 && !url.Contains("..") && !SafeChars().IsMatch(url)
        && (url.StartsWith("https://upload.wikimedia.org/", StringComparison.Ordinal) || url.StartsWith("/api/v1/web-images/", StringComparison.Ordinal));

    [GeneratedRegex("[<>\"'\\s]")]
    private static partial Regex SafeChars();
}

/// <summary>
/// Finds free-licence photos of each Azad Kashmir destination on Wikimedia
/// Commons, by location: only files within a small radius of the place's own
/// coordinates (1 km for places on the LoC), so a same-named place on the
/// other side never comes in. Weekly, and when the team asks.
/// </summary>
public sealed partial class WebPhotoWorker(string connectionString, IHttpClientFactory httpFactory, ILogger<WebPhotoWorker> logger) : BackgroundService
{
    public const string HttpClientName = "commons";
    private readonly Channel<bool> _kick = Channel.CreateBounded<bool>(1);
    private int _running;

    public DateTimeOffset? LastRun { get; private set; }

    public bool Running => _running == 1;

    /// <summary>Places right on the Line of Control: search a tighter circle.</summary>
    private static readonly HashSet<string> OnTheLine = ["keran", "upper-neelum", "kel", "taobat", "chakothi", "sharda", "dao-khan"];

    /// <summary>Anything tagged with these is not Azad Kashmir and is never used.</summary>
    private static readonly string[] Excluded =
    [
        "jammu and kashmir (union territory)", "indian-administered", "indian administered", "srinagar", "gulmarg", "pahalgam",
        "sonamarg", "kupwara", "baramulla", "anantnag", "ladakh", "kargil", "dal lake", "jammu division", "kashmir division",
        "india", "pulwama", "budgam", "uri,", "uri sector", "poonch district, india", "rajouri",
    ];

    public bool RequestRun() => _running == 0 && _kick.Writer.TryWrite(true);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try { await Task.Delay(TimeSpan.FromMinutes(3), stoppingToken); } catch (OperationCanceledException) { return; }
        while (!stoppingToken.IsCancellationRequested)
        {
            if (Interlocked.Exchange(ref _running, 1) == 0)
            {
                try { await RunOnceAsync(stoppingToken); LastRun = DateTimeOffset.UtcNow; }
                catch (OperationCanceledException) { return; }
                catch (Exception exception) { logger.LogWarning(exception, "Photo search failed; tries again next week or when asked."); }
                finally { Interlocked.Exchange(ref _running, 0); }
            }
            using var week = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
            week.CancelAfter(TimeSpan.FromDays(7));
            try { await _kick.Reader.ReadAsync(week.Token); }
            catch (OperationCanceledException) when (!stoppingToken.IsCancellationRequested) { /* the weekly run */ }
            catch (OperationCanceledException) { return; }
        }
    }

    public async Task RunOnceAsync(CancellationToken ct)
    {
        var places = new List<(Guid Id, string Slug, double Lat, double Lng)>();
        await using (var c = new NpgsqlConnection(connectionString))
        {
            await c.OpenAsync(ct);
            await using var cmd = new NpgsqlCommand(
                """
                SELECT id, slug, ST_Y(location::geometry), ST_X(location::geometry) FROM udrive.destinations
                 WHERE is_active AND location IS NOT NULL AND lower(district) = ANY(@ajk) ORDER BY name_en;
                """, c);
            cmd.Parameters.AddWithValue("ajk", WebsiteService.AjkDistricts);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct)) places.Add((r.GetGuid(0), r.GetString(1), r.GetDouble(2), r.GetDouble(3)));
        }

        var client = httpFactory.CreateClient(HttpClientName);
        foreach (var p in places)
        {
            ct.ThrowIfCancellationRequested();
            var radius = OnTheLine.Contains(p.Slug) ? 1000 : 2000;
            var inv = CultureInfo.InvariantCulture;
            var url = "https://commons.wikimedia.org/w/api.php?action=query&format=json&formatversion=2"
                + "&generator=geosearch&ggsnamespace=6&ggslimit=40"
                + $"&ggscoord={p.Lat.ToString("0.#####", inv)}%7C{p.Lng.ToString("0.#####", inv)}&ggsradius={radius}"
                + "&prop=imageinfo&iiprop=url%7Csize%7Cmime%7Cextmetadata&iiurlwidth=1600"
                + "&iiextmetadatafilter=LicenseShortName%7CLicenseUrl%7CArtist%7CDateTimeOriginal%7CCategories%7CImageDescription%7CObjectName";
            try
            {
                using var response = await client.GetAsync(url, ct);
                if (!response.IsSuccessStatusCode) continue;
                var found = Pick(await response.Content.ReadAsStringAsync(ct));
                if (found.Count > 0) await SaveAsync(p.Id, found, ct);
            }
            catch (HttpRequestException exception) { logger.LogInformation(exception, "Commons search failed for {Slug}.", p.Slug); }
            catch (TaskCanceledException) when (!ct.IsCancellationRequested) { /* slow; next place */ }
            await Task.Delay(TimeSpan.FromSeconds(1.5), ct); // be polite to Wikimedia
        }
    }

    internal sealed record Found(string PageId, string Url, string PageUrl, string Author, string License, string? LicenseUrl, string Season, int? Month, int Width, int Height);

    /// <summary>Keeps landscape, large, freely licensed photos that are not tagged as somewhere else.</summary>
    internal static List<Found> Pick(string json)
    {
        var list = new List<Found>();
        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("query", out var q) || !q.TryGetProperty("pages", out var pages)) return list;
        foreach (var page in pages.EnumerateArray())
        {
            if (!page.TryGetProperty("imageinfo", out var infos) || infos.GetArrayLength() == 0) continue;
            var ii = infos[0];
            var mime = Str(ii, "mime");
            if (mime is not ("image/jpeg" or "image/webp")) continue;
            var w = ii.TryGetProperty("width", out var we) ? we.GetInt32() : 0;
            var h = ii.TryGetProperty("height", out var he) ? he.GetInt32() : 0;
            if (w < 1200 || h == 0 || w < h * 1.25) continue;
            var thumb = Str(ii, "thumburl") ?? Str(ii, "url");
            if (thumb is null || !WebPhotoService.SafeUrl(thumb)) continue;
            var meta = ii.TryGetProperty("extmetadata", out var m) ? m : default;
            string Meta(string k) => meta.ValueKind == JsonValueKind.Object && meta.TryGetProperty(k, out var v) && v.TryGetProperty("value", out var vv) ? vv.ToString() : "";
            var license = Meta("LicenseShortName").Trim();
            var ok = license.StartsWith("CC BY", StringComparison.OrdinalIgnoreCase) || license.StartsWith("CC0", StringComparison.OrdinalIgnoreCase)
                || license.StartsWith("Public domain", StringComparison.OrdinalIgnoreCase);
            if (!ok || license.Contains("NC", StringComparison.Ordinal) || license.Contains("ND", StringComparison.Ordinal)) continue;
            var title = page.TryGetProperty("title", out var t) ? t.GetString() ?? "" : "";
            var text = (title + " " + Meta("Categories") + " " + Meta("ImageDescription") + " " + Meta("ObjectName")).ToLowerInvariant();
            if (Excluded.Any(text.Contains)) continue;
            var author = Plain(Meta("Artist"), 120);
            if (author.Length == 0) author = "Unknown";
            var licenseUrl = Meta("LicenseUrl").Trim();
            int? month = null;
            var taken = Plain(Meta("DateTimeOriginal"), 40);
            if (DateTime.TryParse(taken.Length >= 10 ? taken[..10] : taken, CultureInfo.InvariantCulture, DateTimeStyles.None, out var dt)) month = dt.Month;
            var pageId = page.TryGetProperty("pageid", out var pid) ? pid.GetInt64().ToString(CultureInfo.InvariantCulture) : "";
            if (pageId.Length == 0) continue;
            list.Add(new Found(pageId, thumb, $"https://commons.wikimedia.org/?curid={pageId}", author, Plain(license, 60),
                licenseUrl.StartsWith("https://", StringComparison.Ordinal) && licenseUrl.Length < 300 && !licenseUrl.Any(ch => ch is '<' or '>' or '"' or '\'' or ' ') ? licenseUrl : null,
                Season(text, month), month, w, h));
        }
        return list.OrderByDescending(x => x.Width).Take(WebPhotoService.PerPlace * 2).ToList();
    }

    internal static string Season(string text, int? month)
    {
        if (text.Contains("snow") || text.Contains("winter")) return text.Contains("snow") ? "snow" : "winter";
        if (text.Contains("autumn") || text.Contains("fall colo")) return "autumn";
        if (text.Contains("spring") || text.Contains("blossom")) return "spring";
        return month switch
        {
            12 or 1 or 2 => "winter",
            3 or 4 => "spring",
            5 or 6 or 7 or 8 => "summer",
            9 or 10 or 11 => "autumn",
            _ => "any",
        };
    }

    private async Task SaveAsync(Guid destinationId, List<Found> found, CancellationToken ct)
    {
        await using var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        foreach (var f in found)
        {
            // A hidden photo stays hidden: only its details are refreshed.
            await using var cmd = new NpgsqlCommand(
                """
                INSERT INTO udrive.web_photos (destination_id, source, source_ref, url, page_url, author, license, license_url, season, taken_month, width, height)
                VALUES (@d, 'Commons', @ref, @url, @page, @author, @license, @lurl, @season, @month, @w, @h)
                ON CONFLICT (destination_id, source, source_ref) DO UPDATE SET
                    url = EXCLUDED.url, author = EXCLUDED.author, license = EXCLUDED.license, license_url = EXCLUDED.license_url,
                    width = EXCLUDED.width, height = EXCLUDED.height, updated_at = now();
                """, c);
            cmd.Parameters.AddWithValue("d", destinationId);
            cmd.Parameters.AddWithValue("ref", f.PageId);
            cmd.Parameters.AddWithValue("url", f.Url);
            cmd.Parameters.AddWithValue("page", f.PageUrl);
            cmd.Parameters.AddWithValue("author", f.Author);
            cmd.Parameters.AddWithValue("license", f.License);
            cmd.Parameters.Add(new NpgsqlParameter("lurl", NpgsqlDbType.Varchar) { Value = (object?)f.LicenseUrl ?? DBNull.Value });
            cmd.Parameters.AddWithValue("season", f.Season);
            cmd.Parameters.Add(new NpgsqlParameter("month", NpgsqlDbType.Smallint) { Value = f.Month is { } mo ? (short)mo : DBNull.Value });
            cmd.Parameters.AddWithValue("w", f.Width);
            cmd.Parameters.AddWithValue("h", f.Height);
            try { await cmd.ExecuteNonQueryAsync(ct); }
            catch (PostgresException exception) { logger.LogInformation("Photo {Ref} skipped ({State}).", f.PageId, exception.SqlState); }
        }
    }

    private static string? Str(JsonElement e, string name) => e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    /// <summary>Commons "Artist" is HTML: keep the words only.</summary>
    internal static string Plain(string html, int max)
    {
        var text = System.Net.WebUtility.HtmlDecode(Tags().Replace(html ?? "", " "));
        text = Spaces().Replace(text, " ").Replace("<", "").Replace(">", "").Trim();
        return text.Length > max ? text[..max].Trim() : text;
    }

    [GeneratedRegex("<[^>]*>")]
    private static partial Regex Tags();

    [GeneratedRegex("\\s+")]
    private static partial Regex Spaces();
}
