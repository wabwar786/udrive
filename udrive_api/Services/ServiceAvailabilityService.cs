using Microsoft.AspNetCore.Http;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Which services are open to customers.
/// </summary>
/// <remarks>
/// Read by the customer app on every launch, and written only from the admin
/// portal. Drivers never consult it: a closed service still accepts vehicle
/// registrations, which is the whole point — otherwise the first day a service
/// opens it has no fleet.
/// </remarks>
public sealed class ServiceAvailabilityService(string connectionString)
{
    /// <summary>Every service and its current state.</summary>
    /// <remarks>
    /// Returns the whole list rather than only the closed ones. A client that
    /// receives "these are closed" has to assume everything else is open, and
    /// assumes wrongly the moment a new service is added.
    /// </remarks>
    public async Task<ServiceResult<IReadOnlyList<ServiceAvailabilityDto>>> ListAsync(
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT service_key, is_open, badge_label, closed_message, updated_at
            FROM udrive.service_availability
            ORDER BY service_key;
            """;

        var list = new List<ServiceAvailabilityDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            list.Add(new ServiceAvailabilityDto(
                reader.GetString(0),
                reader.GetBoolean(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetFieldValue<DateTimeOffset>(4)));
        }

        // A known key with no row still appears, open.
        //
        // Without this, a missing row means the Admin's Services page simply
        // does not list that service — there is nothing to switch and nothing
        // saying why. Listing it as open is both true (the app treats an
        // unknown key as open) and useful: switching it off writes the row,
        // because UpdateAsync upserts.
        var present = list.Select(row => row.ServiceKey).ToHashSet(StringComparer.Ordinal);
        foreach (var key in KnownServiceKeys)
        {
            if (present.Contains(key)) continue;
            list.Add(new ServiceAvailabilityDto(
                key, true, "SOON", "This service is not open yet.",
                DateTimeOffset.UtcNow));
        }

        return ServiceResult<IReadOnlyList<ServiceAvailabilityDto>>.Ok(
            list.OrderBy(row => row.ServiceKey, StringComparer.Ordinal).ToList());
    }

    /// <summary>One numeric operational setting, with a default and a clamp.</summary>
    /// <remarks>
    /// These are dials, not constants. Each one's right value depends on things
    /// that change without a release — how many drivers are online, how spread
    /// out a town is, what data costs — so they live where they can be turned
    /// without cutting one.
    ///
    /// Every read is clamped. A value that makes the platform stop working
    /// should not be reachable by a typo in a text field.
    /// </remarks>
    private async Task<double> ReadNumberAsync(
        string key,
        double fallback,
        double min,
        double max,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT value_json #>> '{}' FROM udrive.system_settings
            WHERE key = @key;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("key", key);
        var value = await command.ExecuteScalarAsync(cancellationToken) as string;

        return double.TryParse(value, out var parsed)
            ? Math.Clamp(parsed, min, max)
            : fallback;
    }

    private async Task WriteNumberAsync(
        Guid adminUserId,
        string key,
        string description,
        double value,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.system_settings
                (key, value_json, description, is_public,
                 updated_by_user_id, created_at, updated_at)
            VALUES (@key, to_jsonb(@value::text), @description, true,
                    @admin, now(), now())
            ON CONFLICT (key) DO UPDATE
            SET value_json = EXCLUDED.value_json,
                is_public = true,
                updated_by_user_id = EXCLUDED.updated_by_user_id,
                updated_at = now();
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("key", key);
        command.Parameters.AddWithValue("value", value.ToString("0.##"));
        command.Parameters.AddWithValue("description", description);
        command.Parameters.AddWithValue("admin", adminUserId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>The platform's cut of each fare, as a percentage.</summary>
    /// <remarks>
    /// Taken from the Driver's prepaid balance the moment a trip starts.
    /// Clamped 0–40: zero is a legitimate choice while building a fleet, and
    /// anything above forty is a number no driver would keep working under —
    /// a typo that empties their balance in three rides is not a setting.
    /// </remarks>
    public Task<double> CommissionPercentageAsync(CancellationToken ct) =>
        ReadNumberAsync("driver.commission.percentage", 10, 0, 40, ct);

    public Task SetCommissionPercentageAsync(
            Guid admin, double percentage, CancellationToken ct) =>
        WriteNumberAsync(admin, "driver.commission.percentage",
            "The platform's cut of each fare, taken when a trip starts.",
            Math.Clamp(percentage, 0, 40), ct);

    /// <summary>Commission on each kind of work, in percent.</summary>
    /// <remarks>
    /// City rides keep the original key. The other three fall back to the
    /// city rate when an Admin has not set them, so a missing row never means
    /// "free".
    /// </remarks>
    public async Task<CommissionRatesDto> CommissionRatesAsync(CancellationToken ct)
    {
        var city = await CommissionPercentageAsync(ct);
        return new CommissionRatesDto(
            city,
            await ReadNumberAsync("driver.commission.intercity_percentage", city, 0, 40, ct),
            await ReadNumberAsync("driver.commission.tour_percentage", city, 0, 40, ct),
            await ReadNumberAsync("driver.commission.rent_percentage", city, 0, 40, ct),
            await ReadNumberAsync("hotel.commission.percentage", 0, 0, 40, ct),
            await ReadNumberAsync("hotel.wallet.minimum_balance", 0, 0, 1_000_000, ct),
            await ReadNumberAsync("hotel.wallet.low_balance_alert", 500, 0, 1_000_000, ct));
    }

    public async Task SetCommissionRatesAsync(
        Guid admin, SetCommissionRequest request, CancellationToken ct)
    {
        await SetCommissionPercentageAsync(admin, request.Percentage, ct);
        if (request.IntercityPercentage is { } intercity)
        {
            await WriteNumberAsync(admin, "driver.commission.intercity_percentage",
                "Commission on city-to-city rides, taken when the ride starts.",
                Math.Clamp(intercity, 0, 40), ct);
        }

        if (request.TourPercentage is { } tour)
        {
            await WriteNumberAsync(admin, "driver.commission.tour_percentage",
                "Commission on tour bookings, taken when the tour starts.",
                Math.Clamp(tour, 0, 40), ct);
        }

        if (request.RentPercentage is { } rent)
        {
            await WriteNumberAsync(admin, "driver.commission.rent_percentage",
                "Commission on rent-a-car bookings, taken when the driver accepts.",
                Math.Clamp(rent, 0, 40), ct);
        }

        if (request.HotelPercentage is { } hotel)
        {
            await WriteNumberAsync(admin, "hotel.commission.percentage",
                "Commission (%) on a hotel booking, taken from the hotel wallet when the booking is confirmed.",
                Math.Clamp(hotel, 0, 40), ct);
        }

        if (request.HotelMinimumBalance is { } minimum)
        {
            await WriteNumberAsync(admin, "hotel.wallet.minimum_balance",
                "Below this hotel wallet balance (PKR) the hotel is hidden from new customers.",
                Math.Clamp(minimum, 0, 1_000_000), ct);
        }

        if (request.HotelLowBalanceAlert is { } alert)
        {
            await WriteNumberAsync(admin, "hotel.wallet.low_balance_alert",
                "Below this hotel wallet balance (PKR) the owner is asked to top up.",
                Math.Clamp(alert, 0, 1_000_000), ct);
        }
    }

    /// <summary>Welcome credit per kind of work: city (the original key), tour, rent, hotel.</summary>
    public async Task<(double City, double Tour, double Rent, double Hotel)> WelcomeBonusesAsync(CancellationToken ct) =>
        (await WelcomeBonusAsync(ct),
         await ReadNumberAsync("driver.welcome.tour_bonus", 500, 0, 20000, ct),
         await ReadNumberAsync("driver.welcome.rent_bonus", 500, 0, 20000, ct),
         await ReadNumberAsync("hotel.welcome.bonus", 500, 0, 20000, ct));

    public async Task SetKindWelcomeBonusesAsync(
        Guid admin, double? tour, double? rent, double? hotel, CancellationToken ct)
    {
        if (tour is { } t)
        {
            await WriteNumberAsync(admin, "driver.welcome.tour_bonus",
                "Welcome credit (PKR) when a vehicle is first approved for tours.", Math.Clamp(t, 0, 20000), ct);
        }

        if (rent is { } r)
        {
            await WriteNumberAsync(admin, "driver.welcome.rent_bonus",
                "Welcome credit (PKR) when a vehicle is first approved for rent-a-car.", Math.Clamp(r, 0, 20000), ct);
        }

        if (hotel is { } h)
        {
            await WriteNumberAsync(admin, "hotel.welcome.bonus",
                "Welcome credit (PKR) in the hotel owner's wallet when a hotel is first approved.", Math.Clamp(h, 0, 20000), ct);
        }
    }

    /// <summary>What a newly approved Driver is credited, in rupees.</summary>
    /// <remarks>
    /// A settable number rather than a constant, because its purpose expires.
    /// Early on it buys a fleet: a driver who has to top up before their first
    /// fare has been asked to pay to find out whether the platform works. Once
    /// there are drivers, that reason is gone and the figure comes down.
    ///
    /// Clamped 0–20,000. Zero turns it off, which is where it ends up.
    /// </remarks>
    public Task<double> WelcomeBonusAsync(CancellationToken ct) =>
        ReadNumberAsync("driver.welcome.bonus", 1000, 0, 20000, ct);

    public Task SetWelcomeBonusAsync(Guid admin, double amount, CancellationToken ct) =>
        WriteNumberAsync(admin, "driver.welcome.bonus",
            "Credited once to a driver's wallet when they are approved.",
            Math.Clamp(amount, 0, 20000), ct);

    /// <summary>How long a Driver has to answer a ride request, in seconds.</summary>
    /// <remarks>
    /// The countdown on the request card. Sixty by default: thirty was too
    /// short to read the route, look at the fare and decide on a phone held
    /// in one hand at a stop. Clamped 15–300.
    /// </remarks>
    public async Task<int> DriverDecisionSecondsAsync(CancellationToken ct) =>
        (int)await ReadNumberAsync("dispatch.driver_decision_seconds", 60, 15, 300, ct);

    /// <summary>How long a Driver's offer stays open to the Customer, in seconds.</summary>
    /// <remarks>
    /// For a ride wanted now. Never longer than the request itself; a
    /// booking for later keeps its own rule. Clamped 30–900.
    /// </remarks>
    public async Task<int> OfferValidSecondsAsync(CancellationToken ct) =>
        (int)await ReadNumberAsync("dispatch.offer_valid_seconds", 180, 30, 900, ct);

    /// <summary>Below this commission balance a Driver is told to top up, in rupees.</summary>
    public Task<double> LowBalanceAlertAsync(CancellationToken ct) =>
        ReadNumberAsync("driver.wallet.low_balance_alert", 50, 0, 100000, ct);

    /// <summary>The EasyPaisa account Drivers top up to.</summary>
    /// <remarks>
    /// Held here rather than printed in the app, because the number changes —
    /// accounts get closed, ownership moves — and a number baked into a release
    /// means money sent to somewhere nobody is watching until the next deploy.
    /// </remarks>
    public async Task<(string Number, string Name)> TopupAccountAsync(
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT key, value_json #>> '{}'
            FROM udrive.system_settings
            WHERE key IN ('payments.easypaisa.number', 'payments.easypaisa.name');
            """;

        var number = string.Empty;
        var name = string.Empty;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            var value = reader.IsDBNull(1) ? string.Empty : reader.GetString(1);
            if (reader.GetString(0).EndsWith("number")) number = value;
            else name = value;
        }

        return (number, name);
    }

    public async Task SetTopupAccountAsync(
        Guid admin,
        string number,
        string name,
        CancellationToken cancellationToken)
    {
        await WriteTextAsync(admin, "payments.easypaisa.number",
            "The EasyPaisa account drivers top up to.", number, cancellationToken);
        await WriteTextAsync(admin, "payments.easypaisa.name",
            "The name on the EasyPaisa account.", name, cancellationToken);
    }

    /// <param name="isPublic">
    /// Whether unauthenticated clients may read it. The EasyPaisa account is
    /// not public; a vehicle photograph is, because the customer app shows it
    /// before anyone signs in.
    /// </param>
    private async Task WriteTextAsync(
        Guid adminUserId,
        string key,
        string description,
        string value,
        CancellationToken cancellationToken,
        bool isPublic = false)
    {
        const string sql = """
            INSERT INTO udrive.system_settings
                (key, value_json, description, is_public,
                 updated_by_user_id, created_at, updated_at)
            VALUES (@key, to_jsonb(@value::text), @description, @isPublic,
                    @admin, now(), now())
            ON CONFLICT (key) DO UPDATE
            SET value_json = EXCLUDED.value_json,
                is_public = EXCLUDED.is_public,
                updated_by_user_id = EXCLUDED.updated_by_user_id,
                updated_at = now();
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("key", key);
        command.Parameters.AddWithValue("value", value.Trim());
        command.Parameters.AddWithValue("description", description);
        command.Parameters.AddWithValue("admin", adminUserId);
        command.Parameters.AddWithValue("isPublic", isPublic);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>What the offer card shows a customer.</summary>
    /// <remarks>
    /// Ratings and ride counts are off to begin with, and that is the point of
    /// making them settable. A new platform has no ratings — so "★ 0.00" and
    /// "0 rides" appear beside every driver, and they read as *a bad driver*
    /// rather than a new one. Worse than showing nothing at all.
    ///
    /// They go on when the numbers start meaning something, without a release.
    /// </remarks>
    public async Task<Dictionary<string, bool>> OfferCardFieldsAsync(
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT key, value_json #>> '{}'
            FROM udrive.system_settings
            WHERE key LIKE 'offer.card.%';
            """;

        // Defaults live here rather than in the database, so a fresh install
        // behaves correctly before anybody opens the portal.
        var fields = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase)
        {
            ["vehiclePhoto"] = true,
            ["driverPhoto"] = true,
            ["rating"] = false,
            ["rides"] = false,
            ["plate"] = true,
        };

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            var name = reader.GetString(0)["offer.card.".Length..];
            if (fields.ContainsKey(name))
            {
                fields[name] = reader.IsDBNull(1)
                    || reader.GetString(1).Equals("true", StringComparison.OrdinalIgnoreCase);
            }
        }

        return fields;
    }

    public async Task SetOfferCardFieldsAsync(
        Guid admin,
        IReadOnlyDictionary<string, bool> fields,
        CancellationToken cancellationToken)
    {
        foreach (var (name, value) in fields)
        {
            await WriteTextAsync(
                admin,
                $"offer.card.{name}",
                "Whether this appears on the driver offer card.",
                value ? "true" : "false",
                cancellationToken,
                isPublic: true);
        }
    }

    /// <summary>Points a vehicle category at an uploaded photograph.</summary>
    /// <remarks>
    /// Public, because the customer app reads these before anyone signs in —
    /// the picture is the thing on screen while somebody chooses a vehicle.
    /// </remarks>
    public Task SetVehicleImageAsync(
            Guid admin, string category, string url, CancellationToken ct) =>
        WriteTextAsync(admin, $"vehicle.image.{category}",
            "Photograph shown for this vehicle category.", url, ct,
            isPublic: true);

    /// <summary>How far from a pickup a Driver may be and still be offered it.</summary>
    /// <remarks>
    /// Five kilometres in a dense town is a lot of drivers and a lot of wasted
    /// notifications; in a valley where the next car is twenty minutes away it
    /// is not nearly enough. Nobody can pick one number for both.
    /// </remarks>
    public Task<double> RequestRadiusKmAsync(CancellationToken ct) =>
        ReadNumberAsync("marketplace.request.radius.km", 5, 0.5, 50, ct);

    /// <summary>How far around themselves a Customer sees vehicles.</summary>
    /// <remarks>
    /// Separate from the request radius on purpose. This one is about honesty —
    /// showing cars that are realistically going to come — and the other is
    /// about reach. Setting them together would mean widening the map every
    /// time you widened the search.
    /// </remarks>
    public Task<double> NearbyRadiusKmAsync(CancellationToken ct) =>
        ReadNumberAsync("marketplace.nearby.radius.km", 1, 0.2, 25, ct);

    public Task SetRequestRadiusAsync(Guid admin, double km, CancellationToken ct) =>
        WriteNumberAsync(admin, "marketplace.request.radius.km",
            "How far from a pickup a driver may be and still be offered it, in km.",
            Math.Clamp(km, 0.5, 50), ct);

    public Task SetNearbyRadiusAsync(Guid admin, double km, CancellationToken ct) =>
        WriteNumberAsync(admin, "marketplace.nearby.radius.km",
            "How far around themselves a customer sees vehicles, in km.",
            Math.Clamp(km, 0.2, 25), ct);

    /// <summary>How often a Driver publishes their position, in seconds.</summary>
    /// <remarks>
    /// An operational dial rather than a constant. Two seconds makes the map
    /// smooth and costs battery and data; ten is cheap and makes the car jump a
    /// block at a time. Which is right depends on things that change without a
    /// release — how many drivers are online, what a megabyte costs them, how
    /// much of the fleet is on an old handset — so it belongs where it can be
    /// turned without one.
    ///
    /// Clamped to 1–60. Below one second the fixes arrive faster than the GPS
    /// produces them and the extra calls are pure cost; above a minute the map
    /// is no longer live in any useful sense, and a value that makes the
    /// product stop working should not be reachable by a typo.
    /// </remarks>
    public async Task<int> TrackingIntervalSecondsAsync(
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT value_json #>> '{}' FROM udrive.system_settings
            WHERE key = 'tracking.ping.seconds';
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        var value = await command.ExecuteScalarAsync(cancellationToken) as string;

        return int.TryParse(value, out var seconds)
            ? Math.Clamp(seconds, 1, 60)
            : 2;
    }

    /// <summary>Sets how often Drivers publish their position.</summary>
    public async Task<ServiceResult<bool>> SetTrackingIntervalAsync(
        Guid adminUserId,
        int seconds,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.system_settings
                (key, value_json, description, is_public,
                 updated_by_user_id, created_at, updated_at)
            VALUES ('tracking.ping.seconds', to_jsonb(@value::text),
                    'How often a driver publishes their position, in seconds.',
                    true, @admin, now(), now())
            ON CONFLICT (key) DO UPDATE
            SET value_json = EXCLUDED.value_json,
                is_public = true,
                updated_by_user_id = EXCLUDED.updated_by_user_id,
                updated_at = now();
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue(
            "value", Math.Clamp(seconds, 1, 60).ToString());
        command.Parameters.AddWithValue("admin", adminUserId);
        await command.ExecuteNonQueryAsync(cancellationToken);

        return ServiceResult<bool>.Ok(true);
    }

    /// <summary>Updates one service.</summary>
    /// <remarks>
    /// The key set is fixed because each key maps to a screen in the app — a
    /// key an Admin invented would render a tile that opens nothing. But a
    /// known key whose row has gone missing is written rather than refused.
    /// <para>
    /// This used to be UPDATE only. If the seed had not run, or a row had been
    /// deleted, the Admin was told "'hotels' is not a service this platform
    /// knows about" — about a service sitting on their own home screen — and
    /// had no way to close it. Meanwhile the app, finding no row, treats an
    /// unknown key as open, so the service stayed open and no SOON badge could
    /// appear. The switch was dead in exactly the case where someone was
    /// reaching for it.
    /// </para>
    /// </remarks>
    public async Task<ServiceResult<bool>> UpdateAsync(
        Guid adminUserId,
        string serviceKey,
        UpdateServiceAvailabilityRequest request,
        CancellationToken cancellationToken)
    {
        // A key the platform does not have a screen for is still refused —
        // before touching the database, so the error is about the key and not
        // about a failed write.
        if (!KnownServiceKeys.Contains(serviceKey))
        {
            return ServiceResult<bool>.Fail(
                StatusCodes.Status404NotFound,
                "service_not_found",
                $"'{serviceKey}' is not a service this platform knows about.");
        }

        const string sql = """
            INSERT INTO udrive.service_availability
                (service_key, is_open, badge_label, closed_message,
                 updated_by_user_id, updated_at)
            VALUES (@key, @isOpen, @badge, @message, @admin, now())
            ON CONFLICT (service_key) DO UPDATE
            SET is_open = EXCLUDED.is_open,
                badge_label = EXCLUDED.badge_label,
                closed_message = EXCLUDED.closed_message,
                updated_by_user_id = EXCLUDED.updated_by_user_id,
                updated_at = now()
            RETURNING service_key;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("key", serviceKey);
        command.Parameters.AddWithValue("isOpen", request.IsOpen);
        command.Parameters.AddWithValue(
            "badge",
            string.IsNullOrWhiteSpace(request.BadgeLabel)
                ? "SOON"
                : request.BadgeLabel.Trim());
        command.Parameters.AddWithValue(
            "message",
            string.IsNullOrWhiteSpace(request.ClosedMessage)
                ? "This service is not open yet."
                : request.ClosedMessage.Trim());
        command.Parameters.AddWithValue("admin", adminUserId);

        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is null or DBNull
            ? ServiceResult<bool>.Fail(
                StatusCodes.Status500InternalServerError,
                "service_not_saved",
                "The service switch could not be saved. Try again.")
            : ServiceResult<bool>.Ok(true);
    }

    /// <summary>Every service key that has a screen behind it in the app.</summary>
    /// <remarks>
    /// The same seven the customer home screen asks for by name, and the same
    /// seven migration 045 seeds. Kept here so the API can tell an Admin which
    /// keys are real without a round trip, and so a row that has gone missing
    /// can be written back rather than refused.
    /// </remarks>
    internal static readonly IReadOnlySet<string> KnownServiceKeys =
        new HashSet<string>(StringComparer.Ordinal)
        {
            "cityRides",
            "tour",
            "cityToCity",
            "hotels",
            "coster",
            "explore",
            "carRental",
        };
}
