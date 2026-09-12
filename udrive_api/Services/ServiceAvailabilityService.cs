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

        return ServiceResult<IReadOnlyList<ServiceAvailabilityDto>>.Ok(list);
    }

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
    /// Updates only, never inserts. The key set is fixed because each key maps
    /// to a screen in the app — a key an Admin invented would render a tile
    /// that opens nothing.
    /// </remarks>
    public async Task<ServiceResult<bool>> UpdateAsync(
        Guid adminUserId,
        string serviceKey,
        UpdateServiceAvailabilityRequest request,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.service_availability
            SET is_open = @isOpen,
                badge_label = @badge,
                closed_message = @message,
                updated_by_user_id = @admin,
                updated_at = now()
            WHERE service_key = @key
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
                StatusCodes.Status404NotFound,
                "service_not_found",
                $"'{serviceKey}' is not a service this platform knows about.")
            : ServiceResult<bool>.Ok(true);
    }
}
