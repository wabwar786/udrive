using System.Globalization;
using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Near me: local businesses that list themselves, approved by an admin.
/// </summary>
/// <remarks>
/// The customer sees only approved, active listings, nearest first. Opening
/// state is worked out here in Pakistan time, so every phone agrees whatever
/// its own clock or time zone says. A listing with no hours has
/// <c>openNow = null</c>: the app then says nothing rather than guessing.
/// </remarks>
public sealed class BusinessService(string connectionString)
{
    public static readonly string[] Categories =
        ["Restaurant", "Grocery", "MedicalStore", "Hospital", "Bank", "Fuel", "Mosque"];

    /// <summary>How many listings one account may hold.</summary>
    private const int MaxPerOwner = 10;

    private const double EarthRadiusKm = 6371.0;

    // The columns every read returns, in the order Read() expects. @lat/@lng
    // are bound by the nearby search; other reads select NULL for distance.
    private const string Columns = """
        b.id, b.name, b.category, b.address, b.phone, b.description,
        b.latitude, b.longitude, b.photo_url, b.open_24_hours,
        to_char(b.opens_at, 'HH24:MI'), to_char(b.closes_at, 'HH24:MI'),
        CASE
            WHEN b.open_24_hours THEN true
            WHEN b.opens_at IS NULL OR b.closes_at IS NULL THEN NULL
            WHEN b.opens_at = b.closes_at THEN true
            WHEN b.opens_at < b.closes_at THEN
                 (now() AT TIME ZONE 'Asia/Karachi')::time >= b.opens_at
             AND (now() AT TIME ZONE 'Asia/Karachi')::time <  b.closes_at
            ELSE (now() AT TIME ZONE 'Asia/Karachi')::time >= b.opens_at
              OR (now() AT TIME ZONE 'Asia/Karachi')::time <  b.closes_at
        END,
        b.approval_status, b.rejection_reason, b.is_active,
        COALESCE(u.email LIKE 'demo.%@udrive.local', false)
        """;

    // ────────────────────────────────────────────────────────── customer

    public async Task<ServiceResult<IReadOnlyList<BusinessDto>>> NearbyAsync(
        double latitude,
        double longitude,
        double radiusKm,
        string? category,
        string? query,
        CancellationToken ct)
    {
        if (latitude is < -90 or > 90 || longitude is < -180 or > 180)
        {
            return ServiceResult<IReadOnlyList<BusinessDto>>.Fail(
                400, "location_invalid", "The location is not valid.");
        }

        var radius = Math.Clamp(radiusKm, 0.5, 25);
        string? canonical = null;
        if (!string.IsNullOrWhiteSpace(category))
        {
            canonical = Canonical(category);
            if (canonical is null)
            {
                return ServiceResult<IReadOnlyList<BusinessDto>>.Fail(
                    400, "category_invalid", "Unknown business category.");
            }
        }

        // A box first, so the haversine only runs on rows that can be inside
        // the circle.
        var latDelta = radius / 111.0;
        var lngDelta = radius / (111.0 * Math.Max(Math.Cos(latitude * Math.PI / 180), 0.2));

        var sql = $"""
            SELECT * FROM (
                SELECT {Columns},
                       {EarthRadiusKm.ToString(CultureInfo.InvariantCulture)} * 2 * asin(sqrt(
                           power(sin(radians(b.latitude - @lat) / 2), 2)
                         + cos(radians(@lat)) * cos(radians(b.latitude))
                         * power(sin(radians(b.longitude - @lng) / 2), 2))) AS distance_km
                FROM udrive.businesses b
                JOIN udrive.users u ON u.id = b.owner_user_id
                WHERE b.approval_status = 'Approved' AND b.is_active
                  AND b.latitude  BETWEEN @lat - @dlat AND @lat + @dlat
                  AND b.longitude BETWEEN @lng - @dlng AND @lng + @dlng
                  AND (@category = '' OR b.category = @category)
                  AND (@q = '' OR b.name ILIKE '%' || @q || '%'
                               OR b.address ILIKE '%' || @q || '%'
                               OR b.description ILIKE '%' || @q || '%')
            ) x
            WHERE x.distance_km <= @radius
            ORDER BY x.distance_km
            LIMIT 100;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.Parameters.AddWithValue("lat", latitude);
        command.Parameters.AddWithValue("lng", longitude);
        command.Parameters.AddWithValue("dlat", latDelta);
        command.Parameters.AddWithValue("dlng", lngDelta);
        command.Parameters.AddWithValue("radius", radius);
        command.Parameters.AddWithValue("category", canonical ?? string.Empty);
        command.Parameters.AddWithValue("q", Clip(query?.Trim(), 60) ?? string.Empty);

        var list = new List<BusinessDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            list.Add(Read(reader, reader.GetDouble(17)));
        }
        return ServiceResult<IReadOnlyList<BusinessDto>>.Ok(list);
    }

    public async Task<ServiceResult<BusinessDto>> GetAsync(Guid id, CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT {Columns}
            FROM udrive.businesses b
            JOIN udrive.users u ON u.id = b.owner_user_id
            WHERE b.id = @id AND b.approval_status = 'Approved' AND b.is_active;
            """;
        command.Parameters.AddWithValue("id", id);
        await using var reader = await command.ExecuteReaderAsync(ct);
        return await reader.ReadAsync(ct)
            ? ServiceResult<BusinessDto>.Ok(Read(reader, null))
            : ServiceResult<BusinessDto>.Fail(404, "business_not_found", "Business not found.");
    }

    // ───────────────────────────────────────────────────────────── owner

    public async Task<ServiceResult<IReadOnlyList<BusinessDto>>> MineAsync(Guid ownerId, CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT {Columns}
            FROM udrive.businesses b
            JOIN udrive.users u ON u.id = b.owner_user_id
            WHERE b.owner_user_id = @owner
            ORDER BY b.created_at DESC;
            """;
        command.Parameters.AddWithValue("owner", ownerId);
        var list = new List<BusinessDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct)) list.Add(Read(reader, null));
        return ServiceResult<IReadOnlyList<BusinessDto>>.Ok(list);
    }

    public async Task<ServiceResult<object>> CreateAsync(Guid ownerId, SaveBusinessRequest request, CancellationToken ct)
    {
        var problem = Validate(request, out var clean);
        if (problem is not null) return ServiceResult<object>.Fail(400, problem.Value.Code, problem.Value.Message);

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);

        await using (var count = connection.CreateCommand())
        {
            count.CommandText = "SELECT count(*) FROM udrive.businesses WHERE owner_user_id = @owner;";
            count.Parameters.AddWithValue("owner", ownerId);
            if (Convert.ToInt32(await count.ExecuteScalarAsync(ct)) >= MaxPerOwner)
            {
                return ServiceResult<object>.Fail(409, "business_limit",
                    $"One account can list up to {MaxPerOwner} businesses.");
            }
        }

        await using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO udrive.businesses
                (owner_user_id, name, category, address, phone, description,
                 latitude, longitude, open_24_hours, opens_at, closes_at,
                 approval_status, is_active, created_at, updated_at)
            VALUES
                (@owner, @name, @category, @address, @phone, @description,
                 @lat, @lng, @open24, @opens, @closes,
                 'Pending', true, now(), now())
            RETURNING id;
            """;
        command.Parameters.AddWithValue("owner", ownerId);
        Bind(command, clean);
        var id = (Guid)(await command.ExecuteScalarAsync(ct))!;
        return ServiceResult<object>.Created(new { id, status = "Pending" },
            "Submitted for review. Your listing goes live once UDrive approves it.");
    }

    /// <summary>An owner's edit. It goes back to review before customers see it.</summary>
    public async Task<ServiceResult<object>> UpdateAsync(Guid ownerId, Guid id, SaveBusinessRequest request, CancellationToken ct)
    {
        var problem = Validate(request, out var clean);
        if (problem is not null) return ServiceResult<object>.Fail(400, problem.Value.Code, problem.Value.Message);

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            UPDATE udrive.businesses
            SET name = @name, category = @category, address = @address,
                phone = @phone, description = @description,
                latitude = @lat, longitude = @lng,
                open_24_hours = @open24, opens_at = @opens, closes_at = @closes,
                approval_status = 'Pending', rejection_reason = NULL,
                reviewed_by = NULL, reviewed_at = NULL, updated_at = now()
            WHERE id = @id AND owner_user_id = @owner
            RETURNING id;
            """;
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("owner", ownerId);
        Bind(command, clean);
        return await command.ExecuteScalarAsync(ct) is Guid
            ? ServiceResult<object>.Ok(new { id, status = "Pending" },
                "Saved. The changes go live once UDrive approves them.")
            : ServiceResult<object>.Fail(404, "business_not_found", "Business not found.");
    }

    // ───────────────────────────────────────────────────────────── admin

    public async Task<ServiceResult<IReadOnlyList<AdminBusinessDto>>> AdminListAsync(string? status, CancellationToken ct)
    {
        var filter = string.IsNullOrWhiteSpace(status) || status.Equals("All", StringComparison.OrdinalIgnoreCase)
            ? string.Empty
            : status.Trim();

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT b.id, b.name, b.category, b.address, b.phone, b.description,
                   b.latitude, b.longitude, b.open_24_hours,
                   to_char(b.opens_at, 'HH24:MI'), to_char(b.closes_at, 'HH24:MI'),
                   b.approval_status, b.rejection_reason, b.is_active,
                   COALESCE(NULLIF(u.full_name, ''), 'Owner'), COALESCE(u.phone_number, ''),
                   b.created_at, COALESCE(u.email LIKE 'demo.%@udrive.local', false)
            FROM udrive.businesses b
            JOIN udrive.users u ON u.id = b.owner_user_id
            WHERE (@status = '' OR b.approval_status = @status)
            ORDER BY (b.approval_status = 'Pending') DESC, b.created_at DESC
            LIMIT 500;
            """;
        command.Parameters.AddWithValue("status", filter);
        var list = new List<AdminBusinessDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            list.Add(new AdminBusinessDto(
                reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
                reader.GetString(4), reader.GetString(5), reader.GetDouble(6), reader.GetDouble(7),
                reader.GetBoolean(8),
                reader.IsDBNull(9) ? null : reader.GetString(9),
                reader.IsDBNull(10) ? null : reader.GetString(10),
                reader.GetString(11),
                reader.IsDBNull(12) ? null : reader.GetString(12),
                reader.GetBoolean(13), reader.GetString(14), reader.GetString(15),
                reader.GetDateTime(16), reader.GetBoolean(17)));
        }
        return ServiceResult<IReadOnlyList<AdminBusinessDto>>.Ok(list);
    }

    public async Task<ServiceResult<object>> ReviewAsync(Guid adminId, Guid id, ReviewBusinessRequest request, CancellationToken ct)
    {
        if (!request.Approve && string.IsNullOrWhiteSpace(request.Reason))
        {
            return ServiceResult<object>.Fail(400, "rejection_reason_required",
                "Add a reason before rejecting this business.");
        }

        var status = request.Approve ? "Approved" : "Rejected";
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var transaction = await connection.BeginTransactionAsync(ct);
        try
        {
            await using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = """
                UPDATE udrive.businesses
                SET approval_status = @status,
                    rejection_reason = NULLIF(@reason, ''),
                    reviewed_by = @admin, reviewed_at = now(), updated_at = now()
                WHERE id = @id
                RETURNING id;
                """;
            command.Parameters.AddWithValue("status", status);
            command.Parameters.AddWithValue("reason", request.Approve ? string.Empty : Clip(request.Reason!.Trim(), 500)!);
            command.Parameters.AddWithValue("admin", adminId);
            command.Parameters.AddWithValue("id", id);
            if (await command.ExecuteScalarAsync(ct) is not Guid)
            {
                await transaction.RollbackAsync(ct);
                return ServiceResult<object>.Fail(404, "business_not_found", "Business not found.");
            }

            await Audit(connection, transaction, adminId,
                request.Approve ? "BusinessApproved" : "BusinessRejected", id,
                new { status, reason = request.Approve ? null : request.Reason?.Trim() }, ct);
            await transaction.CommitAsync(ct);
            return ServiceResult<object>.Ok(new { id, status });
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            throw;
        }
    }

    public async Task<ServiceResult<object>> SetActiveAsync(Guid adminId, Guid id, bool isActive, CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var transaction = await connection.BeginTransactionAsync(ct);
        try
        {
            await using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = """
                UPDATE udrive.businesses SET is_active = @active, updated_at = now()
                WHERE id = @id RETURNING id;
                """;
            command.Parameters.AddWithValue("active", isActive);
            command.Parameters.AddWithValue("id", id);
            if (await command.ExecuteScalarAsync(ct) is not Guid)
            {
                await transaction.RollbackAsync(ct);
                return ServiceResult<object>.Fail(404, "business_not_found", "Business not found.");
            }

            await Audit(connection, transaction, adminId, "BusinessVisibilityChanged", id, new { isActive }, ct);
            await transaction.CommitAsync(ct);
            return ServiceResult<object>.Ok(new { id, isActive });
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            throw;
        }
    }

    // ─────────────────────────────────────────────────────────── helpers

    private sealed record Clean(
        string Name, string Category, string Address, string Phone, string Description,
        double Latitude, double Longitude, bool Open24Hours, TimeOnly? OpensAt, TimeOnly? ClosesAt);

    private static (string Code, string Message)? Validate(SaveBusinessRequest request, out Clean clean)
    {
        clean = null!;
        var name = request.Name?.Trim() ?? string.Empty;
        var address = request.Address?.Trim() ?? string.Empty;
        var phone = request.Phone?.Trim() ?? string.Empty;
        var description = request.Description?.Trim() ?? string.Empty;
        var category = Canonical(request.Category);

        if (name.Length is < 2 or > 120) return ("name_invalid", "Enter the business name (2–120 characters).");
        if (category is null) return ("category_invalid", "Choose a category.");
        if (address.Length is < 3 or > 300) return ("address_invalid", "Enter the address.");
        var digits = phone.Count(char.IsDigit);
        if (digits is < 7 or > 15 || phone.Any(c => !char.IsDigit(c) && c is not ('+' or ' ' or '-')))
        {
            return ("phone_invalid", "Enter a contact number.");
        }
        if (description.Length > 400) return ("description_too_long", "Keep the description under 400 characters.");

        // Pakistan and Azad Kashmir, roughly. A pin at 0,0 or abroad is a
        // phone that never got a fix, and would list the shop in the sea.
        if (request.Latitude is < 23 or > 37.5 || request.Longitude is < 60 or > 80)
        {
            return ("location_invalid", "Pin the business location again — it is outside Pakistan and Azad Kashmir.");
        }

        TimeOnly? opens = null, closes = null;
        if (!request.Open24Hours)
        {
            var hasOpen = !string.IsNullOrWhiteSpace(request.OpensAt);
            var hasClose = !string.IsNullOrWhiteSpace(request.ClosesAt);
            if (hasOpen != hasClose) return ("hours_invalid", "Give both the opening and the closing time, or neither.");
            if (hasOpen)
            {
                if (!TimeOnly.TryParseExact(request.OpensAt!.Trim(), "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var o)
                    || !TimeOnly.TryParseExact(request.ClosesAt!.Trim(), "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var c))
                {
                    return ("hours_invalid", "Opening hours must look like 09:00.");
                }
                opens = o;
                closes = c;
            }
        }

        clean = new Clean(name, category, address, phone, description,
            request.Latitude, request.Longitude, request.Open24Hours, opens, closes);
        return null;
    }

    private static void Bind(NpgsqlCommand command, Clean clean)
    {
        command.Parameters.AddWithValue("name", clean.Name);
        command.Parameters.AddWithValue("category", clean.Category);
        command.Parameters.AddWithValue("address", clean.Address);
        command.Parameters.AddWithValue("phone", clean.Phone);
        command.Parameters.AddWithValue("description", clean.Description);
        command.Parameters.AddWithValue("lat", clean.Latitude);
        command.Parameters.AddWithValue("lng", clean.Longitude);
        command.Parameters.AddWithValue("open24", clean.Open24Hours);
        command.Parameters.Add(new NpgsqlParameter("opens", NpgsqlTypes.NpgsqlDbType.Time)
            { Value = clean.OpensAt is { } o ? o.ToTimeSpan() : DBNull.Value });
        command.Parameters.Add(new NpgsqlParameter("closes", NpgsqlTypes.NpgsqlDbType.Time)
            { Value = clean.ClosesAt is { } c ? c.ToTimeSpan() : DBNull.Value });
    }

    private static BusinessDto Read(NpgsqlDataReader r, double? distanceKm) => new(
        r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetString(3), r.GetString(4), r.GetString(5),
        r.GetDouble(6), r.GetDouble(7),
        r.IsDBNull(8) || string.IsNullOrWhiteSpace(r.GetString(8)) ? [] : [r.GetString(8)],
        r.GetBoolean(9),
        r.IsDBNull(10) ? null : r.GetString(10),
        r.IsDBNull(11) ? null : r.GetString(11),
        r.IsDBNull(12) ? null : r.GetBoolean(12),
        distanceKm is null ? null : Math.Round(distanceKm.Value, 2),
        r.GetString(13),
        r.IsDBNull(14) ? null : r.GetString(14),
        r.GetBoolean(15),
        r.GetBoolean(16));

    private static string? Canonical(string? category)
    {
        if (string.IsNullOrWhiteSpace(category)) return null;
        var needle = new string(category.Where(char.IsLetter).ToArray());
        return Categories.FirstOrDefault(c => c.Equals(needle, StringComparison.OrdinalIgnoreCase));
    }

    private static string? Clip(string? value, int max) =>
        value is null ? null : value.Length <= max ? value : value[..max];

    private static async Task Audit(
        NpgsqlConnection connection, NpgsqlTransaction transaction, Guid adminId,
        string action, Guid id, object changes, CancellationToken ct)
    {
        await using var audit = connection.CreateCommand();
        audit.Transaction = transaction;
        audit.CommandText = """
            INSERT INTO udrive.audit_logs
                (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
            VALUES
                (gen_random_uuid(), @admin, @action, 'Business', CAST(@id AS text),
                 CAST(@changes AS jsonb), now(), now());
            """;
        audit.Parameters.AddWithValue("admin", adminId);
        audit.Parameters.AddWithValue("action", action);
        audit.Parameters.AddWithValue("id", id);
        audit.Parameters.AddWithValue("changes", System.Text.Json.JsonSerializer.Serialize(changes));
        await audit.ExecuteNonQueryAsync(ct);
    }
}
