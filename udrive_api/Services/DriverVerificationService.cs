using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;

namespace UDrive.Api.Services;

public sealed class DriverVerificationService(
    string connectionString,
    AuthOptions authOptions,
    LocalFileStorageService fileStorage)
{
    private static readonly HashSet<string> RequiredDriverDocuments =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "CNIC_FRONT",
            "CNIC_BACK",
            "DRIVING_LICENCE",
            "SELFIE"
        };

    private static readonly HashSet<string> RequiredVehicleDocuments =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "REGISTRATION_BOOK",
            "VEHICLE_FRONT",
            "VEHICLE_REAR",
            "VEHICLE_INTERIOR"
        };

    private static readonly HashSet<string> AllowedVehicleDocuments =
        new(RequiredVehicleDocuments, StringComparer.OrdinalIgnoreCase)
        {
            "INSURANCE",
            "FITNESS_CERTIFICATE"
        };

    public async Task<ServiceResult<DriverOnboardingDto>> GetOnboardingAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        var profile = await GetDriverProfileAsync(userId, cancellationToken);
        return profile is null
            ? ServiceResult<DriverOnboardingDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_profile_not_found",
                "Driver registration has not been started.")
            : ServiceResult<DriverOnboardingDto>.Ok(profile);
    }

    public async Task<ServiceResult<DriverOnboardingDto>> SaveOnboardingAsync(
        Guid userId,
        DriverOnboardingRequest request,
        CancellationToken cancellationToken)
    {
        var existingProfile = await GetDriverProfileAsync(userId, cancellationToken);
        if (existingProfile?.VerificationStatus is "Approved" or "Suspended")
        {
            return ServiceResult<DriverOnboardingDto>.Fail(
                StatusCodes.Status409Conflict,
                "approved_profile_locked",
                "An approved or suspended Driver profile cannot be edited. Ask an Admin to request changes first.");
        }

        var normalizedCnic = new string(request.CnicNumber.Where(char.IsDigit).ToArray());
        if (normalizedCnic.Length != 13)
        {
            return ServiceResult<DriverOnboardingDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_cnic",
                "CNIC must contain exactly 13 digits.");
        }

        if (!PhoneNumberNormalizer.TryNormalizePakistan(
                request.EmergencyContactPhone,
                out var emergencyPhone))
        {
            return ServiceResult<DriverOnboardingDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_emergency_phone",
                "Enter a valid emergency contact mobile number.");
        }

        var licence = request.DrivingLicenceNumber.Trim().ToUpperInvariant();
        var cnicHash = SecurityHashing.HashWithSecret(normalizedCnic, authOptions.IdentityHashSecret);
        var licenceHash = SecurityHashing.HashWithSecret(licence, authOptions.IdentityHashSecret);
        var payoutMasked = SecurityHashing.MaskAccount(request.PayoutAccount);
        var languages = SanitizeArray(request.Languages, 8);
        var serviceAreas = SanitizeArray(request.ServiceAreas, 16);

        const string sql = """
            INSERT INTO udrive.driver_profiles
                (id, user_id, cnic_number_masked, driving_licence_number_masked,
                 cnic_number_hash, driving_licence_number_hash, verification_status,
                 average_rating, completed_trips, safety_score, languages, service_areas,
                 is_online, date_of_birth, residential_address,
                 emergency_contact_name, emergency_contact_phone, bank_account_title,
                 payout_method, payout_account_masked, created_at, updated_at)
            VALUES
                (@id, @userId, @cnicMasked, @licenceMasked, @cnicHash, @licenceHash,
                 'Draft', 0, 0, 80, @languages, @serviceAreas, false, @dob, @address,
                 @emergencyName, @emergencyPhone, @bankTitle, @payoutMethod,
                 @payoutMasked, now(), now())
            ON CONFLICT (user_id) DO UPDATE SET
                cnic_number_masked = EXCLUDED.cnic_number_masked,
                driving_licence_number_masked = EXCLUDED.driving_licence_number_masked,
                cnic_number_hash = EXCLUDED.cnic_number_hash,
                driving_licence_number_hash = EXCLUDED.driving_licence_number_hash,
                date_of_birth = EXCLUDED.date_of_birth,
                residential_address = EXCLUDED.residential_address,
                emergency_contact_name = EXCLUDED.emergency_contact_name,
                emergency_contact_phone = EXCLUDED.emergency_contact_phone,
                bank_account_title = EXCLUDED.bank_account_title,
                payout_method = EXCLUDED.payout_method,
                payout_account_masked = EXCLUDED.payout_account_masked,
                languages = EXCLUDED.languages,
                service_areas = EXCLUDED.service_areas,
                verification_status = CASE
                    WHEN udrive.driver_profiles.verification_status IN ('Approved', 'Suspended')
                    THEN udrive.driver_profiles.verification_status
                    ELSE 'Draft'
                END,
                updated_at = now()
            RETURNING id;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        await using (var command = new NpgsqlCommand(sql, connection, transaction))
        {
            command.Parameters.AddWithValue("id", Guid.NewGuid());
            command.Parameters.AddWithValue("userId", userId);
            command.Parameters.AddWithValue("cnicMasked", SecurityHashing.MaskCnic(normalizedCnic));
            command.Parameters.AddWithValue("licenceMasked", SecurityHashing.MaskLicence(licence));
            command.Parameters.AddWithValue("cnicHash", cnicHash);
            command.Parameters.AddWithValue("licenceHash", licenceHash);
            command.Parameters.AddWithValue("languages", languages);
            command.Parameters.AddWithValue("serviceAreas", serviceAreas);
            command.Parameters.AddWithValue("dob", (object?)request.DateOfBirth ?? DBNull.Value);
            command.Parameters.AddWithValue("address", request.Address.Trim());
            command.Parameters.AddWithValue("emergencyName", request.EmergencyContactName.Trim());
            command.Parameters.AddWithValue("emergencyPhone", emergencyPhone);
            command.Parameters.AddWithValue("bankTitle", (object?)request.BankAccountTitle?.Trim() ?? DBNull.Value);
            command.Parameters.AddWithValue("payoutMethod", (object?)request.PayoutMethod?.Trim() ?? DBNull.Value);
            command.Parameters.AddWithValue("payoutMasked", string.IsNullOrWhiteSpace(payoutMasked) ? DBNull.Value : payoutMasked);
            await command.ExecuteScalarAsync(cancellationToken);
        }

        await using (var userCommand = new NpgsqlCommand("""
            UPDATE udrive.users
            SET full_name = @name, updated_at = now()
            WHERE id = @userId;
            """, connection, transaction))
        {
            userCommand.Parameters.AddWithValue("name", request.FullName.Trim());
            userCommand.Parameters.AddWithValue("userId", userId);
            await userCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        var profile = await GetDriverProfileAsync(userId, cancellationToken)
            ?? throw new InvalidOperationException("Driver profile was not saved.");
        return ServiceResult<DriverOnboardingDto>.Ok(profile, "Driver registration saved.");
    }

    public async Task<ServiceResult<DriverDocumentDto>> UploadDriverDocumentAsync(
        Guid userId,
        string documentType,
        DateOnly? expiryDate,
        IFormFile file,
        CancellationToken cancellationToken)
    {
        var driverProfileId = await GetDriverProfileIdAsync(userId, cancellationToken);
        if (driverProfileId is null)
        {
            return ServiceResult<DriverDocumentDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_profile_not_found",
                "Complete driver registration before uploading documents.");
        }

        var profile = await GetDriverProfileAsync(userId, cancellationToken);
        if (profile?.VerificationStatus is "Approved" or "Suspended")
        {
            return ServiceResult<DriverDocumentDto>.Fail(
                StatusCodes.Status409Conflict,
                "approved_profile_locked",
                "Approved or suspended Driver documents cannot be replaced until an Admin requests changes.");
        }

        var normalizedType = NormalizeDocumentType(documentType);
        if (!RequiredDriverDocuments.Contains(normalizedType))
        {
            return ServiceResult<DriverDocumentDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_driver_document_type",
                $"Document type must be one of: {string.Join(", ", RequiredDriverDocuments)}.");
        }
        var stored = await fileStorage.SaveAsync(file, "driver-documents", driverProfileId.Value, cancellationToken);
        var id = Guid.NewGuid();
        const string sql = """
            INSERT INTO udrive.driver_documents
                (id, driver_profile_id, document_type, file_url, expiry_date,
                 status, created_at, updated_at)
            VALUES
                (@id, @driverId, @type, @url, @expiry, 'Submitted', now(), now())
            ON CONFLICT (driver_profile_id, document_type) DO UPDATE SET
                file_url = EXCLUDED.file_url,
                expiry_date = EXCLUDED.expiry_date,
                status = 'Submitted',
                review_notes = NULL,
                updated_at = now()
            RETURNING id;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("driverId", driverProfileId.Value);
        command.Parameters.AddWithValue("type", normalizedType);
        command.Parameters.AddWithValue("url", stored.RelativeUrl);
        command.Parameters.AddWithValue("expiry", (object?)expiryDate ?? DBNull.Value);
        var resultId = (Guid)(await command.ExecuteScalarAsync(cancellationToken) ?? id);
        return ServiceResult<DriverDocumentDto>.Created(new DriverDocumentDto(
            resultId,
            normalizedType,
            stored.RelativeUrl,
            expiryDate,
            "Submitted",
            null));
    }

    public async Task<ServiceResult<DriverOnboardingDto>> SubmitOnboardingAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        var driverProfileId = await GetDriverProfileIdAsync(userId, cancellationToken);
        if (driverProfileId is null)
        {
            return ServiceResult<DriverOnboardingDto>.Fail(
                StatusCodes.Status404NotFound,
                "driver_profile_not_found",
                "Complete driver registration first.");
        }

        var currentProfile = await GetDriverProfileAsync(userId, cancellationToken);
        if (currentProfile?.VerificationStatus is "Approved" or "Suspended")
        {
            return ServiceResult<DriverOnboardingDto>.Fail(
                StatusCodes.Status409Conflict,
                "driver_application_locked",
                "This Driver application is already approved or suspended.");
        }

        var documentTypes = await GetDocumentTypesAsync(
            "udrive.driver_documents",
            "driver_profile_id",
            driverProfileId.Value,
            cancellationToken);
        var missing = RequiredDriverDocuments.Except(documentTypes, StringComparer.OrdinalIgnoreCase).ToArray();
        if (missing.Length > 0)
        {
            return ServiceResult<DriverOnboardingDto>.Fail(
                StatusCodes.Status400BadRequest,
                "driver_documents_missing",
                $"Upload these required documents: {string.Join(", ", missing)}.");
        }

        const string sql = """
            UPDATE udrive.driver_profiles
            SET verification_status = 'Submitted', submitted_at = now(),
                review_notes = NULL, updated_at = now()
            WHERE id = @id
              AND verification_status NOT IN ('Approved', 'Suspended');
            """;
        await ExecuteAsync(sql, cancellationToken, ("id", driverProfileId.Value));
        var profile = await GetDriverProfileAsync(userId, cancellationToken)
            ?? throw new InvalidOperationException("Driver profile could not be loaded.");
        return ServiceResult<DriverOnboardingDto>.Ok(profile, "Driver application submitted for review.");
    }

    public async Task<ServiceResult<IReadOnlyList<DriverDocumentDto>>> GetDriverDocumentsAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        var driverProfileId = await GetDriverProfileIdAsync(userId, cancellationToken);
        if (driverProfileId is null)
        {
            return ServiceResult<IReadOnlyList<DriverDocumentDto>>.Ok([]);
        }

        const string sql = """
            SELECT id, document_type, file_url, expiry_date, status, review_notes
            FROM udrive.driver_documents
            WHERE driver_profile_id = @driverId
            ORDER BY document_type;
            """;
        var result = new List<DriverDocumentDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driverId", driverProfileId.Value);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(new DriverDocumentDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetFieldValue<DateOnly>(3),
                reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5)));
        }
        return ServiceResult<IReadOnlyList<DriverDocumentDto>>.Ok(result);
    }

    public async Task<ServiceResult<VehicleDto>> CreateVehicleAsync(
        Guid userId,
        VehicleUpsertRequest request,
        CancellationToken cancellationToken)
    {
        var driverProfileId = await GetDriverProfileIdAsync(userId, cancellationToken);
        if (driverProfileId is null)
        {
            return ServiceResult<VehicleDto>.Fail(
                StatusCodes.Status400BadRequest,
                "driver_profile_required",
                "Complete driver registration before adding a vehicle.");
        }

        var id = Guid.NewGuid();
        var readiness = CalculateMountainReadiness(request);
        const string sql = """
            INSERT INTO udrive.vehicles
                (id, driver_profile_id, category, make, model, year,
                 registration_number, colour, passenger_capacity, luggage_capacity,
                 has_air_conditioning, has_heating, is_four_by_four,
                 has_first_aid_kit, has_fire_extinguisher, has_spare_tyre,
                 has_snow_chains, has_child_seat, mountain_readiness_score,
                 status, created_at, updated_at)
            VALUES
                (@id, @driverId, @category, @make, @model, @year,
                 @registration, @colour, @passengers, @luggage,
                 @ac, @heating, @fourByFour, @firstAid, @fireExtinguisher,
                 @spareTyre, @snowChains, @childSeat, @readiness,
                 'Draft', now(), now());
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        AddVehicleParameters(command, id, driverProfileId.Value, request, readiness);
        try
        {
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            return ServiceResult<VehicleDto>.Fail(
                StatusCodes.Status409Conflict,
                "registration_number_exists",
                "This vehicle registration number is already registered.");
        }

        return ServiceResult<VehicleDto>.Created(
            await GetVehicleAsync(userId, id, cancellationToken)
                ?? throw new InvalidOperationException("Vehicle could not be loaded."));
    }

    public async Task<ServiceResult<VehicleDto>> UpdateVehicleAsync(
        Guid userId,
        Guid vehicleId,
        VehicleUpsertRequest request,
        CancellationToken cancellationToken)
    {
        var existing = await GetVehicleAsync(userId, vehicleId, cancellationToken);
        if (existing is null)
        {
            return ServiceResult<VehicleDto>.Fail(
                StatusCodes.Status404NotFound,
                "vehicle_not_found",
                "Vehicle not found.");
        }
        if (existing.Status is "Verified" or "Suspended")
        {
            return ServiceResult<VehicleDto>.Fail(
                StatusCodes.Status409Conflict,
                "verified_vehicle_locked",
                "A verified or suspended vehicle cannot be edited until an Admin requests changes.");
        }

        var readiness = CalculateMountainReadiness(request);
        const string sql = """
            UPDATE udrive.vehicles v
            SET category = @category, make = @make, model = @model, year = @year,
                registration_number = @registration, colour = @colour,
                passenger_capacity = @passengers, luggage_capacity = @luggage,
                has_air_conditioning = @ac, has_heating = @heating,
                is_four_by_four = @fourByFour, has_first_aid_kit = @firstAid,
                has_fire_extinguisher = @fireExtinguisher,
                has_spare_tyre = @spareTyre, has_snow_chains = @snowChains,
                has_child_seat = @childSeat, mountain_readiness_score = @readiness,
                status = CASE WHEN v.status = 'Verified' THEN 'Verified' ELSE 'Draft' END,
                updated_at = now()
            FROM udrive.driver_profiles dp
            WHERE v.id = @id AND v.driver_profile_id = dp.id AND dp.user_id = @userId;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        AddVehicleParameters(command, vehicleId, Guid.Empty, request, readiness);
        command.Parameters.AddWithValue("userId", userId);
        try
        {
            var affected = await command.ExecuteNonQueryAsync(cancellationToken);
            if (affected == 0)
            {
                return ServiceResult<VehicleDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "vehicle_not_found",
                    "Vehicle not found.");
            }
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            return ServiceResult<VehicleDto>.Fail(
                StatusCodes.Status409Conflict,
                "registration_number_exists",
                "This vehicle registration number is already registered.");
        }

        return ServiceResult<VehicleDto>.Ok(
            await GetVehicleAsync(userId, vehicleId, cancellationToken)
                ?? throw new InvalidOperationException("Vehicle could not be loaded."));
    }

    public async Task<ServiceResult<IReadOnlyList<VehicleDto>>> GetVehiclesAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT v.id
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            WHERE dp.user_id = @userId
            ORDER BY v.created_at DESC;
            """;
        var ids = new List<Guid>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            ids.Add(reader.GetGuid(0));
        }
        await reader.CloseAsync();

        var vehicles = new List<VehicleDto>();
        foreach (var id in ids)
        {
            var vehicle = await GetVehicleAsync(userId, id, cancellationToken);
            if (vehicle is not null)
            {
                vehicles.Add(vehicle);
            }
        }
        return ServiceResult<IReadOnlyList<VehicleDto>>.Ok(vehicles);
    }

    public async Task<ServiceResult<VehicleDocumentDto>> UploadVehicleDocumentAsync(
        Guid userId,
        Guid vehicleId,
        string documentType,
        DateOnly? expiryDate,
        IFormFile file,
        CancellationToken cancellationToken)
    {
        if (!await OwnsVehicleAsync(userId, vehicleId, cancellationToken))
        {
            return ServiceResult<VehicleDocumentDto>.Fail(
                StatusCodes.Status404NotFound,
                "vehicle_not_found",
                "Vehicle not found.");
        }

        var existing = await GetVehicleAsync(userId, vehicleId, cancellationToken);
        if (existing?.Status is "Verified" or "Suspended")
        {
            return ServiceResult<VehicleDocumentDto>.Fail(
                StatusCodes.Status409Conflict,
                "verified_vehicle_locked",
                "Verified or suspended vehicle documents cannot be replaced until an Admin requests changes.");
        }

        var normalizedType = NormalizeDocumentType(documentType);
        if (!AllowedVehicleDocuments.Contains(normalizedType))
        {
            return ServiceResult<VehicleDocumentDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_vehicle_document_type",
                $"Document type must be one of: {string.Join(", ", AllowedVehicleDocuments)}.");
        }
        var stored = await fileStorage.SaveAsync(file, "vehicle-documents", vehicleId, cancellationToken);
        var id = Guid.NewGuid();
        const string sql = """
            INSERT INTO udrive.vehicle_documents
                (id, vehicle_id, document_type, file_url, expiry_date,
                 status, created_at, updated_at)
            VALUES
                (@id, @vehicleId, @type, @url, @expiry, 'PendingReview', now(), now())
            ON CONFLICT (vehicle_id, document_type) DO UPDATE SET
                file_url = EXCLUDED.file_url,
                expiry_date = EXCLUDED.expiry_date,
                status = 'PendingReview',
                review_notes = NULL,
                updated_at = now()
            RETURNING id;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("vehicleId", vehicleId);
        command.Parameters.AddWithValue("type", normalizedType);
        command.Parameters.AddWithValue("url", stored.RelativeUrl);
        command.Parameters.AddWithValue("expiry", (object?)expiryDate ?? DBNull.Value);
        var resultId = (Guid)(await command.ExecuteScalarAsync(cancellationToken) ?? id);
        return ServiceResult<VehicleDocumentDto>.Created(new VehicleDocumentDto(
            resultId,
            normalizedType,
            stored.RelativeUrl,
            expiryDate,
            "PendingReview",
            null));
    }

    public async Task<ServiceResult<VehicleDto>> SubmitVehicleAsync(
        Guid userId,
        Guid vehicleId,
        CancellationToken cancellationToken)
    {
        if (!await OwnsVehicleAsync(userId, vehicleId, cancellationToken))
        {
            return ServiceResult<VehicleDto>.Fail(
                StatusCodes.Status404NotFound,
                "vehicle_not_found",
                "Vehicle not found.");
        }

        var existing = await GetVehicleAsync(userId, vehicleId, cancellationToken);
        if (existing?.Status is "Verified" or "Suspended")
        {
            return ServiceResult<VehicleDto>.Fail(
                StatusCodes.Status409Conflict,
                "vehicle_application_locked",
                "This vehicle is already verified or suspended.");
        }

        var documentTypes = await GetDocumentTypesAsync(
            "udrive.vehicle_documents",
            "vehicle_id",
            vehicleId,
            cancellationToken);
        var missing = RequiredVehicleDocuments.Except(documentTypes, StringComparer.OrdinalIgnoreCase).ToArray();
        if (missing.Length > 0)
        {
            return ServiceResult<VehicleDto>.Fail(
                StatusCodes.Status400BadRequest,
                "vehicle_documents_missing",
                $"Upload these required vehicle documents: {string.Join(", ", missing)}.");
        }

        const string sql = """
            UPDATE udrive.vehicles
            SET status = 'PendingReview', updated_at = now()
            WHERE id = @id AND status <> 'Verified';
            """;
        await ExecuteAsync(sql, cancellationToken, ("id", vehicleId));
        return ServiceResult<VehicleDto>.Ok(
            await GetVehicleAsync(userId, vehicleId, cancellationToken)
                ?? throw new InvalidOperationException("Vehicle could not be loaded."),
            "Vehicle submitted for verification.");
    }

    private async Task<DriverOnboardingDto?> GetDriverProfileAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT id, verification_status, cnic_number_masked,
                   driving_licence_number_masked, date_of_birth,
                   residential_address, emergency_contact_name,
                   emergency_contact_phone, bank_account_title,
                   payout_method, payout_account_masked, languages,
                   service_areas, submitted_at, reviewed_at, review_notes
            FROM udrive.driver_profiles
            WHERE user_id = @userId
            LIMIT 1;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new DriverOnboardingDto(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.IsDBNull(2) ? null : reader.GetString(2),
            reader.IsDBNull(3) ? null : reader.GetString(3),
            reader.IsDBNull(4) ? null : reader.GetFieldValue<DateOnly>(4),
            reader.IsDBNull(5) ? null : reader.GetString(5),
            reader.IsDBNull(6) ? null : reader.GetString(6),
            reader.IsDBNull(7) ? null : reader.GetString(7),
            reader.IsDBNull(8) ? null : reader.GetString(8),
            reader.IsDBNull(9) ? null : reader.GetString(9),
            reader.IsDBNull(10) ? null : reader.GetString(10),
            reader.IsDBNull(11) ? [] : reader.GetFieldValue<string[]>(11),
            reader.IsDBNull(12) ? [] : reader.GetFieldValue<string[]>(12),
            reader.IsDBNull(13) ? null : reader.GetFieldValue<DateTimeOffset>(13),
            reader.IsDBNull(14) ? null : reader.GetFieldValue<DateTimeOffset>(14),
            reader.IsDBNull(15) ? null : reader.GetString(15));
    }

    private async Task<Guid?> GetDriverProfileIdAsync(Guid userId, CancellationToken cancellationToken)
    {
        const string sql = "SELECT id FROM udrive.driver_profiles WHERE user_id = @userId LIMIT 1;";
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);
        var value = await command.ExecuteScalarAsync(cancellationToken);
        return value is Guid id ? id : null;
    }

    private async Task<VehicleDto?> GetVehicleAsync(
        Guid userId,
        Guid vehicleId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT v.id, v.category, v.make, v.model, v.year,
                   v.registration_number, v.colour, v.passenger_capacity,
                   v.luggage_capacity, v.has_air_conditioning, v.has_heating,
                   v.is_four_by_four, v.has_first_aid_kit,
                   v.has_fire_extinguisher, v.has_spare_tyre,
                   v.has_snow_chains, v.has_child_seat,
                   v.mountain_readiness_score, v.status
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            WHERE v.id = @vehicleId AND dp.user_id = @userId
            LIMIT 1;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("vehicleId", vehicleId);
        command.Parameters.AddWithValue("userId", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        var values = new object[19];
        reader.GetValues(values);
        await reader.CloseAsync();
        var documents = await GetVehicleDocumentsAsync(vehicleId, cancellationToken);
        return new VehicleDto(
            (Guid)values[0],
            (string)values[1],
            (string)values[2],
            (string)values[3],
            (int)values[4],
            (string)values[5],
            (string)values[6],
            (int)values[7],
            (int)values[8],
            (bool)values[9],
            (bool)values[10],
            (bool)values[11],
            (bool)values[12],
            (bool)values[13],
            (bool)values[14],
            (bool)values[15],
            (bool)values[16],
            (int)values[17],
            (string)values[18],
            documents);
    }

    private async Task<IReadOnlyList<VehicleDocumentDto>> GetVehicleDocumentsAsync(
        Guid vehicleId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT id, document_type, file_url, expiry_date, status, review_notes
            FROM udrive.vehicle_documents
            WHERE vehicle_id = @vehicleId
            ORDER BY document_type;
            """;
        var result = new List<VehicleDocumentDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("vehicleId", vehicleId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(new VehicleDocumentDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetFieldValue<DateOnly>(3),
                reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5)));
        }
        return result;
    }

    private async Task<bool> OwnsVehicleAsync(Guid userId, Guid vehicleId, CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT EXISTS(
                SELECT 1
                FROM udrive.vehicles v
                JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                WHERE v.id = @vehicleId AND dp.user_id = @userId);
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("vehicleId", vehicleId);
        command.Parameters.AddWithValue("userId", userId);
        return (bool)(await command.ExecuteScalarAsync(cancellationToken) ?? false);
    }

    private async Task<HashSet<string>> GetDocumentTypesAsync(
        string table,
        string ownerColumn,
        Guid ownerId,
        CancellationToken cancellationToken)
    {
        var sql = $"SELECT document_type FROM {table} WHERE {ownerColumn} = @ownerId;";
        var types = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("ownerId", ownerId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            types.Add(reader.GetString(0));
        }
        return types;
    }

    private static int CalculateMountainReadiness(VehicleUpsertRequest request)
    {
        var score = 20;
        if (request.IsFourByFour) score += 25;
        if (request.HasFirstAidKit) score += 12;
        if (request.HasFireExtinguisher) score += 10;
        if (request.HasSpareTyre) score += 12;
        if (request.HasSnowChains) score += 10;
        if (request.HasHeating) score += 5;
        if (request.HasAirConditioning) score += 3;
        if (request.HasChildSeat) score += 3;
        return Math.Min(score, 100);
    }

    private static void AddVehicleParameters(
        NpgsqlCommand command,
        Guid id,
        Guid driverProfileId,
        VehicleUpsertRequest request,
        int readiness)
    {
        command.Parameters.AddWithValue("id", id);
        if (driverProfileId != Guid.Empty)
        {
            command.Parameters.AddWithValue("driverId", driverProfileId);
        }
        command.Parameters.AddWithValue("category", request.Category.Trim());
        command.Parameters.AddWithValue("make", request.Make.Trim());
        command.Parameters.AddWithValue("model", request.Model.Trim());
        command.Parameters.AddWithValue("year", request.Year);
        command.Parameters.AddWithValue("registration", request.RegistrationNumber.Trim().ToUpperInvariant());
        command.Parameters.AddWithValue("colour", request.Colour.Trim());
        command.Parameters.AddWithValue("passengers", request.PassengerCapacity);
        command.Parameters.AddWithValue("luggage", request.LuggageCapacity);
        command.Parameters.AddWithValue("ac", request.HasAirConditioning);
        command.Parameters.AddWithValue("heating", request.HasHeating);
        command.Parameters.AddWithValue("fourByFour", request.IsFourByFour);
        command.Parameters.AddWithValue("firstAid", request.HasFirstAidKit);
        command.Parameters.AddWithValue("fireExtinguisher", request.HasFireExtinguisher);
        command.Parameters.AddWithValue("spareTyre", request.HasSpareTyre);
        command.Parameters.AddWithValue("snowChains", request.HasSnowChains);
        command.Parameters.AddWithValue("childSeat", request.HasChildSeat);
        command.Parameters.AddWithValue("readiness", readiness);
    }

    private static string[] SanitizeArray(string[]? values, int maximum)
    {
        return (values ?? [])
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(maximum)
            .ToArray();
    }

    private static string NormalizeDocumentType(string type)
    {
        return new string(type.Trim().ToUpperInvariant()
            .Select(character => char.IsLetterOrDigit(character) ? character : '_')
            .ToArray());
    }

    private async Task ExecuteAsync(
        string sql,
        CancellationToken cancellationToken,
        params (string Name, object Value)[] parameters)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        foreach (var parameter in parameters)
        {
            command.Parameters.AddWithValue(parameter.Name, parameter.Value);
        }
        await command.ExecuteNonQueryAsync(cancellationToken);
    }
}
