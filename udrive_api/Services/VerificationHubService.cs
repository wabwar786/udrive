using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// The one Verification page: city rides, tour vehicles, rent-a-car, hotels and
/// businesses, each with its own queue and its own approval, filtered by
/// district or tehsil.
/// </summary>
/// <remarks>
/// City rides are reviewed here too, in the same layout as tours: one row per
/// vehicle a driver registered for rides, approved together with its driver
/// through AdminVerificationService. Every queue is decided through the
/// service that owns the thing, so approving from this page has exactly the
/// effects it always had.
/// </remarks>
public sealed class VerificationHubService(
    string connectionString,
    ListingService listings,
    HotelService hotels,
    BusinessService businesses,
    AdminVerificationService? admin = null)
{
    public static readonly string[] Tabs = ["city", "tour", "rent", "hotels", "businesses"];

    // ─────────────────────────────────────────────────────── summary

    public async Task<ServiceResult<VerificationSummaryDto>> SummaryAsync(
        string? area, CancellationToken ct, IReadOnlyList<Guid>? allowed = null)
    {
        await using var connection = await OpenAsync(ct);
        await RentalService.ExpireOverdueAsync(connection, ct);
        var areaId = ParseArea(area, out var unassigned);

        await using var command = new NpgsqlCommand(
            $"""
            SELECT
              (SELECT count(*)::int FROM udrive.vehicles v
                JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                LEFT JOIN udrive.territories t ON t.id = COALESCE(v.territory_id, dp.territory_id)
                WHERE COALESCE(v.listed_via, 'Driver') = 'Driver' AND v.status <> 'Deleted'
                  AND COALESCE(dp.profile_kind, 'Driver') = 'Driver'
                  AND ({CityStatusSql}) = 'Waiting'
                  AND {AreaSql("t", "COALESCE(v.territory_id, dp.territory_id)")}),
              (SELECT count(*)::int FROM udrive.vehicles v
                JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                LEFT JOIN udrive.territories t ON t.id = COALESCE(v.territory_id, dp.territory_id)
                WHERE v.listed_via IN ('Listing', 'Staff') AND v.status <> 'Deleted'
                  AND ({WaitingSql("tour")})
                  AND {AreaSql("t", "COALESCE(v.territory_id, dp.territory_id)")}),
              (SELECT count(*)::int FROM udrive.vehicles v
                JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                LEFT JOIN udrive.territories t ON t.id = COALESCE(v.territory_id, dp.territory_id)
                WHERE v.listed_via IN ('Listing', 'Staff') AND v.status <> 'Deleted'
                  AND ({WaitingSql("rent")})
                  AND {AreaSql("t", "COALESCE(v.territory_id, dp.territory_id)")}),
              (SELECT count(*)::int FROM udrive.hotels h
                LEFT JOIN udrive.territories t ON t.id = h.territory_id
                WHERE h.approval_status = 'Pending' AND {AreaSql("t", "h.territory_id")}),
              (SELECT count(*)::int FROM udrive.businesses b
                LEFT JOIN udrive.territories t ON t.id = b.territory_id
                WHERE b.approval_status = 'Pending' AND {AreaSql("t", "b.territory_id")});
            """, connection);
        BindArea(command, areaId, unassigned, allowed);
        await using var reader = await command.ExecuteReaderAsync(ct);
        await reader.ReadAsync(ct);
        return ServiceResult<VerificationSummaryDto>.Ok(new VerificationSummaryDto(
            reader.GetInt32(0), reader.GetInt32(1), reader.GetInt32(2), reader.GetInt32(3), reader.GetInt32(4)));
    }

    // ─────────────────────────────────────────────────────── queues

    /// <param name="tab">city, tour, rent, hotels or businesses.</param>
    /// <param name="status">Waiting (default), Approved, Rejected, Info or All.</param>
    /// <param name="area">A district or tehsil id, "none" for unassigned, or empty for all.</param>
    public async Task<ServiceResult<IReadOnlyList<VerificationRowDto>>> QueueAsync(
        string tab, string? status, string? area, string? search, CancellationToken ct, IReadOnlyList<Guid>? allowed = null)
    {
        await using var connection = await OpenAsync(ct);
        var areaId = ParseArea(area, out var unassigned);
        var want = NormaliseStatus(status);
        var rows = tab switch
        {
            "city" => await CityRowsAsync(connection, want, areaId, unassigned, search, null, ct, allowed),
            "tour" or "rent" => await VehicleRowsAsync(connection, tab, want, areaId, unassigned, search, null, ct, allowed),
            "hotels" => await HotelRowsAsync(connection, want, areaId, unassigned, search, null, ct, allowed),
            "businesses" => await BusinessRowsAsync(connection, want, areaId, unassigned, search, null, ct, allowed),
            _ => null,
        };
        return rows is null
            ? Fail<IReadOnlyList<VerificationRowDto>>(400, "tab_invalid", "Unknown verification tab.")
            : ServiceResult<IReadOnlyList<VerificationRowDto>>.Ok(rows);
    }

    public async Task<ServiceResult<VerificationDetailDto>> DetailAsync(string tab, Guid id, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        switch (tab)
        {
            case "city":
            {
                var city = await CityDetailAsync(connection, id, ct);
                return city is null
                    ? Fail<VerificationDetailDto>(404, "not_found", "That vehicle was not found.")
                    : ServiceResult<VerificationDetailDto>.Ok(city);
            }
            case "tour":
            case "rent":
            {
                var row = (await VehicleRowsAsync(connection, tab, "All", null, false, null, id, ct)).FirstOrDefault();
                if (row is null) return Fail<VerificationDetailDto>(404, "not_found", "That vehicle was not found.");
                var checks = await ListingService.PurposeChecksAsync(connection, id, tab, ct);
                var docs = await VehicleDocumentsAsync(connection, id, ct);
                var facts = await VehicleFactsAsync(connection, id, tab, ct);
                var drivers = await listings.OwnerDriversForVehicleAsync(connection, id, ct);
                var blocked = checks.FirstOrDefault(c => !c.Ok);
                return ServiceResult<VerificationDetailDto>.Ok(new VerificationDetailDto(
                    row, docs, checks, facts, drivers,
                    blocked is null && row.Status != "Approved",
                    blocked is null ? null : $"Not ready: {blocked.Label}",
                    row.Status != "Approved"));
            }
            case "hotels":
            {
                var row = (await HotelRowsAsync(connection, "All", null, false, null, id, ct)).FirstOrDefault();
                if (row is null) return Fail<VerificationDetailDto>(404, "not_found", "That hotel was not found.");
                var (docs, checks, facts) = await HotelDetailAsync(connection, id, ct);
                var blocked = checks.FirstOrDefault(c => !c.Ok);
                return ServiceResult<VerificationDetailDto>.Ok(new VerificationDetailDto(
                    row, docs, checks, facts, [],
                    blocked is null && row.Status != "Approved",
                    blocked is null ? null : $"Not ready: {blocked.Label}",
                    false));
            }
            case "businesses":
            {
                var row = (await BusinessRowsAsync(connection, "All", null, false, null, id, ct)).FirstOrDefault();
                if (row is null) return Fail<VerificationDetailDto>(404, "not_found", "That business was not found.");
                var (docs, checks, facts) = await BusinessDetailAsync(connection, id, ct);
                var blocked = checks.FirstOrDefault(c => !c.Ok);
                return ServiceResult<VerificationDetailDto>.Ok(new VerificationDetailDto(
                    row, docs, checks, facts, [],
                    blocked is null && row.Status != "Approved",
                    blocked is null ? null : $"Not ready: {blocked.Label}",
                    false));
            }
            default:
                return Fail<VerificationDetailDto>(400, "tab_invalid", "Unknown verification tab.");
        }
    }

    // ─────────────────────────────────────────────────────── decisions

    /// <summary>A WhatsApp message to send after the decision, when there is one.</summary>
    public sealed record Decision(object Data, string? NotifyPhone, string? NotifyMessage);

    public async Task<ServiceResult<Decision>> ApproveAsync(Guid adminId, string tab, Guid id, CancellationToken ct)
    {
        switch (tab)
        {
            case "city":
                return await ApproveCityAsync(adminId, id, ct);
            case "tour":
            case "rent":
            {
                var result = await listings.ApprovePurposeAsync(adminId, id, tab, ct);
                return result.Success
                    ? ServiceResult<Decision>.Ok(new Decision(result.Data!.Listing, result.Data.OwnerPhone, result.Data.Message))
                    : Fail<Decision>(result.StatusCode, result.ErrorCode!, result.Message!);
            }
            case "hotels":
            {
                await using (var connection = await OpenAsync(ct))
                {
                    var (_, checks, _) = await HotelDetailAsync(connection, id, ct);
                    var missing = checks.FirstOrDefault(c => !c.Ok);
                    if (missing is not null)
                    {
                        return Fail<Decision>(409, "approval_blocked", $"Not ready: {missing.Label}.");
                    }
                }

                var result = await hotels.ReviewAsync(adminId, id, new ReviewHotelRequest(true, null), ct);
                return await Wrap(result, "hotels", id, true, null, ct);
            }
            case "businesses":
            {
                var result = await businesses.ReviewAsync(adminId, id, new ReviewBusinessRequest(true, null), ct);
                return await Wrap(result, "businesses", id, true, null, ct);
            }
            default:
                return Fail<Decision>(400, "tab_invalid", "Unknown verification tab.");
        }
    }

    public async Task<ServiceResult<Decision>> RejectAsync(
        Guid adminId, string tab, Guid id, string? reason, bool requestInfo, CancellationToken ct)
    {
        switch (tab)
        {
            case "city":
                return await RejectCityAsync(adminId, id, reason, requestInfo, ct);
            case "tour":
            case "rent":
            {
                var result = await listings.RejectPurposeAsync(adminId, id, tab, reason, requestInfo, ct);
                return result.Success
                    ? ServiceResult<Decision>.Ok(new Decision(result.Data!.Listing, result.Data.OwnerPhone, result.Data.Message))
                    : Fail<Decision>(result.StatusCode, result.ErrorCode!, result.Message!);
            }
            case "hotels" when !requestInfo:
            {
                var result = await hotels.ReviewAsync(adminId, id, new ReviewHotelRequest(false, reason), ct);
                return await Wrap(result, "hotels", id, false, reason, ct);
            }
            case "businesses" when !requestInfo:
            {
                var result = await businesses.ReviewAsync(adminId, id, new ReviewBusinessRequest(false, reason), ct);
                return await Wrap(result, "businesses", id, false, reason, ct);
            }
            case "hotels":
            case "businesses":
                return Fail<Decision>(400, "info_not_supported", "Hotels and businesses can be approved or rejected.");
            default:
                return Fail<Decision>(400, "tab_invalid", "Unknown verification tab.");
        }
    }

    /// <summary>Corrects where something is: a driver, a vehicle, a hotel or a business.</summary>
    /// <param name="kind">city-driver, city-vehicle, tour, rent, hotels or businesses.</param>
    public async Task<ServiceResult<object>> SetLocationAsync(
        Guid adminId, string kind, Guid id, Guid tehsilId, CancellationToken ct)
    {
        var table = kind switch
        {
            "city-driver" => "udrive.driver_profiles",
            "city-vehicle" or "city" or "tour" or "rent" => "udrive.vehicles",
            "hotels" => "udrive.hotels",
            "businesses" => "udrive.businesses",
            _ => null,
        };
        if (table is null) return Fail<object>(400, "kind_invalid", "Unknown kind.");

        await using var connection = await OpenAsync(ct);
        if (!await AreaService.IsTehsilAsync(connection, null, tehsilId, ct))
        {
            return Fail<object>(400, "area_invalid", "Choose a tehsil.");
        }

        // The table name comes from the fixed map above, never the caller.
        await using (var command = new NpgsqlCommand(
            $"UPDATE {table} SET territory_id = @tehsil, updated_at = now() WHERE id = @id RETURNING id;", connection))
        {
            command.Parameters.AddWithValue("id", id);
            command.Parameters.AddWithValue("tehsil", tehsilId);
            if (await command.ExecuteScalarAsync(ct) is not Guid)
            {
                return Fail<object>(404, "not_found", "Not found.");
            }
        }

        await using (var audit = new NpgsqlCommand(
            """
            INSERT INTO udrive.audit_logs (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
            VALUES (gen_random_uuid(), @admin, 'AreaCorrected', @entity, CAST(@id AS text),
                    jsonb_build_object('tehsilId', @tehsil), now(), now());
            """, connection))
        {
            audit.Parameters.AddWithValue("admin", adminId);
            audit.Parameters.AddWithValue("entity", kind);
            audit.Parameters.AddWithValue("id", id);
            audit.Parameters.AddWithValue("tehsil", tehsilId);
            await audit.ExecuteNonQueryAsync(ct);
        }

        return ServiceResult<object>.Ok(new { id, tehsilId });
    }

    private async Task<ServiceResult<Decision>> Wrap(
        ServiceResult<object> result, string tab, Guid id, bool approved, string? reason, CancellationToken ct)
    {
        if (!result.Success) return Fail<Decision>(result.StatusCode, result.ErrorCode!, result.Message!);

        await using var connection = await OpenAsync(ct);
        var row = tab == "hotels"
            ? (await HotelRowsAsync(connection, "All", null, false, null, id, ct)).FirstOrDefault()
            : (await BusinessRowsAsync(connection, "All", null, false, null, id, ct)).FirstOrDefault();
        if (row is null) return ServiceResult<Decision>.Ok(new Decision(result.Data!, null, null));

        var what = tab == "hotels" ? "hotel" : "business";
        var message = approved
            ? $"UDrive: your {what} \"{row.Title}\" is approved and customers can see it now."
            : $"UDrive: your {what} \"{row.Title}\" was not approved — {reason?.Trim()}";
        return ServiceResult<Decision>.Ok(new Decision(row, row.PersonPhone, message));
    }

    // ─────────────────────────────────────────────────────── city rides

    /// <summary>
    /// The city-rides row status, from the driver's and the vehicle's own
    /// statuses. One row per vehicle a driver registered for rides.
    /// </summary>
    private const string CityStatusSql = """
        CASE
            WHEN dp.verification_status = 'Rejected' OR v.status = 'Suspended' THEN 'Rejected'
            WHEN dp.verification_status = 'ChangesRequired' OR v.status = 'ChangesRequired' THEN 'Info'
            WHEN dp.verification_status IN ('Submitted', 'UnderReview') OR v.status = 'PendingReview' THEN 'Waiting'
            WHEN dp.verification_status = 'Approved' AND v.status = 'Verified' THEN 'Approved'
            ELSE 'Other'
        END
        """;

    private static async Task<IReadOnlyList<VerificationRowDto>> CityRowsAsync(
        NpgsqlConnection connection, string want, Guid? area, bool unassigned,
        string? search, Guid? id, CancellationToken ct, IReadOnlyList<Guid>? allowed = null)
    {
        await using var command = new NpgsqlCommand(
            $"""
            SELECT * FROM (
                SELECT v.id,
                       trim(concat_ws(' ', v.make, v.model, v.year::text)) || ' · ' || v.registration_number AS title,
                       {CityUsesSql} AS uses,
                       COALESCE(NULLIF(u.full_name, ''), 'Driver') AS person,
                       COALESCE(u.phone_number, '') AS phone,
                       t.id AS tehsil_id, t.name AS tehsil, d.name AS district,
                       COALESCE(dp.submitted_at, v.created_at) AS since,
                       {CityStatusSql} AS row_status,
                       NULLIF(COALESCE(dp.review_notes,
                           (SELECT vd.review_notes FROM udrive.vehicle_documents vd
                             WHERE vd.vehicle_id = v.id AND NULLIF(vd.review_notes, '') IS NOT NULL
                             ORDER BY vd.updated_at DESC LIMIT 1)), '') AS note,
                       NULLIF(v.image_url, '') AS photo,
                       {CityChecksDoneSql} AS done
                FROM udrive.vehicles v
                JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                JOIN udrive.users u ON u.id = dp.user_id
                LEFT JOIN udrive.territories t ON t.id = COALESCE(v.territory_id, dp.territory_id)
                LEFT JOIN udrive.territories d ON d.id = t.parent_id
                WHERE COALESCE(v.listed_via, 'Driver') = 'Driver'
                  AND v.status <> 'Deleted'
                  AND COALESCE(dp.profile_kind, 'Driver') = 'Driver'
                  AND {AreaSql("t", "COALESCE(v.territory_id, dp.territory_id)")}
                  AND (@q = '' OR v.registration_number ILIKE @like OR v.make ILIKE @like OR v.model ILIKE @like
                       OR u.full_name ILIKE @like OR u.phone_number ILIKE @like)
                  AND (@id::uuid IS NULL OR v.id = @id::uuid)
            ) x
            WHERE (@want = 'All' OR x.row_status = @want)
            ORDER BY (x.row_status = 'Waiting') DESC, x.since
            LIMIT 300;
            """, connection);
        BindArea(command, area, unassigned, allowed);
        BindSearch(command, search, id);
        command.Parameters.AddWithValue("want", want);

        var list = new List<VerificationRowDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        string? S(int i) => reader.IsDBNull(i) ? null : reader.GetString(i);
        while (await reader.ReadAsync(ct))
        {
            var status = reader.GetString(9);
            list.Add(new VerificationRowDto(
                "city", reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetString(3), reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetGuid(5), S(6), S(7),
                reader.GetFieldValue<DateTimeOffset>(8),
                status == "Other" ? "Rejected" : status,
                S(10), reader.GetInt32(12), CityChecksTotal, S(11), 0));
        }

        return list;
    }

    /// <summary>What the vehicle was registered for, in words.</summary>
    private const string CityUsesSql = """
        CASE
            WHEN COALESCE(v.wants_city, v.available_for_city, false)
                 AND COALESCE(v.wants_intercity, v.available_for_intercity, false) THEN 'City + City to city'
            WHEN COALESCE(v.wants_intercity, v.available_for_intercity, false) THEN 'City to city'
            ELSE 'City rides'
        END || ' · ' || v.passenger_capacity::text || ' seats'
        """;

    private const int CityChecksTotal = 6;

    /// <summary>The six checks below, counted in SQL for the list.</summary>
    private const string CityChecksDoneSql = """
        ((SELECT count(DISTINCT dd.document_type) FROM udrive.driver_documents dd
           WHERE dd.driver_profile_id = dp.id
             AND dd.document_type IN ('CNIC_FRONT','CNIC_BACK','SELFIE_WITH_CNIC','DRIVING_LICENCE','DRIVING_LICENCE_BACK','SELFIE')) = 6)::int
        + (COALESCE(dp.driving_licence_expiry > (now() AT TIME ZONE 'Asia/Karachi')::date, false))::int
        + EXISTS (SELECT 1 FROM udrive.vehicle_documents vd WHERE vd.vehicle_id = v.id AND vd.document_type = 'VEHICLE_FRONT')::int
        + ((SELECT count(DISTINCT vd.document_type) FROM udrive.vehicle_documents vd
             WHERE vd.vehicle_id = v.id AND vd.document_type IN ('REGISTRATION_BOOK','REGISTRATION_BOOK_BACK')) = 2)::int
        + (COALESCE(v.territory_id, dp.territory_id) IS NOT NULL)::int
        + (v.wants_city IS NOT NULL OR v.wants_intercity IS NOT NULL
           OR COALESCE(v.available_for_city, false) OR COALESCE(v.available_for_intercity, false))::int
        """;

    private static async Task<VerificationDetailDto?> CityDetailAsync(
        NpgsqlConnection connection, Guid vehicleId, CancellationToken ct)
    {
        var row = (await CityRowsAsync(connection, "All", null, false, null, vehicleId, ct)).FirstOrDefault();
        if (row is null) return null;

        var documents = new List<VerificationDocumentDto>();
        var have = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        await using (var command = new NpgsqlCommand(
            """
            SELECT 'd:' || dd.document_type, dd.file_url FROM udrive.driver_documents dd
            JOIN udrive.vehicles v ON v.driver_profile_id = dd.driver_profile_id
            WHERE v.id = @id
            UNION ALL
            SELECT 'v:' || vd.document_type, vd.file_url FROM udrive.vehicle_documents vd
            WHERE vd.vehicle_id = @id;
            """, connection))
        {
            command.Parameters.AddWithValue("id", vehicleId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct)) have[reader.GetString(0)] = reader.GetString(1);
        }

        (string Key, string Label)[] wanted =
        [
            ("d:SELFIE", "Selfie"), ("d:CNIC_FRONT", "CNIC front"), ("d:CNIC_BACK", "CNIC back"),
            ("d:SELFIE_WITH_CNIC", "Selfie + CNIC"), ("d:DRIVING_LICENCE", "Licence front"),
            ("d:DRIVING_LICENCE_BACK", "Licence back"), ("v:VEHICLE_FRONT", "Gaari front"),
            ("v:REGISTRATION_BOOK", "Reg. book front"), ("v:REGISTRATION_BOOK_BACK", "Reg. book back"),
        ];
        foreach (var (key, label) in wanted)
        {
            documents.Add(new(label, have.TryGetValue(key, out var url) ? url : null));
        }

        var driverDocs = wanted.Take(6).Count(w => have.ContainsKey(w.Key));
        var regDocs = wanted.Skip(7).Count(w => have.ContainsKey(w.Key));

        DateOnly? licence;
        bool areaKnown;
        bool usesKnown;
        string uses;
        string driverStatus;
        string vehicleStatus;
        await using (var command = new NpgsqlCommand(
            $"""
            SELECT dp.driving_licence_expiry,
                   COALESCE(v.territory_id, dp.territory_id) IS NOT NULL,
                   v.wants_city IS NOT NULL OR v.wants_intercity IS NOT NULL
                     OR COALESCE(v.available_for_city, false) OR COALESCE(v.available_for_intercity, false),
                   {CityUsesSql},
                   dp.verification_status, v.status
            FROM udrive.vehicles v JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            WHERE v.id = @id;
            """, connection))
        {
            command.Parameters.AddWithValue("id", vehicleId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            await reader.ReadAsync(ct);
            licence = reader.IsDBNull(0) ? null : DateOnly.FromDateTime(reader.GetDateTime(0));
            areaKnown = reader.GetBoolean(1);
            usesKnown = reader.GetBoolean(2);
            uses = reader.GetString(3);
            driverStatus = reader.GetString(4);
            vehicleStatus = reader.GetString(5);
        }

        var today = DateOnly.FromDateTime(DateTime.UtcNow.AddHours(5));
        var licenceValid = licence is { } l && l > today;
        var checks = new List<VerificationCheckDto>
        {
            new($"Driver documents ({driverDocs}/6)", driverDocs == 6),
            new(licence is null ? "Licence expiry date nahi" : licenceValid ? "Licence valid" : "Licence expired", licenceValid),
            new("Gaari ki photo (front)", have.ContainsKey("v:VEHICLE_FRONT")),
            new(regDocs == 2 ? "Registration front aur back" : "Registration front aur back — " + (regDocs == 0 ? "dono missing" : "aik missing"), regDocs == 2),
            new("District aur tehsil maloom", areaKnown),
            new("Gaari kis ke liye: " + uses.Split(" · ")[0], usesKnown),
        };

        var facts = new List<VerificationFactDto>
        {
            new("Kaam", uses.Split(" · ")[0]),
            new("Seats", uses.Split(" · ").Last().Replace(" seats", string.Empty)),
            new("Licence", licence is null ? "—" : $"{(licenceValid ? "Valid" : "Expired")} · {licence:MMM yyyy}"),
            new("Driver status", driverStatus),
            new("Gaari status", vehicleStatus),
        };

        var blocked = checks.FirstOrDefault(c => !c.Ok);
        return new VerificationDetailDto(
            row, documents, checks, facts, [],
            blocked is null && row.Status != "Approved",
            blocked is null ? null : $"Not ready: {blocked.Label}",
            row.Status != "Approved");
    }

    /// <summary>Approves the driver and the vehicle together.</summary>
    private async Task<ServiceResult<Decision>> ApproveCityAsync(Guid adminId, Guid vehicleId, CancellationToken ct)
    {
        if (admin is null) return Fail<Decision>(500, "not_configured", "City approval is not available.");

        Guid profileId;
        string driverStatus;
        string vehicleStatus;
        string phone;
        string title;
        await using (var connection = await OpenAsync(ct))
        {
            var detail = await CityDetailAsync(connection, vehicleId, ct);
            if (detail is null) return Fail<Decision>(404, "not_found", "That vehicle was not found.");
            if (!detail.CanApprove)
            {
                return Fail<Decision>(409, "approval_blocked", detail.BlockReason ?? "Not ready yet.");
            }

            await using var command = new NpgsqlCommand(
                """
                SELECT dp.id, dp.verification_status, v.status, COALESCE(u.phone_number, ''),
                       trim(concat_ws(' ', v.make, v.model)) || ' (' || v.registration_number || ')'
                FROM udrive.vehicles v
                JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                JOIN udrive.users u ON u.id = dp.user_id
                WHERE v.id = @id;
                """, connection);
            command.Parameters.AddWithValue("id", vehicleId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            await reader.ReadAsync(ct);
            profileId = reader.GetGuid(0);
            driverStatus = reader.GetString(1);
            vehicleStatus = reader.GetString(2);
            phone = reader.GetString(3);
            title = reader.GetString(4);
        }

        // The vehicle first: a driver cannot be approved without a verified one.
        if (vehicleStatus != "Verified")
        {
            var vehicle = await admin.ReviewVehicleAsync(
                adminId, vehicleId, new VerificationReviewRequest("Verified", null), null, ct);
            if (!vehicle.Success) return Fail<Decision>(vehicle.StatusCode, vehicle.ErrorCode!, vehicle.Message!);
        }

        if (driverStatus != "Approved")
        {
            var driver = await admin.ReviewDriverAsync(
                adminId, profileId, new VerificationReviewRequest("Approved", null), null, ct);
            if (!driver.Success) return Fail<Decision>(driver.StatusCode, driver.ErrorCode!, driver.Message!);
        }

        await using (var connection = await OpenAsync(ct))
        {
            var row = (await CityRowsAsync(connection, "All", null, false, null, vehicleId, ct)).First();
            return ServiceResult<Decision>.Ok(
                new Decision(row, phone,
                    $"UDrive: Mubarak ho! Aap aur aap ki gaari {title} city rides ke liye approve ho gaye. "
                    + "App kholein aur online ho jayein."),
                "Driver aur gaari approve ho gaye.");
        }
    }

    /// <summary>
    /// Reject: the driver while they are still waiting, otherwise the vehicle.
    /// Ask for info: whichever of the two is waiting is sent back for changes.
    /// </summary>
    private async Task<ServiceResult<Decision>> RejectCityAsync(
        Guid adminId, Guid vehicleId, string? reason, bool requestInfo, CancellationToken ct)
    {
        if (admin is null) return Fail<Decision>(500, "not_configured", "City approval is not available.");
        var note = reason?.Trim();
        if (string.IsNullOrEmpty(note))
        {
            return Fail<Decision>(400, "note_required", "Write a note to the driver.");
        }

        Guid profileId;
        string driverStatus;
        string vehicleStatus;
        string phone;
        string title;
        await using (var connection = await OpenAsync(ct))
        {
            await using var command = new NpgsqlCommand(
                """
                SELECT dp.id, dp.verification_status, v.status, COALESCE(u.phone_number, ''),
                       trim(concat_ws(' ', v.make, v.model)) || ' (' || v.registration_number || ')'
                FROM udrive.vehicles v
                JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                JOIN udrive.users u ON u.id = dp.user_id
                WHERE v.id = @id AND v.status <> 'Deleted';
                """, connection);
            command.Parameters.AddWithValue("id", vehicleId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct)) return Fail<Decision>(404, "not_found", "That vehicle was not found.");
            profileId = reader.GetGuid(0);
            driverStatus = reader.GetString(1);
            vehicleStatus = reader.GetString(2);
            phone = reader.GetString(3);
            title = reader.GetString(4);
        }

        var driverWaiting = driverStatus is "Submitted" or "UnderReview" or "ChangesRequired";
        if (driverWaiting)
        {
            var driver = await admin.ReviewDriverAsync(
                adminId, profileId,
                new VerificationReviewRequest(requestInfo ? "ChangesRequired" : "Rejected", note), null, ct);
            if (!driver.Success) return Fail<Decision>(driver.StatusCode, driver.ErrorCode!, driver.Message!);
        }

        if (requestInfo || !driverWaiting)
        {
            if (vehicleStatus != "Verified" || !requestInfo)
            {
                var vehicle = await admin.ReviewVehicleAsync(
                    adminId, vehicleId,
                    new VerificationReviewRequest(requestInfo ? "ChangesRequired" : "Suspended", note), null, ct);
                if (!vehicle.Success) return Fail<Decision>(vehicle.StatusCode, vehicle.ErrorCode!, vehicle.Message!);
            }
        }

        await using (var connection = await OpenAsync(ct))
        {
            var row = (await CityRowsAsync(connection, "All", null, false, null, vehicleId, ct)).First();
            var message = requestInfo
                ? $"UDrive: {title} ki city rides registration mein yeh cheez chahiye — {note}. App mein upload karein."
                : $"UDrive: {title} city rides ke liye approve nahi ho saki — {note}";
            return ServiceResult<Decision>.Ok(
                new Decision(row, phone, message),
                requestInfo ? "Driver ko bata diya gaya kya chahiye." : "Reject ho gaya.");
        }
    }

    // ─────────────────────────────────────────────────────── rows

    private static async Task<IReadOnlyList<VerificationRowDto>> VehicleRowsAsync(
        NpgsqlConnection connection, string purpose, string want, Guid? area, bool unassigned,
        string? search, Guid? id, CancellationToken ct, IReadOnlyList<Guid>? allowed = null)
    {
        var p = purpose == "rent" ? "rent" : "tour";
        var statusFilter = want switch
        {
            "Waiting" => WaitingSql(p),
            "Approved" => $"v.{p}_review_status = 'Approved'",
            "Rejected" => $"v.{p}_review_status = 'Rejected'",
            "Info" => $"v.{p}_review_status = 'Info'",
            _ => $"v.{p}_review_status <> 'None'",
        };

        // p is "rent" or "tour", fixed above; never the caller's text.
        await using var command = new NpgsqlCommand(
            $"""
            SELECT v.id,
                   trim(concat_ws(' ', v.make, v.model)) || ' · ' || v.registration_number,
                   v.passenger_capacity::text || ' seats'
                     || CASE WHEN '{p}' = 'rent'
                             THEN COALESCE(' · with driver Rs ' || to_char(v.rent_with_driver_daily, 'FM999,999,999'), '')
                                  || COALESCE(' · self-drive Rs ' || to_char(v.rent_self_drive_daily, 'FM999,999,999'), '')
                             ELSE ' · mountain score ' || v.mountain_readiness_score || '%' END,
                   COALESCE(NULLIF(u.full_name, ''), 'Owner'), COALESCE(u.phone_number, ''),
                   t.id, t.name, d.name,
                   COALESCE(v.listing_submitted_at, v.created_at),
                   v.{p}_review_status, v.{p}_review_note,
                   NULLIF(v.image_url, ''),
                   (SELECT count(*)::int FROM udrive.fleet_drivers fd
                     WHERE fd.owner_profile_id = dp.id AND fd.status = 'Submitted')
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            LEFT JOIN udrive.territories t ON t.id = COALESCE(v.territory_id, dp.territory_id)
            LEFT JOIN udrive.territories d ON d.id = t.parent_id
            WHERE v.listed_via IN ('Listing', 'Staff') AND v.status <> 'Deleted'
              AND ({statusFilter})
              AND {AreaSql("t", "COALESCE(v.territory_id, dp.territory_id)")}
              AND (@q = '' OR v.registration_number ILIKE @like OR v.make ILIKE @like OR v.model ILIKE @like
                   OR u.full_name ILIKE @like OR u.phone_number ILIKE @like)
              AND (@id::uuid IS NULL OR v.id = @id::uuid)
            ORDER BY (v.{p}_review_status = 'Pending') DESC, v.listing_submitted_at NULLS LAST, v.created_at
            LIMIT 300;
            """, connection);
        BindArea(command, area, unassigned, allowed);
        BindSearch(command, search, id);

        var raw = new List<VerificationRowDto>();
        await using (var reader = await command.ExecuteReaderAsync(ct))
        {
            string? S(int i) => reader.IsDBNull(i) ? null : reader.GetString(i);
            while (await reader.ReadAsync(ct))
            {
                var waitingDrivers = reader.GetInt32(12);
                raw.Add(new VerificationRowDto(
                    p, reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetString(3), reader.GetString(4),
                    reader.IsDBNull(5) ? null : reader.GetGuid(5), S(6), S(7),
                    reader.GetFieldValue<DateTimeOffset>(8),
                    RowStatus(reader.GetString(9), waitingDrivers),
                    S(10), 0, 0, S(11), waitingDrivers));
            }
        }

        // The checks need their own queries, so they run after the reader closes.
        var list = new List<VerificationRowDto>(raw.Count);
        foreach (var row in raw)
        {
            var checks = await ListingService.PurposeChecksAsync(connection, row.Id, p, ct);
            list.Add(row with { ChecksDone = checks.Count(c => c.Ok), ChecksTotal = checks.Count });
        }

        return list;
    }

    private static async Task<IReadOnlyList<VerificationRowDto>> HotelRowsAsync(
        NpgsqlConnection connection, string want, Guid? area, bool unassigned, string? search, Guid? id, CancellationToken ct,
        IReadOnlyList<Guid>? allowed = null)
    {
        await using var command = new NpgsqlCommand(
            $"""
            SELECT h.id, COALESCE(h.name, ''),
                   (SELECT COALESCE(sum(r.total_rooms), 0)::int FROM udrive.hotel_rooms r WHERE r.hotel_id = h.id)::text
                     || ' rooms · ' || COALESCE(NULLIF(h.address, ''), h.city, ''),
                   COALESCE(NULLIF(u.full_name, ''), 'Owner'), COALESCE(NULLIF(h.contact_phone, ''), u.phone_number, ''),
                   t.id, t.name, d.name, h.created_at, h.approval_status, h.rejection_reason, NULLIF(h.main_image_url, ''),
                   (NULLIF(h.main_image_url, '') IS NOT NULL)::int
                   + (h.latitude IS NOT NULL AND h.longitude IS NOT NULL)::int
                   + EXISTS (SELECT 1 FROM udrive.hotel_rooms r WHERE r.hotel_id = h.id AND r.base_rate > 0)::int
                   + (NULLIF(h.contact_phone, '') IS NOT NULL)::int
            FROM udrive.hotels h
            JOIN udrive.users u ON u.id = h.owner_user_id
            LEFT JOIN udrive.territories t ON t.id = h.territory_id
            LEFT JOIN udrive.territories d ON d.id = t.parent_id
            WHERE ({SimpleStatusSql("h.approval_status", want)})
              AND {AreaSql("t", "h.territory_id")}
              AND (@q = '' OR h.name ILIKE @like OR h.city ILIKE @like OR u.full_name ILIKE @like OR h.contact_phone ILIKE @like)
              AND (@id::uuid IS NULL OR h.id = @id::uuid)
            ORDER BY (h.approval_status = 'Pending') DESC, h.created_at
            LIMIT 300;
            """, connection);
        BindArea(command, area, unassigned, allowed);
        BindSearch(command, search, id);
        return await SimpleRowsAsync(command, "hotels", 4, ct);
    }

    private static async Task<IReadOnlyList<VerificationRowDto>> BusinessRowsAsync(
        NpgsqlConnection connection, string want, Guid? area, bool unassigned, string? search, Guid? id, CancellationToken ct,
        IReadOnlyList<Guid>? allowed = null)
    {
        await using var command = new NpgsqlCommand(
            $"""
            SELECT b.id, b.name, COALESCE(b.category, '') || ' · ' || COALESCE(b.address, ''),
                   COALESCE(NULLIF(u.full_name, ''), 'Owner'), COALESCE(NULLIF(b.phone, ''), u.phone_number, ''),
                   t.id, t.name, d.name, b.created_at, b.approval_status, b.rejection_reason, NULLIF(b.photo_url, ''),
                   (NULLIF(b.photo_url, '') IS NOT NULL)::int
                   + (b.latitude IS NOT NULL AND b.longitude IS NOT NULL)::int
                   + (NULLIF(b.phone, '') IS NOT NULL)::int
                   + (NOT EXISTS (SELECT 1 FROM udrive.businesses o
                                  WHERE o.id <> b.id AND o.approval_status = 'Approved'
                                    AND lower(o.name) = lower(b.name)
                                    AND abs(o.latitude - b.latitude) < 0.002 AND abs(o.longitude - b.longitude) < 0.002))::int
            FROM udrive.businesses b
            JOIN udrive.users u ON u.id = b.owner_user_id
            LEFT JOIN udrive.territories t ON t.id = b.territory_id
            LEFT JOIN udrive.territories d ON d.id = t.parent_id
            WHERE ({SimpleStatusSql("b.approval_status", want)})
              AND {AreaSql("t", "b.territory_id")}
              AND (@q = '' OR b.name ILIKE @like OR b.category ILIKE @like OR u.full_name ILIKE @like OR b.phone ILIKE @like)
              AND (@id::uuid IS NULL OR b.id = @id::uuid)
            ORDER BY (b.approval_status = 'Pending') DESC, b.created_at
            LIMIT 300;
            """, connection);
        BindArea(command, area, unassigned, allowed);
        BindSearch(command, search, id);
        return await SimpleRowsAsync(command, "businesses", 4, ct);
    }

    private static async Task<IReadOnlyList<VerificationRowDto>> SimpleRowsAsync(
        NpgsqlCommand command, string kind, int checksTotal, CancellationToken ct)
    {
        var list = new List<VerificationRowDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        string? S(int i) => reader.IsDBNull(i) ? null : reader.GetString(i);
        while (await reader.ReadAsync(ct))
        {
            var approval = reader.GetString(9);
            list.Add(new VerificationRowDto(
                kind, reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetString(3), reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetGuid(5), S(6), S(7),
                reader.GetFieldValue<DateTimeOffset>(8),
                approval switch { "Pending" => "Waiting", "Approved" => "Approved", _ => "Rejected" },
                approval == "Rejected" ? S(10) : null,
                reader.GetInt32(12), checksTotal,
                S(11),
                0));
        }

        return list;
    }

    // ─────────────────────────────────────────────────────── detail parts

    private static async Task<IReadOnlyList<VerificationDocumentDto>> VehicleDocumentsAsync(
        NpgsqlConnection connection, Guid vehicleId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT
              (SELECT file_url FROM udrive.vehicle_documents d WHERE d.vehicle_id = v.id AND d.document_type = 'VEHICLE_FRONT'),
              (SELECT file_url FROM udrive.vehicle_documents d WHERE d.vehicle_id = v.id AND d.document_type = 'REGISTRATION_BOOK'),
              (SELECT file_url FROM udrive.vehicle_documents d WHERE d.vehicle_id = v.id AND d.document_type = 'REGISTRATION_BOOK_BACK'),
              (SELECT file_url FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id AND d.document_type = 'CNIC_FRONT'),
              (SELECT file_url FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id AND d.document_type = 'CNIC_BACK'),
              (SELECT file_url FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id
                 AND d.document_type IN ('SELFIE', 'SELFIE_WITH_CNIC') ORDER BY d.document_type LIMIT 1),
              (SELECT file_url FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id AND d.document_type = 'DRIVING_LICENCE'),
              (SELECT file_url FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id AND d.document_type = 'DRIVING_LICENCE_BACK'),
              dp.drives_self AND COALESCE(dp.profile_kind, 'Driver') = 'Owner'
            FROM udrive.vehicles v JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            WHERE v.id = @id;
            """, connection);
        command.Parameters.AddWithValue("id", vehicleId);
        await using var reader = await command.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct)) return [];
        string? S(int i) => reader.IsDBNull(i) ? null : reader.GetString(i);
        var list = new List<VerificationDocumentDto>
        {
            new("Car front", S(0)), new("Reg. book front", S(1)), new("Reg. book back", S(2)),
            new("CNIC front", S(3)), new("CNIC back", S(4)), new("Selfie", S(5)),
        };
        if (reader.GetBoolean(8))
        {
            list.Add(new("Licence front", S(6)));
            list.Add(new("Licence back", S(7)));
        }

        return list;
    }

    private static async Task<IReadOnlyList<VerificationFactDto>> VehicleFactsAsync(
        NpgsqlConnection connection, Guid vehicleId, string purpose, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT v.year, v.category, v.passenger_capacity, v.is_four_by_four,
                   v.rent_with_driver_daily, v.rent_self_drive_daily, v.rent_pickup_point,
                   v.mountain_readiness_score, v.listed_via,
                   CASE WHEN COALESCE(dp.profile_kind, 'Driver') = 'Driver' THEN 'UDrive driver (drives himself)'
                        WHEN dp.drives_self THEN 'Owner drives, and/or his drivers'
                        ELSE 'His drivers only' END,
                   (SELECT count(*)::int FROM udrive.vehicles x WHERE x.driver_profile_id = dp.id AND x.status <> 'Deleted')
            FROM udrive.vehicles v JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            WHERE v.id = @id;
            """, connection);
        command.Parameters.AddWithValue("id", vehicleId);
        await using var reader = await command.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct)) return [];
        var list = new List<VerificationFactDto>
        {
            new("Year", reader.GetInt32(0).ToString()),
            new("Type", reader.GetString(1) + (reader.GetBoolean(3) ? " · 4×4" : string.Empty)),
            new("Seats", reader.GetInt32(2).ToString()),
            new("Who drives", reader.GetString(9)),
            new("Owner's vehicles", reader.GetInt32(10).ToString()),
            new("Added by", reader.GetString(8) == "Staff" ? "UDrive staff" : "Owner, from the app"),
        };
        if (purpose == "rent")
        {
            list.Add(new("With driver / day", reader.IsDBNull(4) ? "—" : $"Rs {reader.GetDecimal(4):N0}"));
            list.Add(new("Self-drive / day", reader.IsDBNull(5) ? "—" : $"Rs {reader.GetDecimal(5):N0}"));
            list.Add(new("Pickup", reader.IsDBNull(6) ? "—" : reader.GetString(6)));
        }
        else
        {
            list.Add(new("Mountain score", reader.GetInt32(7) + "%"));
        }

        return list;
    }

    private static async Task<(IReadOnlyList<VerificationDocumentDto>, IReadOnlyList<VerificationCheckDto>, IReadOnlyList<VerificationFactDto>)>
        HotelDetailAsync(NpgsqlConnection connection, Guid hotelId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT NULLIF(h.main_image_url, ''), h.latitude, h.longitude, NULLIF(h.contact_phone, ''),
                   COALESCE(h.address, ''), COALESCE(h.city, ''), COALESCE(h.district, ''),
                   (SELECT count(*)::int FROM udrive.hotel_rooms r WHERE r.hotel_id = h.id),
                   EXISTS (SELECT 1 FROM udrive.hotel_rooms r WHERE r.hotel_id = h.id AND r.base_rate > 0),
                   ARRAY(SELECT r.image_url FROM udrive.hotel_rooms r
                         WHERE r.hotel_id = h.id AND NULLIF(r.image_url, '') IS NOT NULL ORDER BY r.created_at LIMIT 4)
            FROM udrive.hotels h WHERE h.id = @id;
            """, connection);
        command.Parameters.AddWithValue("id", hotelId);
        await using var reader = await command.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct)) return ([], [], []);
        var front = reader.IsDBNull(0) ? null : reader.GetString(0);
        var hasPin = !reader.IsDBNull(1) && !reader.IsDBNull(2);
        var phone = reader.IsDBNull(3) ? null : reader.GetString(3);
        var docs = new List<VerificationDocumentDto> { new("Hotel photo", front) };
        var roomImages = reader.GetFieldValue<string[]>(9);
        for (var i = 0; i < roomImages.Length; i++) docs.Add(new($"Room photo {i + 1}", roomImages[i]));
        var checks = new List<VerificationCheckDto>
        {
            new("Photo of the hotel", front is not null),
            new("Location pin on the map", hasPin),
            new("At least one room with a price", reader.GetBoolean(8)),
            new("Contact phone", phone is not null),
        };
        var facts = new List<VerificationFactDto>
        {
            new("Address", reader.GetString(4)),
            new("City / district (as typed)", $"{reader.GetString(5)} / {reader.GetString(6)}"),
            new("Room types", reader.GetInt32(7).ToString()),
            new("Phone", phone ?? "—"),
            new("Map", hasPin ? $"{reader.GetDouble(1):F5}, {reader.GetDouble(2):F5}" : "—"),
        };
        return (docs, checks, facts);
    }

    private static async Task<(IReadOnlyList<VerificationDocumentDto>, IReadOnlyList<VerificationCheckDto>, IReadOnlyList<VerificationFactDto>)>
        BusinessDetailAsync(NpgsqlConnection connection, Guid businessId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT NULLIF(b.photo_url, ''), b.latitude, b.longitude, NULLIF(b.phone, ''),
                   COALESCE(b.category, ''), COALESCE(b.address, ''), COALESCE(b.description, ''), b.open_24_hours,
                   to_char(b.opens_at, 'HH24:MI'), to_char(b.closes_at, 'HH24:MI'),
                   EXISTS (SELECT 1 FROM udrive.businesses o
                           WHERE o.id <> b.id AND o.approval_status = 'Approved'
                             AND lower(o.name) = lower(b.name)
                             AND abs(o.latitude - b.latitude) < 0.002 AND abs(o.longitude - b.longitude) < 0.002)
            FROM udrive.businesses b WHERE b.id = @id;
            """, connection);
        command.Parameters.AddWithValue("id", businessId);
        await using var reader = await command.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct)) return ([], [], []);
        var photo = reader.IsDBNull(0) ? null : reader.GetString(0);
        var phone = reader.IsDBNull(3) ? null : reader.GetString(3);
        var hours = reader.GetBoolean(7)
            ? "Open 24 hours"
            : reader.IsDBNull(8) ? "—" : $"{reader.GetString(8)} – {(reader.IsDBNull(9) ? "?" : reader.GetString(9))}";
        var docs = new List<VerificationDocumentDto> { new("Photo", photo) };
        var checks = new List<VerificationCheckDto>
        {
            new("Real photo of the place", photo is not null),
            new("Pin on the map", true),
            new("Phone number", phone is not null),
            new("Not a duplicate of an approved place", !reader.GetBoolean(10)),
        };
        var facts = new List<VerificationFactDto>
        {
            new("Category", reader.GetString(4)),
            new("Address", reader.GetString(5)),
            new("Hours", hours),
            new("Phone", phone ?? "—"),
            new("Map", $"{reader.GetDouble(1):F5}, {reader.GetDouble(2):F5}"),
            new("Description", string.IsNullOrWhiteSpace(reader.GetString(6)) ? "—" : reader.GetString(6)),
        };
        return (docs, checks, facts);
    }

    // ─────────────────────────────────────────────────────── helpers

    /// <summary>Waiting = the use is pending, or it is live and a new driver waits.</summary>
    private static string WaitingSql(string p) =>
        $"""
        v.{p}_review_status = 'Pending'
        OR (v.{p}_review_status = 'Approved' AND EXISTS (
              SELECT 1 FROM udrive.fleet_drivers fd
              WHERE fd.owner_profile_id = v.driver_profile_id AND fd.status = 'Submitted'))
        """;

    private static string SimpleStatusSql(string column, string want) => want switch
    {
        "Waiting" => $"{column} = 'Pending'",
        "Approved" => $"{column} = 'Approved'",
        "Rejected" => $"{column} = 'Rejected'",
        "Info" => "false",
        _ => "true",
    };

    /// <summary>
    /// Matches a tehsil row <paramref name="t"/> against the area filter: a
    /// tehsil id, its district's id, or "none" for things with no tehsil yet.
    /// </summary>
    private static string AreaSql(string t, string territoryExpression) =>
        $"""
        (@unassigned AND {territoryExpression} IS NULL
         OR NOT @unassigned AND (@area::uuid IS NULL OR {t}.id = @area::uuid OR {t}.parent_id = @area::uuid))
        AND (@allowed::uuid[] IS NULL OR {t}.id = ANY(@allowed::uuid[]) OR {t}.parent_id = ANY(@allowed::uuid[]))
        """;

    /// <param name="allowed">A team user's districts / tehsils; null = every area.</param>
    private static void BindArea(NpgsqlCommand command, Guid? area, bool unassigned, IReadOnlyList<Guid>? allowed = null)
    {
        command.Parameters.Add(new NpgsqlParameter("area", NpgsqlDbType.Uuid) { Value = (object?)area ?? DBNull.Value });
        command.Parameters.AddWithValue("unassigned", unassigned);
        command.Parameters.Add(new NpgsqlParameter("allowed", NpgsqlDbType.Array | NpgsqlDbType.Uuid)
        {
            Value = allowed is null ? DBNull.Value : allowed.ToArray(),
        });
    }

    private static void BindSearch(NpgsqlCommand command, string? search, Guid? id)
    {
        var q = search?.Trim() ?? string.Empty;
        if (q.Length > 80) q = q[..80];
        command.Parameters.AddWithValue("q", q);
        command.Parameters.AddWithValue("like", "%" + q.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_") + "%");
        command.Parameters.Add(new NpgsqlParameter("id", NpgsqlDbType.Uuid) { Value = (object?)id ?? DBNull.Value });
    }

    private static Guid? ParseArea(string? area, out bool unassigned)
    {
        unassigned = string.Equals(area?.Trim(), "none", StringComparison.OrdinalIgnoreCase);
        return Guid.TryParse(area, out var id) ? id : null;
    }

    private static string NormaliseStatus(string? status) => status?.Trim().ToLowerInvariant() switch
    {
        null or "" or "waiting" or "pending" => "Waiting",
        "approved" => "Approved",
        "rejected" => "Rejected",
        "info" => "Info",
        _ => "All",
    };

    private static string RowStatus(string review, int driversWaiting) => review switch
    {
        "Pending" => "Waiting",
        "Approved" when driversWaiting > 0 => "Waiting",
        "Approved" => "Approved",
        "Info" => "Info",
        _ => "Rejected",
    };

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken ct)
    {
        var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        return connection;
    }

    private static ServiceResult<T> Fail<T>(int status, string code, string message) =>
        ServiceResult<T>.Fail(status, code, message);
}
