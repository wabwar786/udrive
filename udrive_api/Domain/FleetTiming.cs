using Npgsql;

namespace UDrive.Api.Domain;

/// <summary>
/// The four numbers that decide when a vehicle is free for its next job.
/// </summary>
/// <remarks>
/// They used to be two hard-coded constants in three different queries —
/// <c>interval '8 hours'</c> in the two overlap checks and <c>1000</c> metres in
/// the ride-request feed — and nothing anywhere said what they meant. The eight
/// hours in particular was not a turnaround, it was a working day: a Driver who
/// finished a twenty-minute city ride at nine in the morning was treated as busy
/// until five in the evening, and every booking offered in between came back
/// "Driver or vehicle has an overlapping active booking".
///
/// They are settings now because the right figure depends on the road. An Admin
/// who knows the Neelum valley can raise the turnaround; one dispatching inside
/// Muzaffarabad can drop it.
/// </remarks>
/// <param name="TurnaroundMinutes">
/// Between one booking ending and the next starting. Drop the passengers, fuel,
/// clean, drive to the next pickup.
/// </param>
/// <param name="LeadWindowMinutes">
/// How long before a trip ends the Driver may take the next one. This buys the
/// Driver their next job rather than letting the next customer go elsewhere
/// while the Driver is still on the road. It permits no overlap: the next
/// booking must still start after this one ends plus the turnaround.
/// </param>
/// <param name="AssumedTripMinutes">
/// Used only when a booking has no return time at all. A real return time
/// always wins.
/// </param>
/// <param name="NearDestinationMetres">
/// Close enough to the drop-off to count as about to be free.
/// </param>
public sealed record FleetTiming(
    int TurnaroundMinutes,
    int LeadWindowMinutes,
    int AssumedTripMinutes,
    int NearDestinationMetres)
{
    /// <summary>What the platform uses when the settings table says nothing.</summary>
    public static readonly FleetTiming Default = new(60, 180, 240, 1500);

    /// <summary>Reads all four from <c>system_settings</c> in one round trip.</summary>
    public static async Task<FleetTiming> LoadAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                COALESCE((SELECT GREATEST(0, (value_json #>> '{}')::int)
                          FROM udrive.system_settings
                          WHERE key = 'fleet.turnaround_minutes'), @turnaround),
                COALESCE((SELECT GREATEST(0, (value_json #>> '{}')::int)
                          FROM udrive.system_settings
                          WHERE key = 'fleet.lead_window_minutes'), @lead),
                COALESCE((SELECT GREATEST(0, (value_json #>> '{}')::int)
                          FROM udrive.system_settings
                          WHERE key = 'fleet.assumed_trip_minutes'), @assumed),
                COALESCE((SELECT GREATEST(0, (value_json #>> '{}')::int)
                          FROM udrive.system_settings
                          WHERE key = 'fleet.near_destination_metres'), @near);
            """;

        await using var command = transaction is null
            ? new NpgsqlCommand(sql, connection)
            : new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("turnaround", Default.TurnaroundMinutes);
        command.Parameters.AddWithValue("lead", Default.LeadWindowMinutes);
        command.Parameters.AddWithValue("assumed", Default.AssumedTripMinutes);
        command.Parameters.AddWithValue("near", Default.NearDestinationMetres);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? new FleetTiming(
                reader.GetInt32(0),
                reader.GetInt32(1),
                reader.GetInt32(2),
                reader.GetInt32(3))
            : Default;
    }

    /// <summary>The two an overlap check needs.</summary>
    public void AddOverlapTo(NpgsqlCommand command)
    {
        command.Parameters.AddWithValue("turnaroundMinutes", TurnaroundMinutes);
        command.Parameters.AddWithValue("assumedTripMinutes", AssumedTripMinutes);
    }

    /// <summary>The four the ride-request feed needs.</summary>
    public void AddFeedTo(NpgsqlCommand command)
    {
        AddOverlapTo(command);
        command.Parameters.AddWithValue("leadWindowMinutes", LeadWindowMinutes);
        command.Parameters.AddWithValue("nearDestinationMetres", (double)NearDestinationMetres);
    }
}
