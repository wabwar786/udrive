using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using System.Text.RegularExpressions;
using Npgsql;
using UDrive.Api.Common;

namespace UDrive.Api.Services;

/// <summary>What the app sends when it opens, comes back to the front, and every 30 minutes.</summary>
public sealed record UsagePingRequest(
    string InstallId,
    string? Platform,
    string? Manufacturer,
    string? Model,
    string? OsVersion,
    int? Sdk,
    string? AppVersion,
    string? BuildNumber,
    string? Flavor,
    string? Locale,
    string? Timezone,
    string? Screen,
    string? Network,
    string? Carrier);

public sealed record UsageCountDto(string Name, int Count);

public sealed record UsageSummaryDto(
    int Days,
    int Devices,
    int ActiveToday,
    int NewInstalls,
    int Sessions,
    int GuestPercent,
    bool GeoConfigured,
    IReadOnlyList<UsageCountDto> Cities,
    IReadOnlyList<UsageCountDto> Versions,
    IReadOnlyList<UsageCountDto> Phones,
    IReadOnlyList<UsageCountDto> Networks);

public sealed record UsageDeviceDto(
    string InstallId,
    Guid? UserId,
    string? UserName,
    string? UserPhone,
    string? Role,
    string? Manufacturer,
    string? Model,
    string? OsVersion,
    int? Sdk,
    string? AppVersion,
    string? BuildNumber,
    string? Flavor,
    string? Locale,
    string? Timezone,
    string? Screen,
    string? LastIp,
    string? LastCity,
    string? LastNetwork,
    DateTimeOffset FirstSeenAt,
    DateTimeOffset LastSeenAt,
    int Sessions);

public sealed record UsageSessionDto(
    DateTimeOffset StartedAt,
    DateTimeOffset LastSeenAt,
    string? Ip,
    string? City,
    string? Region,
    string? Country,
    string? Org,
    string? Network,
    string? AppVersion,
    string? UserName,
    int Pings);

public sealed record UsageDeviceDetailDto(UsageDeviceDto Device, IReadOnlyList<UsageSessionDto> Sessions);

public sealed record UsageGeoTokenRequest(string? Token);

/// <summary>
/// Admin → App usage: which phones, app versions and networks the app runs
/// on, and roughly where (the city of the IP address — never GPS).
/// </summary>
/// <remarks>
/// A device is the app's own install id (a random value kept on the phone;
/// reinstalling makes a new one). Opening the app, or coming back to it after
/// 30 minutes, starts a session. The city is looked up later by
/// <see cref="IpGeoWorker"/>, so a ping never waits on another service.
/// </remarks>
public sealed partial class UsageService(string connectionString)
{
    public const string TokenSetting = "analytics.ipinfo_token";

    [GeneratedRegex("^[A-Za-z0-9_-]{8,64}$")]
    private static partial Regex InstallIdPattern();

    public async Task<ServiceResult<bool>> PingAsync(UsagePingRequest request, Guid? userId, IPAddress? address, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.InstallId) || !InstallIdPattern().IsMatch(request.InstallId))
            return ServiceResult<bool>.Fail(400, "install_id_invalid", "install id galat hai.");

        var ip = address is null ? null : (address.IsIPv4MappedToIPv6 ? address.MapToIPv4() : address).ToString();
        var network = Clip(JoinNetwork(request.Network, request.Carrier), 60);

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var tx = await connection.BeginTransactionAsync(ct);

        await using (var device = new NpgsqlCommand(
            """
            INSERT INTO udrive.app_devices AS d
                (install_id, user_id, platform, manufacturer, model, os_version, sdk, app_version, build_number,
                 build_flavor, locale, timezone, screen, last_ip, last_network, last_city)
            VALUES (@id, @user, @platform, @manufacturer, @model, @os, @sdk, @app, @build,
                    @flavor, @locale, @tz, @screen, @ip, @network, (SELECT city FROM udrive.ip_geo WHERE ip = @ip))
            ON CONFLICT (install_id) DO UPDATE SET
                user_id = COALESCE(EXCLUDED.user_id, d.user_id),
                platform = COALESCE(EXCLUDED.platform, d.platform),
                manufacturer = COALESCE(EXCLUDED.manufacturer, d.manufacturer),
                model = COALESCE(EXCLUDED.model, d.model),
                os_version = COALESCE(EXCLUDED.os_version, d.os_version),
                sdk = COALESCE(EXCLUDED.sdk, d.sdk),
                app_version = COALESCE(EXCLUDED.app_version, d.app_version),
                build_number = COALESCE(EXCLUDED.build_number, d.build_number),
                build_flavor = COALESCE(EXCLUDED.build_flavor, d.build_flavor),
                locale = COALESCE(EXCLUDED.locale, d.locale),
                timezone = COALESCE(EXCLUDED.timezone, d.timezone),
                screen = COALESCE(EXCLUDED.screen, d.screen),
                last_ip = COALESCE(EXCLUDED.last_ip, d.last_ip),
                last_network = COALESCE(EXCLUDED.last_network, d.last_network),
                last_city = COALESCE(EXCLUDED.last_city, CASE WHEN EXCLUDED.last_ip IS DISTINCT FROM d.last_ip THEN NULL ELSE d.last_city END),
                last_seen_at = now();
            """, connection, tx))
        {
            device.Parameters.AddWithValue("id", request.InstallId);
            device.Parameters.Add(new NpgsqlParameter("user", NpgsqlTypes.NpgsqlDbType.Uuid) { Value = (object?)userId ?? DBNull.Value });
            device.Parameters.AddWithValue("platform", Clip(request.Platform, 16)?.ToLowerInvariant() ?? "android");
            Add(device, "manufacturer", Clip(request.Manufacturer, 60));
            Add(device, "model", Clip(request.Model, 80));
            Add(device, "os", Clip(request.OsVersion, 40));
            device.Parameters.Add(new NpgsqlParameter("sdk", NpgsqlTypes.NpgsqlDbType.Integer) { Value = (object?)request.Sdk ?? DBNull.Value });
            Add(device, "app", Clip(request.AppVersion, 40));
            Add(device, "build", Clip(request.BuildNumber, 20));
            Add(device, "flavor", Clip(request.Flavor, 20));
            Add(device, "locale", Clip(request.Locale, 20));
            Add(device, "tz", Clip(request.Timezone, 60));
            Add(device, "screen", Clip(request.Screen, 20));
            Add(device, "ip", ip);
            Add(device, "network", network);
            await device.ExecuteNonQueryAsync(ct);
        }

        // The latest session continues while the app keeps pinging from the same address.
        await using (var touch = new NpgsqlCommand(
            """
            UPDATE udrive.app_sessions SET
                last_seen_at = now(), pings = pings + 1,
                user_id = COALESCE(@user, user_id),
                network = COALESCE(@network, network)
            WHERE id = (
                SELECT id FROM udrive.app_sessions
                WHERE install_id = @id
                ORDER BY last_seen_at DESC LIMIT 1)
              AND last_seen_at > now() - interval '35 minutes'
              AND ip IS NOT DISTINCT FROM @ip;
            """, connection, tx))
        {
            touch.Parameters.AddWithValue("id", request.InstallId);
            touch.Parameters.Add(new NpgsqlParameter("user", NpgsqlTypes.NpgsqlDbType.Uuid) { Value = (object?)userId ?? DBNull.Value });
            Add(touch, "network", network);
            Add(touch, "ip", ip);
            if (await touch.ExecuteNonQueryAsync(ct) == 0)
            {
                await using var insert = new NpgsqlCommand(
                    """
                    INSERT INTO udrive.app_sessions (install_id, user_id, ip, city, region, country, org, network, app_version)
                    SELECT @id, @user, @ip, g.city, g.region, g.country, g.org, @network, @app
                    FROM (SELECT 1) one LEFT JOIN udrive.ip_geo g ON g.ip = @ip;
                    """, connection, tx);
                insert.Parameters.AddWithValue("id", request.InstallId);
                insert.Parameters.Add(new NpgsqlParameter("user", NpgsqlTypes.NpgsqlDbType.Uuid) { Value = (object?)userId ?? DBNull.Value });
                Add(insert, "ip", ip);
                Add(insert, "network", network);
                Add(insert, "app", Clip(request.AppVersion, 40));
                await insert.ExecuteNonQueryAsync(ct);
            }
        }

        await tx.CommitAsync(ct);
        return ServiceResult<bool>.Ok(true);
    }

    public async Task<ServiceResult<UsageSummaryDto>> SummaryAsync(int days, string? role, CancellationToken ct)
    {
        days = Math.Clamp(days, 1, 90);
        var roleFilter = NormaliseRole(role);
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);

        int devices = 0, today = 0, installs = 0, sessions = 0, guests = 0;
        await using (var command = new NpgsqlCommand(
            $"""
            WITH dev AS (
                SELECT d.* FROM udrive.app_devices d LEFT JOIN udrive.users u ON u.id = d.user_id
                WHERE {RoleClause}
            )
            SELECT
                (SELECT count(*) FROM dev WHERE last_seen_at > now() - make_interval(days => @days))::int,
                (SELECT count(*) FROM dev WHERE last_seen_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Karachi') AT TIME ZONE 'Asia/Karachi'))::int,
                (SELECT count(*) FROM dev WHERE first_seen_at > now() - make_interval(days => @days))::int,
                (SELECT count(*) FROM udrive.app_sessions s JOIN dev ON dev.install_id = s.install_id
                 WHERE s.started_at > now() - make_interval(days => @days))::int,
                (SELECT count(*) FROM dev WHERE user_id IS NULL AND last_seen_at > now() - make_interval(days => @days))::int;
            """, connection))
        {
            command.Parameters.AddWithValue("days", days);
            command.Parameters.AddWithValue("role", roleFilter);
            await using var reader = await command.ExecuteReaderAsync(ct);
            if (await reader.ReadAsync(ct))
            {
                devices = Convert.ToInt32(reader.GetValue(0));
                today = Convert.ToInt32(reader.GetValue(1));
                installs = Convert.ToInt32(reader.GetValue(2));
                sessions = Convert.ToInt32(reader.GetValue(3));
                guests = Convert.ToInt32(reader.GetValue(4));
            }
        }

        var cities = await CountsAsync(connection,
            $"""
            SELECT COALESCE(NULLIF(s.city, ''), 'Na-maloom'), count(DISTINCT s.install_id)::int
            FROM udrive.app_sessions s
            JOIN udrive.app_devices d ON d.install_id = s.install_id
            LEFT JOIN udrive.users u ON u.id = d.user_id
            WHERE s.started_at > now() - make_interval(days => @days) AND {RoleClause}
            GROUP BY 1 ORDER BY 2 DESC LIMIT 15;
            """, days, roleFilter, ct);
        var versions = await CountsAsync(connection,
            $"""
            SELECT COALESCE(d.app_version, '?') || ' · ' || COALESCE(d.build_flavor, 'play'), count(*)::int
            FROM udrive.app_devices d LEFT JOIN udrive.users u ON u.id = d.user_id
            WHERE d.last_seen_at > now() - make_interval(days => @days) AND {RoleClause}
            GROUP BY 1 ORDER BY 2 DESC LIMIT 10;
            """, days, roleFilter, ct);
        var phones = await CountsAsync(connection,
            $"""
            SELECT COALESCE(initcap(d.manufacturer), '?'), count(*)::int
            FROM udrive.app_devices d LEFT JOIN udrive.users u ON u.id = d.user_id
            WHERE d.last_seen_at > now() - make_interval(days => @days) AND {RoleClause}
            GROUP BY 1 ORDER BY 2 DESC LIMIT 10;
            """, days, roleFilter, ct);
        var networks = await CountsAsync(connection,
            $"""
            SELECT COALESCE(d.last_network, '?'), count(*)::int
            FROM udrive.app_devices d LEFT JOIN udrive.users u ON u.id = d.user_id
            WHERE d.last_seen_at > now() - make_interval(days => @days) AND {RoleClause}
            GROUP BY 1 ORDER BY 2 DESC LIMIT 10;
            """, days, roleFilter, ct);

        var geo = !string.IsNullOrWhiteSpace(await TokenAsync(connection, ct));
        return ServiceResult<UsageSummaryDto>.Ok(new UsageSummaryDto(
            days, devices, today, installs, sessions,
            devices == 0 ? 0 : (int)Math.Round(guests * 100.0 / devices),
            geo, cities, versions, phones, networks));
    }

    public async Task<ServiceResult<IReadOnlyList<UsageDeviceDto>>> DevicesAsync(
        int days, string? role, string? search, string? city, int limit, CancellationToken ct)
    {
        days = Math.Clamp(days, 1, 180);
        limit = Math.Clamp(limit, 1, 300);
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand(
            $"""
            {DeviceSelect}
            WHERE d.last_seen_at > now() - make_interval(days => @days) AND {RoleClause}
              AND (@q = '' OR d.install_id ILIKE @like OR u.full_name ILIKE @like OR u.phone_number ILIKE @like
                   OR d.model ILIKE @like OR d.manufacturer ILIKE @like OR d.last_ip ILIKE @like OR d.last_city ILIKE @like)
              AND (@city = '' OR COALESCE(NULLIF(d.last_city, ''), 'Na-maloom') = @city
                   OR EXISTS (SELECT 1 FROM udrive.app_sessions s2 WHERE s2.install_id = d.install_id
                              AND s2.started_at > now() - make_interval(days => @days)
                              AND COALESCE(NULLIF(s2.city, ''), 'Na-maloom') = @city))
            ORDER BY d.last_seen_at DESC
            LIMIT @limit;
            """, connection);
        var q = search?.Trim() ?? string.Empty;
        command.Parameters.AddWithValue("days", days);
        command.Parameters.AddWithValue("role", NormaliseRole(role));
        command.Parameters.AddWithValue("q", q);
        command.Parameters.AddWithValue("like", "%" + q.Replace("%", "").Replace("_", "\\_") + "%");
        command.Parameters.AddWithValue("city", city?.Trim() ?? string.Empty);
        command.Parameters.AddWithValue("limit", limit);
        var items = new List<UsageDeviceDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct)) items.Add(ReadDevice(reader));
        return ServiceResult<IReadOnlyList<UsageDeviceDto>>.Ok(items);
    }

    public async Task<ServiceResult<UsageDeviceDetailDto>> DeviceAsync(string installId, CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        UsageDeviceDto? device = null;
        await using (var command = new NpgsqlCommand($"{DeviceSelect} WHERE d.install_id = @id;", connection))
        {
            command.Parameters.AddWithValue("id", installId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            if (await reader.ReadAsync(ct)) device = ReadDevice(reader);
        }

        if (device is null) return ServiceResult<UsageDeviceDetailDto>.Fail(404, "not_found", "Device nahi mila.");

        var sessions = new List<UsageSessionDto>();
        await using (var command = new NpgsqlCommand(
            """
            SELECT s.started_at, s.last_seen_at, s.ip, s.city, s.region, s.country, s.org, s.network, s.app_version,
                   u.full_name, s.pings
            FROM udrive.app_sessions s LEFT JOIN udrive.users u ON u.id = s.user_id
            WHERE s.install_id = @id
            ORDER BY s.started_at DESC
            LIMIT 60;
            """, connection))
        {
            command.Parameters.AddWithValue("id", installId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                sessions.Add(new UsageSessionDto(
                    reader.GetFieldValue<DateTimeOffset>(0),
                    reader.GetFieldValue<DateTimeOffset>(1),
                    Str(reader, 2), Str(reader, 3), Str(reader, 4), Str(reader, 5), Str(reader, 6), Str(reader, 7), Str(reader, 8),
                    Str(reader, 9),
                    Convert.ToInt32(reader.GetValue(10))));
            }
        }

        return ServiceResult<UsageDeviceDetailDto>.Ok(new UsageDeviceDetailDto(device, sessions));
    }

    /// <summary>Saves the ipinfo.io token. Empty switches the city look-up off.</summary>
    public async Task<ServiceResult<bool>> SetTokenAsync(string? token, CancellationToken ct)
    {
        var clean = token?.Trim() ?? string.Empty;
        if (clean.Length > 100 || clean.Any(char.IsWhiteSpace))
            return ServiceResult<bool>.Fail(400, "token_invalid", "Token sahi nahi lag raha.");
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.system_settings (key, value_json, description, is_public, created_at, updated_at)
            VALUES (@key, to_jsonb(@value::text), 'ipinfo.io token used to turn an IP into a city.', false, now(), now())
            ON CONFLICT (key) DO UPDATE SET value_json = EXCLUDED.value_json, updated_at = now();
            """, connection);
        command.Parameters.AddWithValue("key", TokenSetting);
        command.Parameters.AddWithValue("value", clean);
        await command.ExecuteNonQueryAsync(ct);
        return ServiceResult<bool>.Ok(clean.Length > 0,
            clean.Length > 0 ? "Token save ho gaya. Shehar agle 1–2 minute mein aane lagenge." : "Shehar ka pata lagana band.");
    }

    internal static async Task<string?> TokenAsync(NpgsqlConnection connection, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            "SELECT value_json #>> '{}' FROM udrive.system_settings WHERE key = @key;", connection);
        command.Parameters.AddWithValue("key", TokenSetting);
        return (await command.ExecuteScalarAsync(ct))?.ToString();
    }

    /// <summary>Loopback, private, CGNAT and link-local addresses have no city.</summary>
    public static bool IsPublic(string? ip)
    {
        if (!IPAddress.TryParse(ip, out var address)) return false;
        if (IPAddress.IsLoopback(address)) return false;
        if (address.AddressFamily == AddressFamily.InterNetwork)
        {
            var b = address.GetAddressBytes();
            return !(b[0] == 10 || b[0] == 0 || b[0] >= 224
                     || (b[0] == 172 && b[1] >= 16 && b[1] <= 31)
                     || (b[0] == 192 && b[1] == 168)
                     || (b[0] == 169 && b[1] == 254)
                     || (b[0] == 100 && b[1] >= 64 && b[1] <= 127));
        }

        return !(address.IsIPv6LinkLocal || address.IsIPv6SiteLocal || address.IsIPv6UniqueLocal || address.IsIPv6Multicast);
    }

    // ---- Helpers ----------------------------------------------------------------

    // '' all, 'guest' signed out, otherwise users.role.
    private const string RoleClause =
        "(@role = '' OR (@role = 'guest' AND d.user_id IS NULL) OR (@role = 'other' AND u.role NOT IN ('Customer', 'Driver')) OR u.role = @role)";

    private const string DeviceSelect =
        """
        SELECT d.install_id, d.user_id, u.full_name, u.phone_number, u.role,
               d.manufacturer, d.model, d.os_version, d.sdk, d.app_version, d.build_number, d.build_flavor,
               d.locale, d.timezone, d.screen, d.last_ip, d.last_city, d.last_network,
               d.first_seen_at, d.last_seen_at,
               (SELECT count(*) FROM udrive.app_sessions s WHERE s.install_id = d.install_id)::int
        FROM udrive.app_devices d
        LEFT JOIN udrive.users u ON u.id = d.user_id
        """;

    private static UsageDeviceDto ReadDevice(NpgsqlDataReader r) => new(
        r.GetString(0),
        r.IsDBNull(1) ? null : r.GetGuid(1),
        Str(r, 2), Str(r, 3), Str(r, 4), Str(r, 5), Str(r, 6), Str(r, 7),
        r.IsDBNull(8) ? null : Convert.ToInt32(r.GetValue(8)),
        Str(r, 9), Str(r, 10), Str(r, 11), Str(r, 12), Str(r, 13), Str(r, 14), Str(r, 15), Str(r, 16), Str(r, 17),
        r.GetFieldValue<DateTimeOffset>(18),
        r.GetFieldValue<DateTimeOffset>(19),
        Convert.ToInt32(r.GetValue(20)));

    private static async Task<List<UsageCountDto>> CountsAsync(
        NpgsqlConnection connection, string sql, int days, string role, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("days", days);
        command.Parameters.AddWithValue("role", role);
        var items = new List<UsageCountDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct)) items.Add(new UsageCountDto(reader.GetString(0), Convert.ToInt32(reader.GetValue(1))));
        return items;
    }

    private static string NormaliseRole(string? role) => role?.Trim() switch
    {
        null or "" or "all" => string.Empty,
        "guest" => "guest",
        "other" => "other",
        "customer" or "Customer" => "Customer",
        "driver" or "Driver" => "Driver",
        _ => string.Empty,
    };

    private static string? JoinNetwork(string? network, string? carrier)
    {
        var n = network?.Trim();
        var c = carrier?.Trim();
        if (string.IsNullOrEmpty(c)) return string.IsNullOrEmpty(n) ? null : n;
        return string.IsNullOrEmpty(n) ? c : $"{n} · {c}";
    }

    private static void Add(NpgsqlCommand command, string name, string? value) =>
        command.Parameters.Add(new NpgsqlParameter(name, NpgsqlTypes.NpgsqlDbType.Varchar) { Value = (object?)value ?? DBNull.Value });

    private static string? Str(NpgsqlDataReader r, int i) => r.IsDBNull(i) ? null : r.GetValue(i).ToString();

    private static string? Clip(string? value, int max)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var trimmed = value.Trim();
        return trimmed.Length <= max ? trimmed : trimmed[..max];
    }
}

/// <summary>Turns new IP addresses into a city with ipinfo.io, once per address.</summary>
/// <remarks>
/// Runs every minute, at most 40 addresses a run (ipinfo's free plan is
/// 50,000 a month). Without a token in Admin → App usage it does nothing.
/// </remarks>
public sealed class IpGeoWorker(string connectionString, IHttpClientFactory httpFactory, ILogger<IpGeoWorker> logger) : BackgroundService
{
    public const string HttpClientName = "ipinfo";

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(45), stoppingToken);
        }
        catch (OperationCanceledException)
        {
            return;
        }

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
                logger.LogWarning(exception, "IP city look-up failed; trying again in a minute.");
            }

            try
            {
                await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }

    /// <returns>How many addresses were looked up.</returns>
    public async Task<int> RunOnceAsync(CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        var token = await UsageService.TokenAsync(connection, ct);

        var ips = new List<string>();
        await using (var command = new NpgsqlCommand(
            """
            SELECT DISTINCT s.ip FROM udrive.app_sessions s
            WHERE s.city IS NULL AND s.ip IS NOT NULL AND s.started_at > now() - interval '3 days'
              AND NOT EXISTS (SELECT 1 FROM udrive.ip_geo g WHERE g.ip = s.ip)
            LIMIT 40;
            """, connection))
        {
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct)) ips.Add(reader.GetString(0));
        }

        var looked = 0;
        foreach (var ip in ips)
        {
            string? city = null, region = null, country = null, org = null;
            if (!UsageService.IsPublic(ip))
            {
                city = "Local network";
            }
            else
            {
                if (string.IsNullOrWhiteSpace(token)) continue;
                var client = httpFactory.CreateClient(HttpClientName);
                using var response = await client.GetAsync(
                    $"https://ipinfo.io/{Uri.EscapeDataString(ip)}/json?token={Uri.EscapeDataString(token)}", ct);
                if ((int)response.StatusCode == 429 || (int)response.StatusCode == 403)
                {
                    logger.LogWarning("ipinfo.io refused ({Status}); check the token or the monthly limit.", (int)response.StatusCode);
                    break;
                }

                if (!response.IsSuccessStatusCode) continue;
                using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
                city = Text(json.RootElement, "city");
                region = Text(json.RootElement, "region");
                country = Text(json.RootElement, "country");
                org = Text(json.RootElement, "org");
                looked++;
            }

            await using var save = new NpgsqlCommand(
                """
                INSERT INTO udrive.ip_geo (ip, city, region, country, org) VALUES (@ip, @city, @region, @country, @org)
                ON CONFLICT (ip) DO UPDATE SET city = EXCLUDED.city, region = EXCLUDED.region,
                    country = EXCLUDED.country, org = EXCLUDED.org, looked_up_at = now();
                """, connection);
            save.Parameters.AddWithValue("ip", ip);
            save.Parameters.AddWithValue("city", (object?)Clip(city, 120) ?? "Na-maloom");
            save.Parameters.AddWithValue("region", (object?)Clip(region, 120) ?? DBNull.Value);
            save.Parameters.AddWithValue("country", (object?)Clip(country, 8) ?? DBNull.Value);
            save.Parameters.AddWithValue("org", (object?)Clip(org, 160) ?? DBNull.Value);
            await save.ExecuteNonQueryAsync(ct);
        }

        // Fill the sessions and devices from the cache.
        await using (var fill = new NpgsqlCommand(
            """
            UPDATE udrive.app_sessions s SET city = g.city, region = g.region, country = g.country, org = g.org
            FROM udrive.ip_geo g
            WHERE s.ip = g.ip AND s.city IS NULL;
            UPDATE udrive.app_devices d SET last_city = g.city
            FROM udrive.ip_geo g
            WHERE d.last_ip = g.ip AND d.last_city IS NULL;
            """, connection))
        {
            await fill.ExecuteNonQueryAsync(ct);
        }

        return looked;
    }

    private static string? Text(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static string? Clip(string? value, int max) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Length <= max ? value : value[..max];
}
