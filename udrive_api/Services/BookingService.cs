using System.Data;
using System.Globalization;
using System.Security.Cryptography;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Domain.Enums;
using UDrive.Api.Models;
using UDrive.Api.Security;

namespace UDrive.Api.Services;

public sealed class BookingService(
    string connectionString,
    AuthOptions authOptions)
{
    public async Task<ServiceResult<RideRequestDto>> CreateRideRequestAsync(
        Guid userId,
        CreateRideRequestRequest request,
        CancellationToken cancellationToken)
    {
        var validation = ValidateRideRequest(request);
        if (validation is not null)
        {
            return ServiceResult<RideRequestDto>.Fail(
                StatusCodes.Status400BadRequest,
                validation.Value.Code,
                validation.Value.Message);
        }

        var id = Guid.NewGuid();
        var expiresAt = DateTimeOffset.UtcNow.AddHours(1);

        const string sql = """
            INSERT INTO udrive.ride_requests
                (id, customer_user_id, pickup_location, destination_location,
                 pickup_label, destination_label, pickup_at, return_at,
                 booking_type, seats_requested, adults, children, luggage_count,
                 customer_offer, vehicle_category, party_type, family_only,
                 women_only, notes, status, expires_at, version, created_at, updated_at)
            VALUES
                (@id, @userId,
                 ST_SetSRID(ST_MakePoint(@pickupLongitude, @pickupLatitude), 4326)::geography,
                 ST_SetSRID(ST_MakePoint(@destinationLongitude, @destinationLatitude), 4326)::geography,
                 @pickupLabel, @destinationLabel, @pickupAt, @returnAt,
                 @bookingType, @seatsRequested, @adults, @children, @luggageCount,
                 @customerOffer, @vehicleCategory, @partyType, @familyOnly,
                 @womenOnly, @notes, 'ReceivingOffers', @expiresAt, 0, now(), now());
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        await using (var command = new NpgsqlCommand(sql, connection, transaction))
        {
            command.Parameters.AddWithValue("id", id);
            command.Parameters.AddWithValue("userId", userId);
            command.Parameters.AddWithValue("pickupLongitude", request.PickupLongitude);
            command.Parameters.AddWithValue("pickupLatitude", request.PickupLatitude);
            command.Parameters.AddWithValue("destinationLongitude", request.DestinationLongitude);
            command.Parameters.AddWithValue("destinationLatitude", request.DestinationLatitude);
            command.Parameters.AddWithValue("pickupLabel", request.PickupLabel.Trim());
            command.Parameters.AddWithValue("destinationLabel", request.DestinationLabel.Trim());
            command.Parameters.AddWithValue("pickupAt", request.PickupAt.ToUniversalTime());
            command.Parameters.Add(new NpgsqlParameter("returnAt", NpgsqlDbType.TimestampTz) { Value = (object?)request.ReturnAt?.ToUniversalTime() ?? DBNull.Value });
            command.Parameters.AddWithValue("bookingType", request.BookingType.ToString());
            command.Parameters.AddWithValue("seatsRequested", request.SeatsRequested);
            command.Parameters.AddWithValue("adults", request.Adults);
            command.Parameters.AddWithValue("children", request.Children);
            command.Parameters.AddWithValue("luggageCount", request.LuggageCount);
            command.Parameters.AddWithValue("customerOffer", request.CustomerOffer);
            command.Parameters.AddWithValue("vehicleCategory", request.VehicleCategory.Trim());
            command.Parameters.AddWithValue("partyType", SanitizePartyType(request.PartyType));
            command.Parameters.AddWithValue("familyOnly", request.FamilyOnly);
            command.Parameters.AddWithValue("womenOnly", request.WomenOnly);
            command.Parameters.Add(new NpgsqlParameter("notes", NpgsqlDbType.Varchar) { Value = (object?)request.Notes?.Trim() ?? DBNull.Value });
            command.Parameters.AddWithValue("expiresAt", expiresAt);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        if (DemoMarketplaceEnabled())
        {
            await CreateDemoDriverOfferAsync(
                connection,
                transaction,
                id,
                request.CustomerOffer,
                cancellationToken);
        }

        await AddHistoryAsync(
            connection,
            transaction,
            "RideRequest",
            id,
            null,
            null,
            "ReceivingOffers",
            userId,
            request.InstantRide ? "Customer created an instant ride request." : "Customer created an advance ride request.",
            "{}",
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);

        var customerName = await GetUserDisplayNameAsync(userId, cancellationToken);
        var dto = new RideRequestDto(
            id,
            request.PickupLabel.Trim(),
            request.DestinationLabel.Trim(),
            request.PickupLatitude,
            request.PickupLongitude,
            request.DestinationLatitude,
            request.DestinationLongitude,
            request.PickupAt.ToUniversalTime(),
            request.ReturnAt?.ToUniversalTime(),
            request.BookingType.ToString(),
            request.SeatsRequested,
            request.Adults,
            request.Children,
            request.LuggageCount,
            request.CustomerOffer,
            request.VehicleCategory.Trim(),
            SanitizePartyType(request.PartyType),
            request.FamilyOnly,
            request.WomenOnly,
            "ReceivingOffers",
            DemoMarketplaceEnabled() ? 1 : 0,
            null,
            expiresAt,
            DateTimeOffset.UtcNow,
            customerName);

        return ServiceResult<RideRequestDto>.Created(
            dto,
            "Ride request created. Eligible verified Drivers can now submit offers.");
    }

    public async Task<ServiceResult<IReadOnlyList<RideRequestDto>>> GetMyRideRequestsAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        await ExpireRideRequestsAsync(cancellationToken);
        const string sql = """
            SELECT rr.id, rr.pickup_label, rr.destination_label,
                   ST_Y(rr.pickup_location::geometry) AS pickup_latitude,
                   ST_X(rr.pickup_location::geometry) AS pickup_longitude,
                   ST_Y(rr.destination_location::geometry) AS destination_latitude,
                   ST_X(rr.destination_location::geometry) AS destination_longitude,
                   rr.pickup_at, rr.return_at, rr.booking_type,
                   rr.seats_requested, rr.adults, rr.children, rr.luggage_count,
                   rr.customer_offer, rr.vehicle_category, rr.party_type,
                   rr.family_only, rr.women_only, rr.status,
                   (SELECT count(*)::int FROM udrive.driver_offers o
                    WHERE o.ride_request_id = rr.id
                      AND o.status IN ('Pending', 'Countered', 'Accepted', 'Selected')
                      AND o.expires_at > now()) AS offers_count,
                   rr.selected_offer_id, rr.expires_at, rr.created_at,
                   COALESCE(NULLIF(u.full_name, ''), 'Customer') AS customer_name
            FROM udrive.ride_requests rr
            JOIN udrive.users u ON u.id = rr.customer_user_id
            WHERE rr.customer_user_id = @userId
            ORDER BY rr.created_at DESC;
            """;

        var result = new List<RideRequestDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(ReadRideRequest(reader));
        }

        return ServiceResult<IReadOnlyList<RideRequestDto>>.Ok(result);
    }

    public async Task<ServiceResult<IReadOnlyList<RideRequestDto>>> GetEligibleRideRequestsAsync(
        Guid driverUserId,
        CancellationToken cancellationToken)
    {
        await ExpireRideRequestsAsync(cancellationToken);
        var driver = await GetApprovedDriverAsync(driverUserId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<IReadOnlyList<RideRequestDto>>.Fail(
                StatusCodes.Status403Forbidden,
                "driver_not_approved",
                "Only approved Drivers can receive live ride requests.");
        }

        const string sql = """
            SELECT rr.id, rr.pickup_label, rr.destination_label,
                   ST_Y(rr.pickup_location::geometry) AS pickup_latitude,
                   ST_X(rr.pickup_location::geometry) AS pickup_longitude,
                   ST_Y(rr.destination_location::geometry) AS destination_latitude,
                   ST_X(rr.destination_location::geometry) AS destination_longitude,
                   rr.pickup_at, rr.return_at, rr.booking_type,
                   rr.seats_requested, rr.adults, rr.children, rr.luggage_count,
                   rr.customer_offer, rr.vehicle_category, rr.party_type,
                   rr.family_only, rr.women_only, rr.status,
                   (SELECT count(*)::int FROM udrive.driver_offers o
                    WHERE o.ride_request_id = rr.id
                      AND o.status IN ('Pending', 'Countered', 'Accepted', 'Selected')
                      AND o.expires_at > now()) AS offers_count,
                   rr.selected_offer_id, rr.expires_at, rr.created_at,
                   COALESCE(NULLIF(u.full_name, ''), 'Customer') AS customer_name
            FROM udrive.ride_requests rr
            JOIN udrive.users u ON u.id = rr.customer_user_id
            JOIN udrive.driver_presence_locations dpl ON dpl.driver_profile_id = @driverProfileId
            WHERE rr.status IN ('Open', 'ReceivingOffers')
              AND dpl.server_timestamp > now() - interval '2 minutes'
              AND ST_DWithin(dpl.location, rr.pickup_location, 5000)
              AND rr.pickup_at > now() - interval '15 minutes'
              AND (rr.expires_at IS NULL OR rr.expires_at > now())
              AND rr.customer_user_id <> @driverUserId
              AND NOT EXISTS (
                  SELECT 1
                  FROM udrive.bookings active_b
                  JOIN udrive.trip_operations active_o ON active_o.booking_id = active_b.id
                  LEFT JOIN udrive.ride_requests active_rr ON active_rr.id = active_b.ride_request_id
                  WHERE active_b.driver_profile_id = @driverProfileId
                    AND active_o.trip_status IN ('DriverAccepted','DriverEnRoute','DriverArrived','TripStarted','Emergency')
                    AND (
                      active_o.trip_status <> 'TripStarted'
                      OR active_rr.destination_location IS NULL
                      OR NOT ST_DWithin(dpl.location, active_rr.destination_location, 1000)
                    )
              )
              AND NOT EXISTS (
                  SELECT 1
                  FROM udrive.driver_ride_request_decisions d
                  WHERE d.ride_request_id = rr.id
                    AND d.driver_profile_id = @driverProfileId
                    AND (
                      d.decision = 'Rejected'
                      OR COALESCE(d.customer_reject_count, 0) >= 5
                      OR (d.decision = 'Offered' AND d.updated_at > now() - interval '20 seconds')
                    )
              )
            ORDER BY rr.pickup_at, rr.created_at DESC
            LIMIT 100;
            """;

        var result = new List<RideRequestDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driverUserId", driverUserId);
        command.Parameters.AddWithValue("driverProfileId", driver.DriverProfileId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(ReadRideRequest(reader));
        }

        return ServiceResult<IReadOnlyList<RideRequestDto>>.Ok(result);
    }

    public async Task<ServiceResult<IReadOnlyList<DriverRideOfferStatusDto>>> GetMyDriverRideOffersAsync(
        Guid driverUserId,
        CancellationToken cancellationToken)
    {
        await ExpireRideRequestsAsync(cancellationToken);
        var driver = await GetApprovedDriverAsync(driverUserId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<IReadOnlyList<DriverRideOfferStatusDto>>.Fail(
                StatusCodes.Status403Forbidden,
                "driver_not_approved",
                "Only approved Drivers can view ride offers.");
        }

        const string sql = """
            SELECT o.id, o.ride_request_id, o.vehicle_id,
                   concat(v.make, ' ', v.model) AS vehicle,
                   v.registration_number,
                   COALESCE(o.counter_amount, o.amount) AS driver_amount,
                   o.status AS offer_status,
                   (rr.selected_offer_id = o.id OR o.status = 'Selected') AS selected_by_customer,
                   b.id AS booking_id,
                   b.status AS booking_status,
                   rr.pickup_label, rr.destination_label,
                   ST_Y(rr.pickup_location::geometry) AS pickup_latitude,
                   ST_X(rr.pickup_location::geometry) AS pickup_longitude,
                   ST_Y(rr.destination_location::geometry) AS destination_latitude,
                   ST_X(rr.destination_location::geometry) AS destination_longitude,
                   rr.booking_type, rr.seats_requested, rr.customer_offer,
                   rr.vehicle_category,
                   COALESCE(NULLIF(u.full_name, ''), 'Customer') AS customer_name,
                   o.created_at, o.expires_at
            FROM udrive.driver_offers o
            JOIN udrive.ride_requests rr ON rr.id = o.ride_request_id
            JOIN udrive.users u ON u.id = rr.customer_user_id
            JOIN udrive.vehicles v ON v.id = o.vehicle_id
            LEFT JOIN udrive.bookings b ON b.ride_request_id = rr.id
                                      AND b.driver_profile_id = o.driver_profile_id
            WHERE o.driver_profile_id = @driverProfileId
              AND o.created_at > now() - interval '24 hours'
            ORDER BY
              CASE WHEN b.id IS NOT NULL AND b.status NOT IN ('Completed','Cancelled','Rejected') THEN 0
                   WHEN o.status IN ('Pending','Countered','Accepted') AND o.expires_at > now() THEN 1
                   ELSE 2 END,
              o.updated_at DESC
            LIMIT 50;
            """;

        var result = new List<DriverRideOfferStatusDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("driverProfileId", driver.DriverProfileId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(new DriverRideOfferStatusDto(
                reader.GetGuid(0),
                reader.GetGuid(1),
                reader.GetGuid(2),
                reader.GetString(3),
                reader.GetString(4),
                reader.GetDecimal(5),
                reader.GetString(6),
                reader.GetBoolean(7),
                reader.IsDBNull(8) ? null : reader.GetGuid(8),
                reader.IsDBNull(9) ? null : reader.GetString(9),
                reader.GetString(10),
                reader.GetString(11),
                reader.GetDouble(12),
                reader.GetDouble(13),
                reader.GetDouble(14),
                reader.GetDouble(15),
                reader.GetString(16),
                reader.GetInt32(17),
                reader.GetDecimal(18),
                reader.GetString(19),
                reader.GetString(20),
                reader.GetFieldValue<DateTimeOffset>(21),
                reader.GetFieldValue<DateTimeOffset>(22)));
        }

        return ServiceResult<IReadOnlyList<DriverRideOfferStatusDto>>.Ok(result);
    }

    public async Task<ServiceResult<DriverRideRequestDecisionDto>> RejectRideRequestAsync(
        Guid driverUserId,
        Guid rideRequestId,
        RejectRideRequestRequest request,
        CancellationToken cancellationToken)
    {
        var driver = await GetApprovedDriverAsync(driverUserId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<DriverRideRequestDecisionDto>.Fail(
                StatusCodes.Status403Forbidden,
                "driver_not_approved",
                "Only approved Drivers can review live ride requests.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        const string requestSql = """
            SELECT 1
            FROM udrive.ride_requests
            WHERE id = @rideRequestId
              AND status IN ('Open', 'ReceivingOffers')
              AND pickup_at > now() - interval '15 minutes'
              AND (expires_at IS NULL OR expires_at > now());
            """;
        await using (var check = new NpgsqlCommand(requestSql, connection))
        {
            check.Parameters.AddWithValue("rideRequestId", rideRequestId);
            if (await check.ExecuteScalarAsync(cancellationToken) is null)
            {
                return ServiceResult<DriverRideRequestDecisionDto>.Fail(
                    StatusCodes.Status409Conflict,
                    "ride_request_closed",
                    "This Customer request is no longer available.");
            }
        }

        const string sql = """
            INSERT INTO udrive.driver_ride_request_decisions
                (ride_request_id, driver_profile_id, decision, reason, created_at, updated_at)
            VALUES
                (@rideRequestId, @driverProfileId, 'Rejected', @reason, now(), now())
            ON CONFLICT (ride_request_id, driver_profile_id) DO UPDATE
            SET decision = 'Rejected', reason = EXCLUDED.reason, updated_at = now()
            RETURNING created_at;
            """;
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("rideRequestId", rideRequestId);
        command.Parameters.AddWithValue("driverProfileId", driver.DriverProfileId);
        command.Parameters.Add(new NpgsqlParameter("reason", NpgsqlDbType.Varchar)
        {
            Value = (object?)request.Reason?.Trim() ?? DBNull.Value
        });
        var createdAt = (DateTimeOffset)(await command.ExecuteScalarAsync(cancellationToken)
            ?? DateTimeOffset.UtcNow);

        return ServiceResult<DriverRideRequestDecisionDto>.Ok(
            new DriverRideRequestDecisionDto(rideRequestId, "Rejected", createdAt),
            "The request was removed from your Driver queue.");
    }

    public async Task<ServiceResult<DriverOfferDto>> SubmitDriverOfferAsync(
        Guid driverUserId,
        Guid rideRequestId,
        SubmitDriverOfferRequest request,
        CancellationToken cancellationToken)
    {
        var driver = await GetApprovedDriverAsync(driverUserId, cancellationToken);
        if (driver is null)
        {
            return ServiceResult<DriverOfferDto>.Fail(
                StatusCodes.Status403Forbidden,
                "driver_not_approved",
                "Only approved Drivers can submit offers.");
        }

        if (!driver.VehicleIds.Contains(request.VehicleId))
        {
            return ServiceResult<DriverOfferDto>.Fail(
                StatusCodes.Status400BadRequest,
                "vehicle_not_verified",
                "Select a verified vehicle registered to your Driver profile.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.ReadCommitted,
            cancellationToken);

        DateTimeOffset pickupAt;
        DateTimeOffset? requestExpiresAt;

        const string lockSql = """
            SELECT status, pickup_at, expires_at
            FROM udrive.ride_requests
            WHERE id = @rideRequestId
            FOR UPDATE;
            """;
        await using (var lockCommand = new NpgsqlCommand(lockSql, connection, transaction))
        {
            lockCommand.Parameters.AddWithValue("rideRequestId", rideRequestId);
            await using var reader = await lockCommand.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<DriverOfferDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "ride_request_not_found",
                    "The ride request was not found.");
            }

            var status = reader.GetString(0);
            pickupAt = reader.GetFieldValue<DateTimeOffset>(1);
            requestExpiresAt = reader.IsDBNull(2) ? null : reader.GetFieldValue<DateTimeOffset>(2);
            if (status is not ("Open" or "ReceivingOffers") || pickupAt < DateTimeOffset.UtcNow.AddMinutes(-15) || (requestExpiresAt is not null && requestExpiresAt <= DateTimeOffset.UtcNow))
            {
                return ServiceResult<DriverOfferDto>.Fail(
                    StatusCodes.Status409Conflict,
                    "ride_request_closed",
                    "This ride request is no longer accepting offers.");
            }
        }

        // Customer can explicitly reject the same Driver up to five times for this ride.
        const string rejectLimitSql = """
            SELECT COALESCE(customer_reject_count, 0)
            FROM udrive.driver_ride_request_decisions
            WHERE ride_request_id = @rideRequestId
              AND driver_profile_id = @driverProfileId;
            """;
        await using (var rejectLimitCommand = new NpgsqlCommand(rejectLimitSql, connection, transaction))
        {
            rejectLimitCommand.Parameters.AddWithValue("rideRequestId", rideRequestId);
            rejectLimitCommand.Parameters.AddWithValue("driverProfileId", driver.DriverProfileId);
            var rejectCountValue = await rejectLimitCommand.ExecuteScalarAsync(cancellationToken);
            var customerRejectCount = rejectCountValue is null || rejectCountValue is DBNull
                ? 0
                : Convert.ToInt32(rejectCountValue);
            if (customerRejectCount >= 5)
            {
                return ServiceResult<DriverOfferDto>.Fail(
                    StatusCodes.Status409Conflict,
                    "customer_driver_reject_limit",
                    "The Customer has rejected this Driver five times for this ride.");
            }
        }

        var offerId = Guid.NewGuid();
        var instantLike = pickupAt <= DateTimeOffset.UtcNow.AddMinutes(1);
        var offerExpiresAt = instantLike
            ? new[]
            {
                DateTimeOffset.UtcNow.AddSeconds(35),
                requestExpiresAt ?? DateTimeOffset.UtcNow.AddSeconds(35)
            }.Min()
            : new[]
            {
                DateTimeOffset.UtcNow.AddMinutes(15),
                pickupAt,
                requestExpiresAt ?? pickupAt
            }.Min();
        // ETA is calculated by the server from the Driver's latest GPS position to the pickup point.
        // The mobile Driver app only submits the fare; it does not need to guess an ETA.
        var calculatedEtaMinutes = Math.Clamp(request.EstimatedArrivalMinutes, 1, 600);
        const string etaSql = """
            SELECT ST_Distance(dpl.location, rr.pickup_location)
            FROM udrive.driver_presence_locations dpl
            JOIN udrive.ride_requests rr ON rr.id=@rideRequestId
            WHERE dpl.driver_profile_id=@driverProfileId
              AND dpl.server_timestamp > now() - interval '2 minutes'
            ORDER BY dpl.server_timestamp DESC
            LIMIT 1;
            """;
        await using (var etaCommand = new NpgsqlCommand(etaSql, connection, transaction))
        {
            etaCommand.Parameters.AddWithValue("rideRequestId", rideRequestId);
            etaCommand.Parameters.AddWithValue("driverProfileId", driver.DriverProfileId);
            var distanceValue = await etaCommand.ExecuteScalarAsync(cancellationToken);
            if (distanceValue is not null && distanceValue is not DBNull)
            {
                var distanceMeters = Convert.ToDouble(distanceValue);
                // Practical city estimate: about 30 km/h average including local-road slowing.
                calculatedEtaMinutes = Math.Clamp((int)Math.Ceiling(distanceMeters / 500d), 1, 60);
            }
        }

        const string offerSql = """
            INSERT INTO udrive.driver_offers
                (id, ride_request_id, driver_profile_id, vehicle_id, amount,
                 estimated_arrival_minutes, message, status, expires_at,
                 counter_amount, responded_at, version, created_at, updated_at)
            VALUES
                (@id, @rideRequestId, @driverProfileId, @vehicleId, @amount,
                 @eta, @message, 'Countered', @expiresAt, @amount, now(), 0,
                 now(), now())
            ON CONFLICT (ride_request_id, driver_profile_id)
                WHERE status IN ('Pending','Countered','Accepted')
            DO UPDATE SET
                vehicle_id = EXCLUDED.vehicle_id,
                amount = EXCLUDED.amount,
                counter_amount = EXCLUDED.counter_amount,
                estimated_arrival_minutes = EXCLUDED.estimated_arrival_minutes,
                message = EXCLUDED.message,
                status = 'Countered',
                expires_at = EXCLUDED.expires_at,
                responded_at = now(),
                version = udrive.driver_offers.version + 1,
                updated_at = now()
            RETURNING id;
            """;

        await using (var command = new NpgsqlCommand(offerSql, connection, transaction))
        {
            command.Parameters.AddWithValue("id", offerId);
            command.Parameters.AddWithValue("rideRequestId", rideRequestId);
            command.Parameters.AddWithValue("driverProfileId", driver.DriverProfileId);
            command.Parameters.AddWithValue("vehicleId", request.VehicleId);
            command.Parameters.AddWithValue("amount", request.Amount);
            command.Parameters.AddWithValue("eta", calculatedEtaMinutes);
            command.Parameters.Add(new NpgsqlParameter("message", NpgsqlDbType.Varchar) { Value = (object?)request.Message?.Trim() ?? DBNull.Value });
            command.Parameters.AddWithValue("expiresAt", offerExpiresAt);
            offerId = (Guid)(await command.ExecuteScalarAsync(cancellationToken)
                ?? throw new InvalidOperationException("The Driver offer could not be saved."));
        }

        await using (var decisionCommand = new NpgsqlCommand(
            """
            INSERT INTO udrive.driver_ride_request_decisions
                (ride_request_id, driver_profile_id, decision, reason, created_at, updated_at)
            VALUES (@rideRequestId, @driverProfileId, 'Offered', NULL, now(), now())
            ON CONFLICT (ride_request_id, driver_profile_id) DO UPDATE
            SET decision = 'Offered', reason = NULL, updated_at = now();
            """,
            connection,
            transaction))
        {
            decisionCommand.Parameters.AddWithValue("rideRequestId", rideRequestId);
            decisionCommand.Parameters.AddWithValue("driverProfileId", driver.DriverProfileId);
            await decisionCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var updateRide = new NpgsqlCommand(
            "UPDATE udrive.ride_requests SET status = 'ReceivingOffers', version = version + 1, updated_at = now() WHERE id = @id;",
            connection,
            transaction))
        {
            updateRide.Parameters.AddWithValue("id", rideRequestId);
            await updateRide.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return await GetOfferByIdAsync(offerId, cancellationToken);
    }

    public async Task<ServiceResult<IReadOnlyList<DriverOfferDto>>> GetRideOffersAsync(
        Guid customerUserId,
        Guid rideRequestId,
        CancellationToken cancellationToken)
    {
        await ExpireRideRequestsAsync(cancellationToken);
        const string ownerSql = "SELECT 1 FROM udrive.ride_requests WHERE id = @id AND customer_user_id = @userId;";
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using (var ownerCommand = new NpgsqlCommand(ownerSql, connection))
        {
            ownerCommand.Parameters.AddWithValue("id", rideRequestId);
            ownerCommand.Parameters.AddWithValue("userId", customerUserId);
            if (await ownerCommand.ExecuteScalarAsync(cancellationToken) is null)
            {
                return ServiceResult<IReadOnlyList<DriverOfferDto>>.Fail(
                    StatusCodes.Status404NotFound,
                    "ride_request_not_found",
                    "The ride request was not found.");
            }
        }

        var result = await ReadOffersAsync(connection, rideRequestId, cancellationToken);
        return ServiceResult<IReadOnlyList<DriverOfferDto>>.Ok(result);
    }

    public async Task<ServiceResult<bool>> DeclineDriverOfferAsync(
        Guid customerUserId,
        Guid rideRequestId,
        Guid offerId,
        bool countTowardsDriverRejectLimit,
        CancellationToken cancellationToken)
    {
        const string expireSql = """
            UPDATE udrive.driver_offers o
            SET status='Expired', responded_at=now(), updated_at=now(), version=version+1
            FROM udrive.ride_requests rr
            WHERE o.id=@offerId
              AND o.ride_request_id=@rideRequestId
              AND rr.id=o.ride_request_id
              AND rr.customer_user_id=@customerUserId
              AND o.status IN ('Pending','Countered','Accepted')
            RETURNING o.driver_profile_id;
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);

        Guid driverProfileId;
        await using (var command = new NpgsqlCommand(expireSql, connection, transaction))
        {
            command.Parameters.AddWithValue("offerId", offerId);
            command.Parameters.AddWithValue("rideRequestId", rideRequestId);
            command.Parameters.AddWithValue("customerUserId", customerUserId);
            var value = await command.ExecuteScalarAsync(cancellationToken);
            if (value is null || value is DBNull)
            {
                return ServiceResult<bool>.Fail(StatusCodes.Status404NotFound, "offer_not_found", "The Driver offer is no longer available.");
            }
            driverProfileId = (Guid)value;
        }

        // Only an explicit Customer Reject increments the five-rejection limit.
        // Automatic 10-second timeout does not penalize the Driver.
        if (countTowardsDriverRejectLimit)
        {
            const string incrementSql = """
                UPDATE udrive.driver_ride_request_decisions
                SET customer_reject_count = LEAST(customer_reject_count + 1, 5),
                    last_customer_rejected_at = now(),
                    -- Explicit rejection releases the request back to this Driver immediately
                    -- (unless this is rejection #5, which is blocked by the queue filter).
                    updated_at = now() - interval '21 seconds'
                WHERE ride_request_id = @rideRequestId
                  AND driver_profile_id = @driverProfileId;
                """;
            await using var incrementCommand = new NpgsqlCommand(incrementSql, connection, transaction);
            incrementCommand.Parameters.AddWithValue("rideRequestId", rideRequestId);
            incrementCommand.Parameters.AddWithValue("driverProfileId", driverProfileId);
            await incrementCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<bool>.Ok(true);
    }

    public async Task<ServiceResult<BookingDto>> SelectDriverOfferAsync(
        Guid customerUserId,
        Guid rideRequestId,
        Guid offerId,
        SelectDriverOfferRequest request,
        CancellationToken cancellationToken)
    {
        await ExpireRideRequestsAsync(cancellationToken);
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.Serializable,
            cancellationToken);

        const string rideSql = """
            SELECT customer_user_id, pickup_at, return_at, booking_type,
                   seats_requested, customer_offer, pickup_label,
                   destination_label, party_type, status
            FROM udrive.ride_requests
            WHERE id = @rideRequestId
            FOR UPDATE;
            """;

        Guid ownerId;
        DateTimeOffset pickupAt;
        DateTimeOffset? returnAt;
        string bookingType;
        int seats;
        string pickupLabel;
        string destinationLabel;
        string partyType;
        string rideStatus;

        await using (var rideCommand = new NpgsqlCommand(rideSql, connection, transaction))
        {
            rideCommand.Parameters.AddWithValue("rideRequestId", rideRequestId);
            await using var reader = await rideCommand.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<BookingDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "ride_request_not_found",
                    "The ride request was not found.");
            }

            ownerId = reader.GetGuid(0);
            pickupAt = reader.GetFieldValue<DateTimeOffset>(1);
            returnAt = reader.IsDBNull(2) ? null : reader.GetFieldValue<DateTimeOffset>(2);
            bookingType = reader.GetString(3);
            seats = reader.GetInt32(4);
            pickupLabel = reader.GetString(6);
            destinationLabel = reader.GetString(7);
            partyType = reader.GetString(8);
            rideStatus = reader.GetString(9);
        }

        if (ownerId != customerUserId)
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status403Forbidden,
                "ride_request_not_owned",
                "You cannot select a Driver for another Customer's request.");
        }

        if (rideStatus is not ("Open" or "ReceivingOffers"))
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "ride_request_closed",
                "A Driver has already been selected or this request is closed.");
        }

        const string offerSql = """
            SELECT driver_profile_id, vehicle_id,
                   COALESCE(counter_amount, amount) AS final_amount,
                   status, expires_at
            FROM udrive.driver_offers
            WHERE id = @offerId AND ride_request_id = @rideRequestId
            FOR UPDATE;
            """;

        Guid driverProfileId;
        Guid vehicleId;
        decimal totalAmount;
        string offerStatus;
        DateTimeOffset offerExpiresAt;
        await using (var offerCommand = new NpgsqlCommand(offerSql, connection, transaction))
        {
            offerCommand.Parameters.AddWithValue("offerId", offerId);
            offerCommand.Parameters.AddWithValue("rideRequestId", rideRequestId);
            await using var reader = await offerCommand.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<BookingDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "offer_not_found",
                    "The selected Driver offer was not found.");
            }

            driverProfileId = reader.GetGuid(0);
            vehicleId = reader.GetGuid(1);
            totalAmount = reader.GetDecimal(2);
            offerStatus = reader.GetString(3);
            offerExpiresAt = reader.GetFieldValue<DateTimeOffset>(4);
        }

        if (offerStatus is not ("Pending" or "Countered" or "Accepted") || offerExpiresAt.AddSeconds(12) <= DateTimeOffset.UtcNow)
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "offer_expired",
                "The selected Driver offer has expired.");
        }

        var advanceAmount = Math.Clamp(request.AdvanceAmount, 0, totalAmount);
        var remainingAmount = totalAmount - advanceAmount;
        var bookingId = Guid.NewGuid();
        var bookingReference = GenerateReference("UDR");
        var tripOtp = GenerateOtp();
        var tripOtpHash = SecurityHashing.HashWithSecret(tripOtp, authOptions.OtpHashSecret);

        const string bookingSql = """
            INSERT INTO udrive.bookings
                (id, customer_user_id, driver_profile_id, vehicle_id,
                 ride_request_id, tour_package_id, booking_type, status,
                 seats_booked, total_amount, advance_amount, remaining_amount,
                 pickup_at, return_at, trip_otp_hash, booking_reference,
                 pickup_label, destination_label, party_type, selected_offer_id,
                 version, created_at, updated_at)
            VALUES
                (@id, @customerUserId, @driverProfileId, @vehicleId,
                 @rideRequestId, NULL, @bookingType, 'DriverAccepted',
                 @seats, @totalAmount, @advanceAmount, @remainingAmount,
                 @pickupAt, @returnAt, @tripOtpHash, @bookingReference,
                 @pickupLabel, @destinationLabel, @partyType, @offerId,
                 0, now(), now());
            """;
        await using (var bookingCommand = new NpgsqlCommand(bookingSql, connection, transaction))
        {
            bookingCommand.Parameters.AddWithValue("id", bookingId);
            bookingCommand.Parameters.AddWithValue("customerUserId", customerUserId);
            bookingCommand.Parameters.AddWithValue("driverProfileId", driverProfileId);
            bookingCommand.Parameters.AddWithValue("vehicleId", vehicleId);
            bookingCommand.Parameters.AddWithValue("rideRequestId", rideRequestId);
            bookingCommand.Parameters.AddWithValue("bookingType", bookingType);
            bookingCommand.Parameters.AddWithValue("seats", seats);
            bookingCommand.Parameters.AddWithValue("totalAmount", totalAmount);
            bookingCommand.Parameters.AddWithValue("advanceAmount", advanceAmount);
            bookingCommand.Parameters.AddWithValue("remainingAmount", remainingAmount);
            bookingCommand.Parameters.AddWithValue("pickupAt", pickupAt);
            bookingCommand.Parameters.Add(new NpgsqlParameter("returnAt", NpgsqlDbType.TimestampTz) { Value = (object?)returnAt ?? DBNull.Value });
            bookingCommand.Parameters.AddWithValue("tripOtpHash", tripOtpHash);
            bookingCommand.Parameters.AddWithValue("bookingReference", bookingReference);
            bookingCommand.Parameters.AddWithValue("pickupLabel", pickupLabel);
            bookingCommand.Parameters.AddWithValue("destinationLabel", destinationLabel);
            bookingCommand.Parameters.AddWithValue("partyType", partyType);
            bookingCommand.Parameters.AddWithValue("offerId", offerId);
            await bookingCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var operationCommand = new NpgsqlCommand(
            """
            INSERT INTO udrive.trip_operations
                (id, booking_id, operational_status, trip_status, pickup_at, return_at,
                 driver_accepted_at, last_activity_at, version, created_at, updated_at)
            VALUES
                (gen_random_uuid(), @bookingId, 'DriverAccepted', 'DriverAccepted', @pickupAt, @returnAt,
                 now(), now(), 0, now(), now())
            ON CONFLICT (booking_id) DO UPDATE
            SET operational_status='DriverAccepted', trip_status='DriverAccepted',
                driver_accepted_at=COALESCE(udrive.trip_operations.driver_accepted_at, now()),
                last_activity_at=now(), updated_at=now(), version=udrive.trip_operations.version+1;
            """,
            connection,
            transaction))
        {
            operationCommand.Parameters.AddWithValue("bookingId", bookingId);
            operationCommand.Parameters.AddWithValue("pickupAt", pickupAt);
            operationCommand.Parameters.Add(new NpgsqlParameter("returnAt", NpgsqlDbType.TimestampTz) { Value = (object?)returnAt ?? DBNull.Value });
            await operationCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var assignmentCommand = new NpgsqlCommand(
            """
            INSERT INTO udrive.trip_assignments
                (id, booking_id, driver_profile_id, vehicle_id, assignment_type, status,
                 assigned_by_user_id, assignment_notes, accepted_at, version, created_at, updated_at)
            VALUES
                (gen_random_uuid(), @bookingId, @driverProfileId, @vehicleId, 'Marketplace', 'Active',
                 @customerUserId, 'Customer accepted the Driver fare offer.', now(), 0, now(), now())
            ON CONFLICT (booking_id) WHERE status='Active' DO NOTHING;
            """,
            connection,
            transaction))
        {
            assignmentCommand.Parameters.AddWithValue("bookingId", bookingId);
            assignmentCommand.Parameters.AddWithValue("driverProfileId", driverProfileId);
            assignmentCommand.Parameters.AddWithValue("vehicleId", vehicleId);
            assignmentCommand.Parameters.AddWithValue("customerUserId", customerUserId);
            await assignmentCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var tripHistoryCommand = new NpgsqlCommand(
            """
            INSERT INTO udrive.trip_status_history
                (id, booking_id, from_status, to_status, changed_by_user_id, source, reason, metadata_json, created_at)
            VALUES
                (gen_random_uuid(), @bookingId, 'Confirmed', 'DriverAccepted', @customerUserId,
                 'Customer', 'Customer accepted the Driver fare offer.', '{}'::jsonb, now());
            """,
            connection,
            transaction))
        {
            tripHistoryCommand.Parameters.AddWithValue("bookingId", bookingId);
            tripHistoryCommand.Parameters.AddWithValue("customerUserId", customerUserId);
            await tripHistoryCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var notificationCommand = new NpgsqlCommand(
            """
            INSERT INTO udrive.notifications
                (id, user_id, type, title, body, data_json, created_at, updated_at)
            SELECT gen_random_uuid(), dp.user_id, 'OfferAccepted', 'Your offer was accepted',
                   'The Customer accepted your fare offer. The ride is ready to start.',
                   jsonb_build_object('bookingId', @bookingId), now(), now()
            FROM udrive.driver_profiles dp
            WHERE dp.id=@driverProfileId;
            """,
            connection,
            transaction))
        {
            notificationCommand.Parameters.AddWithValue("bookingId", bookingId);
            notificationCommand.Parameters.AddWithValue("driverProfileId", driverProfileId);
            await notificationCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var decisionCommand = new NpgsqlCommand(
            """
            INSERT INTO udrive.driver_ride_request_decisions
                (ride_request_id, driver_profile_id, decision, reason, created_at, updated_at)
            VALUES (@rideRequestId, @driverProfileId, 'Accepted', NULL, now(), now())
            ON CONFLICT (ride_request_id, driver_profile_id) DO UPDATE
            SET decision = 'Accepted', reason = NULL, updated_at = now();
            """,
            connection,
            transaction))
        {
            decisionCommand.Parameters.AddWithValue("rideRequestId", rideRequestId);
            decisionCommand.Parameters.AddWithValue("driverProfileId", driverProfileId);
            await decisionCommand.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var updateRide = new NpgsqlCommand(
            "UPDATE udrive.ride_requests SET status='Confirmed', selected_offer_id=@offerId, version=version+1, updated_at=now() WHERE id=@rideRequestId;",
            connection,
            transaction))
        {
            updateRide.Parameters.AddWithValue("offerId", offerId);
            updateRide.Parameters.AddWithValue("rideRequestId", rideRequestId);
            await updateRide.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var updateOffers = new NpgsqlCommand(
            "UPDATE udrive.driver_offers SET status = CASE WHEN id=@offerId THEN 'Selected' ELSE 'Expired' END, responded_at=now(), version=version+1, updated_at=now() WHERE ride_request_id=@rideRequestId;",
            connection,
            transaction))
        {
            updateOffers.Parameters.AddWithValue("offerId", offerId);
            updateOffers.Parameters.AddWithValue("rideRequestId", rideRequestId);
            await updateOffers.ExecuteNonQueryAsync(cancellationToken);
        }

        await AddHistoryAsync(
            connection,
            transaction,
            "Booking",
            bookingId,
            bookingReference,
            null,
            "DriverAccepted",
            customerUserId,
            "Customer selected a verified Driver offer.",
            $"{{\"rideRequestId\":\"{rideRequestId}\",\"offerId\":\"{offerId}\"}}",
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return await GetBookingByIdAsync(customerUserId, bookingId, tripOtp, cancellationToken);
    }

    public async Task<ServiceResult<IReadOnlyList<BookingDto>>> GetMyBookingsAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT b.id, b.booking_reference, b.booking_type, b.status,
                   b.seats_booked, b.total_amount, b.advance_amount,
                   b.remaining_amount, b.pickup_at, b.return_at,
                   COALESCE(b.pickup_label, rr.pickup_label, tp.pickup_point, ''),
                   COALESCE(b.destination_label, rr.destination_label, d.name_en, ''),
                   COALESCE(b.party_type, rr.party_type, 'Family'),
                   du.full_name, du.phone_number,
                   CASE WHEN v.id IS NULL THEN NULL
                        ELSE concat_ws(' ', v.make, v.model, v.year::text) END,
                   v.registration_number,
                   b.ride_request_id, b.tour_package_id, pb.id,
                   b.created_at
            FROM udrive.bookings b
            LEFT JOIN udrive.ride_requests rr ON rr.id = b.ride_request_id
            LEFT JOIN udrive.tour_packages tp ON tp.id = b.tour_package_id
            LEFT JOIN udrive.destinations d ON d.id = tp.destination_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = b.driver_profile_id
            LEFT JOIN udrive.users du ON du.id = dp.user_id
            LEFT JOIN udrive.vehicles v ON v.id = b.vehicle_id
            LEFT JOIN udrive.package_bookings pb ON pb.booking_id = b.id
            WHERE b.customer_user_id = @userId
               OR dp.user_id = @userId
            ORDER BY b.pickup_at DESC, b.created_at DESC;
            """;

        var result = new List<BookingDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(ReadBooking(reader, null));
        }

        return ServiceResult<IReadOnlyList<BookingDto>>.Ok(result);
    }

    public async Task<ServiceResult<BookingDto>> CancelBookingAsync(
        Guid userId,
        Guid bookingId,
        CancelBookingRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.Serializable,
            cancellationToken);

        const string lockSql = """
            SELECT b.booking_reference, b.status, b.pickup_at, b.tour_package_id,
                   b.seats_booked, b.customer_user_id,
                   dp.user_id AS driver_user_id
            FROM udrive.bookings b
            LEFT JOIN udrive.driver_profiles dp ON dp.id = b.driver_profile_id
            WHERE b.id = @bookingId
            FOR UPDATE OF b;
            """;

        string reference;
        string status;
        DateTimeOffset pickupAt;
        Guid? packageId;
        int seats;
        Guid customerId;
        Guid? driverId;
        await using (var command = new NpgsqlCommand(lockSql, connection, transaction))
        {
            command.Parameters.AddWithValue("bookingId", bookingId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<BookingDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "booking_not_found",
                    "The booking was not found.");
            }
            reference = reader.GetString(0);
            status = reader.GetString(1);
            pickupAt = reader.GetFieldValue<DateTimeOffset>(2);
            packageId = reader.IsDBNull(3) ? null : reader.GetGuid(3);
            seats = reader.GetInt32(4);
            customerId = reader.GetGuid(5);
            driverId = reader.IsDBNull(6) ? null : reader.GetGuid(6);
        }

        if (userId != customerId && userId != driverId)
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status403Forbidden,
                "booking_not_owned",
                "You cannot cancel this booking.");
        }
        if (status is "Completed" or "Cancelled" or "InProgress")
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "booking_cannot_be_cancelled",
                "This booking can no longer be cancelled.");
        }

        if (packageId is not null)
        {
            await using var lockPackage = new NpgsqlCommand(
                "SELECT id FROM udrive.tour_packages WHERE id=@id FOR UPDATE;",
                connection,
                transaction);
            lockPackage.Parameters.AddWithValue("id", packageId.Value);
            await lockPackage.ExecuteScalarAsync(cancellationToken);

            await using var restore = new NpgsqlCommand(
                "UPDATE udrive.tour_packages SET available_seats=LEAST(total_seats, available_seats+@seats), version=version+1, updated_at=now() WHERE id=@id;",
                connection,
                transaction);
            restore.Parameters.AddWithValue("seats", seats);
            restore.Parameters.AddWithValue("id", packageId.Value);
            await restore.ExecuteNonQueryAsync(cancellationToken);

            await using var cancelPackageBooking = new NpgsqlCommand(
                "UPDATE udrive.package_bookings SET status='Cancelled', cancelled_at=now(), cancellation_reason=@reason, version=version+1, updated_at=now() WHERE booking_id=@bookingId;",
                connection,
                transaction);
            cancelPackageBooking.Parameters.AddWithValue("reason", request.Reason.Trim());
            cancelPackageBooking.Parameters.AddWithValue("bookingId", bookingId);
            await cancelPackageBooking.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var update = new NpgsqlCommand(
            "UPDATE udrive.bookings SET status='Cancelled', cancellation_reason=@reason, version=version+1, updated_at=now() WHERE id=@bookingId;",
            connection,
            transaction))
        {
            update.Parameters.AddWithValue("reason", request.Reason.Trim());
            update.Parameters.AddWithValue("bookingId", bookingId);
            await update.ExecuteNonQueryAsync(cancellationToken);
        }

        await AddHistoryAsync(
            connection,
            transaction,
            "Booking",
            bookingId,
            reference,
            status,
            "Cancelled",
            userId,
            request.Reason.Trim(),
            "{}",
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return await GetBookingByIdAsync(userId, bookingId, null, cancellationToken);
    }

    public async Task<ServiceResult<BookingDto>> RescheduleBookingAsync(
        Guid userId,
        Guid bookingId,
        RescheduleBookingRequest request,
        CancellationToken cancellationToken)
    {
        if (request.PickupAt <= DateTimeOffset.UtcNow.AddHours(2))
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_pickup_time",
                "The new pickup time must be at least two hours in the future.");
        }
        if (request.ReturnAt is not null && request.ReturnAt <= request.PickupAt)
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_return_time",
                "Return time must be after pickup time.");
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        const string updateSql = """
            UPDATE udrive.bookings
            SET pickup_at=@pickupAt, return_at=@returnAt,
                version=version+1, updated_at=now()
            WHERE id=@bookingId AND customer_user_id=@userId
              AND status IN ('Pending','Confirmed','DriverAssigned')
            RETURNING booking_reference, status, ride_request_id;
            """;
        string reference;
        string status;
        Guid? rideRequestId;
        await using (var command = new NpgsqlCommand(updateSql, connection, transaction))
        {
            command.Parameters.AddWithValue("pickupAt", request.PickupAt.ToUniversalTime());
            command.Parameters.Add(new NpgsqlParameter("returnAt", NpgsqlDbType.TimestampTz) { Value = (object?)request.ReturnAt?.ToUniversalTime() ?? DBNull.Value });
            command.Parameters.AddWithValue("bookingId", bookingId);
            command.Parameters.AddWithValue("userId", userId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<BookingDto>.Fail(
                    StatusCodes.Status409Conflict,
                    "booking_cannot_be_rescheduled",
                    "Only your upcoming pending or confirmed booking can be rescheduled.");
            }
            reference = reader.GetString(0);
            status = reader.GetString(1);
            rideRequestId = reader.IsDBNull(2) ? null : reader.GetGuid(2);
        }

        if (rideRequestId is not null)
        {
            await using var updateRide = new NpgsqlCommand(
                "UPDATE udrive.ride_requests SET pickup_at=@pickupAt, return_at=@returnAt, version=version+1, updated_at=now() WHERE id=@id;",
                connection,
                transaction);
            updateRide.Parameters.AddWithValue("pickupAt", request.PickupAt.ToUniversalTime());
            updateRide.Parameters.Add(new NpgsqlParameter("returnAt", NpgsqlDbType.TimestampTz) { Value = (object?)request.ReturnAt?.ToUniversalTime() ?? DBNull.Value });
            updateRide.Parameters.AddWithValue("id", rideRequestId.Value);
            await updateRide.ExecuteNonQueryAsync(cancellationToken);
        }

        await AddHistoryAsync(
            connection,
            transaction,
            "Booking",
            bookingId,
            reference,
            status,
            status,
            userId,
            request.Reason?.Trim() ?? "Customer rescheduled the booking.",
            $"{{\"pickupAt\":\"{request.PickupAt:O}\"}}",
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return await GetBookingByIdAsync(userId, bookingId, null, cancellationToken);
    }

    public async Task<ServiceResult<IReadOnlyList<BookingStatusHistoryDto>>> GetHistoryAsync(
        Guid userId,
        Guid bookingId,
        CancellationToken cancellationToken)
    {
        const string ownershipSql = """
            SELECT 1
            FROM udrive.bookings b
            LEFT JOIN udrive.driver_profiles dp ON dp.id=b.driver_profile_id
            WHERE b.id=@bookingId AND (b.customer_user_id=@userId OR dp.user_id=@userId);
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using (var ownership = new NpgsqlCommand(ownershipSql, connection))
        {
            ownership.Parameters.AddWithValue("bookingId", bookingId);
            ownership.Parameters.AddWithValue("userId", userId);
            if (await ownership.ExecuteScalarAsync(cancellationToken) is null)
            {
                return ServiceResult<IReadOnlyList<BookingStatusHistoryDto>>.Fail(
                    StatusCodes.Status404NotFound,
                    "booking_not_found",
                    "The booking was not found.");
            }
        }

        const string sql = """
            SELECT id, entity_type, entity_id, booking_reference,
                   from_status, to_status, reason, created_at
            FROM udrive.booking_status_history
            WHERE entity_type='Booking' AND entity_id=@bookingId
            ORDER BY created_at;
            """;
        var result = new List<BookingStatusHistoryDto>();
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("bookingId", bookingId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(new BookingStatusHistoryDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetGuid(2),
                reader.IsDBNull(3) ? null : reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetString(4),
                reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetString(6),
                reader.GetFieldValue<DateTimeOffset>(7)));
        }
        return ServiceResult<IReadOnlyList<BookingStatusHistoryDto>>.Ok(result);
    }

    private async Task<ServiceResult<DriverOfferDto>> GetOfferByIdAsync(
        Guid offerId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT o.id, o.ride_request_id, o.driver_profile_id, o.vehicle_id,
                   COALESCE(NULLIF(u.full_name, ''), 'Verified Driver'),
                   COALESCE(dp.average_rating, 0), COALESCE(dp.completed_trips, 0),
                   COALESCE(dp.safety_score, 80),
                   COALESCE(NULLIF(concat_ws(' ', v.make, v.model, v.year::text), ''), 'Verified vehicle'),
                   COALESCE(v.registration_number, ''), COALESCE(v.category, 'Vehicle'),
                   COALESCE(ST_Distance(dpl.location, rr.pickup_location) / 1000.0, 0)::double precision AS pickup_distance_km,
                   o.amount, o.counter_amount,
                   o.estimated_arrival_minutes, o.message, o.status,
                   o.expires_at, o.created_at
            FROM udrive.driver_offers o
            LEFT JOIN udrive.driver_profiles dp ON dp.id=o.driver_profile_id
            LEFT JOIN udrive.users u ON u.id=dp.user_id
            LEFT JOIN udrive.vehicles v ON v.id=o.vehicle_id
            LEFT JOIN udrive.ride_requests rr ON rr.id=o.ride_request_id
            LEFT JOIN LATERAL (
                SELECT location
                FROM udrive.driver_presence_locations p
                WHERE p.driver_profile_id=o.driver_profile_id
                ORDER BY p.server_timestamp DESC
                LIMIT 1
            ) dpl ON true
            WHERE o.id=@offerId;
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("offerId", offerId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<DriverOfferDto>.Fail(
                StatusCodes.Status404NotFound,
                "offer_not_found",
                "The Driver offer was not found.");
        }
        return ServiceResult<DriverOfferDto>.Ok(ReadOffer(reader));
    }

    private async Task<List<DriverOfferDto>> ReadOffersAsync(
        NpgsqlConnection connection,
        Guid rideRequestId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT o.id, o.ride_request_id, o.driver_profile_id, o.vehicle_id,
                   COALESCE(NULLIF(u.full_name, ''), 'Verified Driver'),
                   COALESCE(dp.average_rating, 0), COALESCE(dp.completed_trips, 0),
                   COALESCE(dp.safety_score, 80),
                   COALESCE(NULLIF(concat_ws(' ', v.make, v.model, v.year::text), ''), 'Verified vehicle'),
                   COALESCE(v.registration_number, ''), COALESCE(v.category, 'Vehicle'),
                   COALESCE(ST_Distance(dpl.location, rr.pickup_location) / 1000.0, 0)::double precision AS pickup_distance_km,
                   o.amount, o.counter_amount,
                   o.estimated_arrival_minutes, o.message, o.status,
                   o.expires_at, o.created_at
            FROM udrive.driver_offers o
            LEFT JOIN udrive.driver_profiles dp ON dp.id=o.driver_profile_id
            LEFT JOIN udrive.users u ON u.id=dp.user_id
            LEFT JOIN udrive.vehicles v ON v.id=o.vehicle_id
            LEFT JOIN udrive.ride_requests rr ON rr.id=o.ride_request_id
            LEFT JOIN LATERAL (
                SELECT location
                FROM udrive.driver_presence_locations p
                WHERE p.driver_profile_id=o.driver_profile_id
                ORDER BY p.server_timestamp DESC
                LIMIT 1
            ) dpl ON true
            WHERE o.ride_request_id=@rideRequestId
              AND o.status IN ('Pending','Countered','Accepted','Selected')
              AND (o.status='Selected' OR o.expires_at > now())
            ORDER BY COALESCE(o.counter_amount, o.amount),
                     dp.safety_score DESC,
                     o.created_at;
            """;
        var result = new List<DriverOfferDto>();
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("rideRequestId", rideRequestId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(ReadOffer(reader));
        }
        return result;
    }

    private async Task<ServiceResult<BookingDto>> GetBookingByIdAsync(
        Guid userId,
        Guid bookingId,
        string? tripOtp,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT b.id, b.booking_reference, b.booking_type, b.status,
                   b.seats_booked, b.total_amount, b.advance_amount,
                   b.remaining_amount, b.pickup_at, b.return_at,
                   COALESCE(b.pickup_label, rr.pickup_label, tp.pickup_point, ''),
                   COALESCE(b.destination_label, rr.destination_label, d.name_en, ''),
                   COALESCE(b.party_type, rr.party_type, 'Family'),
                   du.full_name, du.phone_number,
                   CASE WHEN v.id IS NULL THEN NULL
                        ELSE concat_ws(' ', v.make, v.model, v.year::text) END,
                   v.registration_number,
                   b.ride_request_id, b.tour_package_id, pb.id,
                   b.created_at
            FROM udrive.bookings b
            LEFT JOIN udrive.ride_requests rr ON rr.id=b.ride_request_id
            LEFT JOIN udrive.tour_packages tp ON tp.id=b.tour_package_id
            LEFT JOIN udrive.destinations d ON d.id=tp.destination_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id=b.driver_profile_id
            LEFT JOIN udrive.users du ON du.id=dp.user_id
            LEFT JOIN udrive.vehicles v ON v.id=b.vehicle_id
            LEFT JOIN udrive.package_bookings pb ON pb.booking_id=b.id
            WHERE b.id=@bookingId
              AND (b.customer_user_id=@userId OR dp.user_id=@userId);
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("bookingId", bookingId);
        command.Parameters.AddWithValue("userId", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status404NotFound,
                "booking_not_found",
                "The booking was not found.");
        }
        return ServiceResult<BookingDto>.Ok(ReadBooking(reader, tripOtp));
    }

    private async Task ExpireRideRequestsAsync(CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.ride_requests
            SET status='Expired', version=version+1, updated_at=now()
            WHERE status IN ('Open','SearchingDrivers','ReceivingOffers')
              AND pickup_at <= now() - interval '15 minutes';

            UPDATE udrive.ride_requests rr
            SET status='NoDriverAccepted', version=version+1, updated_at=now()
            WHERE rr.status IN ('Open','SearchingDrivers','ReceivingOffers')
              AND rr.pickup_at > now()
              AND rr.expires_at IS NOT NULL
              AND rr.expires_at <= now()
              AND NOT EXISTS (
                  SELECT 1 FROM udrive.driver_offers o
                  WHERE o.ride_request_id=rr.id
              );

            UPDATE udrive.ride_requests rr
            SET status='Expired', version=version+1, updated_at=now()
            WHERE rr.status IN ('Open','SearchingDrivers','ReceivingOffers')
              AND rr.pickup_at > now()
              AND rr.expires_at IS NOT NULL
              AND rr.expires_at <= now()
              AND EXISTS (
                  SELECT 1 FROM udrive.driver_offers o
                  WHERE o.ride_request_id=rr.id
              );
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private async Task<ApprovedDriverContext?> GetApprovedDriverAsync(
        Guid userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT dp.id,
                   COALESCE(array_agg(v.id) FILTER (WHERE lower(v.status) IN ('verified','approved')), '{}'::uuid[])
            FROM udrive.driver_profiles dp
            LEFT JOIN udrive.vehicles v ON v.driver_profile_id=dp.id
            WHERE dp.user_id=@userId AND lower(dp.verification_status) IN ('approved','verified')
            GROUP BY dp.id;
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return null;
        return new ApprovedDriverContext(
            reader.GetGuid(0),
            reader.GetFieldValue<Guid[]>(1));
    }

    private async Task CreateDemoDriverOfferAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid rideRequestId,
        decimal customerOffer,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.driver_offers
                (id, ride_request_id, driver_profile_id, vehicle_id, amount,
                 estimated_arrival_minutes, message, status, expires_at,
                 counter_amount, responded_at, version, created_at, updated_at)
            SELECT gen_random_uuid(), @rideRequestId, dp.id, v.id,
                   GREATEST(@customerOffer, round(@customerOffer * 1.05, 0)),
                   18, 'Verified tourism Driver · Demo marketplace offer',
                   'Countered', now() + interval '20 minutes',
                   GREATEST(@customerOffer, round(@customerOffer * 1.05, 0)),
                   now(), 0, now(), now()
            FROM udrive.driver_profiles dp
            JOIN udrive.vehicles v ON v.driver_profile_id=dp.id AND v.status='Verified'
            WHERE lower(dp.verification_status) IN ('approved','verified')
            ORDER BY dp.safety_score DESC, dp.average_rating DESC
            LIMIT 1;
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("rideRequestId", rideRequestId);
        command.Parameters.AddWithValue("customerOffer", customerOffer);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    internal static async Task AddHistoryAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        string entityType,
        Guid entityId,
        string? bookingReference,
        string? fromStatus,
        string toStatus,
        Guid? changedBy,
        string? reason,
        string metadataJson,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.booking_status_history
                (id, entity_type, entity_id, booking_reference, from_status,
                 to_status, changed_by_user_id, reason, metadata_json, created_at)
            VALUES
                (gen_random_uuid(), @entityType, @entityId, @bookingReference,
                 @fromStatus, @toStatus, @changedBy, @reason,
                 CAST(@metadataJson AS jsonb), now());
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("entityType", entityType);
        command.Parameters.AddWithValue("entityId", entityId);
        command.Parameters.Add(new NpgsqlParameter("bookingReference", NpgsqlDbType.Varchar) { Value = (object?)bookingReference ?? DBNull.Value });
        command.Parameters.Add(new NpgsqlParameter("fromStatus", NpgsqlDbType.Varchar) { Value = (object?)fromStatus ?? DBNull.Value });
        command.Parameters.AddWithValue("toStatus", toStatus);
        command.Parameters.Add(new NpgsqlParameter("changedBy", NpgsqlDbType.Uuid) { Value = (object?)changedBy ?? DBNull.Value });
        command.Parameters.Add(new NpgsqlParameter("reason", NpgsqlDbType.Varchar) { Value = (object?)reason ?? DBNull.Value });
        command.Parameters.AddWithValue("metadataJson", metadataJson);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private async Task<string> GetUserDisplayNameAsync(Guid userId, CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(
            "SELECT COALESCE(NULLIF(full_name, ''), 'Customer') FROM udrive.users WHERE id = @id;",
            connection);
        command.Parameters.AddWithValue("id", userId);
        return (await command.ExecuteScalarAsync(cancellationToken))?.ToString() ?? "Customer";
    }

    private static RideRequestDto ReadRideRequest(NpgsqlDataReader reader) => new(
        reader.GetGuid(0),
        reader.GetString(1),
        reader.GetString(2),
        reader.GetDouble(3),
        reader.GetDouble(4),
        reader.GetDouble(5),
        reader.GetDouble(6),
        reader.GetFieldValue<DateTimeOffset>(7),
        reader.IsDBNull(8) ? null : reader.GetFieldValue<DateTimeOffset>(8),
        reader.GetString(9),
        reader.GetInt32(10),
        reader.GetInt32(11),
        reader.GetInt32(12),
        reader.GetInt32(13),
        reader.GetDecimal(14),
        reader.GetString(15),
        reader.GetString(16),
        reader.GetBoolean(17),
        reader.GetBoolean(18),
        reader.GetString(19),
        reader.GetInt32(20),
        reader.IsDBNull(21) ? null : reader.GetGuid(21),
        reader.IsDBNull(22) ? null : reader.GetFieldValue<DateTimeOffset>(22),
        reader.GetFieldValue<DateTimeOffset>(23),
        reader.IsDBNull(24) ? "Customer" : reader.GetString(24));

    private static DriverOfferDto ReadOffer(NpgsqlDataReader reader) => new(
        reader.GetGuid(0),
        reader.GetGuid(1),
        reader.GetGuid(2),
        reader.GetGuid(3),
        reader.GetString(4),
        reader.GetDecimal(5),
        reader.GetInt32(6),
        reader.GetInt32(7),
        reader.GetString(8),
        reader.GetString(9),
        reader.GetString(10),
        reader.GetDouble(11),
        reader.GetDecimal(12),
        reader.IsDBNull(13) ? null : reader.GetDecimal(13),
        reader.GetInt32(14),
        reader.IsDBNull(15) ? null : reader.GetString(15),
        reader.GetString(16),
        reader.GetFieldValue<DateTimeOffset>(17),
        reader.GetFieldValue<DateTimeOffset>(18));

    private static BookingDto ReadBooking(NpgsqlDataReader reader, string? tripOtp) => new(
        reader.GetGuid(0),
        reader.GetString(1),
        reader.GetString(2),
        reader.GetString(3),
        reader.GetInt32(4),
        reader.GetDecimal(5),
        reader.GetDecimal(6),
        reader.GetDecimal(7),
        reader.GetFieldValue<DateTimeOffset>(8),
        reader.IsDBNull(9) ? null : reader.GetFieldValue<DateTimeOffset>(9),
        reader.GetString(10),
        reader.GetString(11),
        reader.GetString(12),
        reader.IsDBNull(13) ? null : reader.GetString(13),
        reader.IsDBNull(14) ? null : reader.GetString(14),
        reader.IsDBNull(15) ? null : reader.GetString(15),
        reader.IsDBNull(16) ? null : reader.GetString(16),
        reader.IsDBNull(17) ? null : reader.GetGuid(17),
        reader.IsDBNull(18) ? null : reader.GetGuid(18),
        reader.IsDBNull(19) ? null : reader.GetGuid(19),
        tripOtp,
        reader.GetFieldValue<DateTimeOffset>(20));

    private static (string Code, string Message)? ValidateRideRequest(CreateRideRequestRequest request)
    {
        var now = DateTimeOffset.UtcNow;
        if (request.InstantRide)
        {
            // Instant rides are allowed to start immediately. Keep a small clock-skew
            // tolerance so web/mobile clients do not fail while the request is in transit.
            if (request.PickupAt < now.AddMinutes(-5))
                return ("pickup_in_past", "Pickup time cannot be in the past.");
        }
        else if (request.PickupAt <= now.AddMinutes(30))
        {
            return ("pickup_too_soon", "Advance bookings must be at least 30 minutes in the future.");
        }
        if (request.PickupAt > now.AddYears(1))
            return ("pickup_too_far", "Advance bookings can be created up to one year ahead.");
        if (request.ReturnAt is not null && request.ReturnAt <= request.PickupAt)
            return ("invalid_return_time", "Return time must be after pickup time.");
        if (request.Adults + request.Children != request.SeatsRequested)
            return ("passenger_count_mismatch", "Seats requested must match adults plus children.");
        if (request.WomenOnly && request.FamilyOnly)
            return ("conflicting_preferences", "Choose either family-only or women-only preference.");
        return null;
    }

    private static string SanitizePartyType(string value)
    {
        var normalized = value.Trim();
        return normalized.Length == 0 ? "Family" : normalized[..Math.Min(normalized.Length, 32)];
    }

    private static string GenerateReference(string prefix) =>
        $"{prefix}-{DateTimeOffset.UtcNow:yyMMdd}-{Convert.ToHexString(RandomNumberGenerator.GetBytes(3))}";

    private static string GenerateOtp() =>
        RandomNumberGenerator.GetInt32(1000, 10000).ToString(CultureInfo.InvariantCulture);

    private static bool DemoMarketplaceEnabled() =>
        !string.Equals(
            Environment.GetEnvironmentVariable("ENABLE_DEMO_MARKETPLACE"),
            "false",
            StringComparison.OrdinalIgnoreCase);

    private sealed record ApprovedDriverContext(
        Guid DriverProfileId,
        IReadOnlyCollection<Guid> VehicleIds);
}
