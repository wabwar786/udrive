using Npgsql;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

public sealed class MarketplacePricingService(string connectionString)
{
    /// <summary>
    /// The rates the customer app prices a trip from.
    /// </summary>
    /// <remarks>
    /// <paramref name="latitude"/> and <paramref name="longitude"/> are the
    /// pickup. When supplied, any admin pricing rule covering that spot today
    /// overrides the flat table.
    ///
    /// Both null still works and simply returns the flat rates, so an older app
    /// build keeps pricing exactly as it did.
    /// </remarks>
    public async Task<IReadOnlyList<ServiceVehicleRateDto>> GetRatesAsync(
        string serviceType,
        CancellationToken cancellationToken,
        double? latitude = null,
        double? longitude = null)
    {
        const string sql = """
            SELECT service_type, vehicle_category, per_seat_rate,
                   whole_vehicle_rate, per_km_rate, currency,
                   base_fare, fuel_type, seat_capacity
            FROM udrive.service_vehicle_rates
            WHERE is_active = true
              AND lower(service_type) = lower(@service)
            ORDER BY vehicle_category;
            """;

        var list = new List<ServiceVehicleRateDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("service", serviceType);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(new ServiceVehicleRateDto(
                reader.GetString(0),
                reader.GetString(1),
                reader.GetDecimal(2),
                reader.GetDecimal(3),
                reader.GetDecimal(4),
                reader.GetString(5),
                // PerMinuteRate is not on this table; it arrives from the
                // pricing rule below, or stays at the record's own default.
                2m,
                reader.GetDecimal(6),
                reader.GetString(7),
                reader.GetInt32(8)));
        }

        // The reader has to close before the connection can be used again for
        // the rule lookups below.
        await reader.CloseAsync();

        // Overlay the admin's rules. Each is looked up per category against the
        // pickup and today's date; where one matches, its figures replace the
        // flat ones. This is how "PKR 80/km in Muzaffarabad on Sundays" reaches
        // the customer without a deploy.
        for (var i = 0; i < list.Count; i++)
        {
            var rate = list[i];
            var rule = await PricingRulesService.ResolveAsync(
                connection,
                rate.ServiceType,
                rate.VehicleCategory,
                latitude,
                longitude,
                cancellationToken);
            if (rule is null) continue;

            list[i] = rate with
            {
                PerKmRate = rule.PerKmRate,
                PerMinuteRate = rule.PerMinuteRate,
                WholeVehicleRate = rule.MinimumFare > 0
                    ? rule.MinimumFare
                    : rate.WholeVehicleRate,
                // A rule's base fare overlays only when it sets one. Zero is
                // "this rule has nothing to say about the flagfall", not "make
                // the flagfall zero" — otherwise every rule written before base
                // fares existed would silently strip one.
                BaseFare = rule.BaseFare > 0 ? rule.BaseFare : rate.BaseFare,
            };
        }

        // Categories that have a rule but no base row.
        //
        // This is why admin rates appeared to do nothing. The list above is
        // seeded from `service_vehicle_rates`, and the rules only *overlay*
        // what is already in it — so a category with no row there was dropped
        // before any rule could touch it, and the app fell back to its built-in
        // figures. A rate set in the portal simply never arrived.
        //
        // A rule is a statement that this vehicle is priced, which is enough to
        // include it. The seeded table stops being a gate on the portal.
        var known = list
            .Select(entry => entry.VehicleCategory)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        foreach (var category in await RuledCategoriesAsync(
                     connection, serviceType, cancellationToken))
        {
            if (known.Contains(category)) continue;

            var rule = await PricingRulesService.ResolveAsync(
                connection, serviceType, category,
                latitude, longitude, cancellationToken);
            if (rule is null) continue;

            list.Add(new ServiceVehicleRateDto(
                serviceType,
                category,
                // Per-seat is not something a pricing rule carries, and
                // inventing one would put a number in front of a customer that
                // no admin chose. Zero leaves the client's own share-out to
                // apply, which is what it does for every other vehicle without
                // a seat price.
                0,
                rule.MinimumFare,
                rule.PerKmRate,
                "PKR",
                rule.PerMinuteRate,
                rule.BaseFare,
                // Without these two the record's own defaults applied — four
                // seats and petrol — so a Coster known only through a pricing
                // rule was divided by four instead of twenty-two and indexed
                // against the wrong pump price. Both are properties of the
                // category, not of the rule, so they come from the same map the
                // rates table is seeded from.
                FuelTypeFor(category),
                SeatCapacityFor(category)));
        }

        return list;
    }

    /// <summary>Which pump price moves a category, when no rate row says.</summary>
    /// <remarks>
    /// The same split as <c>service_vehicle_rates.fuel_type</c>: the two
    /// passenger vans run on diesel here, everything else on petrol.
    /// </remarks>
    private static string FuelTypeFor(string category) =>
        category.Equals("Coster", StringComparison.OrdinalIgnoreCase)
        || category.Equals("Hiace", StringComparison.OrdinalIgnoreCase)
            ? "Diesel"
            : "Petrol";

    /// <summary>Seats a category sells, when no rate row says.</summary>
    private static int SeatCapacityFor(string category) => category.ToLowerInvariant() switch
    {
        "bike" => 1,
        "rickshaw" => 3,
        "car" => 4,
        "hiace" => 12,
        "coster" => 22,
        _ => 4,
    };

    /// <summary>Vehicle categories that have an active pricing rule.</summary>
    private static async Task<IReadOnlyList<string>> RuledCategoriesAsync(
        NpgsqlConnection connection,
        string serviceType,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT DISTINCT vehicle_category
            FROM udrive.pricing_rules
            WHERE is_active = true
              AND lower(service_type) = lower(@service)
            ORDER BY vehicle_category;
            """;

        var categories = new List<string>();
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("service", serviceType);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            categories.Add(reader.GetString(0));
        }

        await reader.CloseAsync();
        return categories;
    }

    public async Task<IReadOnlyList<PublicVehicleDto>> GetAvailableVehiclesAsync(
        string serviceType,
        string? query,
        int limit,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT v.id,
                   dp.id,
                   u.full_name,
                   dp.average_rating,
                   dp.completed_trips,
                   dp.safety_score,
                   dp.is_online,
                   v.category,
                   v.make,
                   v.model,
                   v.year,
                   v.registration_number,
                   v.colour,
                   v.passenger_capacity,
                   v.luggage_capacity,
                   v.has_air_conditioning,
                   v.has_heating,
                   v.is_four_by_four,
                   v.mountain_readiness_score,
                   NULLIF(v.image_url, ''),
                   dp.service_areas,
                   COALESCE(u.email LIKE 'demo.%@udrive.local', false),
                   COALESCE(NULLIF(v.booking_mode, ''), 'WholeVehicle'),
                   COALESCE(v.available_for_tour, false)
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE v.status = 'Verified'
              AND dp.verification_status = 'Approved'
              AND u.status = 'Approved'
              -- The self-test vehicle is never a car a customer can book.
              --
              -- Unconditional here, unlike the ride-request guard: no step in
              -- the run asserts that this vehicle appears in the public list,
              -- so there is nothing to keep visible.
              --
              -- COALESCE because NULL NOT LIKE 'x' is NULL, not true, and a
              -- bare NOT LIKE would drop every driver with no email address.
              AND COALESCE(u.email, '') NOT LIKE 'selftest.%@udrive.local'
              AND (
                    (lower(@service) = 'privatevehicle' AND lower(v.category) <> 'rickshaw')
                    OR (lower(@service) = 'tours' AND v.passenger_capacity >= 4)
                    OR lower(@service) IN ('city', 'citytocity', 'city-to-city')
                  )
              AND (
                    @query = ''
                    OR concat_ws(' ', v.make, v.model, v.category,
                                      v.registration_number, u.full_name,
                                      array_to_string(dp.service_areas, ' '))
                       ILIKE '%' || @query || '%'
                  )
            -- The second sort key used to be
            --   COALESCE(u.email LIKE 'demo.%@udrive.local', false) DESC
            -- which put seeded demo accounts AHEAD of every real driver in the
            -- list a customer sees. Ranking is now online first, then the
            -- driver's own rating.
            ORDER BY dp.is_online DESC,
                     dp.average_rating DESC,
                     v.mountain_readiness_score DESC,
                     v.updated_at DESC
            LIMIT @limit;
            """;

        var list = new List<PublicVehicleDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("service", serviceType.Trim());
        command.Parameters.AddWithValue("query", query?.Trim() ?? string.Empty);
        command.Parameters.AddWithValue("limit", limit);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(new PublicVehicleDto(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.GetDecimal(3),
                reader.GetInt32(4),
                reader.GetInt32(5),
                reader.GetBoolean(6),
                reader.GetString(7),
                reader.GetString(8),
                reader.GetString(9),
                reader.GetInt32(10),
                reader.GetString(11),
                reader.GetString(12),
                reader.GetInt32(13),
                reader.GetInt32(14),
                reader.GetBoolean(15),
                reader.GetBoolean(16),
                reader.GetBoolean(17),
                reader.GetInt32(18),
                reader.IsDBNull(19) ? null : reader.GetString(19),
                reader.GetFieldValue<string[]>(20),
                reader.GetBoolean(21),
                reader.GetString(22),
                reader.GetBoolean(23)));
        }

        return list;
    }


    public async Task<IReadOnlyList<string>> GetAmbulanceCitiesAsync(CancellationToken cancellationToken)
    {
        const string sql = "SELECT DISTINCT city FROM udrive.ambulance_services WHERE is_active=true ORDER BY city";
        var list = new List<string>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken)) list.Add(reader.GetString(0));
        return list;
    }

    public async Task<IReadOnlyList<AmbulanceServiceDto>> GetAmbulancesAsync(string? city, CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT id,name,city,phone_number,per_km_fare,currency,NULLIF(image_url,'')
            FROM udrive.ambulance_services
            WHERE is_active=true
              AND (@city='' OR lower(city)=lower(@city))
            ORDER BY city,name;
            """;
        var list = new List<AmbulanceServiceDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("city", city?.Trim() ?? string.Empty);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(new AmbulanceServiceDto(
                reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
                reader.GetDecimal(4), reader.GetString(5), reader.IsDBNull(6) ? null : reader.GetString(6)));
        }
        return list;
    }


    /// <summary>
    /// Vehicles that are online and within <paramref name="radiusKm"/> of the
    /// customer, for the home-screen map.
    /// </summary>
    /// <remarks>
    /// Freshness matters more than volume here: a driver who closed the app ten
    /// minutes ago must not appear as an available vehicle, or the customer
    /// books something that was never there. Presence older than
    /// <c>PresenceFreshness</c> is excluded.
    ///
    /// Coordinates are rounded to about 100 m before leaving the server. This
    /// endpoint needs no authentication, so precise live positions would let
    /// anyone follow an individual driver.
    /// </remarks>
    public async Task<IReadOnlyList<NearbyVehicleDto>> GetNearbyVehiclesAsync(
        double latitude,
        double longitude,
        double radiusKm,
        string? category,
        bool tourOnly,
        int limit,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT v.id,
                   v.category,
                   ST_Y(dpl.location::geometry) AS lat,
                   ST_X(dpl.location::geometry) AS lng,
                   ST_Distance(
                       dpl.location,
                       ST_SetSRID(ST_MakePoint(@lng, @lat), 4326)::geography
                   ) / 1000.0 AS distance_km,
                   COALESCE(NULLIF(v.booking_mode, ''), 'WholeVehicle'),
                   COALESCE(dp.average_rating, 0),
                   v.passenger_capacity,
                   COALESCE(v.available_for_tour, false),
                   dpl.heading
            FROM udrive.driver_presence_locations dpl
            JOIN udrive.driver_profiles dp ON dp.id = dpl.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            JOIN udrive.vehicles v ON v.driver_profile_id = dp.id
            WHERE ST_DWithin(
                      dpl.location,
                      ST_SetSRID(ST_MakePoint(@lng, @lat), 4326)::geography,
                      @radiusMeters
                  )
              AND dpl.server_timestamp > now() - @freshness
              AND dp.is_online = true
              AND dp.verification_status = 'Approved'
              AND u.status = 'Approved'
              AND v.status = 'Verified'
              -- The self-test Driver posts a presence ping during a run, which
              -- would otherwise put a car on a real customer's map.
              AND COALESCE(u.email, '') NOT LIKE 'selftest.%@udrive.local'
              AND (@category = '' OR lower(v.category) = lower(@category))
              AND (@tourOnly = false OR COALESCE(v.available_for_tour, false) = true)
            ORDER BY distance_km
            LIMIT @limit;
            """;

        var list = new List<NearbyVehicleDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("lat", latitude);
        command.Parameters.AddWithValue("lng", longitude);
        command.Parameters.AddWithValue("radiusMeters", radiusKm * 1000.0);
        command.Parameters.AddWithValue("freshness", PresenceFreshness);
        command.Parameters.AddWithValue("category", category?.Trim() ?? string.Empty);
        command.Parameters.AddWithValue("tourOnly", tourOnly);
        command.Parameters.AddWithValue("limit", limit);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            var distanceKm = reader.GetDouble(4);

            list.Add(new NearbyVehicleDto(
                reader.GetGuid(0).ToString(),
                reader.GetString(1),
                FuzzCoordinate(reader.GetDouble(2)),
                FuzzCoordinate(reader.GetDouble(3)),
                Math.Round(distanceKm, 1),
                EstimateEtaMinutes(distanceKm),
                reader.GetString(5),
                reader.GetDecimal(6),
                reader.GetInt32(7),
                reader.GetBoolean(8),
                // Deliberately not fuzzed. Heading says which way a car is
                // pointing, not where it is, so rounding it would only make the
                // marker point wrong.
                reader.IsDBNull(9) ? null : reader.GetDouble(9)));
        }

        return list;
    }

    /// <summary>Presence older than this is treated as offline.</summary>
    private static readonly TimeSpan PresenceFreshness = TimeSpan.FromSeconds(90);

    /// <summary>
    /// Rounds to 3 decimal places — roughly 100 m at Kashmir's latitude.
    /// </summary>
    private static double FuzzCoordinate(double value) => Math.Round(value, 3);

    /// <summary>
    /// Rough arrival estimate from straight-line distance.
    /// </summary>
    /// <remarks>
    /// Mountain roads are far longer than the straight line, so this multiplies
    /// by 1.6 before applying an average 25 km/h. It is a hint on a map pin, not
    /// a promise — a real figure needs the Distance Matrix API.
    /// </remarks>
    private static int EstimateEtaMinutes(double distanceKm)
    {
        var roadKm = distanceKm * 1.6;
        var minutes = (int)Math.Ceiling(roadKm / 25.0 * 60.0);
        return Math.Clamp(minutes, 1, 180);
    }

    /// <summary>Marks a Driver offline when they turn the switch off.</summary>
    /// <remarks>
    /// Presence expiring after ninety seconds would eventually hide them
    /// anyway, but a Driver who has just declared themselves unavailable should
    /// not keep receiving requests for another minute and a half.
    /// </remarks>
    public async Task<bool> GoOfflineAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.driver_profiles
            SET is_online = false, updated_at = now()
            WHERE user_id = @user;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("user", userId);
        return await command.ExecuteNonQueryAsync(cancellationToken) > 0;
    }

    public async Task<bool> UpdatePresenceAsync(
        Guid userId,
        DriverPresenceUpdateRequest request,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.driver_presence_locations
                (driver_profile_id, location, accuracy_meters, heading,
                 device_timestamp, server_timestamp, updated_at)
            SELECT dp.id,
                   ST_SetSRID(ST_MakePoint(@lng, @lat), 4326)::geography,
                   @accuracy,
                   @heading,
                   @device,
                   now(),
                   now()
            FROM udrive.driver_profiles dp
            WHERE dp.user_id = @user
              AND dp.verification_status = 'Approved'
            ON CONFLICT(driver_profile_id) DO UPDATE SET
                location = excluded.location,
                accuracy_meters = excluded.accuracy_meters,
                -- A parked phone reports no heading. Keeping the last known one
                -- leaves the car pointing the way it was last seen driving,
                -- which is better than snapping every stationary car to north.
                heading = COALESCE(excluded.heading,
                                   udrive.driver_presence_locations.heading),
                device_timestamp = excluded.device_timestamp,
                server_timestamp = now(),
                updated_at = now();
            """;

        // Publishing a position IS going online.
        //
        // `driver_profiles.is_online` was only ever written by the admin
        // suspension path, which sets it false — nothing in the system ever set
        // it true. The nearby-vehicles query requires it, so every driver was
        // filtered out and no vehicle has ever appeared on a customer's map.
        //
        // The Driver app posts presence every fifteen seconds while the online
        // switch is on and stops when it is off, so this is the honest signal.
        // The ninety-second freshness window still hides a driver whose app has
        // died without switching off.
        const string onlineSql = """
            UPDATE udrive.driver_profiles
            SET is_online = true, updated_at = now()
            WHERE user_id = @user
              AND verification_status = 'Approved'
              AND is_online = false;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        await using (var onlineCommand = new NpgsqlCommand(onlineSql, connection))
        {
            onlineCommand.Parameters.AddWithValue("user", userId);
            await onlineCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("user", userId);
        command.Parameters.AddWithValue("lng", request.Longitude);
        command.Parameters.AddWithValue("lat", request.Latitude);
        command.Parameters.AddWithValue(
            "accuracy",
            (object?)request.Accuracy ?? DBNull.Value);
        command.Parameters.AddWithValue(
            "heading",
            (object?)request.Heading ?? DBNull.Value);
        command.Parameters.AddWithValue(
            "device",
            request.DeviceTimestamp.ToUniversalTime());
        return await command.ExecuteNonQueryAsync(cancellationToken) > 0;
    }
}
