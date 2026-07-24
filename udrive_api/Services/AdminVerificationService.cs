using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

public sealed class AdminVerificationService(string connectionString)
{
    private static readonly HashSet<string> DriverDecisions =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "UnderReview",
            "ChangesRequired",
            "Approved",
            "Rejected",
            "Suspended"
        };

    private static readonly HashSet<string> VehicleDecisions =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "PendingReview",
            "ChangesRequired",
            "Verified",
            "Suspended",
            "Expired"
        };

    public async Task<ServiceResult<IReadOnlyList<DriverReviewListItemDto>>> GetDriversAsync(
        string? status,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT dp.id, u.id, u.full_name, u.phone_number,
                   dp.verification_status, dp.cnic_number_masked,
                   dp.driving_licence_number_masked, dp.submitted_at,
                   (SELECT count(*) FROM udrive.driver_documents dd WHERE dd.driver_profile_id = dp.id),
                   (SELECT count(*) FROM udrive.vehicles v WHERE v.driver_profile_id = dp.id)
            FROM udrive.driver_profiles dp
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE (@status IS NULL OR dp.verification_status = @status)
            ORDER BY dp.submitted_at NULLS LAST, dp.created_at DESC;
            """;

        var result = new List<DriverReviewListItemDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        var statusParameter = command.Parameters.Add("status", NpgsqlDbType.Varchar);
        statusParameter.Value = string.IsNullOrWhiteSpace(status) ? DBNull.Value : status.Trim();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(new DriverReviewListItemDto(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetString(6),
                reader.IsDBNull(7) ? null : reader.GetFieldValue<DateTimeOffset>(7),
                Convert.ToInt32(reader.GetInt64(8)),
                Convert.ToInt32(reader.GetInt64(9))));
        }
        return ServiceResult<IReadOnlyList<DriverReviewListItemDto>>.Ok(result);
    }

    public async Task<ServiceResult<DriverReviewDetailDto>> GetDriverDetailAsync(
        Guid driverProfileId,
        CancellationToken cancellationToken)
    {
        const string driverSql = """
            SELECT dp.id, u.id, u.full_name, u.phone_number,
                   dp.verification_status, dp.cnic_number_masked,
                   dp.driving_licence_number_masked, dp.submitted_at,
                   (SELECT count(*) FROM udrive.driver_documents dd WHERE dd.driver_profile_id = dp.id),
                   (SELECT count(*) FROM udrive.vehicles v WHERE v.driver_profile_id = dp.id),
                   dp.date_of_birth, dp.residential_address,
                   dp.emergency_contact_name, dp.emergency_contact_phone,
                   dp.bank_account_title, dp.payout_method, dp.payout_account_masked,
                   dp.languages, dp.service_areas, dp.reviewed_at, dp.review_notes
            FROM udrive.driver_profiles dp
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE dp.id = @id
            LIMIT 1;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(driverSql, connection);
        command.Parameters.AddWithValue("id", driverProfileId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<DriverReviewDetailDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "Driver application not found.");
        }

        var listItem = new DriverReviewListItemDto(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetString(4),
            reader.IsDBNull(5) ? null : reader.GetString(5),
            reader.IsDBNull(6) ? null : reader.GetString(6),
            reader.IsDBNull(7) ? null : reader.GetFieldValue<DateTimeOffset>(7),
            Convert.ToInt32(reader.GetInt64(8)),
            Convert.ToInt32(reader.GetInt64(9)));

        var profile = new DriverOnboardingDto(
            reader.GetGuid(0),
            reader.GetString(4),
            reader.IsDBNull(5) ? null : reader.GetString(5),
            reader.IsDBNull(6) ? null : reader.GetString(6),
            reader.IsDBNull(10) ? null : reader.GetFieldValue<DateOnly>(10),
            reader.IsDBNull(11) ? null : reader.GetString(11),
            reader.IsDBNull(12) ? null : reader.GetString(12),
            reader.IsDBNull(13) ? null : reader.GetString(13),
            reader.IsDBNull(14) ? null : reader.GetString(14),
            reader.IsDBNull(15) ? null : reader.GetString(15),
            reader.IsDBNull(16) ? null : reader.GetString(16),
            reader.IsDBNull(17) ? [] : reader.GetFieldValue<string[]>(17),
            reader.IsDBNull(18) ? [] : reader.GetFieldValue<string[]>(18),
            reader.IsDBNull(7) ? null : reader.GetFieldValue<DateTimeOffset>(7),
            reader.IsDBNull(19) ? null : reader.GetFieldValue<DateTimeOffset>(19),
            reader.IsDBNull(20) ? null : reader.GetString(20));
        await reader.CloseAsync();

        var documents = new List<DriverDocumentDto>();
        await using (var documentCommand = new NpgsqlCommand("""
            SELECT id, document_type, file_url, expiry_date, status, review_notes
            FROM udrive.driver_documents
            WHERE driver_profile_id = @id
            ORDER BY document_type;
            """, connection))
        {
            documentCommand.Parameters.AddWithValue("id", driverProfileId);
            await using var documentReader = await documentCommand.ExecuteReaderAsync(cancellationToken);
            while (await documentReader.ReadAsync(cancellationToken))
            {
                documents.Add(new DriverDocumentDto(
                    documentReader.GetGuid(0),
                    documentReader.GetString(1),
                    documentReader.GetString(2),
                    documentReader.IsDBNull(3) ? null : documentReader.GetFieldValue<DateOnly>(3),
                    documentReader.GetString(4),
                    documentReader.IsDBNull(5) ? null : documentReader.GetString(5)));
            }
        }

        var vehicles = new List<VehicleReviewListItemDto>();
        await using (var vehicleCommand = new NpgsqlCommand("""
            SELECT v.id, v.driver_profile_id, u.full_name,
                   v.registration_number, v.make || ' ' || v.model,
                   v.status, v.mountain_readiness_score,
                   (SELECT count(*) FROM udrive.vehicle_documents vd WHERE vd.vehicle_id = v.id)
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE v.driver_profile_id = @id
            ORDER BY v.created_at DESC;
            """, connection))
        {
            vehicleCommand.Parameters.AddWithValue("id", driverProfileId);
            await using var vehicleReader = await vehicleCommand.ExecuteReaderAsync(cancellationToken);
            while (await vehicleReader.ReadAsync(cancellationToken))
            {
                vehicles.Add(new VehicleReviewListItemDto(
                    vehicleReader.GetGuid(0),
                    vehicleReader.GetGuid(1),
                    vehicleReader.GetString(2),
                    vehicleReader.GetString(3),
                    vehicleReader.GetString(4),
                    vehicleReader.GetString(5),
                    vehicleReader.GetInt32(6),
                    Convert.ToInt32(vehicleReader.GetInt64(7))));
            }
        }

        return ServiceResult<DriverReviewDetailDto>.Ok(
            new DriverReviewDetailDto(listItem, profile, documents, vehicles));
    }

    public async Task<ServiceResult<bool>> ReviewDriverAsync(
        Guid adminUserId,
        Guid driverProfileId,
        VerificationReviewRequest request,
        string? ipAddress,
        CancellationToken cancellationToken)
    {
        if (!DriverDecisions.Contains(request.Decision))
        {
            return ServiceResult<bool>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_driver_decision",
                $"Decision must be one of: {string.Join(", ", DriverDecisions)}.");
        }

        const string updateSql = """
            UPDATE udrive.driver_profiles
            SET verification_status = @decision,
                reviewed_at = now(),
                reviewed_by_user_id = @adminUserId,
                review_notes = @notes,
                updated_at = now()
            WHERE id = @driverProfileId
            RETURNING user_id;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        if (string.Equals(request.Decision, "Approved", StringComparison.OrdinalIgnoreCase))
        {
            await using var readinessCommand = new NpgsqlCommand("""
                SELECT
                    (SELECT count(DISTINCT document_type)
                     FROM udrive.driver_documents
                     WHERE driver_profile_id = @driverProfileId
                       AND document_type IN ('CNIC_FRONT','CNIC_BACK','DRIVING_LICENCE','SELFIE')),
                    EXISTS(
                        SELECT 1 FROM udrive.vehicles
                        WHERE driver_profile_id = @driverProfileId AND status = 'Verified');
                """, connection, transaction);
            readinessCommand.Parameters.AddWithValue("driverProfileId", driverProfileId);
            await using var readinessReader = await readinessCommand.ExecuteReaderAsync(cancellationToken);
            await readinessReader.ReadAsync(cancellationToken);
            var documentCount = Convert.ToInt32(readinessReader.GetInt64(0));
            var hasVerifiedVehicle = readinessReader.GetBoolean(1);
            await readinessReader.CloseAsync();
            if (documentCount < 4 || !hasVerifiedVehicle)
            {
                await transaction.RollbackAsync(cancellationToken);
                return ServiceResult<bool>.Fail(
                    StatusCodes.Status400BadRequest,
                    "driver_not_ready_for_approval",
                    "Verify all four required driver documents and at least one vehicle before approving the driver.");
            }
        }

        Guid? driverUserId;
        await using (var updateCommand = new NpgsqlCommand(updateSql, connection, transaction))
        {
            updateCommand.Parameters.AddWithValue("decision", NormalizeDecision(request.Decision, DriverDecisions));
            updateCommand.Parameters.AddWithValue("adminUserId", adminUserId);
            updateCommand.Parameters.AddWithValue("notes", (object?)request.Notes?.Trim() ?? DBNull.Value);
            updateCommand.Parameters.AddWithValue("driverProfileId", driverProfileId);
            var value = await updateCommand.ExecuteScalarAsync(cancellationToken);
            driverUserId = value is Guid id ? id : null;
        }

        if (driverUserId is null)
        {
            await transaction.RollbackAsync(cancellationToken);
            return ServiceResult<bool>.Fail(
                StatusCodes.Status404NotFound,
                "driver_not_found",
                "Driver application not found.");
        }

        if (string.Equals(request.Decision, "Approved", StringComparison.OrdinalIgnoreCase))
        {
            await using var roleCommand = new NpgsqlCommand("""
                INSERT INTO udrive.user_roles (user_id, role, created_at)
                VALUES (@userId, 'Driver', now())
                ON CONFLICT (user_id, role) DO NOTHING;
                UPDATE udrive.users
                SET role = 'Driver', token_version = token_version + 1, updated_at = now()
                WHERE id = @userId;
                """, connection, transaction);
            roleCommand.Parameters.AddWithValue("userId", driverUserId.Value);
            await roleCommand.ExecuteNonQueryAsync(cancellationToken);

            await using var documentsCommand = new NpgsqlCommand("""
                UPDATE udrive.driver_documents
                SET status = 'Verified', review_notes = @notes, updated_at = now()
                WHERE driver_profile_id = @driverProfileId;
                """, connection, transaction);
            documentsCommand.Parameters.AddWithValue("notes", (object?)request.Notes?.Trim() ?? DBNull.Value);
            documentsCommand.Parameters.AddWithValue("driverProfileId", driverProfileId);
            await documentsCommand.ExecuteNonQueryAsync(cancellationToken);
        }
        else
        {
            var removeDriverRole = string.Equals(request.Decision, "Rejected", StringComparison.OrdinalIgnoreCase)
                || string.Equals(request.Decision, "Suspended", StringComparison.OrdinalIgnoreCase);
            await using var versionCommand = new NpgsqlCommand(removeDriverRole
                ? """
                    DELETE FROM udrive.user_roles
                    WHERE user_id = @userId AND role = 'Driver';
                    UPDATE udrive.users
                    SET role = CASE WHEN role = 'Driver' THEN 'Customer' ELSE role END,
                        token_version = token_version + 1,
                        updated_at = now()
                    WHERE id = @userId;
                    """
                : """
                    UPDATE udrive.users
                    SET token_version = token_version + 1, updated_at = now()
                    WHERE id = @userId;
                    """, connection, transaction);
            versionCommand.Parameters.AddWithValue("userId", driverUserId.Value);
            await versionCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await InsertAuditAsync(
            connection,
            transaction,
            adminUserId,
            "ReviewDriver",
            "DriverProfile",
            driverProfileId,
            request.Decision,
            request.Notes,
            ipAddress,
            cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<bool>.Ok(true, "Driver verification status updated.");
    }

    public async Task<ServiceResult<IReadOnlyList<VehicleReviewListItemDto>>> GetVehiclesAsync(
        string? status,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT v.id, v.driver_profile_id, u.full_name,
                   v.registration_number, v.make || ' ' || v.model,
                   v.status, v.mountain_readiness_score,
                   (SELECT count(*) FROM udrive.vehicle_documents vd WHERE vd.vehicle_id = v.id)
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE (@status IS NULL OR v.status = @status)
            ORDER BY v.created_at DESC;
            """;
        var result = new List<VehicleReviewListItemDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        var statusParameter = command.Parameters.Add("status", NpgsqlDbType.Varchar);
        statusParameter.Value = string.IsNullOrWhiteSpace(status) ? DBNull.Value : status.Trim();
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(new VehicleReviewListItemDto(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetString(4),
                reader.GetString(5),
                reader.GetInt32(6),
                Convert.ToInt32(reader.GetInt64(7))));
        }
        return ServiceResult<IReadOnlyList<VehicleReviewListItemDto>>.Ok(result);
    }

    public async Task<ServiceResult<VehicleReviewDetailDto>> GetVehicleDetailAsync(
        Guid vehicleId,
        CancellationToken cancellationToken)
    {
        const string vehicleSql = """
            SELECT v.id, v.driver_profile_id, u.full_name,
                   v.registration_number, v.make || ' ' || v.model,
                   v.status, v.mountain_readiness_score,
                   (SELECT count(*) FROM udrive.vehicle_documents vd WHERE vd.vehicle_id = v.id)
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE v.id = @id
            LIMIT 1;
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(vehicleSql, connection);
        command.Parameters.AddWithValue("id", vehicleId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<VehicleReviewDetailDto>.Fail(
                StatusCodes.Status404NotFound,
                "vehicle_not_found",
                "Vehicle not found.");
        }

        var item = new VehicleReviewListItemDto(
            reader.GetGuid(0),
            reader.GetGuid(1),
            reader.GetString(2),
            reader.GetString(3),
            reader.GetString(4),
            reader.GetString(5),
            reader.GetInt32(6),
            Convert.ToInt32(reader.GetInt64(7)));
        await reader.CloseAsync();

        var documents = new List<VehicleDocumentDto>();
        await using var documentCommand = new NpgsqlCommand("""
            SELECT id, document_type, file_url, expiry_date, status, review_notes
            FROM udrive.vehicle_documents
            WHERE vehicle_id = @id
            ORDER BY document_type;
            """, connection);
        documentCommand.Parameters.AddWithValue("id", vehicleId);
        await using var documentReader = await documentCommand.ExecuteReaderAsync(cancellationToken);
        while (await documentReader.ReadAsync(cancellationToken))
        {
            documents.Add(new VehicleDocumentDto(
                documentReader.GetGuid(0),
                documentReader.GetString(1),
                documentReader.GetString(2),
                documentReader.IsDBNull(3) ? null : documentReader.GetFieldValue<DateOnly>(3),
                documentReader.GetString(4),
                documentReader.IsDBNull(5) ? null : documentReader.GetString(5)));
        }

        return ServiceResult<VehicleReviewDetailDto>.Ok(new VehicleReviewDetailDto(item, documents));
    }

    public async Task<ServiceResult<bool>> ReviewVehicleAsync(
        Guid adminUserId,
        Guid vehicleId,
        VerificationReviewRequest request,
        string? ipAddress,
        CancellationToken cancellationToken)
    {
        if (!VehicleDecisions.Contains(request.Decision))
        {
            return ServiceResult<bool>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_vehicle_decision",
                $"Decision must be one of: {string.Join(", ", VehicleDecisions)}.");
        }

        const string updateSql = """
            UPDATE udrive.vehicles
            SET status = @decision, updated_at = now()
            WHERE id = @vehicleId;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        if (string.Equals(request.Decision, "Verified", StringComparison.OrdinalIgnoreCase))
        {
            await using var readinessCommand = new NpgsqlCommand("""
                SELECT count(DISTINCT document_type)
                FROM udrive.vehicle_documents
                WHERE vehicle_id = @vehicleId
                  AND document_type IN ('REGISTRATION_BOOK','VEHICLE_FRONT','VEHICLE_REAR','VEHICLE_INTERIOR');
                """, connection, transaction);
            readinessCommand.Parameters.AddWithValue("vehicleId", vehicleId);
            var documentCount = Convert.ToInt32((long)(await readinessCommand.ExecuteScalarAsync(cancellationToken) ?? 0L));
            if (documentCount < 4)
            {
                await transaction.RollbackAsync(cancellationToken);
                return ServiceResult<bool>.Fail(
                    StatusCodes.Status400BadRequest,
                    "vehicle_not_ready_for_verification",
                    "All four required vehicle documents and photographs must be uploaded before verification.");
            }
        }

        await using (var command = new NpgsqlCommand(updateSql, connection, transaction))
        {
            command.Parameters.AddWithValue("decision", NormalizeDecision(request.Decision, VehicleDecisions));
            command.Parameters.AddWithValue("vehicleId", vehicleId);
            var affected = await command.ExecuteNonQueryAsync(cancellationToken);
            if (affected == 0)
            {
                await transaction.RollbackAsync(cancellationToken);
                return ServiceResult<bool>.Fail(
                    StatusCodes.Status404NotFound,
                    "vehicle_not_found",
                    "Vehicle not found.");
            }
        }

        await using (var documentCommand = new NpgsqlCommand("""
            UPDATE udrive.vehicle_documents
            SET status = @documentStatus,
                review_notes = @notes,
                updated_at = now()
            WHERE vehicle_id = @vehicleId;
            """, connection, transaction))
        {
            var documentStatus = string.Equals(request.Decision, "Verified", StringComparison.OrdinalIgnoreCase)
                ? "Verified"
                : NormalizeDecision(request.Decision, VehicleDecisions);
            documentCommand.Parameters.AddWithValue("documentStatus", documentStatus);
            documentCommand.Parameters.AddWithValue("notes", (object?)request.Notes?.Trim() ?? DBNull.Value);
            documentCommand.Parameters.AddWithValue("vehicleId", vehicleId);
            await documentCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await InsertAuditAsync(
            connection,
            transaction,
            adminUserId,
            "ReviewVehicle",
            "Vehicle",
            vehicleId,
            request.Decision,
            request.Notes,
            ipAddress,
            cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<bool>.Ok(true, "Vehicle verification status updated.");
    }

    private static string NormalizeDecision(string decision, HashSet<string> allowed)
    {
        return allowed.First(value => string.Equals(value, decision, StringComparison.OrdinalIgnoreCase));
    }

    private static async Task InsertAuditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid actorUserId,
        string action,
        string entityType,
        Guid entityId,
        string decision,
        string? notes,
        string? ipAddress,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.audit_logs
                (id, actor_user_id, action, entity_type, entity_id,
                 ip_address, changes_json, created_at, updated_at)
            VALUES
                (@id, @actor, @action, @entityType, @entityId,
                 @ip, jsonb_build_object('decision', @decision, 'notes', @notes),
                 now(), now());
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("id", Guid.NewGuid());
        command.Parameters.AddWithValue("actor", actorUserId);
        command.Parameters.AddWithValue("action", action);
        command.Parameters.AddWithValue("entityType", entityType);
        command.Parameters.AddWithValue("entityId", entityId.ToString());
        command.Parameters.AddWithValue("ip", (object?)ipAddress ?? DBNull.Value);
        command.Parameters.AddWithValue("decision", decision);
        command.Parameters.AddWithValue("notes", (object?)notes ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
