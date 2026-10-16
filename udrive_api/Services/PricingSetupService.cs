using System.Globalization;
using Microsoft.AspNetCore.Http;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The admin Pricing page ("Pricing — aasan").
/// </summary>
/// <remarks>
/// One row per vehicle carries the everyday City rate — shuru fees, per km,
/// per minute, minimum — and the switches that sit on top of the meter
/// (rounding, pahari area, petrol index, rush, customer max offer).
///
/// Every number is the admin's. The page shows a suggestion beside each box,
/// worked out from the pump price and from what customers actually paid, but
/// nothing here writes a suggestion by itself: the admin presses "Use" and
/// then Save.
///
/// The everyday rate is stored as the pricing rule that applies everywhere,
/// every day (no area, no days). Saving it also writes the same figures into
/// <c>service_vehicle_rates</c>, because the rate lookup only lets a rule's
/// base fare and minimum overlay that table when they are above zero — so a
/// stale number there would otherwise come back the moment the admin typed 0.
/// </remarks>
public sealed class PricingSetupService(string connectionString, PricingSettingsService settingsService)
{
    public static readonly string[] Vehicles = ["Car", "Bike", "Rickshaw", "Hiace", "Coster"];
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
    private static readonly decimal[] RoundingSteps = [1m, 5m, 10m, 50m, 100m];

    /// <summary>Litres per kilometre, for the fuel part of a suggestion.</summary>
    /// <remarks>Typical AJK figures on mixed and hill roads; only used to suggest.</remarks>
    private static decimal LitresPerKm(string category) => category switch
    {
        "Bike" => 0.025m,
        "Rickshaw" => 0.040m,
        "Car" => 0.080m,
        "Hiace" => 0.110m,
        "Coster" => 0.170m,
        _ => 0.080m,
    };

    private static bool IsDiesel(string category) => category is "Hiace" or "Coster";

    /// <summary>Used only when no pump price has been recorded yet.</summary>
    private static decimal DefaultPerKm(string category) => category switch
    {
        "Bike" => 32m,
        "Rickshaw" => 40m,
        "Car" => 65m,
        "Hiace" => 110m,
        "Coster" => 160m,
        _ => 65m,
    };

    // Same ordering as PricingRulesService.ResolveAsync for a pickup no area
    // rule covers: the row shown on the page is the one a customer is quoted.
    private const string StandardRulesSql = """
        SELECT id, vehicle_category, base_fare, per_km_rate, per_minute_rate, minimum_fare
          FROM udrive.pricing_rules
         WHERE is_active
           AND lower(service_type) = 'city'
           AND area_radius_km IS NULL
           AND (days_of_week IS NULL OR cardinality(days_of_week) = 0 OR cardinality(days_of_week) = 7)
         ORDER BY priority DESC,
                  (days_of_week IS NOT NULL AND cardinality(days_of_week) > 0) DESC,
                  updated_at DESC;
        """;

    // ───────────────────────────────────────────────────────────────── read

    public async Task<ServiceResult<PricingSetupDto>> GetAsync(CancellationToken ct)
    {
        await using var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);

        var standard = new Dictionary<string, (Guid Id, decimal Base, decimal Km, decimal Min, decimal Floor)>(StringComparer.OrdinalIgnoreCase);
        var standardIds = new List<Guid>();
        await using (var cmd = new NpgsqlCommand(StandardRulesSql, c))
        await using (var r = await cmd.ExecuteReaderAsync(ct))
        {
            while (await r.ReadAsync(ct))
            {
                var id = r.GetGuid(0);
                var cat = Canonical(r.GetString(1));
                if (cat is null || standard.ContainsKey(cat)) continue;
                standard[cat] = (id, r.GetDecimal(2), r.GetDecimal(3), r.GetDecimal(4), r.GetDecimal(5));
                standardIds.Add(id);
            }
        }

        // Vehicles with no everyday rule still show what the flat table holds.
        var flat = new Dictionary<string, (decimal Base, decimal Km, decimal Floor)>(StringComparer.OrdinalIgnoreCase);
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT vehicle_category, base_fare, per_km_rate, whole_vehicle_rate
              FROM udrive.service_vehicle_rates
             WHERE lower(service_type) = 'city';
            """, c))
        await using (var r = await cmd.ExecuteReaderAsync(ct))
        {
            while (await r.ReadAsync(ct))
            {
                var cat = Canonical(r.GetString(0));
                if (cat is null) continue;
                flat[cat] = (r.GetDecimal(1), r.GetDecimal(2), r.GetDecimal(3));
            }
        }

        var prices = await FuelPricesAsync(c, ct);
        var market = await MarketPerKmAsync(c, ct);

        var rows = new List<PricingVehicleRowDto>();
        foreach (var cat in Vehicles)
        {
            var suggestion = Suggest(cat, prices, market.TryGetValue(cat, out var m) ? m : (null, 0));
            if (standard.TryGetValue(cat, out var s))
            {
                rows.Add(new PricingVehicleRowDto(cat, s.Id, s.Base, s.Km, s.Min, s.Floor, suggestion));
            }
            else if (flat.TryGetValue(cat, out var f))
            {
                rows.Add(new PricingVehicleRowDto(cat, null, f.Base, f.Km, 2m, f.Floor, suggestion));
            }
            else
            {
                rows.Add(new PricingVehicleRowDto(cat, null, 0m, 0m, 0m, 0m, suggestion));
            }
        }

        settingsService.Invalidate();
        var settings = await settingsService.GetAsync(ct);
        var switches = new PricingSwitchesDto(
            PricingSettingsService.Decimal(settings, "pricing.rounding.step", 5m),
            PricingSettingsService.Bool(settings, "pricing.zones.enabled", true),
            PricingSettingsService.Bool(settings, "pricing.fuel.enabled", true),
            PricingSettingsService.Bool(settings, "pricing.surge.enabled", false),
            PricingSettingsService.Decimal(settings, "pricing.offer.ceiling_multiplier", 3m));

        var activeZones = await CountAsync(c, "SELECT count(*) FROM udrive.pricing_zones WHERE is_active;", ct);
        var special = await CountAsync(c,
            """
            SELECT count(*) FROM udrive.pricing_rules
             WHERE is_active
               AND NOT (lower(service_type) = 'city' AND area_radius_km IS NULL
                        AND (days_of_week IS NULL OR cardinality(days_of_week) = 0 OR cardinality(days_of_week) = 7));
            """, ct);

        var ops = new List<string>();
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT COALESCE(t.name, 'Area'), f.vehicle_class, (f.percent::float8)::text
              FROM udrive.ops_fare_adjustments f
              LEFT JOIN udrive.territories t ON t.id = f.territory_id
             WHERE f.ended_early_at IS NULL AND now() BETWEEN f.starts_at AND f.ends_at
             ORDER BY f.created_at DESC LIMIT 10;
            """, c))
        await using (var r = await cmd.ExecuteReaderAsync(ct))
        {
            while (await r.ReadAsync(ct))
            {
                var pct = double.Parse(r.GetString(2), Inv);
                ops.Add($"{r.GetString(0)} {r.GetString(1)} {(pct > 0 ? "+" : "")}{pct.ToString("0.#", Inv)}%");
            }
        }

        var status = new PricingStatusDto(
            activeZones,
            PricingSettingsService.Decimal(settings, "pricing.fuel.baseline.petrol", 0m),
            PricingSettingsService.Decimal(settings, "pricing.fuel.baseline.diesel", 0m),
            prices.TryGetValue("Petrol", out var petrol) ? petrol : null,
            prices.TryGetValue("Diesel", out var diesel) ? diesel : null,
            PricingSettingsService.SurgeSteps(settings).Count,
            special,
            ops);

        return ServiceResult<PricingSetupDto>.Ok(new PricingSetupDto(
            rows, switches, SwitchSuggestions(switches, status), status, standardIds));
    }

    // ──────────────────────────────────────────────────────────── suggestions

    /// <summary>
    /// A starting point for one vehicle. Never written by the system.
    /// </summary>
    /// <remarks>
    /// Fuel is roughly a third of what a kilometre costs a driver once wear,
    /// tyres and his own earning are counted, so the fuel cost per km is
    /// tripled. Where at least ten completed trips in the last 30 days show
    /// what customers actually paid per km, the suggestion is the average of
    /// the two. The other three boxes follow from per km so they stay in
    /// proportion: per minute ≈ 5% of per km, shuru fees ≈ one kilometre, and
    /// the minimum ≈ a 3 km / 10 minute trip.
    /// </remarks>
    internal static PricingVehicleSuggestionDto Suggest(
        string cat,
        IReadOnlyDictionary<string, decimal> prices,
        (decimal? PerKm, int Trips) market)
    {
        var fuelType = IsDiesel(cat) ? "Diesel" : "Petrol";
        decimal? fuelCost = prices.TryGetValue(fuelType, out var price) && price > 0
            ? Math.Round(price * LitresPerKm(cat), 2)
            : null;

        var fuelBased = fuelCost is { } fc ? fc * 3m : DefaultPerKm(cat);
        string basis;
        decimal perKm;
        if (market.PerKm is { } mk && market.Trips >= 10)
        {
            perKm = (fuelBased + mk) / 2m;
            basis = fuelCost is null
                ? $"UDrive default + {market.Trips} trips ka asal kiraya"
                : $"{fuelType} {price.ToString("0", Inv)}/litre + {market.Trips} trips ka asal kiraya";
        }
        else
        {
            perKm = fuelBased;
            basis = fuelCost is null
                ? "Fuel price nahi daali — UDrive default"
                : $"{fuelType} {price.ToString("0", Inv)}/litre × {LitresPerKm(cat).ToString("0.###", Inv)} litre/km × 3";
        }

        perKm = Math.Max(1m, Math.Round(perKm, 0, MidpointRounding.AwayFromZero));
        var perMinute = Math.Round(perKm / 20m, 0, MidpointRounding.AwayFromZero);
        var baseFare = FareEngine.RoundUp(perKm, 5m);
        var minimum = FareEngine.RoundUp(baseFare + perKm * 3m + perMinute * 10m, 50m);

        return new PricingVehicleSuggestionDto(
            baseFare, perKm, perMinute, minimum, basis, fuelCost, market.PerKm, market.Trips);
    }

    internal static IReadOnlyList<PricingSwitchSuggestionDto> SwitchSuggestions(PricingSwitchesDto s, PricingStatusDto st) =>
    [
        new("rounding", "5", "App ki list bhi 5 rupay par round karti hai — dono same rahenge"),
        st.ActiveZones > 0
            ? new("zones", "on", $"{st.ActiveZones} pahari zone set hain")
            : new("zones", "off", "Koi zone active nahi — On karne se kuch nahi badlega"),
        st.PetrolPrice is null && st.DieselPrice is null
            ? new("fuel", "off", "Pehle Fuel prices mein aaj ki keemat daalein")
            : new("fuel", "on", "Petrol/diesel ki keemat badle to kiraya saath badle"),
        st.SurgeSteps == 0
            ? new("surge", "off", "Rush ke steps set nahi — On karne se kuch nahi hoga")
            : new("surge", "off", "Jab tak drivers kam hain, rush ka hisaab sahi nahi banta"),
        new("ceiling", "3", "Customer zyada se zyada 3 guna tak offer kar sake"),
    ];

    // ───────────────────────────────────────────────────────────────── write

    public async Task<ServiceResult<PricingSetupDto>> SaveRatesAsync(
        Guid adminId, SavePricingRatesRequest request, CancellationToken ct)
    {
        if (request.Rates is null || request.Rates.Count == 0)
        {
            return Fail("pricing_nothing", "Koi rate nahi bheja.");
        }

        var clean = new List<SavePricingRateRequest>();
        foreach (var rate in request.Rates)
        {
            var cat = Canonical(rate.Category);
            if (cat is null) return Fail("pricing_vehicle", $"Gaari '{rate.Category}' nahi pehchani.");
            if (rate.PerKmRate is < 1m or > 100000m) return Fail("pricing_per_km", $"{cat}: Per km kam az kam 1 hona chahiye.");
            if (rate.PerMinuteRate is < 0m or > 10000m) return Fail("pricing_per_minute", $"{cat}: Per minute 0 se 10,000 tak.");
            if (rate.BaseFare is < 0m or > 100000m) return Fail("pricing_base", $"{cat}: Shuru fees 0 se 100,000 tak.");
            if (rate.MinimumFare is < 1m or > 500000m) return Fail("pricing_minimum", $"{cat}: Minimum kam az kam 1 hona chahiye.");
            clean.Add(rate with { Category = cat });
        }

        await using var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        await using var tx = await c.BeginTransactionAsync(ct);

        foreach (var rate in clean)
        {
            // The rule this vehicle is quoted from today, when no area rule
            // covers the pickup.
            Guid? keep = null;
            var duplicates = new List<Guid>();
            await using (var find = new NpgsqlCommand(StandardRulesSql, c, tx))
            await using (var r = await find.ExecuteReaderAsync(ct))
            {
                while (await r.ReadAsync(ct))
                {
                    if (!string.Equals(Canonical(r.GetString(1)), rate.Category, StringComparison.Ordinal)) continue;
                    if (keep is null) keep = r.GetGuid(0);
                    else duplicates.Add(r.GetGuid(0));
                }
            }

            if (keep is { } id)
            {
                await using var up = new NpgsqlCommand(
                    """
                    UPDATE udrive.pricing_rules
                       SET base_fare = @base, per_km_rate = @km, per_minute_rate = @min, minimum_fare = @floor,
                           days_of_week = NULL, updated_at = now()
                     WHERE id = @id;
                    """, c, tx);
                BindRate(up, rate);
                up.Parameters.AddWithValue("id", id);
                await up.ExecuteNonQueryAsync(ct);
            }
            else
            {
                await using var ins = new NpgsqlCommand(
                    """
                    INSERT INTO udrive.pricing_rules
                        (name, service_type, vehicle_category, per_km_rate, minimum_fare, per_minute_rate,
                         base_fare, days_of_week, priority, is_active)
                    VALUES (@name, 'City', @cat, @km, @floor, @min, @base, NULL, 0, true);
                    """, c, tx);
                BindRate(ins, rate);
                ins.Parameters.AddWithValue("name", $"Standard — {rate.Category}");
                ins.Parameters.AddWithValue("cat", rate.Category);
                await ins.ExecuteNonQueryAsync(ct);
            }

            // Two "everyday" rules for one vehicle is how a saved rate seemed
            // to do nothing: the other one won. Only one stays on.
            foreach (var dup in duplicates)
            {
                await using var off = new NpgsqlCommand(
                    "UPDATE udrive.pricing_rules SET is_active = false, updated_at = now() WHERE id = @id;", c, tx);
                off.Parameters.AddWithValue("id", dup);
                await off.ExecuteNonQueryAsync(ct);
            }

            await using (var flat = new NpgsqlCommand(
                """
                UPDATE udrive.service_vehicle_rates
                   SET base_fare = @base, per_km_rate = @km, whole_vehicle_rate = @floor, updated_at = now()
                 WHERE lower(service_type) = 'city' AND lower(vehicle_category) = lower(@cat);
                """, c, tx))
            {
                BindRate(flat, rate);
                flat.Parameters.AddWithValue("cat", rate.Category);
                await flat.ExecuteNonQueryAsync(ct);
            }

            await using var audit = new NpgsqlCommand(
                """
                INSERT INTO udrive.audit_logs (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
                VALUES (gen_random_uuid(), @actor, 'PricingRateSaved', 'Pricing', @cat,
                        jsonb_build_object('baseFare', @base, 'perKm', @km, 'perMinute', @min, 'minimum', @floor,
                                           'turnedOff', @dups),
                        now(), now());
                """, c, tx);
            BindRate(audit, rate);
            audit.Parameters.AddWithValue("actor", adminId);
            audit.Parameters.AddWithValue("cat", rate.Category);
            audit.Parameters.AddWithValue("dups", duplicates.Count);
            await audit.ExecuteNonQueryAsync(ct);
        }

        await tx.CommitAsync(ct);
        settingsService.Invalidate();
        var fresh = await GetAsync(ct);
        return fresh.Success
            ? ServiceResult<PricingSetupDto>.Ok(fresh.Data!, "Rates save ho gaye. Agle quote se lagu.")
            : fresh;
    }

    public async Task<ServiceResult<PricingSetupDto>> SaveSwitchesAsync(
        Guid adminId, SavePricingSwitchesRequest request, CancellationToken ct)
    {
        if (!RoundingSteps.Contains(request.RoundingStep))
        {
            return Fail("pricing_rounding", "Round 1, 5, 10, 50 ya 100 rupay par ho sakta hai.");
        }

        if (request.OfferCeiling is < 1.5m or > 5m)
        {
            return Fail("pricing_ceiling", "Customer max offer 1.5 se 5 guna tak.");
        }

        await using var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        await using var tx = await c.BeginTransactionAsync(ct);

        var message = "Settings save ho gayi.";

        // Turning the petrol index on with no baseline would change nothing,
        // so the baseline becomes today's pump price: index 1.0 today, and it
        // moves from here as prices move.
        if (request.FuelEnabled)
        {
            var prices = await FuelPricesAsync(c, ct, tx);
            foreach (var (fuel, key) in new[] { ("Petrol", "pricing.fuel.baseline.petrol"), ("Diesel", "pricing.fuel.baseline.diesel") })
            {
                var current = await SettingTextAsync(c, tx, key, ct);
                var hasBaseline = decimal.TryParse(current, NumberStyles.Float, Inv, out var b) && b > 0m;
                if (!hasBaseline && prices.TryGetValue(fuel, out var p) && p > 0m)
                {
                    await UpsertAsync(c, tx, adminId, key, p.ToString(Inv), "numeric",
                        "Fuel price the rate card was set against. 0 disables fuel indexing.", ct);
                    message = "Settings save ho gayi. Petrol index aaj ki keemat se shuru hua (aaj × 1.0).";
                }
            }
        }

        await UpsertAsync(c, tx, adminId, "pricing.rounding.step", request.RoundingStep.ToString(Inv), "numeric",
            "Fares are rounded up to this many rupees.", ct);
        await UpsertAsync(c, tx, adminId, "pricing.zones.enabled", request.ZonesEnabled ? "true" : "false", "boolean",
            "Pahari area (fare zones) on or off for every quote.", ct);
        await UpsertAsync(c, tx, adminId, "pricing.fuel.enabled", request.FuelEnabled ? "true" : "false", "boolean",
            "Petrol / diesel index on or off for every quote.", ct);
        await UpsertAsync(c, tx, adminId, "pricing.surge.enabled", request.SurgeEnabled ? "true" : "false", "boolean",
            "Rush (surge) on or off.", ct);
        await UpsertAsync(c, tx, adminId, "pricing.offer.ceiling_multiplier", request.OfferCeiling.ToString(Inv), "numeric",
            "Highest offer a customer may make, as a multiple of the suggested fare.", ct);

        await using (var audit = new NpgsqlCommand(
            """
            INSERT INTO udrive.audit_logs (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
            VALUES (gen_random_uuid(), @actor, 'PricingSwitchesSaved', 'Pricing', 'switches',
                    jsonb_build_object('rounding', @round, 'zones', @zones, 'fuel', @fuel, 'surge', @surge, 'ceiling', @ceiling),
                    now(), now());
            """, c, tx))
        {
            audit.Parameters.AddWithValue("actor", adminId);
            audit.Parameters.AddWithValue("round", request.RoundingStep);
            audit.Parameters.AddWithValue("zones", request.ZonesEnabled);
            audit.Parameters.AddWithValue("fuel", request.FuelEnabled);
            audit.Parameters.AddWithValue("surge", request.SurgeEnabled);
            audit.Parameters.AddWithValue("ceiling", request.OfferCeiling);
            await audit.ExecuteNonQueryAsync(ct);
        }

        await tx.CommitAsync(ct);
        settingsService.Invalidate();
        var fresh = await GetAsync(ct);
        return fresh.Success ? ServiceResult<PricingSetupDto>.Ok(fresh.Data!, message) : fresh;
    }

    // ───────────────────────────────────────────────────────────── fare check

    /// <summary>The real quote for a sample trip, explained line by line.</summary>
    public async Task<ServiceResult<PricingCheckDto>> CheckAsync(
        Guid adminId, PricingCheckRequest request, FareEngine engine, CancellationToken ct)
    {
        var cat = Canonical(request.Category);
        if (cat is null) return CheckFail("pricing_vehicle", "Gaari chunein.");
        if (request.DistanceKm is <= 0 or > 2000) return CheckFail("pricing_km", "Km 0.1 se 2,000 tak.");
        if (request.Minutes is < 0 or > 6000) return CheckFail("pricing_minutes", "Minute 0 se 6,000 tak.");

        var destLat = request.DestinationLatitude ?? request.PickupLatitude;
        var destLng = request.DestinationLongitude ?? request.PickupLongitude;
        var quoteResult = await engine.AdminCheckAsync(adminId, new FareQuoteRequest(
            "City", cat, "WholeVehicle", 1,
            request.PickupLatitude, request.PickupLongitude, destLat, destLng,
            request.DistanceKm, request.Minutes), ct);
        if (!quoteResult.Success)
        {
            return ServiceResult<PricingCheckDto>.Fail(quoteResult.StatusCode, quoteResult.ErrorCode ?? "pricing_check", quoteResult.Message ?? "Fare nahi bana.");
        }

        var q = quoteResult.Data!;
        var b = q.Breakdown;

        await using var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        var rule = await PricingRulesService.ResolveAsync(c, "City", cat, request.PickupLatitude, request.PickupLongitude, ct);
        var ops = await OpsBoardService.FarePercentAsync(c, request.PickupLatitude, request.PickupLongitude, cat, ct);

        var settings = await settingsService.GetAsync(ct);
        var step = Math.Clamp(PricingSettingsService.Decimal(settings, "pricing.rounding.step", 5m), 0.01m, 1000m);

        var lines = new List<PricingCheckLineDto>
        {
            new("Shuru fees", Money(b.BaseFare), false),
            new(b.FuelFactor == 1m
                    ? $"{Num(b.DistanceKm)} km × {Rate(b.PerKmRate)}"
                    : $"{Num(b.DistanceKm)} km × {Rate(b.PerKmRate)} × petrol index {b.FuelFactor.ToString("0.###", Inv)}",
                Money(b.DistanceCost), false),
            new($"{Num(b.DurationMinutes)} min × {Rate(b.PerMinuteRate)}", Money(b.TimeCost), false),
            new("Meter jama", Money(b.Metered), false),
        };

        var subtotal = b.Metered * b.ZoneFactor + b.ReturnCost;
        if (b.ZoneFactor != 1m)
        {
            lines.Add(new($"Pahari area ({b.OriginZone} / {b.DestinationZone}) × {b.ZoneFactor.ToString("0.###", Inv)}", Money(b.Metered * b.ZoneFactor), false));
        }
        else
        {
            lines.Add(new("Pahari area × 1.0", "—", true));
        }

        if (b.ReturnCost > 0m)
        {
            lines.Add(new($"Wapsi khali ({(b.ReturnShare * 100m).ToString("0", Inv)}%)", "+" + Money(b.ReturnCost), false));
        }

        var charged = Math.Max(subtotal, b.Floor);
        lines.Add(b.Floor > subtotal
            ? new($"Minimum {Money(b.Floor)} lagu (kiraya is se kam tha)", Money(b.Floor), false)
            : new($"Minimum {Money(b.Floor)} (lagu nahi, kiraya zyada hai)", "—", true));

        if (q.Negotiable && ops != 0m)
        {
            charged *= 1m + ops / 100m;
            lines.Add(new($"Ops board aaj {(ops > 0 ? "+" : "")}{ops.ToString("0.#", Inv)}%", Money(charged), false));
        }

        if (b.Surge != 1m)
        {
            lines.Add(new($"Rush × {b.Surge.ToString("0.##", Inv)}", "", false));
        }
        else
        {
            lines.Add(new("Rush × 1.0", "—", true));
        }

        lines.Add(new($"Jama {Money(charged * b.Surge)} → {step.ToString("0.##", Inv)} rupay tak upar round", Money(q.Recommended), false));
        if (q.Negotiable)
        {
            lines.Add(new($"Customer {Money(q.Minimum)} se {Money(q.Maximum)} tak offer kar sakta hai", "", true));
        }

        // What the app's vehicle list shows before a vehicle is tapped — its
        // own quick sum (km × rate + minutes × rate, at least the minimum,
        // nearest 5; no shuru fees, and a per minute of 0 is read as 2).
        // Tapping the vehicle replaces it with the figure above.
        var listPerMinute = b.PerMinuteRate > 0m ? b.PerMinuteRate : 2m;
        var quick = Math.Max(b.PerKmRate * (decimal)b.DistanceKm + listPerMinute * (decimal)b.DurationMinutes, FareEngine.RoundUp(b.Floor, 5m));
        var appList = Math.Round(quick / 5m, MidpointRounding.AwayFromZero) * 5m;

        var ruleName = q.FixedRouteLabel is { } fixedLabel
            ? $"Fixed route: {fixedLabel}"
            : rule is null ? "Koi rule nahi — flat table" : rule.Name;

        return ServiceResult<PricingCheckDto>.Ok(new PricingCheckDto(
            ruleName, lines, q.Recommended, q.Minimum, q.Maximum, q.Negotiable, appList));
    }

    // ──────────────────────────────────────────────────────────────── helpers

    internal static string? Canonical(string? category)
    {
        var value = (category ?? "").Trim();
        if (value.Equals("Coaster", StringComparison.OrdinalIgnoreCase)) value = "Coster";
        return Vehicles.FirstOrDefault(v => v.Equals(value, StringComparison.OrdinalIgnoreCase));
    }

    private static void BindRate(NpgsqlCommand cmd, SavePricingRateRequest rate)
    {
        cmd.Parameters.AddWithValue("base", rate.BaseFare);
        cmd.Parameters.AddWithValue("km", rate.PerKmRate);
        cmd.Parameters.AddWithValue("min", rate.PerMinuteRate);
        cmd.Parameters.AddWithValue("floor", rate.MinimumFare);
    }

    private static async Task<Dictionary<string, decimal>> FuelPricesAsync(
        NpgsqlConnection c, CancellationToken ct, NpgsqlTransaction? tx = null)
    {
        var prices = new Dictionary<string, decimal>(StringComparer.OrdinalIgnoreCase);
        await using var cmd = new NpgsqlCommand(
            """
            SELECT DISTINCT ON (fuel_type) fuel_type, price_per_litre
              FROM udrive.fuel_prices
             WHERE effective_from <= (now() AT TIME ZONE 'Asia/Karachi')::date
             ORDER BY fuel_type, effective_from DESC;
            """, c, tx);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) prices[r.GetString(0)] = r.GetDecimal(1);
        return prices;
    }

    /// <summary>Median rupees per km customers paid, last 30 days, by vehicle.</summary>
    /// <remarks>
    /// Distance is the straight line × 1.3 (the road factor the app uses when
    /// it has no route), so this is an estimate — good enough to suggest from,
    /// and the reason it is only ever averaged with the fuel figure.
    /// </remarks>
    private static async Task<Dictionary<string, (decimal? PerKm, int Trips)>> MarketPerKmAsync(
        NpgsqlConnection c, CancellationToken ct)
    {
        var result = new Dictionary<string, (decimal?, int)>(StringComparer.OrdinalIgnoreCase);
        await using var cmd = new NpgsqlCommand(
            """
            WITH trips AS (
                SELECT r.vehicle_category AS cat,
                       max(b.total_amount) AS paid,
                       ST_Distance(r.pickup_location, r.destination_location) / 1000.0 * 1.3 AS km
                  FROM udrive.bookings b
                  JOIN udrive.ride_requests r ON r.id = b.ride_request_id
                 WHERE b.status = 'Completed'
                   AND b.created_at > now() - interval '30 days'
                   AND b.total_amount > 0
                 GROUP BY r.id, r.vehicle_category, r.pickup_location, r.destination_location
            )
            SELECT cat,
                   (percentile_cont(0.5) WITHIN GROUP (ORDER BY paid / km))::float8::text,
                   count(*)::int
              FROM trips
             WHERE km >= 2
             GROUP BY cat;
            """, c);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct))
        {
            var cat = Canonical(r.GetString(0));
            if (cat is null || r.IsDBNull(1)) continue;
            var perKm = Math.Round((decimal)double.Parse(r.GetString(1), Inv), 1);
            var trips = r.GetInt32(2);
            if (result.TryGetValue(cat, out var existing)) trips += existing.Item2;
            result[cat] = (perKm, trips);
        }

        return result;
    }

    private static async Task<int> CountAsync(NpgsqlConnection c, string sql, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(sql, c);
        var value = await cmd.ExecuteScalarAsync(ct);
        return value is null ? 0 : Convert.ToInt32(value, Inv);
    }

    private static async Task<string?> SettingTextAsync(NpgsqlConnection c, NpgsqlTransaction tx, string key, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand("SELECT value_json #>> '{}' FROM udrive.system_settings WHERE key = @k;", c, tx);
        cmd.Parameters.AddWithValue("k", key);
        var value = await cmd.ExecuteScalarAsync(ct);
        return value?.ToString();
    }

    private static async Task UpsertAsync(
        NpgsqlConnection c, NpgsqlTransaction tx, Guid adminId, string key, string value, string kind,
        string description, CancellationToken ct)
    {
        // Stored as a JSON number or boolean, the way the seeded rows are.
        var sql = kind == "boolean"
            ? "to_jsonb(@value::boolean)"
            : "to_jsonb(@value::numeric)";
        await using var cmd = new NpgsqlCommand(
            $"""
            INSERT INTO udrive.system_settings (key, value_json, description, is_public, updated_by_user_id, created_at, updated_at)
            VALUES (@key, {sql}, @description, false, @user, now(), now())
            ON CONFLICT (key) DO UPDATE SET
                value_json = EXCLUDED.value_json,
                updated_by_user_id = EXCLUDED.updated_by_user_id,
                updated_at = now();
            """, c, tx);
        cmd.Parameters.AddWithValue("key", key);
        cmd.Parameters.AddWithValue("value", value);
        cmd.Parameters.AddWithValue("description", description);
        cmd.Parameters.AddWithValue("user", adminId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static string Money(decimal value) =>
        Math.Round(value, 0, MidpointRounding.AwayFromZero).ToString("#,0", Inv);

    private static string Rate(decimal value) => value.ToString("#,0.##", Inv);

    private static string Num(double value) => value.ToString("#,0.#", Inv);

    private static ServiceResult<PricingSetupDto> Fail(string code, string message) =>
        ServiceResult<PricingSetupDto>.Fail(StatusCodes.Status400BadRequest, code, message);

    private static ServiceResult<PricingCheckDto> CheckFail(string code, string message) =>
        ServiceResult<PricingCheckDto>.Fail(StatusCodes.Status400BadRequest, code, message);
}
