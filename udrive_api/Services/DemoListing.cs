using Npgsql;

namespace UDrive.Api.Services;

/// <summary>
/// Demo listings are shown, labelled "Demo", and never booked.
/// </summary>
/// <remarks>
/// A listing is demo when it belongs to a demo account (email
/// <c>demo.%@udrive.local</c>) — the same rule "Remove demo data" uses. The app
/// shows the label; these checks are the server's half, so a demo tour, car or
/// room cannot be booked even by an old app build that has no label.
/// </remarks>
public static class DemoListing
{
    public const string EmailPattern = "demo.%@udrive.local";
    public const string ErrorCode = "demo_listing";
    public const string Message =
        "This is a demo listing that shows how UDrive works. It cannot be booked.";

    /// <summary>SQL for "this owner is a demo account", given a users alias.</summary>
    public static string IsDemoSql(string userAlias) =>
        $"COALESCE({userAlias}.email LIKE '{EmailPattern}', false)";

    public static Task<bool> IsDemoPackageAsync(string connectionString, Guid packageId, CancellationToken ct) =>
        CheckAsync(connectionString, """
            SELECT EXISTS (
                SELECT 1 FROM udrive.tour_packages tp
                JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
                JOIN udrive.users u ON u.id = dp.user_id
                WHERE tp.id = @id AND u.email LIKE @pattern)
            """, packageId, ct);

    public static Task<bool> IsDemoVehicleAsync(string connectionString, Guid vehicleId, CancellationToken ct) =>
        CheckAsync(connectionString, """
            SELECT EXISTS (
                SELECT 1 FROM udrive.vehicles v
                JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                JOIN udrive.users u ON u.id = dp.user_id
                WHERE v.id = @id AND u.email LIKE @pattern)
            """, vehicleId, ct);

    public static Task<bool> IsDemoHotelAsync(string connectionString, Guid hotelId, CancellationToken ct) =>
        CheckAsync(connectionString, """
            SELECT EXISTS (
                SELECT 1 FROM udrive.hotels h
                JOIN udrive.users u ON u.id = h.owner_user_id
                WHERE h.id = @id AND u.email LIKE @pattern)
            """, hotelId, ct);

    private static async Task<bool> CheckAsync(string connectionString, string sql, Guid id, CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("pattern", EmailPattern);
        return (bool)(await command.ExecuteScalarAsync(ct) ?? false);
    }
}
