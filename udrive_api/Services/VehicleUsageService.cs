using Microsoft.AspNetCore.Http;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Domain;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

/// <summary>
/// What an approved vehicle is used for: city rides, tours, or rent.
/// </summary>
/// <remarks>
/// There is one way to put a vehicle on the platform and this is not it. A
/// Driver registers the vehicle, an Admin verifies it, and only then does this
/// service have anything to act on. Nothing here creates a vehicle, changes its
/// documents, or touches its verification.
///
/// What it does is let a Driver say what the vehicle is *for*, which until now
/// was decided by absence: every verified vehicle took city rides because
/// nothing asked, tour was one flag with no requirement behind it, and rental
/// could not be expressed at all.
/// </remarks>
public sealed class VehicleUsageService(
    string connectionString,
    LocalFileStorageService fileStorage)
{
    /// <summary>Stores the owner's own photograph of this vehicle.</summary>
    /// <remarks>
    /// One photograph, writing <c>vehicles.image_url</c> — a column that has
    /// existed since the first schema and that only the demo seed has ever
    /// filled, because no route let a Driver put anything in it. Four slots, a
    /// gallery and a review queue were all considered and dropped: a rental
    /// listing needs to show that this is a real car in reasonable condition,
    /// and one honest photograph does that.
    ///
    /// Public the moment it is saved. Nobody reviews it, which is the Driver's
    /// own responsibility — a bad photograph costs them the booking, and that
    /// is a faster and fairer correction than a queue.
    ///
    /// Saved under <c>vehicle-images</c>, the one upload category this platform
    /// already serves anonymously, so the customer app can load it in an
    /// ordinary image tag. Driver documents keep their protected route and
    /// nothing here opens them.
    /// </remarks>
    public async Task<ServiceResult<VehicleUsageDto>> UploadPhotoAsync(
        Guid userId,
        Guid vehicleId,
        IFormFile file,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var current = await ReadOneAsync(connection, userId, vehicleId, cancellationToken);
        if (current is null)
        {
            return ServiceResult<VehicleUsageDto>.Fail(
                StatusCodes.Status404NotFound,
                "vehicle_not_found",
                "This vehicle was not found on your account.");
        }

        StoredFile stored;
        try
        {
            stored = await fileStorage.SaveAsync(
                file, "vehicle-images", vehicleId, cancellationToken);
        }
        catch (InvalidDataException error)
        {
            return ServiceResult<VehicleUsageDto>.Fail(
                StatusCodes.Status400BadRequest, "file_invalid", error.Message);
        }
        catch (InvalidOperationException error)
        {
            return ServiceResult<VehicleUsageDto>.Fail(
                StatusCodes.Status503ServiceUnavailable, "storage_unavailable", error.Message);
        }

        // SaveAsync hands back the protected admin path, which is right for a
        // CNIC and wrong for this: an `img` tag cannot send a bearer token, so
        // the picture would upload successfully and then be invisible to every
        // customer. Rewritten onto the anonymous route that serves this one
        // category.
        var segments = stored.RelativeUrl.Split('/', StringSplitOptions.RemoveEmptyEntries);
        var publicUrl = segments.Length >= 2
            ? $"/api/v1/vehicle-images/{segments[^2]}/{segments[^1]}"
            : stored.RelativeUrl;

        await using (var command = new NpgsqlCommand(
            """
            UPDATE udrive.vehicles v
            SET image_url = @url, updated_at = now()
            FROM udrive.driver_profiles dp
            WHERE v.id = @vehicleId
              AND v.driver_profile_id = dp.id
              AND dp.user_id = @userId;
            """,
            connection))
        {
            command.Parameters.AddWithValue("vehicleId", vehicleId);
            command.Parameters.AddWithValue("userId", userId);
            command.Parameters.Add(new NpgsqlParameter("url", NpgsqlDbType.Text)
            {
                Value = publicUrl,
            });
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        var updated = await ReadOneAsync(connection, userId, vehicleId, cancellationToken);
        return ServiceResult<VehicleUsageDto>.Ok(updated!.Dto);
    }

    /// <summary>Every usable vehicle this Driver owns, with its usage.</summary>
    public async Task<ServiceResult<IReadOnlyList<VehicleUsageDto>>> ListAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT v.id, trim(concat_ws(' ', v.make, v.model)),
                   v.registration_number, v.status,
                   COALESCE(v.available_for_city, true),
                   COALESCE(v.available_for_tour, false),
                   COALESCE(v.available_for_rent, false),
                   v.mountain_readiness_score,
                   v.is_four_by_four, v.has_first_aid_kit, v.has_spare_tyre,
                   v.has_fire_extinguisher, v.has_snow_chains,
                   v.has_heating, v.has_air_conditioning, v.has_child_seat,
                   (SELECT count(*) FROM udrive.tour_packages tp
                     WHERE tp.vehicle_id = v.id
                       AND tp.status = 'Active'
                       AND tp.departure_at > now()),
                   v.rent_with_driver_daily, v.rent_self_drive_daily,
                   v.rent_security_deposit, v.rent_minimum_days,
                   v.rent_km_per_day, COALESCE(v.rent_fuel_included, false),
                   v.rent_pickup_point,
                   COALESCE((SELECT LEAST(100, GREATEST(0,
                               (s.value_json #>> '{}')::int))
                             FROM udrive.system_settings s
                             WHERE s.key = 'tour.minimum_readiness'), @readiness),
                   NULLIF(v.image_url, ''),
                   COALESCE(v.available_for_intercity, true)
            FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            WHERE dp.user_id = @userId
              AND v.status <> 'Deleted'
            ORDER BY v.created_at DESC;
            """;

        var list = new List<VehicleUsageDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);
        command.Parameters.AddWithValue("readiness", TourReadiness.DefaultMinimum);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        while (await reader.ReadAsync(cancellationToken))
        {
            var equipment = new TourReadiness.Equipment(
                reader.GetBoolean(8),   // four by four
                reader.GetBoolean(9),   // first aid kit
                reader.GetBoolean(10),  // spare tyre
                reader.GetBoolean(11),  // fire extinguisher
                reader.GetBoolean(12),  // snow chains
                reader.GetBoolean(13),  // heating
                reader.GetBoolean(14),  // air conditioning
                reader.GetBoolean(15)); // child seat

            var required = reader.GetInt32(24);
            var score = reader.GetInt32(7);
            var livePackages = (int)reader.GetInt64(16);

            list.Add(new VehicleUsageDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetBoolean(4),
                reader.GetBoolean(5),
                reader.GetBoolean(6),
                score,
                required,
                TourReadiness.MissingToReach(equipment, required)
                    .Select(item => new TourReadinessItemDto(
                        item.Key, item.Label, item.Points, false))
                    .ToList(),
                livePackages,
                reader.IsDBNull(17) ? null : reader.GetDecimal(17),
                reader.IsDBNull(18) ? null : reader.GetDecimal(18),
                reader.IsDBNull(19) ? null : reader.GetDecimal(19),
                reader.GetInt32(20),
                reader.IsDBNull(21) ? null : reader.GetInt32(21),
                reader.GetBoolean(22),
                reader.IsDBNull(23) ? null : reader.GetString(23),
                reader.IsDBNull(25) ? null : reader.GetString(25),
                reader.GetBoolean(26)));
        }

        return ServiceResult<IReadOnlyList<VehicleUsageDto>>.Ok(list);
    }

    /// <summary>Turns one usage on or off, with the rule that governs it.</summary>
    /// <remarks>
    /// Every rule is checked here rather than in the app. The app shows a
    /// Driver why a switch will not move, which is a kindness; the server
    /// decides whether it moves, which is the rule.
    /// </remarks>
    public async Task<ServiceResult<VehicleUsageDto>> SetUsageAsync(
        Guid userId,
        Guid vehicleId,
        VehicleUsageRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var current = await ReadOneAsync(connection, userId, vehicleId, cancellationToken);
        if (current is null)
        {
            return ServiceResult<VehicleUsageDto>.Fail(
                StatusCodes.Status404NotFound,
                "vehicle_not_found",
                "This vehicle was not found on your account.");
        }

        // Nothing can be switched on before an Admin has verified the vehicle.
        // The usage screen is reached from a verified vehicle, so this is the
        // guard for a request that did not come from it.
        if (!IsUsable(current.Status))
        {
            return ServiceResult<VehicleUsageDto>.Fail(
                StatusCodes.Status409Conflict,
                "vehicle_not_verified",
                "This vehicle has not been verified yet. An Admin verifies it "
                + "first, and then you choose what it is used for.");
        }

        var city = request.AvailableForCity ?? current.AvailableForCity;
        var intercity = request.AvailableForIntercity ?? current.Dto.AvailableForIntercity;
        var tour = request.AvailableForTour ?? current.AvailableForTour;
        var rent = request.AvailableForRent ?? current.AvailableForRent;

        // Rent takes the vehicle out of the city pool, and says so rather than
        // refusing. A car on rent is with somebody else; it is not available to
        // pick anyone up. Turning rent on therefore turns city off — the app
        // confirms this with the Driver before sending the request, so by the
        // time it arrives here it is what they asked for.
        // City to city follows the same rule as city rides.
        if (rent && request.AvailableForRent == true)
        {
            city = false;
            intercity = false;
        }

        if (city && request.AvailableForCity == true) rent = false;
        if (intercity && request.AvailableForIntercity == true) rent = false;

        if (tour && !current.MeetsReadiness)
        {
            return ServiceResult<VehicleUsageDto>.Fail(
                StatusCodes.Status409Conflict,
                "tour_readiness_too_low",
                $"This vehicle's tour readiness is {current.ReadinessScore} and "
                + $"tours need {current.ReadinessRequired}. Open the vehicle to "
                + "see which equipment would close the gap.");
        }

        if (rent && !HasAnyRentRate(current))
        {
            return ServiceResult<VehicleUsageDto>.Fail(
                StatusCodes.Status409Conflict,
                "rent_rate_required",
                "Set a daily rent — with a driver, self-drive, or both — before "
                + "putting this vehicle out on rent.");
        }

        // A photograph before a rental listing, because the listing is a
        // decision about this one car. The alternative the platform has on hand
        // is a stock picture of the model — a different car, in a different
        // colour, in better condition — and showing that to somebody about to
        // hand over a deposit is an advertisement rather than information.
        if (rent && string.IsNullOrWhiteSpace(current.Dto.PhotoUrl))
        {
            return ServiceResult<VehicleUsageDto>.Fail(
                StatusCodes.Status409Conflict,
                "vehicle_photo_required",
                "Add a photograph of this vehicle before putting it out on "
                + "rent. Customers choose a rental by looking at the car.");
        }

        // A Driver with nothing switched on has a verified vehicle doing
        // nothing, which is a state they can reach and may well want (a car off
        // the road for a month). It is allowed, and the app says plainly that
        // no work will come.
        const string sql = """
            UPDATE udrive.vehicles v
            SET available_for_city = @city,
                available_for_intercity = @intercity,
                available_for_tour = @tour,
                available_for_rent = @rent,
                updated_at = now()
            FROM udrive.driver_profiles dp
            WHERE v.id = @vehicleId
              AND v.driver_profile_id = dp.id
              AND dp.user_id = @userId;
            """;

        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("vehicleId", vehicleId);
            command.Parameters.AddWithValue("userId", userId);
            command.Parameters.AddWithValue("city", city);
            command.Parameters.AddWithValue("intercity", intercity);
            command.Parameters.AddWithValue("tour", tour);
            command.Parameters.AddWithValue("rent", rent);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        var updated = await ReadOneAsync(connection, userId, vehicleId, cancellationToken);
        return ServiceResult<VehicleUsageDto>.Ok(updated!.Dto);
    }

    /// <summary>Saves what renting this vehicle costs and requires.</summary>
    /// <remarks>
    /// Saving rates does not switch renting on. The two are separate on
    /// purpose: a Driver may want to work out their pricing over a few days
    /// before the car leaves their yard.
    /// </remarks>
    public async Task<ServiceResult<VehicleUsageDto>> SetRentSettingsAsync(
        Guid userId,
        Guid vehicleId,
        VehicleRentSettingsRequest request,
        CancellationToken cancellationToken)
    {
        if (request.WithDriverDaily is null && request.SelfDriveDaily is null)
        {
            return ServiceResult<VehicleUsageDto>.Fail(
                StatusCodes.Status400BadRequest,
                "rent_rate_required",
                "Set at least one daily rate — with a driver, self-drive, or both.");
        }

        if (request.WithDriverDaily is <= 0 || request.SelfDriveDaily is <= 0)
        {
            return ServiceResult<VehicleUsageDto>.Fail(
                StatusCodes.Status400BadRequest,
                "rent_rate_invalid",
                "A daily rate must be more than zero. Leave it empty to not "
                + "offer that option at all.");
        }

        if (request.MinimumDays < 1)
        {
            return ServiceResult<VehicleUsageDto>.Fail(
                StatusCodes.Status400BadRequest,
                "rent_minimum_days_invalid",
                "The minimum rental is at least one day.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        // A ceiling on the deposit, set by an Admin.
        //
        // Nothing capped it before. An owner could list a car at a fair daily
        // rate and ask two hundred thousand rupees as a deposit, which is not a
        // deposit — it is a way of appearing in the listing without ever being
        // booked, and it makes the whole rental page look dishonest to anyone
        // scrolling it. Zero means no ceiling, which is where it starts.
        var ceiling = await MaximumDepositAsync(connection, cancellationToken);
        if (ceiling > 0 && request.SecurityDeposit > ceiling)
        {
            return ServiceResult<VehicleUsageDto>.Fail(
                StatusCodes.Status409Conflict,
                "rent_deposit_too_high",
                $"The most you can ask as a deposit is PKR {ceiling}.");
        }

        const string sql = """
            UPDATE udrive.vehicles v
            SET rent_with_driver_daily = @withDriver,
                rent_self_drive_daily = @selfDrive,
                rent_security_deposit = @deposit,
                rent_minimum_days = @minimumDays,
                rent_km_per_day = @kmPerDay,
                rent_fuel_included = @fuelIncluded,
                rent_pickup_point = @pickup,
                updated_at = now()
            FROM udrive.driver_profiles dp
            WHERE v.id = @vehicleId
              AND v.driver_profile_id = dp.id
              AND dp.user_id = @userId;
            """;

        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("vehicleId", vehicleId);
            command.Parameters.AddWithValue("userId", userId);
            AddDecimal(command, "withDriver", request.WithDriverDaily);
            AddDecimal(command, "selfDrive", request.SelfDriveDaily);
            AddDecimal(command, "deposit", request.SecurityDeposit);
            command.Parameters.AddWithValue("minimumDays", request.MinimumDays);
            command.Parameters.Add(new NpgsqlParameter("kmPerDay", NpgsqlDbType.Integer)
            {
                Value = (object?)request.KmPerDay ?? DBNull.Value,
            });
            command.Parameters.AddWithValue("fuelIncluded", request.FuelIncluded);
            command.Parameters.Add(new NpgsqlParameter("pickup", NpgsqlDbType.Varchar)
            {
                Value = string.IsNullOrWhiteSpace(request.PickupPoint)
                    ? DBNull.Value
                    : request.PickupPoint.Trim(),
            });

            if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                return ServiceResult<VehicleUsageDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "vehicle_not_found",
                    "This vehicle was not found on your account.");
            }
        }

        var updated = await ReadOneAsync(connection, userId, vehicleId, cancellationToken);
        return ServiceResult<VehicleUsageDto>.Ok(updated!.Dto);
    }

    /// <summary>Records what equipment the vehicle carries, and rescores it.</summary>
    /// <remarks>
    /// Separate from the vehicle edit, which refuses outright once an Admin has
    /// verified the vehicle — and rightly: make, model, registration and
    /// capacity are what was verified, and letting a Driver change them
    /// afterwards would make verification meaningless.
    ///
    /// Equipment is not that. A first-aid kit, a spare tyre, snow chains: these
    /// are things a Driver buys and puts in the boot, and the readiness score is
    /// the only gate standing between them and publishing a tour package. With
    /// the vehicle locked and no other way in, a Driver told "readiness 45, you
    /// need 60" could buy every item on the list and still never reach 60,
    /// because nothing on the platform would record that they had. The gate had
    /// no door.
    ///
    /// The score is recomputed from the same <see cref="TourReadiness"/> table
    /// registration uses, so a vehicle cannot end up scored one way here and
    /// another way there. Nothing else about the vehicle is touched, and its
    /// verification is left exactly as it was.
    ///
    /// Turning tour on is still a separate step, and still subject to the bar:
    /// this records the kit, it does not grant anything.
    /// </remarks>
    public async Task<ServiceResult<VehicleUsageDto>> SetEquipmentAsync(
        Guid userId,
        Guid vehicleId,
        VehicleEquipmentRequest request,
        CancellationToken cancellationToken)
    {
        var equipment = new TourReadiness.Equipment(
            request.FourByFour,
            request.FirstAidKit,
            request.SpareTyre,
            request.FireExtinguisher,
            request.SnowChains,
            request.Heating,
            request.AirConditioning,
            request.ChildSeat);

        const string sql = """
            UPDATE udrive.vehicles v
            SET is_four_by_four = @fourByFour,
                has_first_aid_kit = @firstAid,
                has_spare_tyre = @spareTyre,
                has_fire_extinguisher = @fireExtinguisher,
                has_snow_chains = @snowChains,
                has_heating = @heating,
                has_air_conditioning = @airConditioning,
                has_child_seat = @childSeat,
                mountain_readiness_score = @readiness,
                updated_at = now()
            FROM udrive.driver_profiles dp
            WHERE v.id = @vehicleId
              AND v.driver_profile_id = dp.id
              AND dp.user_id = @userId;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        await using (var command = new NpgsqlCommand(sql, connection))
        {
            command.Parameters.AddWithValue("vehicleId", vehicleId);
            command.Parameters.AddWithValue("userId", userId);
            command.Parameters.AddWithValue("fourByFour", request.FourByFour);
            command.Parameters.AddWithValue("firstAid", request.FirstAidKit);
            command.Parameters.AddWithValue("spareTyre", request.SpareTyre);
            command.Parameters.AddWithValue(
                "fireExtinguisher", request.FireExtinguisher);
            command.Parameters.AddWithValue("snowChains", request.SnowChains);
            command.Parameters.AddWithValue("heating", request.Heating);
            command.Parameters.AddWithValue(
                "airConditioning", request.AirConditioning);
            command.Parameters.AddWithValue("childSeat", request.ChildSeat);
            command.Parameters.AddWithValue(
                "readiness", TourReadiness.Score(equipment));

            if (await command.ExecuteNonQueryAsync(cancellationToken) == 0)
            {
                return ServiceResult<VehicleUsageDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "vehicle_not_found",
                    "This vehicle was not found on your account.");
            }
        }

        // Equipment coming off the vehicle can drop it below the bar, and a
        // vehicle below the bar must not stay switched on for tours — the
        // Customer would find it in a search and the booking would then be
        // refused. Honest about it either way: the Driver is told the switch
        // went off, rather than discovering it later.
        var updated = await ReadOneAsync(connection, userId, vehicleId, cancellationToken);
        if (updated is not null && updated.AvailableForTour && !updated.MeetsReadiness)
        {
            await using var off = new NpgsqlCommand(
                """
                UPDATE udrive.vehicles v
                SET available_for_tour = false, updated_at = now()
                FROM udrive.driver_profiles dp
                WHERE v.id = @vehicleId
                  AND v.driver_profile_id = dp.id
                  AND dp.user_id = @userId;
                """,
                connection);
            off.Parameters.AddWithValue("vehicleId", vehicleId);
            off.Parameters.AddWithValue("userId", userId);
            await off.ExecuteNonQueryAsync(cancellationToken);

            var after = await ReadOneAsync(connection, userId, vehicleId, cancellationToken);
            return ServiceResult<VehicleUsageDto>.Ok(
                after!.Dto,
                $"Readiness is now {after.ReadinessScore}, below the "
                + $"{after.ReadinessRequired} tours need, so this vehicle has "
                + "been taken off tours.");
        }

        return ServiceResult<VehicleUsageDto>.Ok(updated!.Dto);
    }

    // ───────────────────────────────────────────────────────────── reading

    private sealed record Row(
        VehicleUsageDto Dto,
        string Status,
        bool AvailableForCity,
        bool AvailableForTour,
        bool AvailableForRent,
        int ReadinessScore,
        int ReadinessRequired,
        decimal? WithDriverDaily,
        decimal? SelfDriveDaily)
    {
        public bool MeetsReadiness => ReadinessScore >= ReadinessRequired;
    }

    private async Task<Row?> ReadOneAsync(
        NpgsqlConnection connection,
        Guid userId,
        Guid vehicleId,
        CancellationToken cancellationToken)
    {
        var all = await ListAsync(userId, cancellationToken);
        var dto = all.Data?.FirstOrDefault(v => v.VehicleId == vehicleId);
        if (dto is null) return null;

        // The status is not on the DTO — the app has it already from the
        // vehicle itself — so it is read here, where the rule needs it.
        await using var command = new NpgsqlCommand(
            """
            SELECT v.status FROM udrive.vehicles v
            JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            WHERE v.id = @vehicleId AND dp.user_id = @userId;
            """,
            connection);
        command.Parameters.AddWithValue("vehicleId", vehicleId);
        command.Parameters.AddWithValue("userId", userId);
        var status = await command.ExecuteScalarAsync(cancellationToken) as string;
        if (status is null) return null;

        return new Row(
            dto,
            status,
            dto.AvailableForCity,
            dto.AvailableForTour,
            dto.AvailableForRent,
            dto.TourReadinessScore,
            dto.TourReadinessRequired,
            dto.RentWithDriverDaily,
            dto.RentSelfDriveDaily);
    }

    /// <summary>The Admin's ceiling on deposits. Zero means none.</summary>
    private static async Task<int> MaximumDepositAsync(
        NpgsqlConnection connection,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT COALESCE((SELECT GREATEST(0, (value_json #>> '{}')::int)
                             FROM udrive.system_settings
                             WHERE key = 'rental.maximum_deposit'), 0);
            """,
            connection);
        return await command.ExecuteScalarAsync(cancellationToken) is int value ? value : 0;
    }

    private static bool HasAnyRentRate(Row row) =>
        row.WithDriverDaily is > 0 || row.SelfDriveDaily is > 0;

    /// <summary>Verified or Approved, either case — as everywhere else.</summary>
    private static bool IsUsable(string status) =>
        string.Equals(status, "Verified", StringComparison.OrdinalIgnoreCase)
        || string.Equals(status, "Approved", StringComparison.OrdinalIgnoreCase);

    private static void AddDecimal(NpgsqlCommand command, string name, decimal? value) =>
        command.Parameters.Add(new NpgsqlParameter(name, NpgsqlDbType.Numeric)
        {
            Value = (object?)value ?? DBNull.Value,
        });

}
