using Npgsql;
using UDrive.Api.Common;

namespace UDrive.Api.Services;

/// <summary>
/// Self-service account deletion, required by Google Play for any app that
/// lets people create an account.
///
/// What "deleted" means here:
///  * the person can no longer sign in, and every session ends at once
///    (token_version bump + refresh tokens revoked);
///  * name, phone, email, trusted contacts, profile photo, and the driver's
///    CNIC / licence numbers, date of birth, address, emergency contact and
///    payout details are erased or replaced with placeholders;
///  * the phone number is released, so the same number can sign up again as a
///    brand-new account;
///  * every uploaded identity document — CNIC, licence, selfie, selfie with
///    CNIC, registration book, vehicle photographs, wallet top-up screenshots —
///    is deleted from storage, along with the rows that point at it;
///  * trip, payment, wallet and audit rows are kept, now pointing at an
///    anonymous user, because finance, tax and safety investigations need them.
///    The privacy policy states this retention.
///
/// The document deletion is the part that used to be missing. Numbers were
/// nulled but the photographs of the CNIC and the licence stayed on the volume
/// indefinitely, which is the opposite of what the deletion page promised — and
/// an identity document is exactly the thing somebody deleting their account
/// most wants gone.
///
/// A person with a live ride cannot delete mid-trip: the other party and the
/// safety team still need to reach them.
/// </summary>
public sealed class AccountDeletionService(string connectionString, LocalFileStorageService files)
{
    private static readonly string[] LiveTripStatuses =
        ["DriverAccepted", "DriverEnRoute", "DriverArrived", "TripStarted", "Emergency"];

    /// <param name="actorUserId">Who asked: the user themself, or the admin
    /// handling an emailed request from the public deletion page.</param>
    public async Task<ServiceResult<bool>> DeleteAsync(
        Guid userId,
        Guid actorUserId,
        string? reason,
        string? ipAddress,
        CancellationToken cancellationToken)
    {
        var action = actorUserId == userId ? "AccountDeletedBySelf" : "AccountDeletedByAdmin";
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        // Lock the user row so two taps (or two devices) cannot race.
        await using (var lockCommand = new NpgsqlCommand(
            "SELECT status FROM udrive.users WHERE id = @u FOR UPDATE;", connection, transaction))
        {
            lockCommand.Parameters.AddWithValue("u", userId);
            var status = await lockCommand.ExecuteScalarAsync(cancellationToken) as string;
            if (status is null)
            {
                return ServiceResult<bool>.Fail(
                    StatusCodes.Status404NotFound, "user_not_found", "The account could not be found.");
            }
            if (status == "Deleted")
            {
                return ServiceResult<bool>.Ok(true, "This account has already been deleted.");
            }
        }

        await using (var liveCommand = new NpgsqlCommand("""
            SELECT EXISTS (
                SELECT 1
                FROM udrive.bookings b
                JOIN udrive.trip_operations o ON o.booking_id = b.id
                LEFT JOIN udrive.driver_profiles dp ON dp.id = b.driver_profile_id
                WHERE (b.customer_user_id = @u OR dp.user_id = @u)
                  AND o.trip_status = ANY(@live)
            );
            """, connection, transaction))
        {
            liveCommand.Parameters.AddWithValue("u", userId);
            liveCommand.Parameters.AddWithValue("live", LiveTripStatuses);
            if ((bool)(await liveCommand.ExecuteScalarAsync(cancellationToken) ?? false))
            {
                return ServiceResult<bool>.Fail(
                    StatusCodes.Status409Conflict,
                    "live_trip_in_progress",
                    "Finish or cancel your current ride before deleting your account.");
            }
        }

        // Order matters only for readability; everything is one transaction.
        string[] statements =
        [
            """
            UPDATE udrive.users
               SET phone_number = 'deleted:' || left(replace(id::text, '-', ''), 15),
                   full_name = 'Deleted user',
                   email = NULL,
                   status = 'Deleted',
                   phone_verified = false,
                   token_version = token_version + 1,
                   updated_at = now()
             WHERE id = @u;
            """,
            """
            UPDATE udrive.refresh_tokens
               SET revoked_at = now()
             WHERE user_id = @u AND revoked_at IS NULL;
            """,
            "DELETE FROM udrive.trusted_contacts WHERE user_id = @u;",
            """
            UPDATE udrive.customer_profiles
               SET profile_image_url = NULL, emergency_notes = NULL, updated_at = now()
             WHERE user_id = @u;
            """,
            """
            UPDATE udrive.driver_profiles
               SET is_online = false,
                   cnic_number = NULL,
                   cnic_number_hash = NULL,
                   cnic_number_masked = NULL,
                   driving_licence_number = NULL,
                   driving_licence_number_hash = NULL,
                   driving_licence_number_masked = NULL,
                   driving_licence_expiry = NULL,
                   date_of_birth = NULL,
                   residential_address = NULL,
                   emergency_contact_name = NULL,
                   emergency_contact_phone = NULL,
                   bank_account_title = NULL,
                   payout_method = NULL,
                   payout_account_masked = NULL,
                   updated_at = now()
             WHERE user_id = @u;
            """,
            // The document rows themselves. The files they point at are deleted
            // from the volume after this transaction commits — see below.
            """
            DELETE FROM udrive.driver_documents
             WHERE driver_profile_id IN (SELECT id FROM udrive.driver_profiles WHERE user_id = @u);
            """,
            """
            DELETE FROM udrive.vehicle_documents
             WHERE vehicle_id IN (
                   SELECT v.id FROM udrive.vehicles v
                    JOIN udrive.driver_profiles p ON p.id = v.driver_profile_id
                   WHERE p.user_id = @u);
            """,
            // Bank details held separately from the driver profile.
            """
            DELETE FROM udrive.driver_payout_accounts
             WHERE driver_profile_id IN (SELECT id FROM udrive.driver_profiles WHERE user_id = @u);
            """,
            // The top-up rows stay — they are money that moved — but the
            // screenshot of somebody's payment app is personal, so the link
            // goes and the image is deleted with the rest.
            """
            UPDATE udrive.driver_wallet_topups
               SET screenshot_url = NULL, updated_at = now()
             WHERE driver_profile_id IN (SELECT id FROM udrive.driver_profiles WHERE user_id = @u);
            """,
            // Last known position. Neither of these is covered by the 30-day
            // purge that clears the trip trail, so without this a deleted
            // driver's last location would sit in the database forever.
            """
            DELETE FROM udrive.driver_presence_locations
             WHERE driver_profile_id IN (SELECT id FROM udrive.driver_profiles WHERE user_id = @u);
            """,
            """
            DELETE FROM udrive.driver_latest_locations
             WHERE driver_profile_id IN (SELECT id FROM udrive.driver_profiles WHERE user_id = @u);
            """,
            """
            UPDATE udrive.vehicles
               SET status = 'Deleted', updated_at = now()
             WHERE status <> 'Deleted'
               AND driver_profile_id IN (SELECT id FROM udrive.driver_profiles WHERE user_id = @u);
            """,
            """
            INSERT INTO udrive.audit_logs
                (id, actor_user_id, action, entity_type, entity_id, ip_address, changes_json, created_at, updated_at)
            VALUES
                (gen_random_uuid(), @actor, @action, 'User', CAST(@u AS text), @ip,
                 jsonb_build_object('reason', NULLIF(@reason, '')), now(), now());
            """
        ];

        // Read the file paths before the rows that hold them are deleted, and
        // delete the files themselves only after the transaction commits. The
        // other order loses either the paths or the files: a rollback after
        // erasing images would leave rows pointing at nothing.
        var storedFiles = await CollectUploadedFilesAsync(connection, transaction, userId, cancellationToken);

        var cleanReason = (reason ?? string.Empty).Trim();
        if (cleanReason.Length > 500) cleanReason = cleanReason[..500];

        foreach (var sql in statements)
        {
            await using var command = new NpgsqlCommand(sql, connection, transaction);
            command.Parameters.AddWithValue("u", userId);
            if (sql.Contains("@ip"))
            {
                command.Parameters.AddWithValue("ip", (object?)ipAddress ?? DBNull.Value);
                command.Parameters.AddWithValue("reason", cleanReason);
                command.Parameters.AddWithValue("actor", actorUserId);
                command.Parameters.AddWithValue("action", action);
            }
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);

        // Best effort, and deliberately after the commit. A file that cannot be
        // removed — a permission problem, a volume that is not mounted — must
        // not undo a deletion the person has already been told succeeded; it is
        // an operational fault to fix, not a reason to give them their account
        // back. DeleteProtectedFiles swallows per-file errors and reports a
        // count.
        files.DeleteProtectedFiles(storedFiles);

        return ServiceResult<bool>.Ok(true, "Your account has been deleted.");
    }

    /// <summary>
    /// Every file this person uploaded, as the stored URLs the file service
    /// understands.
    /// </summary>
    /// <remarks>
    /// Dispute evidence is not in this list on purpose. It belongs to a case
    /// that has another party to it, and removing one side's evidence would
    /// quietly rewrite a dispute somebody else is still relying on.
    /// </remarks>
    private static async Task<List<string>> CollectUploadedFilesAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT d.file_url
              FROM udrive.driver_documents d
              JOIN udrive.driver_profiles p ON p.id = d.driver_profile_id
             WHERE p.user_id = @u AND d.file_url IS NOT NULL
            UNION ALL
            SELECT vd.file_url
              FROM udrive.vehicle_documents vd
              JOIN udrive.vehicles v ON v.id = vd.vehicle_id
              JOIN udrive.driver_profiles p ON p.id = v.driver_profile_id
             WHERE p.user_id = @u AND vd.file_url IS NOT NULL
            UNION ALL
            SELECT t.screenshot_url
              FROM udrive.driver_wallet_topups t
              JOIN udrive.driver_profiles p ON p.id = t.driver_profile_id
             WHERE p.user_id = @u AND t.screenshot_url IS NOT NULL
            UNION ALL
            -- The customer's own profile photo. It was missing from this union,
            -- so the column was nulled a few lines above while the file stayed
            -- on the volume for good — and both the deletion page and the app's
            -- own confirmation screen tell the person their profile photo is
            -- deleted. Nothing writes that column from the app today, so no such
            -- file exists yet; it is here now so the gap does not ship with the
            -- upload feature whenever that arrives. Exactly the trap the CNIC
            -- photos fell into once already.
            SELECT cp.profile_image_url
              FROM udrive.customer_profiles cp
             WHERE cp.user_id = @u AND cp.profile_image_url IS NOT NULL;
            """;

        var urls = new List<string>();
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("u", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            if (!reader.IsDBNull(0))
            {
                urls.Add(reader.GetString(0));
            }
        }

        return urls;
    }
}
