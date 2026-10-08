using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// Shared SQL for holds. Every place that offers a ride, a tour, a rental, a
/// hotel or a business to a customer checks that it is not on an open hold.
/// </summary>
public static class ListingHolds
{
    public static readonly string[] Kinds = ["city", "tour", "rent", "hotels", "businesses"];

    /// <summary>Closes an open "Review again" hold once Verification has decided.</summary>
    public static async Task CloseReviewAsync(
        NpgsqlConnection connection, NpgsqlTransaction? transaction,
        string kind, Guid entityId, Guid adminId, string note, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.listing_holds
            SET released_at = now(), released_by = @admin, release_note = @note
            WHERE kind = @kind AND entity_id = @id AND hold_type = 'Review' AND released_at IS NULL;
            """, connection, transaction);
        command.Parameters.AddWithValue("admin", adminId);
        command.Parameters.AddWithValue("note", note);
        command.Parameters.AddWithValue("kind", kind);
        command.Parameters.AddWithValue("id", entityId);
        await command.ExecuteNonQueryAsync(ct);
    }
}

/// <summary>
/// The Approved page and the owner's side of it: review again, suspend,
/// unsuspend, documents asked for again, and the re-claim against a
/// suspension.
/// </summary>
/// <remarks>
/// A hold stops new work at once — city ride requests and offers, tour seats,
/// rentals, hotel bookings and the Near me listing — through the open row in
/// listing_holds that each of those checks. Work already confirmed carries on.
/// "Review again" also moves the thing back to Verification (its status
/// becomes waiting, or "info asked" when documents are wanted), so the same
/// approve button there brings it back.
/// </remarks>
public sealed class HoldService(string connectionString, VerificationHubService hub, LocalFileStorageService storage)
{
    private static readonly (string Key, string Label)[] DriverDocs =
    [
        ("SELFIE", "Selfie"), ("CNIC_FRONT", "CNIC front"), ("CNIC_BACK", "CNIC back"),
        ("SELFIE_WITH_CNIC", "Selfie + CNIC"), ("DRIVING_LICENCE", "Licence front"),
        ("DRIVING_LICENCE_BACK", "Licence back"),
    ];

    private static readonly (string Key, string Label)[] VehicleDocs =
    [
        ("VEHICLE_FRONT", "Gaari ki photo (front)"), ("REGISTRATION_BOOK", "Registration book — front"),
        ("REGISTRATION_BOOK_BACK", "Registration book — back"),
    ];

    private const int MaxClaimPhotos = 3;

    // ─────────────────────────────────────────────────────── admin: lists

    public async Task<ServiceResult<ApprovedSummaryDto>> SummaryAsync(
        string? area, CancellationToken ct, IReadOnlyList<Guid>? allowed = null)
    {
        await using var connection = await OpenAsync(ct);
        var areaId = VerificationHubService.ParseArea(area, out var unassigned);
        await using var command = new NpgsqlCommand(
            $"""
            SELECT
              (SELECT count(*)::int FROM udrive.vehicles v
                JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                LEFT JOIN udrive.territories t ON t.id = COALESCE(v.territory_id, dp.territory_id)
                WHERE COALESCE(v.listed_via, 'Driver') = 'Driver'
                  AND lower(v.status) IN ('verified', 'approved')
                  AND lower(dp.verification_status) IN ('approved', 'verified')
                  AND COALESCE(dp.profile_kind, 'Driver') = 'Driver'
                  AND {VerificationHubService.AreaSql("t", "COALESCE(v.territory_id, dp.territory_id)")}),
              (SELECT count(*)::int FROM udrive.vehicles v
                JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                LEFT JOIN udrive.territories t ON t.id = COALESCE(v.territory_id, dp.territory_id)
                WHERE v.listed_via IN ('Listing', 'Staff') AND v.status <> 'Deleted' AND v.tour_review_status = 'Approved'
                  AND {VerificationHubService.AreaSql("t", "COALESCE(v.territory_id, dp.territory_id)")}),
              (SELECT count(*)::int FROM udrive.vehicles v
                JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                LEFT JOIN udrive.territories t ON t.id = COALESCE(v.territory_id, dp.territory_id)
                WHERE v.listed_via IN ('Listing', 'Staff') AND v.status <> 'Deleted' AND v.rent_review_status = 'Approved'
                  AND {VerificationHubService.AreaSql("t", "COALESCE(v.territory_id, dp.territory_id)")}),
              (SELECT count(*)::int FROM udrive.hotels h
                LEFT JOIN udrive.territories t ON t.id = h.territory_id
                WHERE h.approval_status = 'Approved' AND {VerificationHubService.AreaSql("t", "h.territory_id")}),
              (SELECT count(*)::int FROM udrive.businesses b
                LEFT JOIN udrive.territories t ON t.id = b.territory_id
                WHERE b.approval_status = 'Approved' AND {VerificationHubService.AreaSql("t", "b.territory_id")}),
              (SELECT count(*)::int FROM udrive.listing_holds WHERE hold_type = 'Suspend' AND released_at IS NULL),
              (SELECT count(*)::int FROM udrive.hold_claims c
                JOIN udrive.listing_holds h ON h.id = c.hold_id
                WHERE c.status = 'Pending' AND h.released_at IS NULL);
            """, connection);
        VerificationHubService.BindArea(command, areaId, unassigned, allowed);
        await using var reader = await command.ExecuteReaderAsync(ct);
        await reader.ReadAsync(ct);
        return ServiceResult<ApprovedSummaryDto>.Ok(new ApprovedSummaryDto(
            reader.GetInt32(0), reader.GetInt32(1), reader.GetInt32(2), reader.GetInt32(3),
            reader.GetInt32(4), reader.GetInt32(5), reader.GetInt32(6)));
    }

    /// <param name="state">Live, Suspended or All (default).</param>
    public async Task<ServiceResult<IReadOnlyList<ApprovedRowDto>>> ListAsync(
        string tab, string? state, string? area, string? search, CancellationToken ct, IReadOnlyList<Guid>? allowed = null)
    {
        if (!ListingHolds.Kinds.Contains(tab)) return Fail<IReadOnlyList<ApprovedRowDto>>(400, "tab_invalid", "Unknown tab.");
        var rows = await hub.QueueAsync(tab, "Approved", area, search, ct, allowed);
        if (!rows.Success) return Fail<IReadOnlyList<ApprovedRowDto>>(rows.StatusCode, rows.ErrorCode!, rows.Message!);

        await using var connection = await OpenAsync(ct);
        var holds = await OpenHoldsAsync(connection, tab, ct);
        var want = state?.Trim().ToLowerInvariant();
        var list = new List<ApprovedRowDto>();
        foreach (var row in rows.Data!)
        {
            // A driver who has no vehicle yet has nothing to suspend here.
            if (tab == "city" && row.Subtitle.StartsWith("Sirf driver", StringComparison.Ordinal)) continue;
            holds.TryGetValue(row.Id, out var hold);
            if (hold is { Type: "Review" }) continue;
            var suspended = hold is { Type: "Suspend" };
            if (want == "live" && suspended || want == "suspended" && !suspended) continue;
            list.Add(new ApprovedRowDto(
                row, suspended ? "Suspended" : "Live", hold?.Reason, hold?.CreatedAt, hold?.ClaimWaiting ?? false));
        }

        return ServiceResult<IReadOnlyList<ApprovedRowDto>>.Ok(
            list.OrderByDescending(r => r.ClaimWaiting).ThenByDescending(r => r.State == "Suspended").ToList());
    }

    public async Task<ServiceResult<ApprovedDetailDto>> DetailAsync(string tab, Guid id, CancellationToken ct)
    {
        var detail = await hub.DetailAsync(tab, id, ct);
        if (!detail.Success) return Fail<ApprovedDetailDto>(detail.StatusCode, detail.ErrorCode!, detail.Message!);

        await using var connection = await OpenAsync(ct);
        var hold = await HoldForAsync(connection, tab, id, ct);
        return ServiceResult<ApprovedDetailDto>.Ok(new ApprovedDetailDto(
            detail.Data!,
            hold is { Type: "Suspend" } ? "Suspended" : hold is { Type: "Review" } ? "Review" : "Live",
            hold,
            Requestable(tab).Select(d => new HoldDocDto(d.Key, d.Label, false)).ToList()));
    }

    // ─────────────────────────────────────────────────────── admin: actions

    public async Task<ServiceResult<ApprovedDetailDto>> ReviewAgainAsync(
        Guid adminId, string tab, Guid id, HoldReviewRequest request, CancellationToken ct)
    {
        var note = Clean(request.Note);
        if (note is null) return Fail<ApprovedDetailDto>(400, "note_required", "Wajah likhein — yeh driver / owner ko jayegi.");
        var allowedDocs = Requestable(tab).Select(d => d.Key).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var docs = (request.Documents ?? []).Select(d => d.Trim().ToUpperInvariant()).Distinct().ToArray();
        var badDoc = docs.FirstOrDefault(d => !allowedDocs.Contains(d));
        if (badDoc is not null) return Fail<ApprovedDetailDto>(400, "document_invalid", $"Yeh document yahan nahi maanga ja sakta: {badDoc}");

        await using var connection = await OpenAsync(ct);
        await using var tx = await connection.BeginTransactionAsync(ct);
        var target = await TargetAsync(connection, tx, tab, id, ct);
        if (target is null) return Fail<ApprovedDetailDto>(404, "not_found", "Yeh nahi mila.");

        var open = await OpenHoldIdAsync(connection, tx, tab, id, ct);
        if (open is { Type: "Review" }) return Fail<ApprovedDetailDto>(409, "already_in_review", "Yeh pehle se review mein hai.");
        if (open is null && !target.Live) return Fail<ApprovedDetailDto>(409, "not_live", "Sirf approved cheez dobara review mein bheji ja sakti hai.");

        if (open is { Type: "Suspend" } suspended)
        {
            await ReleaseAsync(connection, tx, suspended.Id, adminId, "Moved to review", ct);
            await CloseClaimAsync(connection, tx, suspended.Id, adminId, "Accepted", "Dobara review mein bheja gaya.", ct);
        }

        // Back to Verification: waiting, or "info asked" when documents are wanted.
        var sql = tab switch
        {
            "city" => "UPDATE udrive.vehicles SET status = @status, updated_at = now() WHERE id = @id;",
            "tour" => "UPDATE udrive.vehicles SET tour_review_status = @status, tour_review_note = @note, updated_at = now() WHERE id = @id;",
            "rent" => "UPDATE udrive.vehicles SET rent_review_status = @status, rent_review_note = @note, updated_at = now() WHERE id = @id;",
            "hotels" => "UPDATE udrive.hotels SET approval_status = 'Pending', updated_at = now() WHERE id = @id;",
            _ => "UPDATE udrive.businesses SET approval_status = 'Pending', updated_at = now() WHERE id = @id;",
        };
        var status = tab == "city"
            ? docs.Length > 0 ? "ChangesRequired" : "PendingReview"
            : docs.Length > 0 ? "Info" : "Pending";
        await using (var command = new NpgsqlCommand(sql, connection, tx))
        {
            command.Parameters.AddWithValue("id", id);
            command.Parameters.AddWithValue("status", status);
            command.Parameters.AddWithValue("note", note);
            await command.ExecuteNonQueryAsync(ct);
        }

        var holdId = await InsertHoldAsync(connection, tx, tab, id, target.OwnerUserId, "Review", note, docs, adminId, ct);
        await StopCityWorkAsync(connection, tx, tab, id, ct);
        var docText = docs.Length == 0 ? "kuch nahi — admin dobara check karega" : string.Join(", ", docs.Select(d => Label(d)));
        await TellAsync(connection, tx, target, "hold_review",
            "Aap ki " + target.Item + " dobara review mein hai",
            $"Jab tak review nahi hoti, koi ride ya booking nahi milegi. Wajah: {note}", holdId, ct);
        await WhatsAppOutbox.QueueAsync(connection, tx, "hold_review_owner", target.Phone,
            new Dictionary<string, string?> { ["item"] = target.Item, ["reason"] = note, ["docs"] = docText }, ct);
        await AuditAsync(connection, tx, adminId, "HoldReviewAgain", tab, id, note, docs, ct);
        await tx.CommitAsync(ct);
        return await DetailAfterAsync(tab, id, "Dobara review mein bhej diya. Rides / bookings band.", ct);
    }

    public async Task<ServiceResult<ApprovedDetailDto>> SuspendAsync(
        Guid adminId, string tab, Guid id, HoldNoteRequest request, CancellationToken ct)
    {
        var note = Clean(request.Note);
        if (note is null) return Fail<ApprovedDetailDto>(400, "note_required", "Wajah saaf likhein — yeh driver / owner ko jayegi.");

        await using var connection = await OpenAsync(ct);
        await using var tx = await connection.BeginTransactionAsync(ct);
        var target = await TargetAsync(connection, tx, tab, id, ct);
        if (target is null) return Fail<ApprovedDetailDto>(404, "not_found", "Yeh nahi mila.");
        var open = await OpenHoldIdAsync(connection, tx, tab, id, ct);
        if (open is not null)
        {
            return Fail<ApprovedDetailDto>(409, "already_held",
                open.Type == "Suspend" ? "Yeh pehle se suspend hai." : "Yeh abhi review mein hai.");
        }

        if (!target.Live) return Fail<ApprovedDetailDto>(409, "not_live", "Sirf approved cheez suspend ho sakti hai.");

        var holdId = await InsertHoldAsync(connection, tx, tab, id, target.OwnerUserId, "Suspend", note, [], adminId, ct);
        await StopCityWorkAsync(connection, tx, tab, id, ct);
        await TellAsync(connection, tx, target, "hold_suspend",
            "Aap ki " + target.Item + " suspend hai",
            $"Jab tak admin dobara chalu nahi karta, koi ride ya booking nahi milegi. Wajah: {note}", holdId, ct);
        await WhatsAppOutbox.QueueAsync(connection, tx, "hold_suspend_owner", target.Phone,
            new Dictionary<string, string?> { ["item"] = target.Item, ["reason"] = note }, ct);
        await AuditAsync(connection, tx, adminId, "HoldSuspend", tab, id, note, [], ct);
        await tx.CommitAsync(ct);
        return await DetailAfterAsync(tab, id, "Suspend ho gaya. Rides / bookings band.", ct);
    }

    public async Task<ServiceResult<ApprovedDetailDto>> UnsuspendAsync(
        Guid adminId, string tab, Guid id, HoldNoteRequest request, CancellationToken ct)
    {
        var note = Clean(request.Note) ?? "Unsuspended";
        await using var connection = await OpenAsync(ct);
        await using var tx = await connection.BeginTransactionAsync(ct);
        var target = await TargetAsync(connection, tx, tab, id, ct);
        if (target is null) return Fail<ApprovedDetailDto>(404, "not_found", "Yeh nahi mila.");
        var open = await OpenHoldIdAsync(connection, tx, tab, id, ct);
        if (open is not { Type: "Suspend" }) return Fail<ApprovedDetailDto>(409, "not_suspended", "Yeh suspend nahi hai.");

        await ReleaseAsync(connection, tx, open.Id, adminId, note.Length > 300 ? note[..300] : note, ct);
        await CloseClaimAsync(connection, tx, open.Id, adminId, "Accepted", Clean(request.Note), ct);
        await TellAsync(connection, tx, target, "hold_released",
            "Aap ki " + target.Item + " dobara chalu hai",
            "Ab rides / bookings phir se milein gi.", open.Id, ct);
        await WhatsAppOutbox.QueueAsync(connection, tx, "hold_released_owner", target.Phone,
            new Dictionary<string, string?> { ["item"] = target.Item }, ct);
        await AuditAsync(connection, tx, adminId, "HoldUnsuspend", tab, id, note, [], ct);
        await tx.CommitAsync(ct);
        return await DetailAfterAsync(tab, id, "Unsuspend ho gaya. Rides / bookings chalu.", ct);
    }

    public async Task<ServiceResult<ApprovedDetailDto>> RejectClaimAsync(
        Guid adminId, string tab, Guid id, HoldNoteRequest request, CancellationToken ct)
    {
        var note = Clean(request.Note);
        if (note is null) return Fail<ApprovedDetailDto>(400, "note_required", "Driver / owner ko jawab likhein.");
        await using var connection = await OpenAsync(ct);
        await using var tx = await connection.BeginTransactionAsync(ct);
        var target = await TargetAsync(connection, tx, tab, id, ct);
        if (target is null) return Fail<ApprovedDetailDto>(404, "not_found", "Yeh nahi mila.");
        var open = await OpenHoldIdAsync(connection, tx, tab, id, ct);
        if (open is null || !await CloseClaimAsync(connection, tx, open.Id, adminId, "Rejected", note, ct))
        {
            return Fail<ApprovedDetailDto>(409, "no_claim", "Koi re-claim intezar mein nahi.");
        }

        await TellAsync(connection, tx, target, "hold_claim_rejected",
            "Re-claim manzoor nahi hua",
            $"Admin: {note}. Aap dobara re-claim kar sakte hain.", open.Id, ct);
        await WhatsAppOutbox.QueueAsync(connection, tx, "claim_rejected_owner", target.Phone,
            new Dictionary<string, string?> { ["item"] = target.Item, ["note"] = note }, ct);
        await AuditAsync(connection, tx, adminId, "HoldClaimRejected", tab, id, note, [], ct);
        await tx.CommitAsync(ct);
        return await DetailAfterAsync(tab, id, "Re-claim reject ho gaya; driver ko bata diya.", ct);
    }

    // ─────────────────────────────────────────────────────── owner

    /// <summary>The caller's open reviews and suspensions, for the dashboard banner.</summary>
    public async Task<ServiceResult<IReadOnlyList<HoldDto>>> MineAsync(Guid userId, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        var ids = new List<Guid>();
        await using (var command = new NpgsqlCommand(
            "SELECT id FROM udrive.listing_holds WHERE owner_user_id = @user AND released_at IS NULL ORDER BY created_at DESC;",
            connection))
        {
            command.Parameters.AddWithValue("user", userId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct)) ids.Add(reader.GetGuid(0));
        }

        var list = new List<HoldDto>();
        foreach (var id in ids)
        {
            var hold = await HoldByIdAsync(connection, null, id, ct);
            if (hold is not null) list.Add(hold);
        }

        return ServiceResult<IReadOnlyList<HoldDto>>.Ok(list);
    }

    /// <summary>One of the documents the Admin asked for again.</summary>
    public async Task<ServiceResult<HoldDto>> UploadAsync(
        Guid userId, Guid holdId, string documentType, IFormFile file, CancellationToken ct)
    {
        var key = documentType.Trim().ToUpperInvariant();
        await using var connection = await OpenAsync(ct);
        var hold = await OwnHoldAsync(connection, userId, holdId, ct);
        if (hold is null) return Fail<HoldDto>(404, "not_found", "Yeh review nahi mila.");
        if (hold.Type != "Review" || !hold.Documents.Any(d => d.Key == key))
        {
            return Fail<HoldDto>(409, "not_requested", "Admin ne yeh document nahi maanga.");
        }

        if (hold.SubmittedAt is not null) return Fail<HoldDto>(409, "already_sent", "Documents bhej diye gaye hain; admin dekh raha hai.");

        Guid profileId;
        await using (var command = new NpgsqlCommand(
            "SELECT driver_profile_id FROM udrive.vehicles WHERE id = @id;", connection))
        {
            command.Parameters.AddWithValue("id", hold.EntityId);
            if (await command.ExecuteScalarAsync(ct) is not Guid found) return Fail<HoldDto>(404, "not_found", "Gaari nahi mili.");
            profileId = found;
        }

        var isDriverDoc = DriverDocs.Any(d => d.Key == key);
        StoredFile stored;
        try
        {
            stored = await storage.SaveAsync(file, isDriverDoc ? "driver-documents" : "vehicle-documents",
                isDriverDoc ? profileId : hold.EntityId, ct);
        }
        catch (InvalidDataException exception)
        {
            return Fail<HoldDto>(400, "file_invalid", exception.Message);
        }

        await using var tx = await connection.BeginTransactionAsync(ct);
        await using (var command = new NpgsqlCommand(
            isDriverDoc
                ? """
                  INSERT INTO udrive.driver_documents (id, driver_profile_id, document_type, file_url, status, created_at, updated_at)
                  VALUES (gen_random_uuid(), @owner, @type, @url, 'Submitted', now(), now())
                  ON CONFLICT (driver_profile_id, document_type) DO UPDATE SET
                      file_url = EXCLUDED.file_url, status = 'Submitted', review_notes = NULL, updated_at = now();
                  """
                : """
                  INSERT INTO udrive.vehicle_documents (id, vehicle_id, document_type, file_url, status, created_at, updated_at)
                  VALUES (gen_random_uuid(), @owner, @type, @url, 'PendingReview', now(), now())
                  ON CONFLICT (vehicle_id, document_type) DO UPDATE SET
                      file_url = EXCLUDED.file_url, status = 'PendingReview', review_notes = NULL, updated_at = now();
                  """, connection, tx))
        {
            command.Parameters.AddWithValue("owner", isDriverDoc ? profileId : hold.EntityId);
            command.Parameters.AddWithValue("type", key);
            command.Parameters.AddWithValue("url", stored.RelativeUrl);
            await command.ExecuteNonQueryAsync(ct);
        }

        await using (var command = new NpgsqlCommand(
            """
            UPDATE udrive.listing_holds
            SET uploaded_docs = ARRAY(SELECT DISTINCT unnest(uploaded_docs || ARRAY[@type]::text[]))
            WHERE id = @id;
            """, connection, tx))
        {
            command.Parameters.AddWithValue("type", key);
            command.Parameters.AddWithValue("id", holdId);
            await command.ExecuteNonQueryAsync(ct);
        }

        await tx.CommitAsync(ct);
        return ServiceResult<HoldDto>.Ok((await HoldByIdAsync(connection, null, holdId, ct))!, "Upload ho gaya.");
    }

    /// <summary>Every asked-for document is in: back to Verification → Waiting.</summary>
    public async Task<ServiceResult<HoldDto>> SubmitAsync(Guid userId, Guid holdId, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        var hold = await OwnHoldAsync(connection, userId, holdId, ct);
        if (hold is null) return Fail<HoldDto>(404, "not_found", "Yeh review nahi mila.");
        if (hold.Type != "Review") return Fail<HoldDto>(409, "not_review", "Yeh review nahi hai.");
        if (hold.SubmittedAt is not null) return ServiceResult<HoldDto>.Ok(hold, "Pehle hi bhej diya gaya hai.");
        var missing = hold.Documents.Where(d => !d.Uploaded).Select(d => d.Label).ToList();
        if (missing.Count > 0) return Fail<HoldDto>(409, "documents_missing", "Pehle yeh upload karein: " + string.Join(", ", missing));

        await using var tx = await connection.BeginTransactionAsync(ct);
        var sql = hold.Kind switch
        {
            "city" => "UPDATE udrive.vehicles SET status = 'PendingReview', updated_at = now() WHERE id = @id AND lower(status) = 'changesrequired';",
            "tour" => "UPDATE udrive.vehicles SET tour_review_status = 'Pending', listing_submitted_at = now(), updated_at = now() WHERE id = @id AND tour_review_status = 'Info';",
            "rent" => "UPDATE udrive.vehicles SET rent_review_status = 'Pending', listing_submitted_at = now(), updated_at = now() WHERE id = @id AND rent_review_status = 'Info';",
            _ => null,
        };
        if (sql is not null)
        {
            await using var command = new NpgsqlCommand(sql, connection, tx);
            command.Parameters.AddWithValue("id", hold.EntityId);
            await command.ExecuteNonQueryAsync(ct);
        }

        await using (var command = new NpgsqlCommand(
            "UPDATE udrive.listing_holds SET submitted_at = now() WHERE id = @id;", connection, tx))
        {
            command.Parameters.AddWithValue("id", holdId);
            await command.ExecuteNonQueryAsync(ct);
        }

        await tx.CommitAsync(ct);
        return ServiceResult<HoldDto>.Ok((await HoldByIdAsync(connection, null, holdId, ct))!,
            "Bhej diya. Admin approve karte hi rides / bookings khud chalu ho jayengi.");
    }

    /// <param name="type">WrongReason or Fixed.</param>
    public async Task<ServiceResult<HoldDto>> ClaimAsync(
        Guid userId, Guid holdId, string? type, string? message, IReadOnlyList<IFormFile> photos, CancellationToken ct)
    {
        var claimType = type?.Trim().ToLowerInvariant() switch
        {
            "wrongreason" or "wrong" => "WrongReason",
            "fixed" => "Fixed",
            _ => null,
        };
        if (claimType is null) return Fail<HoldDto>(400, "type_invalid", "Chunein: wajah galat hai, ya masla hal kar diya.");
        var text = message?.Trim() ?? string.Empty;
        if (text.Length < 5) return Fail<HoldDto>(400, "message_required", "Apni baat likhein (kam az kam 5 huroof).");
        if (text.Length > 1000) text = text[..1000];
        if (photos.Count > MaxClaimPhotos) return Fail<HoldDto>(400, "too_many_photos", $"Zyada se zyada {MaxClaimPhotos} photos.");

        await using var connection = await OpenAsync(ct);
        var hold = await OwnHoldAsync(connection, userId, holdId, ct);
        if (hold is null) return Fail<HoldDto>(404, "not_found", "Yeh suspension nahi mili.");
        if (hold.Type != "Suspend") return Fail<HoldDto>(409, "not_suspended", "Re-claim sirf suspension par hota hai.");
        if (hold.Claim is { Status: "Pending" }) return Fail<HoldDto>(409, "claim_open", "Aap ki pichli request abhi admin ke paas hai.");

        var urls = new List<string>();
        try
        {
            foreach (var photo in photos)
            {
                urls.Add((await storage.SaveAsync(photo, "hold-claims", holdId, ct)).RelativeUrl);
            }
        }
        catch (InvalidDataException exception)
        {
            return Fail<HoldDto>(400, "file_invalid", exception.Message);
        }

        await using (var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.hold_claims (hold_id, user_id, claim_type, message, photo_urls)
            VALUES (@hold, @user, @type, @message, @photos);
            """, connection))
        {
            command.Parameters.AddWithValue("hold", holdId);
            command.Parameters.AddWithValue("user", userId);
            command.Parameters.AddWithValue("type", claimType);
            command.Parameters.AddWithValue("message", text);
            command.Parameters.Add(new NpgsqlParameter("photos", NpgsqlDbType.Array | NpgsqlDbType.Text) { Value = urls.ToArray() });
            try
            {
                await command.ExecuteNonQueryAsync(ct);
            }
            catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
            {
                return Fail<HoldDto>(409, "claim_open", "Aap ki pichli request abhi admin ke paas hai.");
            }
        }

        return ServiceResult<HoldDto>.Ok((await HoldByIdAsync(connection, null, holdId, ct))!,
            "Request bhej di. Jawab app aur WhatsApp par aayega.");
    }

    // ─────────────────────────────────────────────────────── parts

    private sealed record Target(Guid OwnerUserId, string? Phone, string Item, bool Live);

    private static async Task<Target?> TargetAsync(
        NpgsqlConnection connection, NpgsqlTransaction tx, string tab, Guid id, CancellationToken ct)
    {
        var sql = tab switch
        {
            "city" => """
                SELECT dp.user_id, u.phone_number,
                       'gaari ' || trim(concat_ws(' ', v.make, v.model)) || ' (' || v.registration_number || ')',
                       lower(v.status) IN ('verified', 'approved') AND lower(dp.verification_status) IN ('approved', 'verified')
                FROM udrive.vehicles v JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                JOIN udrive.users u ON u.id = dp.user_id
                WHERE v.id = @id AND COALESCE(v.listed_via, 'Driver') = 'Driver' FOR UPDATE OF v;
                """,
            "tour" or "rent" => $"""
                SELECT dp.user_id, u.phone_number,
                       '{(tab == "tour" ? "tour" : "rent-a-car")} gaari ' || trim(concat_ws(' ', v.make, v.model)) || ' (' || v.registration_number || ')',
                       v.{tab}_review_status = 'Approved'
                FROM udrive.vehicles v JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                JOIN udrive.users u ON u.id = dp.user_id
                WHERE v.id = @id AND v.listed_via IN ('Listing', 'Staff') FOR UPDATE OF v;
                """,
            "hotels" => """
                SELECT h.owner_user_id, COALESCE(NULLIF(h.contact_phone, ''), u.phone_number),
                       'hotel "' || h.name || '"', h.approval_status = 'Approved'
                FROM udrive.hotels h JOIN udrive.users u ON u.id = h.owner_user_id
                WHERE h.id = @id FOR UPDATE OF h;
                """,
            "businesses" => """
                SELECT b.owner_user_id, COALESCE(NULLIF(b.phone, ''), u.phone_number),
                       'business "' || b.name || '"', b.approval_status = 'Approved'
                FROM udrive.businesses b JOIN udrive.users u ON u.id = b.owner_user_id
                WHERE b.id = @id FOR UPDATE OF b;
                """,
            _ => null,
        };
        if (sql is null) return null;
        await using var command = new NpgsqlCommand(sql, connection, tx);
        command.Parameters.AddWithValue("id", id);
        await using var reader = await command.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct)) return null;
        return new Target(reader.GetGuid(0), reader.IsDBNull(1) ? null : reader.GetString(1), reader.GetString(2), reader.GetBoolean(3));
    }

    private sealed record OpenHold(Guid Id, string Type);

    private static async Task<OpenHold?> OpenHoldIdAsync(
        NpgsqlConnection connection, NpgsqlTransaction tx, string tab, Guid id, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            "SELECT id, hold_type FROM udrive.listing_holds WHERE kind = @kind AND entity_id = @id AND released_at IS NULL FOR UPDATE;",
            connection, tx);
        command.Parameters.AddWithValue("kind", tab);
        command.Parameters.AddWithValue("id", id);
        await using var reader = await command.ExecuteReaderAsync(ct);
        return await reader.ReadAsync(ct) ? new OpenHold(reader.GetGuid(0), reader.GetString(1)) : null;
    }

    private static async Task<Guid> InsertHoldAsync(
        NpgsqlConnection connection, NpgsqlTransaction tx, string tab, Guid id, Guid owner,
        string type, string reason, string[] docs, Guid adminId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.listing_holds (kind, entity_id, owner_user_id, hold_type, reason, requested_docs, created_by)
            VALUES (@kind, @id, @owner, @type, @reason, @docs, @admin)
            RETURNING id;
            """, connection, tx);
        command.Parameters.AddWithValue("kind", tab);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("owner", owner);
        command.Parameters.AddWithValue("type", type);
        command.Parameters.AddWithValue("reason", reason);
        command.Parameters.Add(new NpgsqlParameter("docs", NpgsqlDbType.Array | NpgsqlDbType.Text) { Value = docs });
        command.Parameters.AddWithValue("admin", adminId);
        return (Guid)(await command.ExecuteScalarAsync(ct))!;
    }

    private static async Task ReleaseAsync(
        NpgsqlConnection connection, NpgsqlTransaction tx, Guid holdId, Guid adminId, string note, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            "UPDATE udrive.listing_holds SET released_at = now(), released_by = @admin, release_note = @note WHERE id = @id;",
            connection, tx);
        command.Parameters.AddWithValue("admin", adminId);
        command.Parameters.AddWithValue("note", note);
        command.Parameters.AddWithValue("id", holdId);
        await command.ExecuteNonQueryAsync(ct);
    }

    /// <returns>True when there was an open claim to close.</returns>
    private static async Task<bool> CloseClaimAsync(
        NpgsqlConnection connection, NpgsqlTransaction tx, Guid holdId, Guid adminId, string status, string? note, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.hold_claims SET status = @status, admin_note = @note, decided_at = now(), decided_by = @admin
            WHERE hold_id = @hold AND status = 'Pending';
            """, connection, tx);
        command.Parameters.AddWithValue("status", status);
        command.Parameters.AddWithValue("note", (object?)note ?? DBNull.Value);
        command.Parameters.AddWithValue("admin", adminId);
        command.Parameters.AddWithValue("hold", holdId);
        return await command.ExecuteNonQueryAsync(ct) > 0;
    }

    /// <summary>
    /// A city vehicle: its open offers lapse, and the driver goes offline when
    /// no other ride vehicle of theirs can still work.
    /// </summary>
    private static async Task StopCityWorkAsync(
        NpgsqlConnection connection, NpgsqlTransaction tx, string tab, Guid vehicleId, CancellationToken ct)
    {
        if (tab != "city") return;
        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.driver_offers
            SET status = 'Expired', responded_at = now(), version = version + 1, updated_at = now()
            WHERE vehicle_id = @id AND status IN ('Pending', 'Countered', 'Accepted');

            WITH idle AS (
                SELECT v.driver_profile_id AS profile_id
                FROM udrive.vehicles v
                WHERE v.id = @id
                  AND NOT EXISTS (
                        SELECT 1 FROM udrive.vehicles o
                        WHERE o.driver_profile_id = v.driver_profile_id AND o.id <> v.id
                          AND COALESCE(o.listed_via, 'Driver') = 'Driver'
                          AND lower(o.status) IN ('verified', 'approved')
                          -- One that takes rides, as the ride feed counts it.
                          AND NOT COALESCE(o.available_for_rent, false)
                          AND (COALESCE(o.available_for_city, true) OR COALESCE(o.available_for_intercity, true))
                          AND NOT EXISTS (SELECT 1 FROM udrive.listing_holds lh
                                          WHERE lh.kind = 'city' AND lh.entity_id = o.id AND lh.released_at IS NULL))
            ), ended AS (
                UPDATE udrive.driver_online_sessions s
                SET ended_at = now(), end_reason = 'Admin', updated_at = now()
                FROM idle
                WHERE s.driver_profile_id = idle.profile_id AND s.ended_at IS NULL
                RETURNING s.driver_profile_id
            )
            UPDATE udrive.driver_profiles p
            SET is_online = false, updated_at = now()
            FROM idle
            WHERE p.id = idle.profile_id AND p.is_online;
            """, connection, tx);
        command.Parameters.AddWithValue("id", vehicleId);
        await command.ExecuteNonQueryAsync(ct);
    }

    private static async Task TellAsync(
        NpgsqlConnection connection, NpgsqlTransaction tx, Target target, string type,
        string title, string body, Guid holdId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.notifications (id, user_id, type, title, body, data_json, action_path, created_at, updated_at)
            VALUES (gen_random_uuid(), @user, @type, @title, @body, jsonb_build_object('holdId', @hold), '/dashboard', now(), now());
            """, connection, tx);
        command.Parameters.AddWithValue("user", target.OwnerUserId);
        command.Parameters.AddWithValue("type", type);
        command.Parameters.AddWithValue("title", title.Length > 150 ? title[..150] : title);
        command.Parameters.AddWithValue("body", body);
        command.Parameters.AddWithValue("hold", holdId);
        await command.ExecuteNonQueryAsync(ct);
    }

    private static async Task AuditAsync(
        NpgsqlConnection connection, NpgsqlTransaction tx, Guid adminId, string action, string tab, Guid id,
        string note, string[] docs, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.audit_logs (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
            VALUES (gen_random_uuid(), @admin, @action, @entity, CAST(@id AS text),
                    jsonb_build_object('note', @note, 'documents', @docs), now(), now());
            """, connection, tx);
        command.Parameters.AddWithValue("admin", adminId);
        command.Parameters.AddWithValue("action", action);
        command.Parameters.AddWithValue("entity", tab);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("note", note);
        command.Parameters.Add(new NpgsqlParameter("docs", NpgsqlDbType.Array | NpgsqlDbType.Text) { Value = docs });
        await command.ExecuteNonQueryAsync(ct);
    }

    private sealed record HoldSummary(string Type, string Reason, DateTimeOffset CreatedAt, bool ClaimWaiting);

    private static async Task<Dictionary<Guid, HoldSummary>> OpenHoldsAsync(
        NpgsqlConnection connection, string tab, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT h.entity_id, h.hold_type, h.reason, h.created_at,
                   EXISTS (SELECT 1 FROM udrive.hold_claims c WHERE c.hold_id = h.id AND c.status = 'Pending')
            FROM udrive.listing_holds h
            WHERE h.kind = @kind AND h.released_at IS NULL;
            """, connection);
        command.Parameters.AddWithValue("kind", tab);
        var map = new Dictionary<Guid, HoldSummary>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            map[reader.GetGuid(0)] = new HoldSummary(
                reader.GetString(1), reader.GetString(2), reader.GetFieldValue<DateTimeOffset>(3), reader.GetBoolean(4));
        }

        return map;
    }

    private static async Task<HoldDto?> HoldForAsync(NpgsqlConnection connection, string tab, Guid id, CancellationToken ct)
    {
        Guid? holdId = null;
        await using (var command = new NpgsqlCommand(
            "SELECT id FROM udrive.listing_holds WHERE kind = @kind AND entity_id = @id AND released_at IS NULL;", connection))
        {
            command.Parameters.AddWithValue("kind", tab);
            command.Parameters.AddWithValue("id", id);
            holdId = await command.ExecuteScalarAsync(ct) as Guid?;
        }

        return holdId is { } found ? await HoldByIdAsync(connection, null, found, ct) : null;
    }

    private static async Task<HoldDto?> OwnHoldAsync(NpgsqlConnection connection, Guid userId, Guid holdId, CancellationToken ct)
    {
        var hold = await HoldByIdAsync(connection, null, holdId, ct, userId);
        return hold;
    }

    private static async Task<HoldDto?> HoldByIdAsync(
        NpgsqlConnection connection, NpgsqlTransaction? tx, Guid holdId, CancellationToken ct, Guid? owner = null)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT h.id, h.kind, h.entity_id, h.hold_type, h.reason, h.requested_docs, h.uploaded_docs,
                   h.created_at, a.full_name, h.submitted_at,
                   CASE h.kind
                     WHEN 'hotels' THEN (SELECT x.name FROM udrive.hotels x WHERE x.id = h.entity_id)
                     WHEN 'businesses' THEN (SELECT x.name FROM udrive.businesses x WHERE x.id = h.entity_id)
                     ELSE (SELECT trim(concat_ws(' ', x.make, x.model, x.year::text)) || ' · ' || x.registration_number
                           FROM udrive.vehicles x WHERE x.id = h.entity_id)
                   END,
                   c.id, c.claim_type, c.message, c.photo_urls, c.status, c.admin_note, c.created_at, c.decided_at
            FROM udrive.listing_holds h
            LEFT JOIN udrive.users a ON a.id = h.created_by
            LEFT JOIN LATERAL (
                SELECT * FROM udrive.hold_claims c WHERE c.hold_id = h.id ORDER BY c.created_at DESC LIMIT 1
            ) c ON true
            WHERE h.id = @id AND h.released_at IS NULL AND (@owner::uuid IS NULL OR h.owner_user_id = @owner::uuid);
            """, connection, tx);
        command.Parameters.AddWithValue("id", holdId);
        command.Parameters.Add(new NpgsqlParameter("owner", NpgsqlDbType.Uuid) { Value = (object?)owner ?? DBNull.Value });
        await using var reader = await command.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct)) return null;
        string? S(int i) => reader.IsDBNull(i) ? null : reader.GetString(i);
        var requested = reader.GetFieldValue<string[]>(5);
        var uploaded = reader.GetFieldValue<string[]>(6).ToHashSet(StringComparer.OrdinalIgnoreCase);
        HoldClaimDto? claim = reader.IsDBNull(11)
            ? null
            : new HoldClaimDto(
                reader.GetGuid(11), reader.GetString(12), reader.GetString(13), reader.GetFieldValue<string[]>(14),
                reader.GetString(15), S(16), reader.GetFieldValue<DateTimeOffset>(17),
                reader.IsDBNull(18) ? null : reader.GetFieldValue<DateTimeOffset>(18));
        return new HoldDto(
            reader.GetGuid(0), reader.GetString(1), reader.GetGuid(2), S(10) ?? "—", reader.GetString(3), reader.GetString(4),
            requested.Select(d => new HoldDocDto(d, Label(d), uploaded.Contains(d))).ToList(),
            reader.GetFieldValue<DateTimeOffset>(7), S(8),
            reader.IsDBNull(9) ? null : reader.GetFieldValue<DateTimeOffset>(9),
            claim);
    }

    private async Task<ServiceResult<ApprovedDetailDto>> DetailAfterAsync(string tab, Guid id, string message, CancellationToken ct)
    {
        var detail = await DetailAsync(tab, id, ct);
        return detail.Success ? ServiceResult<ApprovedDetailDto>.Ok(detail.Data!, message) : detail;
    }

    private static (string Key, string Label)[] Requestable(string tab) => tab switch
    {
        "city" => [.. DriverDocs, .. VehicleDocs],
        "tour" or "rent" => [.. VehicleDocs, .. DriverDocs],
        _ => [],
    };

    private static string Label(string key) =>
        DriverDocs.Concat(VehicleDocs).FirstOrDefault(d => d.Key == key).Label ?? key;

    private static string? Clean(string? note)
    {
        var text = note?.Trim();
        if (string.IsNullOrEmpty(text)) return null;
        return text.Length > 1000 ? text[..1000] : text;
    }

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken ct)
    {
        var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        return connection;
    }

    private static ServiceResult<T> Fail<T>(int status, string code, string message) =>
        ServiceResult<T>.Fail(status, code, message);
}
