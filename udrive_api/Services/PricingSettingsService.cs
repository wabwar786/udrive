using System.Globalization;
using System.Text.Json;
using Npgsql;

namespace UDrive.Api.Services;

/// <summary>
/// Every <c>pricing.*</c> row from <c>udrive.system_settings</c>, cached.
/// </summary>
/// <remarks>
/// A fare quote reads a dozen settings. Fetching them one at a time would put
/// a dozen round trips in front of a screen that opens every time somebody
/// picks a vehicle, so they are loaded together and held for a minute.
///
/// A minute is the whole contract: an admin who changes the surge ceiling sees
/// it take effect on the next quote after that, and nobody has to restart
/// anything. Long enough to stop the query mattering, short enough that
/// "I changed it and nothing happened" is never true for more than a minute.
///
/// Registered as a singleton so one cache serves the process.
/// </remarks>
public sealed class PricingSettingsService(string connectionString)
{
    private readonly SemaphoreSlim _gate = new(1, 1);

    // Both volatile, and the stamp is ticks rather than a DateTimeOffset
    // because `volatile` cannot be applied to a struct field. Without the
    // release ordering a reader on another core can see the new stamp against
    // the old dictionary, and Invalidate's write can go unseen indefinitely —
    // on ARM64, which is most of what this runs on now.
    private volatile Dictionary<string, string> _values = new(StringComparer.OrdinalIgnoreCase);
    private long _loadedAtTicks;

    private static readonly TimeSpan CacheFor = TimeSpan.FromMinutes(1);

    /// <summary>How long a failed load is remembered before trying again.</summary>
    /// <remarks>
    /// Without this, a database that is refusing connections turns every ride
    /// request into its own serial attempt behind the semaphore, because
    /// creating one now reads these settings. Five seconds of stale-or-empty
    /// beats a queue of timeouts.
    /// </remarks>
    private static readonly TimeSpan RetryAfterFailure = TimeSpan.FromSeconds(5);

    public async Task<IReadOnlyDictionary<string, string>> GetAsync(
        CancellationToken cancellationToken)
    {
        if (IsFresh())
        {
            return _values;
        }

        await _gate.WaitAsync(cancellationToken);
        try
        {
            // Another caller may have refreshed while this one waited.
            if (IsFresh())
            {
                return _values;
            }

            const string sql = """
                SELECT key, value_json #>> '{}'
                FROM udrive.system_settings
                WHERE key LIKE 'pricing.%'
                   OR key = 'driver.commission.percentage';
                """;

            var loaded = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);
            await using var command = new NpgsqlCommand(sql, connection);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                var key = reader.GetString(0);
                var value = reader.IsDBNull(1) ? null : reader.GetString(1);
                if (value is not null)
                {
                    loaded[key] = value;
                }
            }

            // The dictionary first, then the stamp: a reader that sees a
            // fresh stamp is then guaranteed to see the dictionary that goes
            // with it.
            _values = loaded;
            Volatile.Write(ref _loadedAtTicks, DateTimeOffset.UtcNow.Ticks);
            return _values;
        }
        catch (NpgsqlException)
        {
            // Hold whatever was last read and stop hammering. On the very
            // first load that is an empty map, which every reader here already
            // treats as "use the documented default".
            Volatile.Write(
                ref _loadedAtTicks,
                DateTimeOffset.UtcNow.Add(RetryAfterFailure - CacheFor).Ticks);
            return _values;
        }
        finally
        {
            _gate.Release();
        }
    }

    private bool IsFresh()
    {
        var ticks = Volatile.Read(ref _loadedAtTicks);
        return ticks != 0
               && DateTimeOffset.UtcNow - new DateTimeOffset(ticks, TimeSpan.Zero) < CacheFor;
    }

    /// <summary>Drops the cache so the next read hits the database.</summary>
    /// <remarks>
    /// Called by every admin endpoint that writes a <c>pricing.*</c> key, so
    /// the person who just saved a change sees it immediately rather than up
    /// to a minute later and concluding the save failed.
    ///
    /// Process-local. With more than one API instance the others still carry
    /// their own copy for up to a minute, which is the documented staleness
    /// and not a bug to chase here.
    /// </remarks>
    public void Invalidate() => Volatile.Write(ref _loadedAtTicks, 0);

    // ------------------------------------------------------------ readers
    //
    // Every reader takes a fallback and uses it whenever the key is absent,
    // empty or unparseable. A malformed setting must not be able to stop the
    // app quoting fares — it degrades to the documented default instead.

    public static decimal Decimal(
        IReadOnlyDictionary<string, string> settings, string key, decimal fallback)
    {
        return settings.TryGetValue(key, out var raw)
            && decimal.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var value)
                ? value
                : fallback;
    }

    public static int Int(
        IReadOnlyDictionary<string, string> settings, string key, int fallback)
    {
        return settings.TryGetValue(key, out var raw)
            && int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value)
                ? value
                : fallback;
    }

    public static bool Bool(
        IReadOnlyDictionary<string, string> settings, string key, bool fallback)
    {
        return settings.TryGetValue(key, out var raw) && bool.TryParse(raw, out var value)
            ? value
            : fallback;
    }

    /// <summary>The surge ladder, lowest ratio first.</summary>
    public static IReadOnlyList<(decimal Ratio, decimal Multiplier)> SurgeSteps(
        IReadOnlyDictionary<string, string> settings)
    {
        if (!settings.TryGetValue("pricing.surge.steps", out var raw)
            || string.IsNullOrWhiteSpace(raw))
        {
            return Array.Empty<(decimal, decimal)>();
        }

        try
        {
            using var document = JsonDocument.Parse(raw);
            if (document.RootElement.ValueKind != JsonValueKind.Array)
            {
                return Array.Empty<(decimal, decimal)>();
            }

            var steps = new List<(decimal Ratio, decimal Multiplier)>();
            foreach (var element in document.RootElement.EnumerateArray())
            {
                if (!element.TryGetProperty("ratio", out var ratio)
                    || !element.TryGetProperty("multiplier", out var multiplier))
                {
                    continue;
                }

                if (ratio.TryGetDecimal(out var r) && multiplier.TryGetDecimal(out var m))
                {
                    steps.Add((r, m));
                }
            }

            steps.Sort((left, right) => left.Ratio.CompareTo(right.Ratio));
            return steps;
        }
        catch (JsonException)
        {
            // A hand-edited setting that is not valid JSON means no surge,
            // which is the safe direction to fail in.
            return Array.Empty<(decimal, decimal)>();
        }
    }
}
