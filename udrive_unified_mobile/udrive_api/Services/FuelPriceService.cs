using Npgsql;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Pump prices, and the index the fare engine multiplies distance by.
/// </summary>
/// <remarks>
/// The rate card is a snapshot of what fuel cost on the day it was written.
/// Pakistan revises pump prices roughly every fortnight, and a rate card that
/// does not move with them quietly becomes wrong in one direction or the
/// other — drivers stop offering, or customers overpay.
///
/// Indexing rather than deriving is deliberate. Deriving a per-km rate from
/// litres-per-100km would replace the operator's own numbers with a model of
/// their business; the index leaves their numbers exactly as they set them and
/// only moves them together as fuel moves.
/// </remarks>
public sealed class FuelPriceService(string connectionString)
{
    /// <summary>Today's price per litre for each fuel, if one is recorded.</summary>
    public async Task<IReadOnlyDictionary<string, decimal>> CurrentAsync(
        CancellationToken cancellationToken)
    {
        // DISTINCT ON takes the newest row per fuel whose effective_from has
        // arrived, so a price can be entered in advance of the day it applies.
        const string sql = """
            SELECT DISTINCT ON (fuel_type) fuel_type, price_per_litre
            FROM udrive.fuel_prices
            WHERE effective_from <= (now() AT TIME ZONE 'Asia/Karachi')::date
            ORDER BY fuel_type, effective_from DESC;
            """;

        var prices = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            prices[reader.GetString(0)] = reader.GetDecimal(1);
        }

        return prices;
    }

    /// <summary>
    /// What to multiply a distance rate by, given today's pump price.
    /// </summary>
    /// <remarks>
    /// Returns exactly 1.0 — no adjustment at all — when no baseline is set or
    /// no price has been recorded. That is the state the platform ships in, so
    /// the day this arrives every fare is what it was the day before.
    ///
    /// The clamp is the point of the caps: an index is a reasonable way to
    /// track a 10% move and a terrible way to survive a 60% one, and the
    /// caps are what stop a single bad number in a single row repricing the
    /// whole platform.
    /// </remarks>
    public static decimal Factor(
        IReadOnlyDictionary<string, decimal> currentPrices,
        IReadOnlyDictionary<string, string> settings,
        string fuelType)
    {
        var baselineKey = string.Equals(fuelType, "Diesel", StringComparison.OrdinalIgnoreCase)
            ? "pricing.fuel.baseline.diesel"
            : "pricing.fuel.baseline.petrol";

        var baseline = PricingSettingsService.Decimal(settings, baselineKey, 0m);
        if (baseline <= 0m)
        {
            return 1.0m;
        }

        if (!currentPrices.TryGetValue(fuelType, out var current) || current <= 0m)
        {
            return 1.0m;
        }

        var minimum = PricingSettingsService.Decimal(settings, "pricing.fuel.factor.min", 0.85m);
        var maximum = PricingSettingsService.Decimal(settings, "pricing.fuel.factor.max", 1.25m);
        if (minimum > maximum)
        {
            (minimum, maximum) = (maximum, minimum);
        }

        var factor = current / baseline;
        return factor < minimum ? minimum : factor > maximum ? maximum : factor;
    }

    // ----------------------------------------------------------- admin
    /// <summary>The pump prices the rate card was set against.</summary>
    public async Task<FuelBaselinesDto> GetBaselinesAsync(CancellationToken cancellationToken)
    {
        // The caps come back with the baselines so the portal can state the
        // index it will actually charge rather than a pair of numbers hard-coded
        // into a page.
        const string sql = """
            SELECT key, (value_json #>> '{}')::numeric
            FROM udrive.system_settings
            WHERE key IN ('pricing.fuel.baseline.petrol', 'pricing.fuel.baseline.diesel',
                          'pricing.fuel.factor.min', 'pricing.fuel.factor.max');
            """;

        decimal petrol = 0m;
        decimal diesel = 0m;
        decimal factorMin = 0.85m;
        decimal factorMax = 1.25m;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            if (reader.IsDBNull(1)) continue;
            var value = reader.GetDecimal(1);
            switch (reader.GetString(0))
            {
                case "pricing.fuel.baseline.petrol": petrol = value; break;
                case "pricing.fuel.baseline.diesel": diesel = value; break;
                case "pricing.fuel.factor.min": factorMin = value; break;
                case "pricing.fuel.factor.max": factorMax = value; break;
            }
        }

        return new FuelBaselinesDto(petrol, diesel, factorMin, factorMax);
    }

    /// <summary>
    /// Moves the baselines, and with them every fare.
    /// </summary>
    /// <remarks>
    /// Setting a baseline to today's pump price is how an operator says
    /// "these rates are correct at this fuel price". Raising it afterwards
    /// lowers every fare and lowering it raises them, so this is the single
    /// most consequential number on the pricing screens — which is why it is
    /// its own deliberate action rather than a field on the rate card.
    /// </remarks>
    public async Task<FuelBaselinesDto> SaveBaselinesAsync(
        SaveFuelBaselinesRequest request,
        Guid? actingUserId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.system_settings
                (key, value_json, description, is_public, updated_by_user_id, created_at, updated_at)
            VALUES (@key, to_jsonb(@value::numeric), @description, false, @user, now(), now())
            ON CONFLICT (key) DO UPDATE SET
                value_json = EXCLUDED.value_json,
                updated_by_user_id = EXCLUDED.updated_by_user_id,
                updated_at = now();
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        foreach (var (key, value, description) in new[]
                 {
                     ("pricing.fuel.baseline.petrol", request.Petrol,
                      "Petrol price per litre that the current rate card was set against. 0 disables fuel indexing."),
                     ("pricing.fuel.baseline.diesel", request.Diesel,
                      "Diesel price per litre that the current rate card was set against. 0 disables fuel indexing."),
                 })
        {
            await using var command = new NpgsqlCommand(sql, connection);
            command.Parameters.AddWithValue("key", key);
            command.Parameters.AddWithValue("value", value);
            command.Parameters.AddWithValue("description", description);
            command.Parameters.AddWithValue("user", (object?)actingUserId ?? DBNull.Value);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        // Re-read so the caps travel back with the saved baselines.
        return await GetBaselinesAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<FuelPriceDto>> ListAsync(
        int limit, CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT id, fuel_type, price_per_litre, effective_from, source, created_at
            FROM udrive.fuel_prices
            ORDER BY effective_from DESC, fuel_type
            LIMIT @limit;
            """;

        var list = new List<FuelPriceDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("limit", limit <= 0 ? 60 : Math.Min(limit, 365));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(new FuelPriceDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetDecimal(2),
                DateOnly.FromDateTime(reader.GetDateTime(3)),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.GetDateTime(5)));
        }

        return list;
    }

    public async Task<FuelPriceDto> RecordAsync(
        SaveFuelPriceRequest request,
        Guid? actingUserId,
        CancellationToken cancellationToken)
    {
        // A price for a day that already has one is a correction, not a second
        // price, so the same day overwrites rather than failing. Re-entering a
        // mistyped number should not require anyone to find a delete button.
        const string sql = """
            INSERT INTO udrive.fuel_prices
                (fuel_type, price_per_litre, effective_from, source, created_by_user_id)
            VALUES (@type, @price, @from, @source, @user)
            ON CONFLICT (fuel_type, effective_from) DO UPDATE SET
                price_per_litre = EXCLUDED.price_per_litre,
                source = EXCLUDED.source,
                created_by_user_id = EXCLUDED.created_by_user_id,
                created_at = now()
            RETURNING id, fuel_type, price_per_litre, effective_from, source, created_at;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("type", request.FuelType);
        command.Parameters.AddWithValue("price", request.PricePerLitre);
        command.Parameters.AddWithValue("from", request.EffectiveFrom.ToDateTime(TimeOnly.MinValue));
        command.Parameters.AddWithValue("source", (object?)request.Source ?? DBNull.Value);
        command.Parameters.AddWithValue("user", (object?)actingUserId ?? DBNull.Value);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        await reader.ReadAsync(cancellationToken);
        return new FuelPriceDto(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetDecimal(2),
            DateOnly.FromDateTime(reader.GetDateTime(3)),
            reader.IsDBNull(4) ? null : reader.GetString(4),
            reader.GetDateTime(5));
    }
}
