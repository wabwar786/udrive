using Npgsql;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

public sealed class MarketplacePricingService(string connectionString)
{
    public async Task<IReadOnlyList<ServiceVehicleRateDto>> GetRatesAsync(
        string serviceType,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT service_type, vehicle_category, per_seat_rate,
                   whole_vehicle_rate, per_km_rate, currency
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
                reader.GetString(5)));
        }

        return list;
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
                   COALESCE(NULLIF(v.booking_mode, ''), 'WholeVehicle')
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE v.status = 'Verified'
              AND dp.verification_status = 'Approved'
              AND u.status = 'Approved'
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
            ORDER BY dp.is_online DESC,
                     COALESCE(u.email LIKE 'demo.%@udrive.local', false) DESC,
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
                reader.GetString(22)));
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

    public async Task<bool> UpdatePresenceAsync(
        Guid userId,
        DriverPresenceUpdateRequest request,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.driver_presence_locations
                (driver_profile_id, location, accuracy_meters,
                 device_timestamp, server_timestamp, updated_at)
            SELECT dp.id,
                   ST_SetSRID(ST_MakePoint(@lng, @lat), 4326)::geography,
                   @accuracy,
                   @device,
                   now(),
                   now()
            FROM udrive.driver_profiles dp
            WHERE dp.user_id = @user
              AND dp.verification_status = 'Approved'
            ON CONFLICT(driver_profile_id) DO UPDATE SET
                location = excluded.location,
                accuracy_meters = excluded.accuracy_meters,
                device_timestamp = excluded.device_timestamp,
                server_timestamp = now(),
                updated_at = now();
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("user", userId);
        command.Parameters.AddWithValue("lng", request.Longitude);
        command.Parameters.AddWithValue("lat", request.Latitude);
        command.Parameters.AddWithValue(
            "accuracy",
            (object?)request.Accuracy ?? DBNull.Value);
        command.Parameters.AddWithValue(
            "device",
            request.DeviceTimestamp.ToUniversalTime());
        return await command.ExecuteNonQueryAsync(cancellationToken) > 0;
    }
}
