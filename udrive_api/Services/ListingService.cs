using System.Globalization;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Domain;
using UDrive.Api.Models;
using UDrive.Api.Security;

namespace UDrive.Api.Services;

/// <summary>
/// "Earn with your vehicle": owners list cars for rent and tours, invite the
/// drivers who will drive customers, block rent days and post daily tour
/// departures. Admins approve each vehicle once and each driver once.
/// </summary>
/// <remarks>
/// Listings live in the tables every search already reads — vehicles,
/// driver_profiles, tour_packages — so an approved listing appears in the
/// rent list and the tours list with no second catalogue to keep in step.
///
/// An owner profile is a driver_profiles row with profile_kind 'Owner'. It
/// needs a CNIC and a selfie; a licence only when the owner drives customers
/// himself. Everyone else who drives is a fleet_drivers row with their own
/// documents, uploaded from their own phone, approved by an admin, and never
/// assignable once their licence has expired.
/// </remarks>
public sealed class ListingService(string connectionString, LocalFileStorageService fileStorage)
{
    private static readonly TimeSpan Karachi = TimeSpan.FromHours(5);

    private const int MaxDriversPerOwner = 30;
    private const int MaxVehiclesPerOwner = 50;

    /// <summary>Owner document kinds → driver_documents.document_type.</summary>
    private static readonly Dictionary<string, string> OwnerDocumentTypes =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["cnic-front"] = "CNIC_FRONT",
            ["cnic-back"] = "CNIC_BACK",
            ["selfie"] = "SELFIE",
            ["licence-front"] = "DRIVING_LICENCE",
            ["licence-back"] = "DRIVING_LICENCE_BACK",
        };

    /// <summary>Vehicle photo kinds → vehicle_documents.document_type.</summary>
    private static readonly Dictionary<string, string> VehicleDocumentTypes =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["front"] = "VEHICLE_FRONT",
            ["registration-front"] = "REGISTRATION_BOOK",
            ["registration-back"] = "REGISTRATION_BOOK_BACK",
        };

    /// <summary>Fleet driver document kinds → fleet_drivers columns (a fixed map: never caller text in SQL).</summary>
    private static readonly Dictionary<string, string> FleetDocumentColumns =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["cnic-front"] = "cnic_front_url",
            ["cnic-back"] = "cnic_back_url",
            ["selfie"] = "selfie_url",
            ["licence-front"] = "licence_front_url",
            ["licence-back"] = "licence_back_url",
        };

    // ═════════════════════════════════════════════════════════ owner: home

    public async Task<ServiceResult<ListingHomeDto>> HomeAsync(Guid userId, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        await RentalService.ExpireOverdueAsync(connection, ct);

        var profileId = await ProfileIdAsync(connection, userId, ct);
        var owner = await OwnerAsync(connection, userId, profileId, ct);
        var vehicles = profileId is null
            ? []
            : await VehiclesAsync(connection, profileId.Value, null, ct);
        var drivers = profileId is null
            ? []
            : await DriversAsync(connection, profileId.Value, ct);

        int invites;
        await using (var command = new NpgsqlCommand(
            """
            SELECT count(*)::int
            FROM udrive.fleet_drivers fd
            JOIN udrive.users u ON u.id = @userId
            WHERE fd.phone_number = u.phone_number
              AND NOT fd.is_owner
              AND fd.status IN ('Invited', 'Rejected');
            """, connection))
        {
            command.Parameters.AddWithValue("userId", userId);
            invites = (int)(await command.ExecuteScalarAsync(ct) ?? 0);
        }

        return ServiceResult<ListingHomeDto>.Ok(new ListingHomeDto(owner, vehicles, drivers, invites));
    }

    // ═════════════════════════════════════════════════════════ owner: vehicle

    public async Task<ServiceResult<ListingVehicleDto>> SaveVehicleAsync(
        Guid userId, Guid? vehicleId, SaveListingVehicleRequest request, CancellationToken ct)
    {
        var problem = ValidateVehicle(request, out var clean);
        if (problem is not null) return Fail<ListingVehicleDto>(400, problem.Value.Code, problem.Value.Message);

        await using var connection = await OpenAsync(ct);
        var profileId = await EnsureOwnerProfileAsync(connection, userId, ct);

        // Self or Both: the owner drives customers, so his licence will be asked.
        // A classic Driver profile always drives himself.
        await using (var command = new NpgsqlCommand(
            """
            UPDATE udrive.driver_profiles
            SET drives_self = CASE WHEN profile_kind = 'Driver' THEN true ELSE @drivesSelf END,
                updated_at = now()
            WHERE id = @profileId;
            """, connection))
        {
            command.Parameters.AddWithValue("profileId", profileId);
            command.Parameters.AddWithValue("drivesSelf", clean.DrivesSelf);
            await command.ExecuteNonQueryAsync(ct);
        }

        var equipment = new TourReadiness.Equipment(
            clean.Kit.FourByFour, clean.Kit.FirstAidKit, clean.Kit.SpareTyre, clean.Kit.FireExtinguisher,
            clean.Kit.SnowChains, clean.Kit.Heating, clean.Kit.AirConditioning, false);
        var readiness = TourReadiness.Score(equipment);

        try
        {
            if (vehicleId is null)
            {
                await using (var count = new NpgsqlCommand(
                    "SELECT count(*)::int FROM udrive.vehicles WHERE driver_profile_id = @p AND status <> 'Deleted';",
                    connection))
                {
                    count.Parameters.AddWithValue("p", profileId);
                    if ((int)(await count.ExecuteScalarAsync(ct) ?? 0) >= MaxVehiclesPerOwner)
                    {
                        return Fail<ListingVehicleDto>(409, "vehicle_limit",
                            $"One account can list up to {MaxVehiclesPerOwner} vehicles.");
                    }
                }

                var id = Guid.NewGuid();
                await using var insert = new NpgsqlCommand(
                    """
                    INSERT INTO udrive.vehicles
                        (id, driver_profile_id, category, make, model, year, registration_number, colour,
                         passenger_capacity, luggage_capacity,
                         has_air_conditioning, has_heating, is_four_by_four, has_first_aid_kit,
                         has_fire_extinguisher, has_spare_tyre, has_snow_chains, has_child_seat,
                         mountain_readiness_score, status, booking_mode,
                         available_for_city, available_for_tour, available_for_rent,
                         rent_with_driver_daily, rent_self_drive_daily, rent_pickup_point, rent_minimum_days,
                         listed_via, listing_wants_rent, listing_wants_tour, created_at, updated_at)
                    VALUES
                        (@id, @profileId, @category, @make, @model, @year, @registration, '',
                         @seats, 0,
                         @ac, @heating, @fourByFour, @firstAid,
                         @extinguisher, @spare, @chains, false,
                         @readiness, 'Draft', @bookingMode,
                         false, false, false,
                         @withDriver, @selfDrive, @pickup, 1,
                         'Listing', @wantsRent, @wantsTour, now(), now());
                    """, connection);
                insert.Parameters.AddWithValue("id", id);
                insert.Parameters.AddWithValue("profileId", profileId);
                BindVehicle(insert, clean, readiness);
                await insert.ExecuteNonQueryAsync(ct);
                vehicleId = id;
            }
            else
            {
                await using var update = new NpgsqlCommand(
                    """
                    UPDATE udrive.vehicles
                    SET category = @category, make = @make, model = @model, year = @year,
                        registration_number = @registration, passenger_capacity = @seats,
                        has_air_conditioning = @ac, has_heating = @heating, is_four_by_four = @fourByFour,
                        has_first_aid_kit = @firstAid, has_fire_extinguisher = @extinguisher,
                        has_spare_tyre = @spare, has_snow_chains = @chains,
                        mountain_readiness_score = @readiness, booking_mode = @bookingMode,
                        rent_with_driver_daily = @withDriver, rent_self_drive_daily = @selfDrive,
                        rent_pickup_point = @pickup,
                        listing_wants_rent = @wantsRent, listing_wants_tour = @wantsTour,
                        -- An edit goes back to the owner's desk: it is submitted again.
                        status = 'Draft', updated_at = now()
                    WHERE id = @id AND driver_profile_id = @profileId
                      AND status IN ('Draft', 'PendingReview', 'Rejected');
                    """, connection);
                update.Parameters.AddWithValue("id", vehicleId.Value);
                update.Parameters.AddWithValue("profileId", profileId);
                BindVehicle(update, clean, readiness);
                if (await update.ExecuteNonQueryAsync(ct) == 0)
                {
                    return Fail<ListingVehicleDto>(409, "listing_locked",
                        "This vehicle is already live. Change its rates from the Rent screen, or ask UDrive support to edit its details.");
                }
            }
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            return Fail<ListingVehicleDto>(409, "registration_taken",
                "A vehicle with this number plate is already on UDrive. If it is yours, contact UDrive support.");
        }

        var list = await VehiclesAsync(connection, profileId, vehicleId, ct);
        return ServiceResult<ListingVehicleDto>.Ok(list[0]);
    }

    public async Task<ServiceResult<ListingVehicleDto>> UploadVehiclePhotoAsync(
        Guid userId, Guid vehicleId, string kind, IFormFile file, CancellationToken ct)
    {
        if (!VehicleDocumentTypes.TryGetValue(kind ?? string.Empty, out var documentType))
        {
            return Fail<ListingVehicleDto>(400, "photo_kind_invalid",
                "Photo must be front, registration-front or registration-back.");
        }

        await using var connection = await OpenAsync(ct);
        var profileId = await ProfileIdAsync(connection, userId, ct);
        var status = profileId is null ? null : await VehicleStatusAsync(connection, profileId.Value, vehicleId, ct);
        if (status is null) return Fail<ListingVehicleDto>(404, "vehicle_not_found", "This vehicle was not found on your account.");

        // The registration book of a live vehicle is what an admin approved;
        // it does not change without a new review. The front photo can.
        if (status == "Verified" && documentType != "VEHICLE_FRONT")
        {
            return Fail<ListingVehicleDto>(409, "listing_locked",
                "This vehicle is already approved. Contact UDrive support to change its registration documents.");
        }

        var saved = await SaveFileAsync(file, documentType == "VEHICLE_FRONT" ? "vehicle-images" : "vehicle-documents", vehicleId, ct);
        if (!saved.Success) return Fail<ListingVehicleDto>(saved.StatusCode, saved.ErrorCode!, saved.Message!);

        await using (var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.vehicle_documents
                (id, vehicle_id, document_type, file_url, status, created_at, updated_at)
            VALUES (gen_random_uuid(), @vehicleId, @type, @url, 'PendingReview', now(), now())
            ON CONFLICT (vehicle_id, document_type) DO UPDATE SET
                file_url = EXCLUDED.file_url, status = 'PendingReview', review_notes = NULL, updated_at = now();
            """, connection))
        {
            command.Parameters.AddWithValue("vehicleId", vehicleId);
            command.Parameters.AddWithValue("type", documentType);
            command.Parameters.AddWithValue("url", saved.Data!.ProtectedUrl);
            await command.ExecuteNonQueryAsync(ct);
        }

        if (documentType == "VEHICLE_FRONT")
        {
            // The same picture is the listing photo customers see.
            await using var command = new NpgsqlCommand(
                "UPDATE udrive.vehicles SET image_url = @url, updated_at = now() WHERE id = @id;", connection);
            command.Parameters.AddWithValue("id", vehicleId);
            command.Parameters.AddWithValue("url", saved.Data!.PublicUrl);
            await command.ExecuteNonQueryAsync(ct);
        }

        var list = await VehiclesAsync(connection, profileId!.Value, vehicleId, ct);
        return ServiceResult<ListingVehicleDto>.Ok(list[0]);
    }

    public async Task<ServiceResult<ListingOwnerDto>> UploadOwnerDocumentAsync(
        Guid userId, string kind, IFormFile file, CancellationToken ct)
    {
        if (!OwnerDocumentTypes.TryGetValue(kind ?? string.Empty, out var documentType))
        {
            return Fail<ListingOwnerDto>(400, "document_kind_invalid",
                "Document must be cnic-front, cnic-back, selfie, licence-front or licence-back.");
        }

        await using var connection = await OpenAsync(ct);
        var profileId = await EnsureOwnerProfileAsync(connection, userId, ct);

        // Once an admin has approved the person, their CNIC and selfie are what
        // was checked; they are not swapped without a new review. A licence can
        // always be added or renewed.
        await using (var check = new NpgsqlCommand(
            """
            SELECT dp.verification_status = 'Approved'
               AND EXISTS (SELECT 1 FROM udrive.driver_documents d
                           WHERE d.driver_profile_id = dp.id AND d.document_type = @type)
            FROM udrive.driver_profiles dp WHERE dp.id = @profileId;
            """, connection))
        {
            check.Parameters.AddWithValue("profileId", profileId);
            check.Parameters.AddWithValue("type", documentType);
            if (await check.ExecuteScalarAsync(ct) is true && documentType is "CNIC_FRONT" or "CNIC_BACK" or "SELFIE")
            {
                return Fail<ListingOwnerDto>(409, "document_locked",
                    "Your identity documents are already approved. Contact UDrive support to change them.");
            }
        }

        var saved = await SaveFileAsync(file, "driver-documents", profileId, ct);
        if (!saved.Success) return Fail<ListingOwnerDto>(saved.StatusCode, saved.ErrorCode!, saved.Message!);

        await using (var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.driver_documents
                (id, driver_profile_id, document_type, file_url, status, created_at, updated_at)
            VALUES (gen_random_uuid(), @profileId, @type, @url, 'Submitted', now(), now())
            ON CONFLICT (driver_profile_id, document_type) DO UPDATE SET
                file_url = EXCLUDED.file_url, status = 'Submitted', review_notes = NULL, updated_at = now();
            """, connection))
        {
            command.Parameters.AddWithValue("profileId", profileId);
            command.Parameters.AddWithValue("type", documentType);
            command.Parameters.AddWithValue("url", saved.Data!.ProtectedUrl);
            await command.ExecuteNonQueryAsync(ct);
        }

        return ServiceResult<ListingOwnerDto>.Ok(await OwnerAsync(connection, userId, profileId, ct));
    }

    public async Task<ServiceResult<ListingVehicleDto>> SubmitAsync(
        Guid userId, Guid vehicleId, SubmitListingRequest request, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        var profileId = await ProfileIdAsync(connection, userId, ct);
        if (profileId is null) return Fail<ListingVehicleDto>(404, "vehicle_not_found", "This vehicle was not found on your account.");

        var list = await VehiclesAsync(connection, profileId.Value, vehicleId, ct);
        if (list.Count == 0) return Fail<ListingVehicleDto>(404, "vehicle_not_found", "This vehicle was not found on your account.");
        var vehicle = list[0];
        if (vehicle.Status == "Verified") return ServiceResult<ListingVehicleDto>.Ok(vehicle);

        if (!vehicle.Docs.Front || !vehicle.Docs.RegistrationFront || !vehicle.Docs.RegistrationBack)
        {
            return Fail<ListingVehicleDto>(409, "listing_photos_missing",
                "Add the car's front photo and both sides of the registration book.");
        }
        if (vehicle.WantsRent && vehicle.WithDriverDaily is not > 0 && vehicle.SelfDriveDaily is not > 0)
        {
            return Fail<ListingVehicleDto>(409, "listing_rent_rate_required",
                "Give a daily rent rate — with driver, self-drive, or both.");
        }

        var owner = await OwnerAsync(connection, userId, profileId, ct);
        if (!owner.CnicFront || !owner.CnicBack || !owner.Selfie)
        {
            return Fail<ListingVehicleDto>(409, "owner_documents_missing",
                "Add both sides of your CNIC and a selfie.");
        }

        var current = await AgreementVersionAsync(connection, ct);
        if (!request.AcceptAgreement || request.AgreementVersion != current)
        {
            return Fail<ListingVehicleDto>(409, "agreement_required",
                "Please read and accept the vehicle owner agreement.");
        }

        string? licenceNumber = null;
        DateOnly? licenceExpiry = null;
        if (owner.DrivesSelf)
        {
            if (!owner.LicenceFront || !owner.LicenceBack)
            {
                return Fail<ListingVehicleDto>(409, "licence_required",
                    "You chose to drive customers yourself, so both sides of your driving licence are needed.");
            }

            licenceNumber = Clip(request.LicenceNumber?.Trim().ToUpperInvariant(), 40) ?? owner.LicenceNumber;
            licenceExpiry = request.LicenceExpiry ?? owner.LicenceExpiry;
            if (string.IsNullOrWhiteSpace(licenceNumber) || licenceNumber.Length < 4 || licenceExpiry is null)
            {
                return Fail<ListingVehicleDto>(409, "licence_required",
                    "Enter your licence number and its expiry date.");
            }
            if (licenceExpiry.Value <= Today())
            {
                return Fail<ListingVehicleDto>(409, "licence_expired",
                    "Your driving licence has expired. Renew it before listing a vehicle you will drive.");
            }
        }

        await using var transaction = await connection.BeginTransactionAsync(ct);
        try
        {
            await using (var command = new NpgsqlCommand(
                """
                UPDATE udrive.driver_profiles
                SET owner_agreement_version = @version, owner_agreement_accepted_at = now(),
                    driving_licence_number = COALESCE(@licence, driving_licence_number),
                    driving_licence_number_masked = COALESCE(@licenceMasked, driving_licence_number_masked),
                    driving_licence_expiry = COALESCE(@expiry, driving_licence_expiry),
                    verification_status = CASE WHEN verification_status IN ('Draft', 'ChangesRequested', 'Rejected')
                                               THEN 'Submitted' ELSE verification_status END,
                    submitted_at = COALESCE(submitted_at, now()),
                    updated_at = now()
                WHERE id = @profileId;

                UPDATE udrive.vehicles
                SET status = 'PendingReview', listing_submitted_at = now(),
                    listing_review_note = NULL, updated_at = now()
                WHERE id = @vehicleId AND driver_profile_id = @profileId;
                """, connection, transaction))
            {
                command.Parameters.AddWithValue("profileId", profileId.Value);
                command.Parameters.AddWithValue("vehicleId", vehicleId);
                command.Parameters.AddWithValue("version", current);
                command.Parameters.Add(new NpgsqlParameter("licence", NpgsqlDbType.Varchar) { Value = (object?)licenceNumber ?? DBNull.Value });
                command.Parameters.Add(new NpgsqlParameter("licenceMasked", NpgsqlDbType.Varchar)
                {
                    Value = licenceNumber is null ? DBNull.Value : MaskLicence(licenceNumber),
                });
                command.Parameters.Add(new NpgsqlParameter("expiry", NpgsqlDbType.Date) { Value = (object?)licenceExpiry ?? DBNull.Value });
                await command.ExecuteNonQueryAsync(ct);
            }

            if (owner.DrivesSelf)
            {
                await UpsertOwnerDriverRowAsync(connection, transaction, userId, profileId.Value,
                    licenceNumber!, licenceExpiry!.Value, current, approve: false, reviewer: null, ct);
            }

            await transaction.CommitAsync(ct);
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            throw;
        }

        list = await VehiclesAsync(connection, profileId.Value, vehicleId, ct);
        return ServiceResult<ListingVehicleDto>.Ok(list[0],
            "Submitted. UDrive usually reviews within 24 hours and the vehicle goes live by itself once approved.");
    }

    // ═════════════════════════════════════════════════════════ owner: drivers

    public sealed record InviteResult(FleetDriverDto Driver, string Phone, string OwnerName);

    public async Task<ServiceResult<InviteResult>> InviteDriverAsync(
        Guid userId, InviteDriverRequest request, CancellationToken ct)
    {
        var name = Clip(request.Name?.Trim(), 120) ?? string.Empty;
        if (name.Length < 2) return Fail<InviteResult>(400, "driver_name_required", "Enter the driver's name.");
        if (!PhoneNumberNormalizer.TryNormalizePakistan(request.Phone, out var phone))
        {
            return Fail<InviteResult>(400, "driver_phone_invalid", "Enter the driver's mobile number, e.g. 0312 3456789.");
        }

        await using var connection = await OpenAsync(ct);
        var profileId = await EnsureOwnerProfileAsync(connection, userId, ct);

        string ownerName;
        string ownerPhone;
        await using (var command = new NpgsqlCommand(
            "SELECT COALESCE(NULLIF(full_name, ''), 'A UDrive owner'), phone_number FROM udrive.users WHERE id = @id;", connection))
        {
            command.Parameters.AddWithValue("id", userId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            await reader.ReadAsync(ct);
            ownerName = reader.GetString(0);
            ownerPhone = reader.GetString(1);
        }

        if (string.Equals(ownerPhone, phone, StringComparison.Ordinal))
        {
            return Fail<InviteResult>(409, "driver_is_owner",
                "That is your own number. Choose \"I drive\" instead, and add your licence in the last step.");
        }

        await using (var count = new NpgsqlCommand(
            "SELECT count(*)::int FROM udrive.fleet_drivers WHERE owner_profile_id = @p AND status NOT IN ('Removed', 'Declined');",
            connection))
        {
            count.Parameters.AddWithValue("p", profileId);
            if ((int)(await count.ExecuteScalarAsync(ct) ?? 0) >= MaxDriversPerOwner)
            {
                return Fail<InviteResult>(409, "driver_limit", $"One account can have up to {MaxDriversPerOwner} drivers.");
            }
        }

        Guid id;
        try
        {
            await using var insert = new NpgsqlCommand(
                """
                INSERT INTO udrive.fleet_drivers
                    (id, owner_profile_id, user_id, phone_number, full_name, is_owner, status, created_at, updated_at)
                VALUES (gen_random_uuid(), @profileId,
                        (SELECT id FROM udrive.users WHERE phone_number = @phone),
                        @phone, @name, false, 'Invited', now(), now())
                RETURNING id;
                """, connection);
            insert.Parameters.AddWithValue("profileId", profileId);
            insert.Parameters.AddWithValue("phone", phone);
            insert.Parameters.AddWithValue("name", name);
            id = (Guid)(await insert.ExecuteScalarAsync(ct))!;
        }
        catch (PostgresException exception) when (exception.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            return Fail<InviteResult>(409, "driver_already_invited", "This number is already one of your drivers.");
        }

        var drivers = await DriversAsync(connection, profileId, ct);
        var driver = drivers.First(d => d.Id == id);
        return ServiceResult<InviteResult>.Ok(new InviteResult(driver, phone, ownerName));
    }

    public async Task<ServiceResult<object>> RemoveDriverAsync(Guid userId, Guid driverId, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        await using var command = new NpgsqlCommand(
            """
            UPDATE udrive.fleet_drivers fd
            SET status = 'Removed', updated_at = now()
            FROM udrive.driver_profiles dp
            WHERE fd.id = @id AND fd.owner_profile_id = dp.id AND dp.user_id = @userId
              AND fd.status <> 'Removed'
            RETURNING fd.id;
            """, connection);
        command.Parameters.AddWithValue("id", driverId);
        command.Parameters.AddWithValue("userId", userId);
        return await command.ExecuteScalarAsync(ct) is Guid
            ? ServiceResult<object>.Ok(new { id = driverId })
            : Fail<object>(404, "driver_not_found", "That driver was not found.");
    }

    // ═════════════════════════════════════════════════════════ invited driver

    public async Task<ServiceResult<IReadOnlyList<DriverInviteDto>>> InvitesAsync(Guid userId, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);

        // Claim invites addressed to this phone, so later lookups use the account.
        await using (var claim = new NpgsqlCommand(
            """
            UPDATE udrive.fleet_drivers fd
            SET user_id = u.id, updated_at = now()
            FROM udrive.users u
            WHERE u.id = @userId AND fd.phone_number = u.phone_number
              AND fd.user_id IS NULL AND NOT fd.is_owner;
            """, connection))
        {
            claim.Parameters.AddWithValue("userId", userId);
            await claim.ExecuteNonQueryAsync(ct);
        }

        return ServiceResult<IReadOnlyList<DriverInviteDto>>.Ok(await InviteRowsAsync(connection, userId, null, ct));
    }

    public async Task<ServiceResult<DriverInviteDto>> UploadInviteDocumentAsync(
        Guid userId, Guid inviteId, string kind, IFormFile file, CancellationToken ct)
    {
        if (!FleetDocumentColumns.TryGetValue(kind ?? string.Empty, out var column))
        {
            return Fail<DriverInviteDto>(400, "document_kind_invalid",
                "Document must be cnic-front, cnic-back, selfie, licence-front or licence-back.");
        }

        await using var connection = await OpenAsync(ct);
        var invite = (await InviteRowsAsync(connection, userId, inviteId, ct)).FirstOrDefault();
        if (invite is null) return Fail<DriverInviteDto>(404, "invite_not_found", "This invite was not found for your number.");
        if (invite.Status == "Approved") return Fail<DriverInviteDto>(409, "invite_locked", "You are already approved.");

        var saved = await SaveFileAsync(file, "fleet-drivers", inviteId, ct);
        if (!saved.Success) return Fail<DriverInviteDto>(saved.StatusCode, saved.ErrorCode!, saved.Message!);

        await using (var command = new NpgsqlCommand(
            $"UPDATE udrive.fleet_drivers SET {column} = @url, user_id = @userId, updated_at = now() WHERE id = @id;",
            connection))
        {
            command.Parameters.AddWithValue("id", inviteId);
            command.Parameters.AddWithValue("userId", userId);
            command.Parameters.AddWithValue("url", saved.Data!.ProtectedUrl);
            await command.ExecuteNonQueryAsync(ct);
        }

        return ServiceResult<DriverInviteDto>.Ok((await InviteRowsAsync(connection, userId, inviteId, ct))[0]);
    }

    public async Task<ServiceResult<DriverInviteDto>> SubmitInviteAsync(
        Guid userId, Guid inviteId, SubmitInviteRequest request, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        var invite = (await InviteRowsAsync(connection, userId, inviteId, ct)).FirstOrDefault();
        if (invite is null) return Fail<DriverInviteDto>(404, "invite_not_found", "This invite was not found for your number.");
        if (invite.Status == "Approved") return ServiceResult<DriverInviteDto>.Ok(invite);

        if (!invite.CnicFront || !invite.CnicBack || !invite.Selfie || !invite.LicenceFront || !invite.LicenceBack)
        {
            return Fail<DriverInviteDto>(409, "documents_missing",
                "Add both sides of your CNIC, both sides of your licence and a selfie.");
        }

        var licence = Clip(request.LicenceNumber?.Trim().ToUpperInvariant(), 40);
        if (string.IsNullOrWhiteSpace(licence) || licence.Length < 4 || request.LicenceExpiry is null)
        {
            return Fail<DriverInviteDto>(400, "licence_required", "Enter your licence number and its expiry date.");
        }
        if (request.LicenceExpiry.Value <= Today())
        {
            return Fail<DriverInviteDto>(409, "licence_expired", "Your driving licence has expired. Renew it first.");
        }

        var current = await AgreementVersionAsync(connection, ct);
        if (!request.AcceptAgreement || request.AgreementVersion != current)
        {
            return Fail<DriverInviteDto>(409, "agreement_required", "Please read and accept the driver agreement.");
        }

        await using (var command = new NpgsqlCommand(
            """
            UPDATE udrive.fleet_drivers
            SET licence_number = @licence, licence_expiry = @expiry,
                agreement_version = @version, agreement_accepted_at = now(),
                status = 'Submitted', submitted_at = now(), review_note = NULL,
                expiry_reminded_at = NULL, user_id = @userId, updated_at = now()
            WHERE id = @id;
            """, connection))
        {
            command.Parameters.AddWithValue("id", inviteId);
            command.Parameters.AddWithValue("userId", userId);
            command.Parameters.AddWithValue("licence", licence);
            command.Parameters.Add(new NpgsqlParameter("expiry", NpgsqlDbType.Date) { Value = request.LicenceExpiry.Value });
            command.Parameters.AddWithValue("version", current);
            await command.ExecuteNonQueryAsync(ct);
        }

        return ServiceResult<DriverInviteDto>.Ok((await InviteRowsAsync(connection, userId, inviteId, ct))[0],
            "Sent. UDrive will check your documents.");
    }

    public async Task<ServiceResult<object>> DeclineInviteAsync(Guid userId, Guid inviteId, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        var invite = (await InviteRowsAsync(connection, userId, inviteId, ct)).FirstOrDefault();
        if (invite is null) return Fail<object>(404, "invite_not_found", "This invite was not found for your number.");

        await using var command = new NpgsqlCommand(
            "UPDATE udrive.fleet_drivers SET status = 'Declined', updated_at = now() WHERE id = @id AND status <> 'Approved';",
            connection);
        command.Parameters.AddWithValue("id", inviteId);
        await command.ExecuteNonQueryAsync(ct);
        return ServiceResult<object>.Ok(new { id = inviteId });
    }

    // ═════════════════════════════════════════════════════════ rent calendar

    public async Task<ServiceResult<IReadOnlyList<RentCalendarDayDto>>> CalendarAsync(
        Guid userId, Guid vehicleId, DateOnly? from, int days, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        var profileId = await ProfileIdAsync(connection, userId, ct);
        if (profileId is null || await VehicleStatusAsync(connection, profileId.Value, vehicleId, ct) is null)
        {
            return Fail<IReadOnlyList<RentCalendarDayDto>>(404, "vehicle_not_found", "This vehicle was not found on your account.");
        }

        await RentalService.ExpireOverdueAsync(connection, ct);
        var start = from ?? new DateOnly(Today().Year, Today().Month, 1);
        return ServiceResult<IReadOnlyList<RentCalendarDayDto>>.Ok(
            await CalendarRowsAsync(connection, vehicleId, start, Math.Clamp(days, 1, 120), ct));
    }

    public async Task<ServiceResult<IReadOnlyList<RentCalendarDayDto>>> SetBlockedDaysAsync(
        Guid userId, Guid vehicleId, BlockedDaysRequest request, CancellationToken ct)
    {
        var block = (request.Block ?? []).Distinct().Take(400).ToArray();
        var unblock = (request.Unblock ?? []).Distinct().Take(400).ToArray();

        await using var connection = await OpenAsync(ct);
        var profileId = await ProfileIdAsync(connection, userId, ct);
        if (profileId is null || await VehicleStatusAsync(connection, profileId.Value, vehicleId, ct) is null)
        {
            return Fail<IReadOnlyList<RentCalendarDayDto>>(404, "vehicle_not_found", "This vehicle was not found on your account.");
        }

        var today = Today();
        await using (var command = new NpgsqlCommand(
            """
            DELETE FROM udrive.rental_blocked_days
            WHERE vehicle_id = @vehicleId AND day = ANY(@unblock);

            -- Never over a day a customer already has: those are opened as bookings.
            INSERT INTO udrive.rental_blocked_days (vehicle_id, day, created_at)
            SELECT @vehicleId, d, now()
            FROM unnest(@block) AS d
            WHERE d >= @today
              AND NOT EXISTS (
                  SELECT 1 FROM udrive.rental_bookings rb
                  WHERE rb.vehicle_id = @vehicleId
                    AND rb.status IN ('PendingOwner', 'Confirmed', 'HandedOver')
                    AND d BETWEEN rb.start_date AND rb.end_date)
            ON CONFLICT DO NOTHING;
            """, connection))
        {
            command.Parameters.AddWithValue("vehicleId", vehicleId);
            command.Parameters.Add(new NpgsqlParameter("unblock", NpgsqlDbType.Array | NpgsqlDbType.Date) { Value = unblock });
            command.Parameters.Add(new NpgsqlParameter("block", NpgsqlDbType.Array | NpgsqlDbType.Date) { Value = block });
            command.Parameters.Add(new NpgsqlParameter("today", NpgsqlDbType.Date) { Value = today });
            await command.ExecuteNonQueryAsync(ct);
        }

        var first = block.Concat(unblock).DefaultIfEmpty(today).Min();
        var start = new DateOnly(first.Year, first.Month, 1);
        return ServiceResult<IReadOnlyList<RentCalendarDayDto>>.Ok(
            await CalendarRowsAsync(connection, vehicleId, start, 42, ct));
    }

    // ═════════════════════════════════════════════════════════ tour departures

    public async Task<ServiceResult<DepartureMonthDto>> DeparturesAsync(
        Guid userId, Guid vehicleId, int year, int month, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        var profileId = await ProfileIdAsync(connection, userId, ct);
        var capacity = profileId is null ? null : await CapacityAsync(connection, profileId.Value, vehicleId, ct);
        if (capacity is null) return Fail<DepartureMonthDto>(404, "vehicle_not_found", "This vehicle was not found on your account.");

        var first = new DateOnly(Math.Clamp(year, 2020, 2100), Math.Clamp(month, 1, 12), 1);
        var last = first.AddMonths(1).AddDays(-1);

        var days = await DepartureRowsAsync(connection, vehicleId,
            "AND (tp.departure_at AT TIME ZONE 'Asia/Karachi')::date BETWEEN @from AND @to AND tp.status = 'Active'",
            command =>
            {
                command.Parameters.Add(new NpgsqlParameter("from", NpgsqlDbType.Date) { Value = first });
                command.Parameters.Add(new NpgsqlParameter("to", NpgsqlDbType.Date) { Value = last });
            }, 100, ct);

        var template = (await DepartureRowsAsync(connection, vehicleId,
            "AND tp.status IN ('Active', 'Completed', 'InProgress')", _ => { }, 1, ct, newestFirst: true))
            .Select(d => d with { Date = null, PackageId = null, SeatsSold = 0 })
            .FirstOrDefault();

        return ServiceResult<DepartureMonthDto>.Ok(
            new DepartureMonthDto(days, template, capacity.Value, capacity.Value > 5));
    }

    public async Task<ServiceResult<DepartureDayDto>> SaveDepartureAsync(
        Guid userId, Guid vehicleId, DateOnly date, SaveDepartureRequest request, CancellationToken ct)
    {
        var from = Clip(request.From?.Trim(), 120) ?? string.Empty;
        if (from.Length < 2) return Fail<DepartureDayDto>(400, "departure_from_required", "Where does the trip start?");
        if (!TimeOnly.TryParseExact(request.Time?.Trim(), "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var time))
        {
            return Fail<DepartureDayDto>(400, "departure_time_invalid", "Choose the departure time.");
        }
        var durationDays = Math.Clamp(request.DurationDays <= 0 ? 1 : request.DurationDays, 1, 7);

        var departureAt = new DateTimeOffset(date.ToDateTime(time), Karachi);
        if (departureAt < DateTimeOffset.UtcNow.AddMinutes(15))
        {
            return Fail<DepartureDayDto>(409, "departure_in_past", "That time has already passed. Choose a later time or another day.");
        }
        if (departureAt > DateTimeOffset.UtcNow.AddDays(120))
        {
            return Fail<DepartureDayDto>(400, "departure_too_far", "Departures can be posted up to 120 days ahead.");
        }

        await using var connection = await OpenAsync(ct);
        var profileId = await ProfileIdAsync(connection, userId, ct);
        if (profileId is null) return Fail<DepartureDayDto>(404, "vehicle_not_found", "This vehicle was not found on your account.");

        int capacity;
        bool liveForTour;
        string profileKind;
        bool drivesSelf;
        await using (var command = new NpgsqlCommand(
            """
            SELECT v.passenger_capacity, v.status = 'Verified' AND v.available_for_tour,
                   dp.profile_kind, dp.drives_self
            FROM udrive.vehicles v JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            WHERE v.id = @vehicleId AND dp.id = @profileId AND v.status <> 'Deleted';
            """, connection))
        {
            command.Parameters.AddWithValue("vehicleId", vehicleId);
            command.Parameters.AddWithValue("profileId", profileId.Value);
            await using var reader = await command.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct)) return Fail<DepartureDayDto>(404, "vehicle_not_found", "This vehicle was not found on your account.");
            capacity = reader.GetInt32(0);
            liveForTour = reader.GetBoolean(1);
            profileKind = reader.GetString(2);
            drivesSelf = reader.GetBoolean(3);
        }

        if (!liveForTour)
        {
            return Fail<DepartureDayDto>(409, "vehicle_not_live_for_tour",
                "This vehicle is not live for tours yet. It needs approval, and an approved driver.");
        }

        var wholePrice = decimal.Round(request.WholeVehiclePrice, 0);
        var seatPrice = capacity > 5 ? decimal.Round(Math.Max(0, request.PricePerSeat), 0) : 0m;
        if (wholePrice <= 0 || wholePrice > 2_000_000) return Fail<DepartureDayDto>(400, "departure_price_required", "Enter the price for the whole vehicle.");
        if (seatPrice > wholePrice) return Fail<DepartureDayDto>(400, "departure_price_invalid", "A seat cannot cost more than the whole vehicle.");

        string destinationName;
        await using (var command = new NpgsqlCommand(
            "SELECT name_en FROM udrive.destinations WHERE id = @id;", connection))
        {
            command.Parameters.AddWithValue("id", request.DestinationId);
            if (await command.ExecuteScalarAsync(ct) is not string name)
            {
                return Fail<DepartureDayDto>(400, "destination_not_found", "Choose where the trip goes.");
            }
            destinationName = name;
        }

        // Who drives: the driver chosen, else the owner when he drives, else the
        // only valid driver. A classic Driver profile is its own driver.
        var returnDate = date.AddDays(durationDays - 1);
        Guid? fleetDriverId = request.FleetDriverId;
        if (profileKind == "Owner" || fleetDriverId is not null)
        {
            var valid = await ValidDriversAsync(connection, profileId.Value, returnDate, ct);
            if (fleetDriverId is null)
            {
                var self = valid.FirstOrDefault(d => d.IsOwner);
                fleetDriverId = drivesSelf && self.Id != Guid.Empty ? self.Id
                    : valid.Count == 1 ? valid[0].Id
                    : null;
            }
            if (fleetDriverId is null || valid.All(d => d.Id != fleetDriverId))
            {
                return Fail<DepartureDayDto>(409, "driver_not_valid",
                    "Choose who drives this departure — an approved driver whose licence is valid on these dates.");
            }
        }

        var pickup = Clip(request.PickupPoint?.Trim(), 200);
        if (string.IsNullOrWhiteSpace(pickup)) pickup = from;

        await using var transaction = await connection.BeginTransactionAsync(ct);
        try
        {
            await using (var @lock = new NpgsqlCommand("SELECT 1 FROM udrive.vehicles WHERE id = @id FOR UPDATE;", connection, transaction))
            {
                @lock.Parameters.AddWithValue("id", vehicleId);
                await @lock.ExecuteScalarAsync(ct);
            }

            // A rental on any of these days wins: the car is with a customer.
            await using (var clash = new NpgsqlCommand(
                """
                SELECT EXISTS (
                    SELECT 1 FROM udrive.rental_bookings rb
                    WHERE rb.vehicle_id = @vehicleId
                      AND rb.status IN ('PendingOwner', 'Confirmed', 'HandedOver')
                      AND daterange(rb.start_date, rb.end_date, '[]') && daterange(@from, @to, '[]'));
                """, connection, transaction))
            {
                clash.Parameters.AddWithValue("vehicleId", vehicleId);
                clash.Parameters.Add(new NpgsqlParameter("from", NpgsqlDbType.Date) { Value = date });
                clash.Parameters.Add(new NpgsqlParameter("to", NpgsqlDbType.Date) { Value = returnDate });
                if (await clash.ExecuteScalarAsync(ct) is true)
                {
                    await transaction.RollbackAsync(ct);
                    return Fail<DepartureDayDto>(409, "vehicle_rented_that_day",
                        "This vehicle is booked for rent on those days.");
                }
            }

            Guid? existingId = null;
            int seatsSold = 0;
            DateTimeOffset existingDeparture = default;
            Guid existingDestination = Guid.Empty;
            await using (var find = new NpgsqlCommand(
                """
                SELECT tp.id, tp.total_seats - tp.available_seats, tp.departure_at, tp.destination_id
                FROM udrive.tour_packages tp
                WHERE tp.vehicle_id = @vehicleId AND tp.status = 'Active'
                  AND (tp.departure_at AT TIME ZONE 'Asia/Karachi')::date = @date
                ORDER BY tp.departure_at
                LIMIT 1;
                """, connection, transaction))
            {
                find.Parameters.AddWithValue("vehicleId", vehicleId);
                find.Parameters.Add(new NpgsqlParameter("date", NpgsqlDbType.Date) { Value = date });
                await using var reader = await find.ExecuteReaderAsync(ct);
                if (await reader.ReadAsync(ct))
                {
                    existingId = reader.GetGuid(0);
                    seatsSold = reader.GetInt32(1);
                    existingDeparture = reader.GetFieldValue<DateTimeOffset>(2);
                    existingDestination = reader.GetGuid(3);
                }
            }

            if (existingId is not null && seatsSold > 0
                && (existingDeparture != departureAt || existingDestination != request.DestinationId))
            {
                await transaction.RollbackAsync(ct);
                return Fail<DepartureDayDto>(409, "departure_has_passengers",
                    $"{seatsSold} seat(s) are already sold, so the route and time can't change. You can still change the driver.");
            }

            var title = Clip($"{from} → {destinationName}", 150)!;
            var returnAt = departureAt.AddDays(durationDays - 1).AddHours(10);

            if (existingId is null)
            {
                await using var insert = new NpgsqlCommand(
                    """
                    INSERT INTO udrive.tour_packages
                        (id, driver_profile_id, vehicle_id, destination_id, title, starting_city, pickup_point,
                         departure_at, return_at, total_seats, available_seats, price_per_seat, whole_vehicle_price,
                         customer_offers_allowed, status, fleet_driver_id, posted_as_daily, created_at, updated_at)
                    VALUES
                        (gen_random_uuid(), @profileId, @vehicleId, @destinationId, @title, @from, @pickup,
                         @departureAt, @returnAt, @seats, @seats, @seatPrice, @wholePrice,
                         true, 'Active', @driverId, true, now(), now())
                    RETURNING id;
                    """, connection, transaction);
                insert.Parameters.AddWithValue("profileId", profileId.Value);
                BindDeparture(insert, vehicleId, request.DestinationId, title, from, pickup!, departureAt, returnAt,
                    capacity, seatPrice, wholePrice, fleetDriverId);
                existingId = (Guid)(await insert.ExecuteScalarAsync(ct))!;
            }
            else
            {
                await using var update = new NpgsqlCommand(
                    """
                    UPDATE udrive.tour_packages
                    SET destination_id = @destinationId, title = @title, starting_city = @from, pickup_point = @pickup,
                        departure_at = @departureAt, return_at = @returnAt,
                        price_per_seat = @seatPrice, whole_vehicle_price = @wholePrice,
                        fleet_driver_id = @driverId, version = version + 1, updated_at = now()
                    WHERE id = @id AND vehicle_id = @vehicleId;
                    """, connection, transaction);
                update.Parameters.AddWithValue("id", existingId.Value);
                BindDeparture(update, vehicleId, request.DestinationId, title, from, pickup!, departureAt, returnAt,
                    capacity, seatPrice, wholePrice, fleetDriverId);
                await update.ExecuteNonQueryAsync(ct);
            }

            await transaction.CommitAsync(ct);
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            throw;
        }

        var saved = await DepartureRowsAsync(connection, vehicleId,
            "AND tp.status = 'Active' AND (tp.departure_at AT TIME ZONE 'Asia/Karachi')::date = @date",
            command => command.Parameters.Add(new NpgsqlParameter("date", NpgsqlDbType.Date) { Value = date }),
            1, ct);
        return ServiceResult<DepartureDayDto>.Ok(saved[0], "Live. Customers can see and book it now.");
    }

    public async Task<ServiceResult<object>> CancelDepartureAsync(
        Guid userId, Guid vehicleId, DateOnly date, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        var profileId = await ProfileIdAsync(connection, userId, ct);
        if (profileId is null || await VehicleStatusAsync(connection, profileId.Value, vehicleId, ct) is null)
        {
            return Fail<object>(404, "vehicle_not_found", "This vehicle was not found on your account.");
        }

        await using var command = new NpgsqlCommand(
            """
            WITH target AS (
                SELECT tp.id, tp.total_seats - tp.available_seats AS sold
                FROM udrive.tour_packages tp
                WHERE tp.vehicle_id = @vehicleId AND tp.status = 'Active'
                  AND (tp.departure_at AT TIME ZONE 'Asia/Karachi')::date = @date
                  AND NOT EXISTS (SELECT 1 FROM udrive.bookings b
                                  WHERE b.tour_package_id = tp.id
                                    AND b.status NOT IN ('Cancelled', 'NoShow', 'Draft'))
            )
            UPDATE udrive.tour_packages tp
            SET status = 'Cancelled', updated_at = now()
            FROM target t
            WHERE tp.id = t.id AND t.sold = 0
            RETURNING tp.id;
            """, connection);
        command.Parameters.AddWithValue("vehicleId", vehicleId);
        command.Parameters.Add(new NpgsqlParameter("date", NpgsqlDbType.Date) { Value = date });
        if (await command.ExecuteScalarAsync(ct) is Guid)
        {
            return ServiceResult<object>.Ok(new { date }, "The departure is cancelled.");
        }

        return Fail<object>(409, "departure_has_passengers",
            "Nothing to cancel, or seats are already sold on this departure. Contact UDrive support to cancel booked seats.");
    }

    // ═════════════════════════════════════════════════════════ admin

    public async Task<ServiceResult<IReadOnlyList<AdminListingDto>>> AdminListingsAsync(string? status, CancellationToken ct)
    {
        var filter = string.IsNullOrWhiteSpace(status) || status.Equals("All", StringComparison.OrdinalIgnoreCase)
            ? string.Empty : status.Trim();
        await using var connection = await OpenAsync(ct);
        return ServiceResult<IReadOnlyList<AdminListingDto>>.Ok(await AdminRowsAsync(connection, filter, null, ct));
    }

    public sealed record ApprovalResult(AdminListingDto Listing, string OwnerPhone, string Message);

    public async Task<ServiceResult<ApprovalResult>> ApproveListingAsync(Guid adminId, Guid vehicleId, CancellationToken ct)
    {
        await using var connection = await OpenAsync(ct);
        var row = (await AdminRowsAsync(connection, string.Empty, vehicleId, ct)).FirstOrDefault();
        if (row is null) return Fail<ApprovalResult>(404, "listing_not_found", "That listing was not found.");
        if (row.Status == "Verified") return ServiceResult<ApprovalResult>.Ok(new ApprovalResult(row, row.OwnerPhone, string.Empty));

        var docs = row.Docs;
        if (docs.Front is null || docs.RegistrationFront is null || docs.RegistrationBack is null
            || docs.CnicFront is null || docs.CnicBack is null || docs.Selfie is null)
        {
            return Fail<ApprovalResult>(409, "listing_documents_missing",
                "Some documents are missing. Use \"Ask for info\" to tell the owner which.");
        }
        if (row.DrivesSelf && (docs.LicenceFront is null || docs.LicenceBack is null || row.LicenceExpiry is null))
        {
            return Fail<ApprovalResult>(409, "listing_licence_missing",
                "The owner drives customers himself but his licence is missing.");
        }

        var minimum = await SettingIntAsync(connection, null, "tour.minimum_readiness", TourReadiness.DefaultMinimum, ct);

        await using var transaction = await connection.BeginTransactionAsync(ct);
        try
        {
            await using (var command = new NpgsqlCommand(
                """
                UPDATE udrive.driver_profiles dp
                SET verification_status = 'Approved', approved_at = COALESCE(approved_at, now()),
                    reviewed_at = now(), reviewed_by_user_id = @admin, updated_at = now()
                FROM udrive.vehicles v
                WHERE v.id = @vehicleId AND v.driver_profile_id = dp.id
                  AND dp.verification_status <> 'Approved';

                UPDATE udrive.driver_documents d
                SET status = 'Approved', updated_at = now()
                FROM udrive.vehicles v
                WHERE v.id = @vehicleId AND d.driver_profile_id = v.driver_profile_id
                  AND d.status <> 'Approved';

                UPDATE udrive.vehicle_documents SET status = 'Verified', updated_at = now()
                WHERE vehicle_id = @vehicleId;

                UPDATE udrive.vehicles v
                SET status = 'Verified', listing_review_note = NULL,
                    available_for_city = false,
                    available_for_rent = v.listing_wants_rent
                        AND NULLIF(v.image_url, '') IS NOT NULL
                        AND (COALESCE(v.rent_with_driver_daily, 0) > 0 OR COALESCE(v.rent_self_drive_daily, 0) > 0),
                    updated_at = now()
                WHERE v.id = @vehicleId;
                """, connection, transaction))
            {
                command.Parameters.AddWithValue("vehicleId", vehicleId);
                command.Parameters.AddWithValue("admin", adminId);
                await command.ExecuteNonQueryAsync(ct);
            }

            if (row.DrivesSelf)
            {
                await using var command = new NpgsqlCommand(
                    """
                    UPDATE udrive.fleet_drivers fd
                    SET status = 'Approved', reviewed_by = @admin, reviewed_at = now(), review_note = NULL, updated_at = now()
                    FROM udrive.vehicles v
                    WHERE v.id = @vehicleId AND fd.owner_profile_id = v.driver_profile_id
                      AND fd.is_owner AND fd.status = 'Submitted';
                    """, connection, transaction);
                command.Parameters.AddWithValue("vehicleId", vehicleId);
                command.Parameters.AddWithValue("admin", adminId);
                await command.ExecuteNonQueryAsync(ct);
            }

            await SwitchToursOnAsync(connection, transaction, "v.id = @key", vehicleId, minimum, ct);
            await AuditAsync(connection, transaction, adminId, "ListingApproved", "Vehicle", vehicleId, new { row.Name, row.RegistrationNumber }, ct);
            await transaction.CommitAsync(ct);
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            throw;
        }

        var after = (await AdminRowsAsync(connection, string.Empty, vehicleId, ct))[0];
        var live = await LiveSummaryAsync(connection, vehicleId, ct);
        var message = $"UDrive: your {after.Name} ({after.RegistrationNumber}) is approved. {live} "
            + "Open the UDrive app → My vehicles.";
        return ServiceResult<ApprovalResult>.Ok(new ApprovalResult(after, after.OwnerPhone, message));
    }

    public async Task<ServiceResult<ApprovalResult>> RejectListingAsync(
        Guid adminId, Guid vehicleId, string? reason, bool requestInfo, CancellationToken ct)
    {
        var note = Clip(reason?.Trim(), 500);
        if (string.IsNullOrWhiteSpace(note))
        {
            return Fail<ApprovalResult>(400, "reason_required",
                requestInfo ? "Write what the owner needs to add or fix." : "Write why the listing is rejected.");
        }

        await using var connection = await OpenAsync(ct);
        await using (var command = new NpgsqlCommand(
            """
            UPDATE udrive.vehicles
            SET status = @status, listing_review_note = @note,
                available_for_rent = false, available_for_tour = false, updated_at = now()
            WHERE id = @id AND listed_via IN ('Listing', 'Staff')
            RETURNING id;
            """, connection))
        {
            command.Parameters.AddWithValue("id", vehicleId);
            command.Parameters.AddWithValue("status", requestInfo ? "Draft" : "Rejected");
            command.Parameters.AddWithValue("note", note);
            if (await command.ExecuteScalarAsync(ct) is not Guid)
            {
                return Fail<ApprovalResult>(404, "listing_not_found", "That listing was not found.");
            }
        }

        await AuditAsync(connection, null, adminId, requestInfo ? "ListingInfoRequested" : "ListingRejected",
            "Vehicle", vehicleId, new { note }, ct);
        var row = (await AdminRowsAsync(connection, string.Empty, vehicleId, ct))[0];
        var message = requestInfo
            ? $"UDrive: please update your {row.Name} listing — {note} Open the UDrive app → My vehicles."
            : $"UDrive: your {row.Name} listing was not approved — {note}";
        return ServiceResult<ApprovalResult>.Ok(new ApprovalResult(row, row.OwnerPhone, message));
    }

    public async Task<ServiceResult<IReadOnlyList<AdminFleetDriverDto>>> AdminDriversAsync(string? status, CancellationToken ct)
    {
        var filter = string.IsNullOrWhiteSpace(status) || status.Equals("All", StringComparison.OrdinalIgnoreCase)
            ? string.Empty : status.Trim();
        await using var connection = await OpenAsync(ct);
        return ServiceResult<IReadOnlyList<AdminFleetDriverDto>>.Ok(await AdminDriverRowsAsync(connection, filter, null, ct));
    }

    public async Task<ServiceResult<AdminFleetDriverDto>> ReviewDriverAsync(
        Guid adminId, Guid driverId, bool approve, string? reason, CancellationToken ct)
    {
        var note = Clip(reason?.Trim(), 500);
        if (!approve && string.IsNullOrWhiteSpace(note))
        {
            return Fail<AdminFleetDriverDto>(400, "reason_required", "Write why the driver is rejected.");
        }

        await using var connection = await OpenAsync(ct);
        var row = (await AdminDriverRowsAsync(connection, string.Empty, driverId, ct)).FirstOrDefault();
        if (row is null) return Fail<AdminFleetDriverDto>(404, "driver_not_found", "That driver was not found.");
        if (approve)
        {
            var d = row.Docs;
            if (d.CnicFront is null || d.CnicBack is null || d.Selfie is null || d.LicenceFront is null || d.LicenceBack is null
                || row.LicenceExpiry is null)
            {
                return Fail<AdminFleetDriverDto>(409, "driver_documents_missing", "Some of the driver's documents are missing.");
            }
            if (row.LicenceExpiry.Value <= Today())
            {
                return Fail<AdminFleetDriverDto>(409, "licence_expired", "This driver's licence has expired.");
            }
        }

        var minimum = await SettingIntAsync(connection, null, "tour.minimum_readiness", TourReadiness.DefaultMinimum, ct);
        await using var transaction = await connection.BeginTransactionAsync(ct);
        try
        {
            await using (var command = new NpgsqlCommand(
                """
                UPDATE udrive.fleet_drivers
                SET status = @status, review_note = @note, reviewed_by = @admin, reviewed_at = now(), updated_at = now()
                WHERE id = @id;
                """, connection, transaction))
            {
                command.Parameters.AddWithValue("id", driverId);
                command.Parameters.AddWithValue("status", approve ? "Approved" : "Rejected");
                command.Parameters.Add(new NpgsqlParameter("note", NpgsqlDbType.Varchar) { Value = approve ? DBNull.Value : note! });
                command.Parameters.AddWithValue("admin", adminId);
                await command.ExecuteNonQueryAsync(ct);
            }

            // An owner whose vehicles waited for a driver: tours can go on now.
            if (approve)
            {
                await SwitchToursOnAsync(connection, transaction,
                    "v.driver_profile_id = (SELECT owner_profile_id FROM udrive.fleet_drivers WHERE id = @key)",
                    driverId, minimum, ct);
            }

            await AuditAsync(connection, transaction, adminId, approve ? "FleetDriverApproved" : "FleetDriverRejected",
                "FleetDriver", driverId, new { note }, ct);
            await transaction.CommitAsync(ct);
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            throw;
        }

        return ServiceResult<AdminFleetDriverDto>.Ok((await AdminDriverRowsAsync(connection, string.Empty, driverId, ct))[0]);
    }

    /// <summary>Staff list a vehicle for an owner they met in person: it goes live at once.</summary>
    public async Task<ServiceResult<AdminListingDto>> AddForOwnerAsync(
        Guid adminId, IFormCollection form, CancellationToken ct)
    {
        string Field(string key) => form.TryGetValue(key, out var value) ? value.ToString().Trim() : string.Empty;
        decimal? Money(string key) => decimal.TryParse(Field(key), NumberStyles.Number, CultureInfo.InvariantCulture, out var m) && m > 0 ? m : null;
        bool Flag(string key) => Field(key) is "true" or "True" or "on" or "1";

        if (!PhoneNumberNormalizer.TryNormalizePakistan(Field("ownerPhone"), out var ownerPhone))
        {
            return Fail<AdminListingDto>(400, "owner_phone_invalid", "Enter the owner's mobile number.");
        }
        var ownerName = Clip(Field("ownerName"), 120) ?? string.Empty;
        if (ownerName.Length < 2) return Fail<AdminListingDto>(400, "owner_name_required", "Enter the owner's name.");

        var request = new SaveListingVehicleRequest(
            Field("category"), Field("make"), Field("model"),
            int.TryParse(Field("year"), out var year) ? year : 0,
            Field("registrationNumber"),
            int.TryParse(Field("seats"), out var seats) ? seats : 0,
            Flag("wantsRent"), Flag("wantsTour"), "Drivers",
            Money("withDriverDaily"), Money("selfDriveDaily"), Field("pickupPoint"),
            new ListingKitDto(Field("category").Equals("Jeep", StringComparison.OrdinalIgnoreCase), false, false, false, false, false, false));
        var problem = ValidateVehicle(request, out var clean);
        if (problem is not null) return Fail<AdminListingDto>(400, problem.Value.Code, problem.Value.Message);

        var front = form.Files.GetFile("front");
        var regFront = form.Files.GetFile("registrationFront");
        var regBack = form.Files.GetFile("registrationBack");
        if (front is null || regFront is null || regBack is null)
        {
            return Fail<AdminListingDto>(400, "listing_photos_missing",
                "Add the car's front photo and both sides of the registration book.");
        }

        await using var connection = await OpenAsync(ct);

        Guid ownerUserId;
        await using (var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.users (id, phone_number, full_name, role, status, preferred_language, phone_verified, created_at, updated_at)
            VALUES (gen_random_uuid(), @phone, @name, 'Customer', 'Approved', 'en', false, now(), now())
            ON CONFLICT (phone_number) DO UPDATE SET
                full_name = CASE WHEN udrive.users.full_name = '' THEN EXCLUDED.full_name ELSE udrive.users.full_name END
            RETURNING id;
            """, connection))
        {
            command.Parameters.AddWithValue("phone", ownerPhone);
            command.Parameters.AddWithValue("name", ownerName);
            ownerUserId = (Guid)(await command.ExecuteScalarAsync(ct))!;
        }
        await using (var command = new NpgsqlCommand(
            "INSERT INTO udrive.user_roles (user_id, role, created_at) VALUES (@id, 'Customer', now()) ON CONFLICT DO NOTHING;", connection))
        {
            command.Parameters.AddWithValue("id", ownerUserId);
            await command.ExecuteNonQueryAsync(ct);
        }

        var saved = await SaveVehicleAsync(ownerUserId, null, request with { Drivers = "Drivers" }, ct);
        if (!saved.Success) return Fail<AdminListingDto>(saved.StatusCode, saved.ErrorCode!, saved.Message!);
        var vehicleId = saved.Data!.Id;

        foreach (var (kind, file) in new[] { ("front", front), ("registration-front", regFront), ("registration-back", regBack) })
        {
            var uploaded = await UploadVehiclePhotoAsync(ownerUserId, vehicleId, kind, file, ct);
            if (!uploaded.Success) return Fail<AdminListingDto>(uploaded.StatusCode, uploaded.ErrorCode!, uploaded.Message!);
        }
        foreach (var (kind, key) in new[] { ("cnic-front", "cnicFront"), ("cnic-back", "cnicBack") })
        {
            var file = form.Files.GetFile(key);
            if (file is null) continue;
            var uploaded = await UploadOwnerDocumentAsync(ownerUserId, kind, file, ct);
            if (!uploaded.Success) return Fail<AdminListingDto>(uploaded.StatusCode, uploaded.ErrorCode!, uploaded.Message!);
        }

        var minimum = await SettingIntAsync(connection, null, "tour.minimum_readiness", TourReadiness.DefaultMinimum, ct);
        await using (var command = new NpgsqlCommand(
            """
            UPDATE udrive.driver_profiles dp
            SET verification_status = 'Approved', approved_at = COALESCE(approved_at, now()),
                drives_self = CASE WHEN dp.profile_kind = 'Driver' THEN true ELSE false END,
                reviewed_at = now(), reviewed_by_user_id = @admin, updated_at = now()
            WHERE dp.user_id = @owner AND dp.verification_status <> 'Approved';

            UPDATE udrive.vehicles v
            SET status = 'Verified', listed_via = 'Staff', listing_added_by = @admin,
                listing_submitted_at = now(), available_for_city = false,
                available_for_rent = v.listing_wants_rent
                    AND NULLIF(v.image_url, '') IS NOT NULL
                    AND (COALESCE(v.rent_with_driver_daily, 0) > 0 OR COALESCE(v.rent_self_drive_daily, 0) > 0),
                updated_at = now()
            WHERE v.id = @vehicleId;
            """, connection))
        {
            command.Parameters.AddWithValue("owner", ownerUserId);
            command.Parameters.AddWithValue("vehicleId", vehicleId);
            command.Parameters.AddWithValue("admin", adminId);
            await command.ExecuteNonQueryAsync(ct);
        }

        await using (var transaction = await connection.BeginTransactionAsync(ct))
        {
            await SwitchToursOnAsync(connection, transaction, "v.id = @key", vehicleId, minimum, ct);
            await AuditAsync(connection, transaction, adminId, "ListingAddedByStaff", "Vehicle", vehicleId,
                new { ownerPhone, clean.RegistrationNumber }, ct);
            await transaction.CommitAsync(ct);
        }

        return ServiceResult<AdminListingDto>.Ok((await AdminRowsAsync(connection, string.Empty, vehicleId, ct))[0],
            "Listed and live. The owner can log in with this number to manage it.");
    }

    // ═════════════════════════════════════════════════════════ internals: reads

    private static async Task<Guid?> ProfileIdAsync(NpgsqlConnection connection, Guid userId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand("SELECT id FROM udrive.driver_profiles WHERE user_id = @userId;", connection);
        command.Parameters.AddWithValue("userId", userId);
        return await command.ExecuteScalarAsync(ct) as Guid?;
    }

    private static async Task<Guid> EnsureOwnerProfileAsync(NpgsqlConnection connection, Guid userId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO udrive.driver_profiles
                (id, user_id, verification_status, profile_kind, drives_self, created_at, updated_at)
            VALUES (gen_random_uuid(), @userId, 'Draft', 'Owner', false, now(), now())
            ON CONFLICT (user_id) DO NOTHING;
            SELECT id FROM udrive.driver_profiles WHERE user_id = @userId;
            """, connection);
        command.Parameters.AddWithValue("userId", userId);
        return (Guid)(await command.ExecuteScalarAsync(ct))!;
    }

    private static async Task<string?> VehicleStatusAsync(NpgsqlConnection connection, Guid profileId, Guid vehicleId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            "SELECT status FROM udrive.vehicles WHERE id = @id AND driver_profile_id = @p AND status <> 'Deleted';", connection);
        command.Parameters.AddWithValue("id", vehicleId);
        command.Parameters.AddWithValue("p", profileId);
        return await command.ExecuteScalarAsync(ct) as string;
    }

    private static async Task<int?> CapacityAsync(NpgsqlConnection connection, Guid profileId, Guid vehicleId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            "SELECT passenger_capacity FROM udrive.vehicles WHERE id = @id AND driver_profile_id = @p AND status <> 'Deleted';", connection);
        command.Parameters.AddWithValue("id", vehicleId);
        command.Parameters.AddWithValue("p", profileId);
        return await command.ExecuteScalarAsync(ct) as int?;
    }

    private async Task<ListingOwnerDto> OwnerAsync(NpgsqlConnection connection, Guid userId, Guid? profileId, CancellationToken ct)
    {
        var version = await AgreementVersionAsync(connection, ct);
        if (profileId is null)
        {
            return new ListingOwnerDto(false, false, false, false, false, false, false, null, null, false, version);
        }

        await using var command = new NpgsqlCommand(
            """
            SELECT dp.drives_self,
                   EXISTS (SELECT 1 FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id AND d.document_type = 'CNIC_FRONT'),
                   EXISTS (SELECT 1 FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id AND d.document_type = 'CNIC_BACK'),
                   EXISTS (SELECT 1 FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id AND d.document_type IN ('SELFIE', 'SELFIE_WITH_CNIC')),
                   EXISTS (SELECT 1 FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id AND d.document_type = 'DRIVING_LICENCE'),
                   EXISTS (SELECT 1 FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id AND d.document_type = 'DRIVING_LICENCE_BACK'),
                   dp.driving_licence_number, dp.driving_licence_expiry,
                   COALESCE(dp.owner_agreement_version, 0)
            FROM udrive.driver_profiles dp WHERE dp.id = @profileId;
            """, connection);
        command.Parameters.AddWithValue("profileId", profileId.Value);
        await using var reader = await command.ExecuteReaderAsync(ct);
        await reader.ReadAsync(ct);
        return new ListingOwnerDto(
            true,
            reader.GetBoolean(0),
            reader.GetBoolean(1), reader.GetBoolean(2), reader.GetBoolean(3), reader.GetBoolean(4), reader.GetBoolean(5),
            reader.IsDBNull(6) ? null : reader.GetString(6),
            reader.IsDBNull(7) ? null : DateOnly.FromDateTime(reader.GetDateTime(7)),
            reader.GetInt32(8) >= version,
            version);
    }

    private static async Task<IReadOnlyList<ListingVehicleDto>> VehiclesAsync(
        NpgsqlConnection connection, Guid profileId, Guid? vehicleId, CancellationToken ct)
    {
        var minimum = await SettingIntAsync(connection, null, "tour.minimum_readiness", TourReadiness.DefaultMinimum, ct);
        await using var command = new NpgsqlCommand(
            """
            SELECT v.id, v.make, v.model, v.year, v.category, v.is_four_by_four, v.registration_number,
                   v.passenger_capacity, NULLIF(v.image_url, ''), v.status, v.listing_review_note,
                   v.listing_wants_rent OR v.available_for_rent, v.listing_wants_tour OR v.available_for_tour,
                   v.available_for_rent, v.available_for_tour,
                   v.rent_with_driver_daily, v.rent_self_drive_daily, v.rent_pickup_point,
                   v.mountain_readiness_score,
                   v.is_four_by_four, v.has_first_aid_kit, v.has_spare_tyre, v.has_fire_extinguisher,
                   v.has_snow_chains, v.has_heating, v.has_air_conditioning,
                   EXISTS (SELECT 1 FROM udrive.vehicle_documents d WHERE d.vehicle_id = v.id AND d.document_type = 'VEHICLE_FRONT'),
                   EXISTS (SELECT 1 FROM udrive.vehicle_documents d WHERE d.vehicle_id = v.id AND d.document_type = 'REGISTRATION_BOOK'),
                   EXISTS (SELECT 1 FROM udrive.vehicle_documents d WHERE d.vehicle_id = v.id AND d.document_type = 'REGISTRATION_BOOK_BACK'),
                   (SELECT count(*)::int FROM udrive.rental_bookings rb WHERE rb.vehicle_id = v.id AND rb.status = 'PendingOwner')
            FROM udrive.vehicles v
            WHERE v.driver_profile_id = @profileId AND v.status <> 'Deleted'
              AND (@vehicleId::uuid IS NULL OR v.id = @vehicleId::uuid)
            ORDER BY v.created_at DESC;
            """, connection);
        command.Parameters.AddWithValue("profileId", profileId);
        command.Parameters.Add(new NpgsqlParameter("vehicleId", NpgsqlDbType.Uuid) { Value = (object?)vehicleId ?? DBNull.Value });

        var list = new List<ListingVehicleDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var make = reader.GetString(1);
            var model = reader.GetString(2);
            list.Add(new ListingVehicleDto(
                reader.GetGuid(0),
                $"{make} {model}".Trim(),
                make, model, reader.GetInt32(3), reader.GetString(4), reader.GetBoolean(5), reader.GetString(6),
                reader.GetInt32(7),
                reader.IsDBNull(8) ? null : reader.GetString(8),
                reader.GetString(9),
                reader.IsDBNull(10) ? null : reader.GetString(10),
                reader.GetBoolean(11), reader.GetBoolean(12), reader.GetBoolean(13), reader.GetBoolean(14),
                reader.IsDBNull(15) ? null : reader.GetDecimal(15),
                reader.IsDBNull(16) ? null : reader.GetDecimal(16),
                reader.IsDBNull(17) ? null : reader.GetString(17),
                reader.GetInt32(18), minimum,
                new ListingKitDto(reader.GetBoolean(19), reader.GetBoolean(20), reader.GetBoolean(21), reader.GetBoolean(22),
                    reader.GetBoolean(23), reader.GetBoolean(24), reader.GetBoolean(25)),
                new ListingVehicleDocsDto(reader.GetBoolean(26), reader.GetBoolean(27), reader.GetBoolean(28)),
                reader.GetInt32(29)));
        }
        return list;
    }

    private static async Task<IReadOnlyList<FleetDriverDto>> DriversAsync(NpgsqlConnection connection, Guid profileId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT fd.id, fd.full_name, fd.phone_number, fd.is_owner, fd.status, fd.licence_expiry, fd.review_note
            FROM udrive.fleet_drivers fd
            WHERE fd.owner_profile_id = @profileId AND fd.status NOT IN ('Removed', 'Declined')
            ORDER BY fd.is_owner DESC, fd.created_at;
            """, connection);
        command.Parameters.AddWithValue("profileId", profileId);
        var today = Today();
        var list = new List<FleetDriverDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var status = reader.GetString(4);
            DateOnly? expiry = reader.IsDBNull(5) ? null : DateOnly.FromDateTime(reader.GetDateTime(5));
            var valid = status == "Approved" && expiry is not null && expiry.Value >= today;
            list.Add(new FleetDriverDto(
                reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetBoolean(3), status,
                expiry, valid,
                expiry is null ? null : expiry.Value.DayNumber - today.DayNumber,
                reader.IsDBNull(6) ? null : reader.GetString(6)));
        }
        return list;
    }

    private readonly record struct ValidDriver(Guid Id, bool IsOwner);

    /// <summary>Approved drivers whose licence is still valid on <paramref name="through"/>.</summary>
    private static async Task<List<ValidDriver>> ValidDriversAsync(
        NpgsqlConnection connection, Guid profileId, DateOnly through, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT id, is_owner FROM udrive.fleet_drivers
            WHERE owner_profile_id = @profileId AND status = 'Approved'
              AND licence_expiry IS NOT NULL AND licence_expiry >= @through;
            """, connection);
        command.Parameters.AddWithValue("profileId", profileId);
        command.Parameters.Add(new NpgsqlParameter("through", NpgsqlDbType.Date) { Value = through });
        var list = new List<ValidDriver>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct)) list.Add(new ValidDriver(reader.GetGuid(0), reader.GetBoolean(1)));
        return list;
    }

    /// <summary>Whether this fleet driver may drive this owner's customers through that date.</summary>
    internal static async Task<bool> IsValidDriverAsync(
        NpgsqlConnection connection, NpgsqlTransaction? transaction, Guid profileId, Guid driverId, DateOnly through, CancellationToken ct)
    {
        await using var command = transaction is null
            ? new NpgsqlCommand(string.Empty, connection)
            : new NpgsqlCommand(string.Empty, connection, transaction);
        command.CommandText = """
            SELECT EXISTS (SELECT 1 FROM udrive.fleet_drivers
                           WHERE id = @id AND owner_profile_id = @profileId AND status = 'Approved'
                             AND licence_expiry IS NOT NULL AND licence_expiry >= @through);
            """;
        command.Parameters.AddWithValue("id", driverId);
        command.Parameters.AddWithValue("profileId", profileId);
        command.Parameters.Add(new NpgsqlParameter("through", NpgsqlDbType.Date) { Value = through });
        return await command.ExecuteScalarAsync(ct) is true;
    }

    private static async Task<IReadOnlyList<DriverInviteDto>> InviteRowsAsync(
        NpgsqlConnection connection, Guid userId, Guid? inviteId, CancellationToken ct)
    {
        var version = await SettingIntAsync(connection, null, "listing.agreement_version", 1, ct);
        await using var command = new NpgsqlCommand(
            """
            SELECT fd.id, COALESCE(NULLIF(ou.full_name, ''), 'A UDrive owner'),
                   COALESCE((SELECT string_agg(trim(concat_ws(' ', v.make, v.model, v.year::text)) || ' · ' || v.registration_number, ', ')
                             FROM udrive.vehicles v
                             WHERE v.driver_profile_id = fd.owner_profile_id AND v.status <> 'Deleted'), ''),
                   fd.status,
                   fd.cnic_front_url IS NOT NULL, fd.cnic_back_url IS NOT NULL, fd.selfie_url IS NOT NULL,
                   fd.licence_front_url IS NOT NULL, fd.licence_back_url IS NOT NULL,
                   fd.licence_number, fd.licence_expiry, fd.review_note
            FROM udrive.fleet_drivers fd
            JOIN udrive.driver_profiles dp ON dp.id = fd.owner_profile_id
            JOIN udrive.users ou ON ou.id = dp.user_id
            JOIN udrive.users me ON me.id = @userId
            WHERE NOT fd.is_owner
              AND (fd.user_id = me.id OR fd.phone_number = me.phone_number)
              AND fd.status IN ('Invited', 'Submitted', 'Rejected', 'Approved')
              AND (@inviteId::uuid IS NULL OR fd.id = @inviteId::uuid)
            ORDER BY fd.created_at DESC;
            """, connection);
        command.Parameters.AddWithValue("userId", userId);
        command.Parameters.Add(new NpgsqlParameter("inviteId", NpgsqlDbType.Uuid) { Value = (object?)inviteId ?? DBNull.Value });
        var list = new List<DriverInviteDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            list.Add(new DriverInviteDto(
                reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
                reader.GetBoolean(4), reader.GetBoolean(5), reader.GetBoolean(6), reader.GetBoolean(7), reader.GetBoolean(8),
                reader.IsDBNull(9) ? null : reader.GetString(9),
                reader.IsDBNull(10) ? null : DateOnly.FromDateTime(reader.GetDateTime(10)),
                version,
                reader.IsDBNull(11) ? null : reader.GetString(11)));
        }
        return list;
    }

    private static async Task<IReadOnlyList<RentCalendarDayDto>> CalendarRowsAsync(
        NpgsqlConnection connection, Guid vehicleId, DateOnly from, int days, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT g.day::date,
                   CASE
                     WHEN g.day::date < @today THEN 'past'
                     WHEN EXISTS (SELECT 1 FROM udrive.rental_bookings rb
                                  WHERE rb.vehicle_id = @vehicleId AND rb.status IN ('Confirmed', 'HandedOver')
                                    AND g.day::date BETWEEN rb.start_date AND rb.end_date) THEN 'booked'
                     WHEN EXISTS (SELECT 1 FROM udrive.rental_bookings rb
                                  WHERE rb.vehicle_id = @vehicleId AND rb.status = 'PendingOwner'
                                    AND g.day::date BETWEEN rb.start_date AND rb.end_date) THEN 'pending'
                     WHEN EXISTS (SELECT 1 FROM udrive.rental_blocked_days b
                                  WHERE b.vehicle_id = @vehicleId AND b.day = g.day::date) THEN 'blocked'
                     WHEN EXISTS (SELECT 1 FROM udrive.tour_packages tp
                                  WHERE tp.vehicle_id = @vehicleId AND tp.status = 'Active'
                                    AND g.day::date BETWEEN (tp.departure_at AT TIME ZONE 'Asia/Karachi')::date
                                                        AND (COALESCE(tp.return_at, tp.departure_at) AT TIME ZONE 'Asia/Karachi')::date)
                       THEN 'tour'
                     ELSE 'free'
                   END
            FROM generate_series(@from::date, @from::date + (@days - 1), interval '1 day') AS g(day)
            ORDER BY 1;
            """, connection);
        command.Parameters.AddWithValue("vehicleId", vehicleId);
        command.Parameters.Add(new NpgsqlParameter("from", NpgsqlDbType.Date) { Value = from });
        command.Parameters.Add(new NpgsqlParameter("today", NpgsqlDbType.Date) { Value = Today() });
        command.Parameters.AddWithValue("days", days);
        var list = new List<RentCalendarDayDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            list.Add(new RentCalendarDayDto(DateOnly.FromDateTime(reader.GetDateTime(0)), reader.GetString(1)));
        }
        return list;
    }

    private static async Task<IReadOnlyList<DepartureDayDto>> DepartureRowsAsync(
        NpgsqlConnection connection, Guid vehicleId, string predicate, Action<NpgsqlCommand> bind,
        int limit, CancellationToken ct, bool newestFirst = false)
    {
        var order = newestFirst ? "tp.created_at DESC" : "tp.departure_at";
        await using var command = new NpgsqlCommand(
            $"""
            SELECT (tp.departure_at AT TIME ZONE 'Asia/Karachi')::date,
                   tp.id, tp.starting_city, tp.destination_id, d.name_en,
                   to_char(tp.departure_at AT TIME ZONE 'Asia/Karachi', 'HH24:MI'),
                   GREATEST(1, ((COALESCE(tp.return_at, tp.departure_at) AT TIME ZONE 'Asia/Karachi')::date
                                - (tp.departure_at AT TIME ZONE 'Asia/Karachi')::date) + 1),
                   tp.total_seats - tp.available_seats, tp.total_seats,
                   tp.price_per_seat, tp.whole_vehicle_price, tp.pickup_point,
                   tp.fleet_driver_id, fd.full_name
            FROM udrive.tour_packages tp
            JOIN udrive.destinations d ON d.id = tp.destination_id
            LEFT JOIN udrive.fleet_drivers fd ON fd.id = tp.fleet_driver_id
            WHERE tp.vehicle_id = @vehicleId {predicate}
            ORDER BY {order}
            LIMIT {limit};
            """, connection);
        command.Parameters.AddWithValue("vehicleId", vehicleId);
        bind(command);
        var list = new List<DepartureDayDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            list.Add(new DepartureDayDto(
                DateOnly.FromDateTime(reader.GetDateTime(0)),
                reader.GetGuid(1), reader.GetString(2), reader.GetGuid(3), reader.GetString(4), reader.GetString(5),
                reader.GetInt32(6), reader.GetInt32(7), reader.GetInt32(8),
                reader.GetDecimal(9), reader.GetDecimal(10), reader.GetString(11),
                reader.IsDBNull(12) ? null : reader.GetGuid(12),
                reader.IsDBNull(13) ? null : reader.GetString(13)));
        }
        return list;
    }

    private static async Task<IReadOnlyList<AdminListingDto>> AdminRowsAsync(
        NpgsqlConnection connection, string status, Guid? vehicleId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT v.id, trim(concat_ws(' ', v.make, v.model)), v.year, v.category, v.registration_number,
                   v.passenger_capacity, NULLIF(v.image_url, ''),
                   v.listing_wants_rent, v.listing_wants_tour, v.rent_with_driver_daily, v.rent_self_drive_daily,
                   v.mountain_readiness_score, v.status, v.listing_review_note, v.listing_submitted_at, v.listed_via,
                   u.id, COALESCE(NULLIF(u.full_name, ''), 'Owner'), u.phone_number,
                   (SELECT count(*)::int FROM udrive.vehicles x WHERE x.driver_profile_id = dp.id AND x.status <> 'Deleted'),
                   dp.drives_self, dp.driving_licence_number, dp.driving_licence_expiry,
                   (SELECT file_url FROM udrive.vehicle_documents d WHERE d.vehicle_id = v.id AND d.document_type = 'VEHICLE_FRONT'),
                   (SELECT file_url FROM udrive.vehicle_documents d WHERE d.vehicle_id = v.id AND d.document_type = 'REGISTRATION_BOOK'),
                   (SELECT file_url FROM udrive.vehicle_documents d WHERE d.vehicle_id = v.id AND d.document_type = 'REGISTRATION_BOOK_BACK'),
                   (SELECT file_url FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id AND d.document_type = 'CNIC_FRONT'),
                   (SELECT file_url FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id AND d.document_type = 'CNIC_BACK'),
                   (SELECT file_url FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id
                      AND d.document_type IN ('SELFIE', 'SELFIE_WITH_CNIC') ORDER BY d.document_type LIMIT 1),
                   (SELECT file_url FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id AND d.document_type = 'DRIVING_LICENCE'),
                   (SELECT file_url FROM udrive.driver_documents d WHERE d.driver_profile_id = dp.id AND d.document_type = 'DRIVING_LICENCE_BACK')
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE v.listed_via IN ('Listing', 'Staff') AND v.status <> 'Deleted'
              AND (@status = '' OR v.status = @status)
              AND (@vehicleId::uuid IS NULL OR v.id = @vehicleId::uuid)
            ORDER BY (v.status = 'PendingReview') DESC, v.listing_submitted_at DESC NULLS LAST, v.created_at DESC
            LIMIT 500;
            """, connection);
        command.Parameters.AddWithValue("status", status);
        command.Parameters.Add(new NpgsqlParameter("vehicleId", NpgsqlDbType.Uuid) { Value = (object?)vehicleId ?? DBNull.Value });
        var list = new List<AdminListingDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        string? S(int i) => reader.IsDBNull(i) ? null : reader.GetString(i);
        while (await reader.ReadAsync(ct))
        {
            list.Add(new AdminListingDto(
                reader.GetGuid(0), reader.GetString(1), reader.GetInt32(2), reader.GetString(3), reader.GetString(4),
                reader.GetInt32(5), S(6), reader.GetBoolean(7), reader.GetBoolean(8),
                reader.IsDBNull(9) ? null : reader.GetDecimal(9),
                reader.IsDBNull(10) ? null : reader.GetDecimal(10),
                reader.GetInt32(11), reader.GetString(12), S(13),
                reader.IsDBNull(14) ? null : reader.GetFieldValue<DateTimeOffset>(14),
                reader.GetString(15), reader.GetGuid(16), reader.GetString(17), reader.GetString(18), reader.GetInt32(19),
                reader.GetBoolean(20), S(21),
                reader.IsDBNull(22) ? null : DateOnly.FromDateTime(reader.GetDateTime(22)),
                new AdminListingDocsDto(S(23), S(24), S(25), S(26), S(27), S(28), S(29), S(30))));
        }
        return list;
    }

    private static async Task<IReadOnlyList<AdminFleetDriverDto>> AdminDriverRowsAsync(
        NpgsqlConnection connection, string status, Guid? driverId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT fd.id, fd.full_name, fd.phone_number, fd.is_owner,
                   COALESCE(NULLIF(ou.full_name, ''), 'Owner'), ou.phone_number,
                   fd.status, fd.licence_number, fd.licence_expiry, fd.submitted_at, fd.review_note,
                   fd.cnic_front_url, fd.cnic_back_url, fd.selfie_url, fd.licence_front_url, fd.licence_back_url
            FROM udrive.fleet_drivers fd
            JOIN udrive.driver_profiles dp ON dp.id = fd.owner_profile_id
            JOIN udrive.users ou ON ou.id = dp.user_id
            WHERE fd.status NOT IN ('Removed', 'Declined')
              AND (@status = '' OR fd.status = @status)
              AND (@driverId::uuid IS NULL OR fd.id = @driverId::uuid)
            ORDER BY (fd.status = 'Submitted') DESC, fd.submitted_at DESC NULLS LAST, fd.created_at DESC
            LIMIT 500;
            """, connection);
        command.Parameters.AddWithValue("status", status);
        command.Parameters.Add(new NpgsqlParameter("driverId", NpgsqlDbType.Uuid) { Value = (object?)driverId ?? DBNull.Value });
        var today = Today();
        var list = new List<AdminFleetDriverDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        string? S(int i) => reader.IsDBNull(i) ? null : reader.GetString(i);
        while (await reader.ReadAsync(ct))
        {
            var rowStatus = reader.GetString(6);
            DateOnly? expiry = reader.IsDBNull(8) ? null : DateOnly.FromDateTime(reader.GetDateTime(8));
            list.Add(new AdminFleetDriverDto(
                reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetBoolean(3),
                reader.GetString(4), reader.GetString(5), rowStatus, S(7), expiry,
                rowStatus == "Approved" && expiry is not null && expiry.Value >= today,
                reader.IsDBNull(9) ? null : reader.GetFieldValue<DateTimeOffset>(9),
                S(10),
                new AdminFleetDriverDocsDto(S(11), S(12), S(13), S(14), S(15))));
        }
        return list;
    }

    // ═════════════════════════════════════════════════════════ internals: writes

    private async Task UpsertOwnerDriverRowAsync(
        NpgsqlConnection connection, NpgsqlTransaction transaction, Guid userId, Guid profileId,
        string licenceNumber, DateOnly licenceExpiry, int agreementVersion, bool approve, Guid? reviewer, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            WITH docs AS (
                SELECT
                    (SELECT file_url FROM udrive.driver_documents WHERE driver_profile_id = @profileId AND document_type = 'CNIC_FRONT') AS cnic_front,
                    (SELECT file_url FROM udrive.driver_documents WHERE driver_profile_id = @profileId AND document_type = 'CNIC_BACK') AS cnic_back,
                    (SELECT file_url FROM udrive.driver_documents WHERE driver_profile_id = @profileId
                       AND document_type IN ('SELFIE', 'SELFIE_WITH_CNIC') ORDER BY document_type LIMIT 1) AS selfie,
                    (SELECT file_url FROM udrive.driver_documents WHERE driver_profile_id = @profileId AND document_type = 'DRIVING_LICENCE') AS lic_front,
                    (SELECT file_url FROM udrive.driver_documents WHERE driver_profile_id = @profileId AND document_type = 'DRIVING_LICENCE_BACK') AS lic_back
            ),
            existing AS (
                UPDATE udrive.fleet_drivers fd
                SET licence_number = @licence, licence_expiry = @expiry,
                    expiry_reminded_at = CASE WHEN fd.licence_expiry IS DISTINCT FROM @expiry
                                              THEN NULL ELSE fd.expiry_reminded_at END,
                    cnic_front_url = docs.cnic_front, cnic_back_url = docs.cnic_back, selfie_url = docs.selfie,
                    licence_front_url = docs.lic_front, licence_back_url = docs.lic_back,
                    agreement_version = @version, agreement_accepted_at = now(),
                    status = CASE WHEN @approve THEN 'Approved'
                                  WHEN fd.status = 'Approved' AND fd.licence_expiry = @expiry THEN 'Approved'
                                  ELSE 'Submitted' END,
                    submitted_at = now(), updated_at = now()
                FROM docs
                WHERE fd.owner_profile_id = @profileId AND fd.is_owner AND fd.status NOT IN ('Removed', 'Declined')
                RETURNING fd.id
            )
            INSERT INTO udrive.fleet_drivers
                (id, owner_profile_id, user_id, phone_number, full_name, is_owner, status,
                 licence_number, licence_expiry, cnic_front_url, cnic_back_url, selfie_url,
                 licence_front_url, licence_back_url, agreement_version, agreement_accepted_at,
                 submitted_at, created_at, updated_at)
            SELECT gen_random_uuid(), @profileId, u.id, u.phone_number, COALESCE(NULLIF(u.full_name, ''), 'Owner'), true,
                   CASE WHEN @approve THEN 'Approved' ELSE 'Submitted' END,
                   @licence, @expiry, docs.cnic_front, docs.cnic_back, docs.selfie, docs.lic_front, docs.lic_back,
                   @version, now(), now(), now(), now()
            FROM udrive.users u, docs
            WHERE u.id = @userId AND NOT EXISTS (SELECT 1 FROM existing);
            """, connection, transaction);
        command.Parameters.AddWithValue("profileId", profileId);
        command.Parameters.AddWithValue("userId", userId);
        command.Parameters.AddWithValue("licence", licenceNumber);
        command.Parameters.Add(new NpgsqlParameter("expiry", NpgsqlDbType.Date) { Value = licenceExpiry });
        command.Parameters.AddWithValue("version", agreementVersion);
        command.Parameters.AddWithValue("approve", approve);
        await command.ExecuteNonQueryAsync(ct);
        _ = reviewer;
    }

    /// <summary>
    /// Turns tours on for verified listing vehicles that asked for them, are
    /// ready enough for mountain roads, and have someone valid to drive.
    /// </summary>
    private static async Task SwitchToursOnAsync(
        NpgsqlConnection connection, NpgsqlTransaction transaction, string scope, Guid key, int minimum, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            $"""
            UPDATE udrive.vehicles v
            SET available_for_tour = true, updated_at = now()
            WHERE {scope}
              AND v.status = 'Verified' AND v.listing_wants_tour AND NOT v.available_for_tour
              AND v.mountain_readiness_score >= @minimum
              AND (EXISTS (SELECT 1 FROM udrive.driver_profiles dp
                           WHERE dp.id = v.driver_profile_id AND dp.profile_kind = 'Driver')
                   OR EXISTS (SELECT 1 FROM udrive.fleet_drivers fd
                              WHERE fd.owner_profile_id = v.driver_profile_id AND fd.status = 'Approved'
                                AND fd.licence_expiry >= (now() AT TIME ZONE 'Asia/Karachi')::date));
            """, connection, transaction);
        command.Parameters.AddWithValue("key", key);
        command.Parameters.AddWithValue("minimum", minimum);
        await command.ExecuteNonQueryAsync(ct);
    }

    private static async Task<string> LiveSummaryAsync(NpgsqlConnection connection, Guid vehicleId, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT available_for_rent, available_for_tour, listing_wants_tour, mountain_readiness_score
            FROM udrive.vehicles WHERE id = @id;
            """, connection);
        command.Parameters.AddWithValue("id", vehicleId);
        await using var reader = await command.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct)) return string.Empty;
        var rent = reader.GetBoolean(0);
        var tour = reader.GetBoolean(1);
        var wantsTour = reader.GetBoolean(2);
        var parts = new List<string>();
        if (rent) parts.Add("It is live for rent.");
        if (tour) parts.Add("It is live for tours — post today's departure in the app.");
        else if (wantsTour) parts.Add("Tours switch on once an approved driver is added (or its tour equipment is complete).");
        return string.Join(' ', parts);
    }

    private static void BindVehicle(NpgsqlCommand command, CleanVehicle clean, int readiness)
    {
        command.Parameters.AddWithValue("category", clean.Category);
        command.Parameters.AddWithValue("make", clean.Make);
        command.Parameters.AddWithValue("model", clean.Model);
        command.Parameters.AddWithValue("year", clean.Year);
        command.Parameters.AddWithValue("registration", clean.RegistrationNumber);
        command.Parameters.AddWithValue("seats", clean.Seats);
        command.Parameters.AddWithValue("ac", clean.Kit.AirConditioning);
        command.Parameters.AddWithValue("heating", clean.Kit.Heating);
        command.Parameters.AddWithValue("fourByFour", clean.Kit.FourByFour);
        command.Parameters.AddWithValue("firstAid", clean.Kit.FirstAidKit);
        command.Parameters.AddWithValue("extinguisher", clean.Kit.FireExtinguisher);
        command.Parameters.AddWithValue("spare", clean.Kit.SpareTyre);
        command.Parameters.AddWithValue("chains", clean.Kit.SnowChains);
        command.Parameters.AddWithValue("readiness", readiness);
        command.Parameters.AddWithValue("bookingMode", clean.Seats > 5 ? "Both" : "WholeVehicle");
        command.Parameters.Add(new NpgsqlParameter("withDriver", NpgsqlDbType.Numeric) { Value = (object?)clean.WithDriverDaily ?? DBNull.Value });
        command.Parameters.Add(new NpgsqlParameter("selfDrive", NpgsqlDbType.Numeric) { Value = (object?)clean.SelfDriveDaily ?? DBNull.Value });
        command.Parameters.Add(new NpgsqlParameter("pickup", NpgsqlDbType.Varchar) { Value = (object?)clean.PickupPoint ?? DBNull.Value });
        command.Parameters.AddWithValue("wantsRent", clean.WantsRent);
        command.Parameters.AddWithValue("wantsTour", clean.WantsTour);
    }

    private static void BindDeparture(
        NpgsqlCommand command, Guid vehicleId, Guid destinationId, string title, string from, string pickup,
        DateTimeOffset departureAt, DateTimeOffset returnAt, int seats, decimal seatPrice, decimal wholePrice, Guid? driverId)
    {
        command.Parameters.AddWithValue("vehicleId", vehicleId);
        command.Parameters.AddWithValue("destinationId", destinationId);
        command.Parameters.AddWithValue("title", title);
        command.Parameters.AddWithValue("from", from);
        command.Parameters.AddWithValue("pickup", pickup);
        command.Parameters.AddWithValue("departureAt", departureAt.ToUniversalTime());
        command.Parameters.AddWithValue("returnAt", returnAt.ToUniversalTime());
        command.Parameters.AddWithValue("seats", seats);
        command.Parameters.AddWithValue("seatPrice", seatPrice);
        command.Parameters.AddWithValue("wholePrice", wholePrice);
        command.Parameters.Add(new NpgsqlParameter("driverId", NpgsqlDbType.Uuid) { Value = (object?)driverId ?? DBNull.Value });
    }

    // ═════════════════════════════════════════════════════════ validation

    private sealed record CleanVehicle(
        string Category, string Make, string Model, int Year, string RegistrationNumber, int Seats,
        bool WantsRent, bool WantsTour, bool DrivesSelf,
        decimal? WithDriverDaily, decimal? SelfDriveDaily, string? PickupPoint, ListingKitDto Kit);

    private static (string Code, string Message)? ValidateVehicle(SaveListingVehicleRequest request, out CleanVehicle clean)
    {
        clean = null!;
        var category = (request.Category ?? string.Empty).Trim().ToLowerInvariant() switch
        {
            "car" => "Car",
            "jeep" or "4x4" => "Jeep",
            "hiace" => "Hiace",
            "coster" or "coaster" => "Coster",
            _ => null,
        };
        if (category is null) return ("category_invalid", "Choose the vehicle type: Car, Jeep, Hiace or Coster.");

        var make = Clip(request.Make?.Trim(), 60) ?? string.Empty;
        var model = Clip(request.Model?.Trim(), 60) ?? string.Empty;
        if (make.Length < 2 || model.Length < 1) return ("make_model_required", "Enter the make and model, e.g. Toyota Corolla.");

        var maxYear = Today().Year + 1;
        if (request.Year < 1980 || request.Year > maxYear) return ("year_invalid", $"Enter a model year between 1980 and {maxYear}.");

        var plate = new string((request.RegistrationNumber ?? string.Empty).Trim().ToUpperInvariant()
            .Where(c => char.IsLetterOrDigit(c) || c is '-' or ' ').ToArray());
        plate = string.Join(' ', plate.Split(' ', StringSplitOptions.RemoveEmptyEntries));
        if (plate.Length < 3 || plate.Length > 20) return ("registration_invalid", "Enter the number plate, e.g. MRD-1234.");

        if (request.Seats < 1 || request.Seats > 60) return ("seats_invalid", "Seats must be between 1 and 60.");
        if (!request.WantsRent && !request.WantsTour) return ("purpose_required", "Choose Rent, Tour, or both.");

        decimal? Rate(decimal? value) => value is > 0 ? decimal.Round(value.Value, 0) : null;
        var withDriver = Rate(request.WithDriverDaily);
        var selfDrive = Rate(request.SelfDriveDaily);
        if (withDriver > 1_000_000 || selfDrive > 1_000_000) return ("rate_invalid", "That daily rate is too high.");
        if (request.WantsRent && withDriver is null && selfDrive is null)
        {
            return ("listing_rent_rate_required", "Give a daily rent rate — with driver, self-drive, or both.");
        }

        var drivesSelf = (request.Drivers ?? "Self").Trim().ToLowerInvariant() is "self" or "both";
        var kit = request.Kit ?? new ListingKitDto(false, false, false, false, false, false, false);
        if (category == "Jeep") kit = kit with { FourByFour = true };

        clean = new CleanVehicle(
            category == "Jeep" ? "Car" : category, make, model, request.Year, plate, request.Seats,
            request.WantsRent, request.WantsTour, drivesSelf,
            request.WantsRent ? withDriver : null, request.WantsRent ? selfDrive : null,
            Clip(request.PickupPoint?.Trim(), 200) is { Length: > 0 } pickup ? pickup : null,
            kit);
        return null;
    }

    // ═════════════════════════════════════════════════════════ helpers

    private sealed record SavedFile(string ProtectedUrl, string PublicUrl);

    private async Task<ServiceResult<SavedFile>> SaveFileAsync(IFormFile? file, string category, Guid ownerId, CancellationToken ct)
    {
        if (file is null) return Fail<SavedFile>(400, "file_required", "Choose a photo.");
        try
        {
            var stored = await fileStorage.SaveAsync(file, category, ownerId, ct);
            var segments = stored.RelativeUrl.Split('/', StringSplitOptions.RemoveEmptyEntries);
            var publicUrl = category == "vehicle-images" && segments.Length >= 2
                ? $"/api/v1/vehicle-images/{segments[^2]}/{segments[^1]}"
                : stored.RelativeUrl;
            return ServiceResult<SavedFile>.Ok(new SavedFile(stored.RelativeUrl, publicUrl));
        }
        catch (InvalidDataException error)
        {
            return Fail<SavedFile>(400, "file_invalid", error.Message);
        }
        catch (InvalidOperationException error)
        {
            return Fail<SavedFile>(503, "storage_unavailable", error.Message);
        }
    }

    internal static async Task<int> SettingIntAsync(
        NpgsqlConnection connection, NpgsqlTransaction? transaction, string key, int fallback, CancellationToken ct)
    {
        await using var command = transaction is null
            ? new NpgsqlCommand(string.Empty, connection)
            : new NpgsqlCommand(string.Empty, connection, transaction);
        command.CommandText = """
            SELECT COALESCE((SELECT GREATEST(0, (value_json #>> '{}')::int)
                             FROM udrive.system_settings WHERE key = @key), @fallback);
            """;
        command.Parameters.AddWithValue("key", key);
        command.Parameters.AddWithValue("fallback", fallback);
        return await command.ExecuteScalarAsync(ct) is int value ? value : fallback;
    }

    private static Task<int> AgreementVersionAsync(NpgsqlConnection connection, CancellationToken ct) =>
        SettingIntAsync(connection, null, "listing.agreement_version", 1, ct);

    private static async Task AuditAsync(
        NpgsqlConnection connection, NpgsqlTransaction? transaction, Guid adminId, string action,
        string entity, Guid id, object changes, CancellationToken ct)
    {
        await using var command = transaction is null
            ? new NpgsqlCommand(string.Empty, connection)
            : new NpgsqlCommand(string.Empty, connection, transaction);
        command.CommandText = """
            INSERT INTO udrive.audit_logs
                (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
            VALUES (gen_random_uuid(), @admin, @action, @entity, CAST(@id AS text), CAST(@changes AS jsonb), now(), now());
            """;
        command.Parameters.AddWithValue("admin", adminId);
        command.Parameters.AddWithValue("action", action);
        command.Parameters.AddWithValue("entity", entity);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("changes", JsonSerializer.Serialize(changes));
        await command.ExecuteNonQueryAsync(ct);
    }

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken ct)
    {
        var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        return connection;
    }

    internal static DateOnly Today() =>
        DateOnly.FromDateTime(DateTimeOffset.UtcNow.ToOffset(Karachi).DateTime);

    private static string MaskLicence(string licence) =>
        licence.Length <= 4 ? new string('*', licence.Length) : new string('*', licence.Length - 4) + licence[^4..];

    private static string? Clip(string? value, int max) =>
        value is null ? null : value.Length <= max ? value : value[..max];

    private static ServiceResult<T> Fail<T>(int status, string code, string message) =>
        ServiceResult<T>.Fail(status, code, message);
}
