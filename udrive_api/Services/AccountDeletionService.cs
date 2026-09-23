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
///  * trip, payment, wallet and audit rows are kept, now pointing at an
///    anonymous user, because finance, tax and safety investigations need them.
///    The privacy policy states this retention.
///
/// A person with a live ride cannot delete mid-trip: the other party and the
/// safety team still need to reach them.
/// </summary>
public sealed class AccountDeletionService(string connectionString)
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
                   driving_licence_number = NULL,
                   driving_licence_number_hash = NULL,
                   date_of_birth = NULL,
                   residential_address = NULL,
                   emergency_contact_name = NULL,
                   emergency_contact_phone = NULL,
                   bank_account_title = NULL,
                   payout_account_masked = NULL,
                   updated_at = now()
             WHERE user_id = @u;
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
        return ServiceResult<bool>.Ok(true, "Your account has been deleted.");
    }
}
