using System.Data;
using System.Security.Cryptography;
using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Domain.Enums;
using UDrive.Api.Models;
using UDrive.Api.Security;

namespace UDrive.Api.Services;

public sealed class PackageMarketplaceService(
    string connectionString,
    AuthOptions authOptions)
{
    public async Task<ServiceResult<TourPackageLiveDto>> CreateDriverPackageAsync(
        Guid driverUserId,
        CreateTourPackageRequest request,
        CancellationToken cancellationToken)
    {
        var context = await GetDriverVehicleContextAsync(
            driverUserId,
            request.VehicleId,
            cancellationToken);
        if (context is null)
        {
            return ServiceResult<TourPackageLiveDto>.Fail(
                StatusCodes.Status403Forbidden,
                "driver_or_vehicle_not_approved",
                "An approved Driver profile and verified vehicle are required.");
        }

        var validation = ValidatePackage(request, context);
        if (validation is not null)
        {
            return ServiceResult<TourPackageLiveDto>.Fail(
                StatusCodes.Status400BadRequest,
                validation.Value.Code,
                validation.Value.Message);
        }

        var id = Guid.NewGuid();
        var routeStops = SanitizeArray(request.RouteStops, 24, 160);
        var inclusions = SanitizeArray(request.Inclusions, 32, 160);
        var exclusions = SanitizeArray(request.Exclusions, 32, 160);
        var itineraryJson = JsonSerializer.Serialize(
            SanitizeArray(request.Itinerary, 30, 500));

        const string sql = """
            INSERT INTO udrive.tour_packages
                (id, driver_profile_id, vehicle_id, destination_id, title,
                 starting_city, pickup_point, departure_at, return_at,
                 total_seats, available_seats, price_per_seat,
                 whole_vehicle_price, family_only, women_only,
                 customer_offers_allowed, status, inclusions, exclusions,
                 itinerary_json, cover_image_url, description,
                 cancellation_policy, passenger_policy, luggage_allowance,
                 route_stops, fuel_included, toll_included, hotel_included,
                 meals_included, guide_included, jeep_transfer_included,
                 driver_accommodation_included, version, created_at, updated_at)
            VALUES
                (@id, @driverProfileId, @vehicleId, @destinationId, @title,
                 @startingCity, @pickupPoint, @departureAt, @returnAt,
                 @totalSeats, @totalSeats, @pricePerSeat,
                 @wholeVehiclePrice, @familyOnly, @womenOnly,
                 @offersAllowed, 'Draft', @inclusions, @exclusions,
                 CAST(@itineraryJson AS jsonb), @coverImageUrl, @description,
                 @cancellationPolicy, @passengerPolicy, @luggageAllowance,
                 @routeStops, @fuelIncluded, @tollIncluded, @hotelIncluded,
                 @mealsIncluded, @guideIncluded, @jeepTransferIncluded,
                 @driverAccommodationIncluded, 0, now(), now());
            """;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("driverProfileId", context.DriverProfileId);
        command.Parameters.AddWithValue("vehicleId", request.VehicleId);
        command.Parameters.AddWithValue("destinationId", request.DestinationId);
        command.Parameters.AddWithValue("title", request.Title.Trim());
        command.Parameters.AddWithValue("startingCity", request.StartingCity.Trim());
        command.Parameters.AddWithValue("pickupPoint", request.PickupPoint.Trim());
        command.Parameters.AddWithValue("departureAt", request.DepartureAt.ToUniversalTime());
        command.Parameters.Add(new NpgsqlParameter("returnAt", NpgsqlDbType.TimestampTz) { Value = (object?)request.ReturnAt?.ToUniversalTime() ?? DBNull.Value });
        command.Parameters.AddWithValue("totalSeats", request.TotalSeats);
        command.Parameters.AddWithValue("pricePerSeat", request.PricePerSeat);
        command.Parameters.AddWithValue("wholeVehiclePrice", request.WholeVehiclePrice);
        command.Parameters.AddWithValue("familyOnly", request.FamilyOnly);
        command.Parameters.AddWithValue("womenOnly", request.WomenOnly);
        command.Parameters.AddWithValue("offersAllowed", request.CustomerOffersAllowed);
        command.Parameters.AddWithValue("inclusions", inclusions);
        command.Parameters.AddWithValue("exclusions", exclusions);
        command.Parameters.AddWithValue("itineraryJson", itineraryJson);
        command.Parameters.Add(new NpgsqlParameter("coverImageUrl", NpgsqlDbType.Text) { Value = (object?)request.CoverImageUrl?.Trim() ?? DBNull.Value });
        command.Parameters.Add(new NpgsqlParameter("description", NpgsqlDbType.Text) { Value = (object?)request.Description?.Trim() ?? DBNull.Value });
        command.Parameters.Add(new NpgsqlParameter("cancellationPolicy", NpgsqlDbType.Text) { Value = (object?)request.CancellationPolicy?.Trim() ?? DBNull.Value });
        command.Parameters.AddWithValue("passengerPolicy", request.PassengerPolicy?.Trim() ?? "Verified passengers only");
        command.Parameters.Add(new NpgsqlParameter("luggageAllowance", NpgsqlDbType.Varchar) { Value = (object?)request.LuggageAllowance?.Trim() ?? DBNull.Value });
        command.Parameters.AddWithValue("routeStops", routeStops);
        command.Parameters.AddWithValue("fuelIncluded", request.FuelIncluded);
        command.Parameters.AddWithValue("tollIncluded", request.TollIncluded);
        command.Parameters.AddWithValue("hotelIncluded", request.HotelIncluded);
        command.Parameters.AddWithValue("mealsIncluded", request.MealsIncluded);
        command.Parameters.AddWithValue("guideIncluded", request.GuideIncluded);
        command.Parameters.AddWithValue("jeepTransferIncluded", request.JeepTransferIncluded);
        command.Parameters.AddWithValue("driverAccommodationIncluded", request.DriverAccommodationIncluded);
        await command.ExecuteNonQueryAsync(cancellationToken);

        return await GetPackageByIdAsync(id, driverUserId, includeNonPublic: true, cancellationToken);
    }

    public async Task<ServiceResult<TourPackageLiveDto>> UpdateDriverPackageAsync(
        Guid driverUserId,
        Guid packageId,
        CreateTourPackageRequest request,
        CancellationToken cancellationToken)
    {
        var context = await GetDriverVehicleContextAsync(
            driverUserId,
            request.VehicleId,
            cancellationToken);
        if (context is null)
        {
            return ServiceResult<TourPackageLiveDto>.Fail(
                StatusCodes.Status403Forbidden,
                "driver_or_vehicle_not_approved",
                "An approved Driver profile and verified vehicle are required.");
        }

        var validation = ValidatePackage(request, context);
        if (validation is not null)
        {
            return ServiceResult<TourPackageLiveDto>.Fail(
                StatusCodes.Status400BadRequest,
                validation.Value.Code,
                validation.Value.Message);
        }

        const string sql = """
            UPDATE udrive.tour_packages
            SET vehicle_id=@vehicleId, destination_id=@destinationId,
                title=@title, starting_city=@startingCity,
                pickup_point=@pickupPoint, departure_at=@departureAt,
                return_at=@returnAt, total_seats=@totalSeats,
                available_seats=LEAST(available_seats, @totalSeats),
                price_per_seat=@pricePerSeat,
                whole_vehicle_price=@wholeVehiclePrice,
                family_only=@familyOnly, women_only=@womenOnly,
                customer_offers_allowed=@offersAllowed,
                inclusions=@inclusions, exclusions=@exclusions,
                itinerary_json=CAST(@itineraryJson AS jsonb),
                cover_image_url=@coverImageUrl, description=@description,
                cancellation_policy=@cancellationPolicy,
                passenger_policy=@passengerPolicy,
                luggage_allowance=@luggageAllowance,
                route_stops=@routeStops, fuel_included=@fuelIncluded,
                toll_included=@tollIncluded, hotel_included=@hotelIncluded,
                meals_included=@mealsIncluded, guide_included=@guideIncluded,
                jeep_transfer_included=@jeepTransferIncluded,
                driver_accommodation_included=@driverAccommodationIncluded,
                status='Draft', review_notes=NULL,
                version=version+1, updated_at=now()
            WHERE id=@packageId AND driver_profile_id=@driverProfileId
              AND status IN ('Draft','ChangesRequired','Rejected')
            RETURNING id;
            """;

        var routeStops = SanitizeArray(request.RouteStops, 24, 160);
        var inclusions = SanitizeArray(request.Inclusions, 32, 160);
        var exclusions = SanitizeArray(request.Exclusions, 32, 160);
        var itineraryJson = JsonSerializer.Serialize(SanitizeArray(request.Itinerary, 30, 500));

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("packageId", packageId);
        command.Parameters.AddWithValue("driverProfileId", context.DriverProfileId);
        AddPackageParameters(command, request, routeStops, inclusions, exclusions, itineraryJson);
        if (await command.ExecuteScalarAsync(cancellationToken) is null)
        {
            return ServiceResult<TourPackageLiveDto>.Fail(
                StatusCodes.Status409Conflict,
                "package_locked",
                "Only your Draft, Changes Required or Rejected package can be edited.");
        }

        return await GetPackageByIdAsync(packageId, driverUserId, includeNonPublic: true, cancellationToken);
    }

    public async Task<ServiceResult<TourPackageLiveDto>> SubmitPackageAsync(
        Guid driverUserId,
        Guid packageId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE udrive.tour_packages tp
            SET status='PendingApproval', submitted_at=now(),
                review_notes=NULL, version=version+1, updated_at=now()
            FROM udrive.driver_profiles dp
            WHERE tp.id=@packageId
              AND tp.driver_profile_id=dp.id
              AND dp.user_id=@userId
              AND dp.verification_status='Approved'
              AND tp.status IN ('Draft','ChangesRequired','Rejected')
              AND tp.departure_at > now() + interval '6 hours'
            RETURNING tp.id;
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("packageId", packageId);
        command.Parameters.AddWithValue("userId", driverUserId);
        if (await command.ExecuteScalarAsync(cancellationToken) is null)
        {
            return ServiceResult<TourPackageLiveDto>.Fail(
                StatusCodes.Status409Conflict,
                "package_cannot_be_submitted",
                "The package must be editable, complete and at least six hours before departure.");
        }
        return await GetPackageByIdAsync(packageId, driverUserId, includeNonPublic: true, cancellationToken);
    }

    public async Task<ServiceResult<TourPackageLiveDto>> TogglePackageAsync(
        Guid driverUserId,
        Guid packageId,
        bool activate,
        CancellationToken cancellationToken)
    {
        var target = activate ? "Active" : "Paused";
        var allowed = activate ? "Paused" : "Active";
        const string sql = """
            UPDATE udrive.tour_packages tp
            SET status=@target, version=version+1, updated_at=now()
            FROM udrive.driver_profiles dp
            WHERE tp.id=@packageId AND tp.driver_profile_id=dp.id
              AND dp.user_id=@userId AND tp.status=@allowed
              AND tp.departure_at > now()
            RETURNING tp.id;
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("target", target);
        command.Parameters.AddWithValue("allowed", allowed);
        command.Parameters.AddWithValue("packageId", packageId);
        command.Parameters.AddWithValue("userId", driverUserId);
        if (await command.ExecuteScalarAsync(cancellationToken) is null)
        {
            return ServiceResult<TourPackageLiveDto>.Fail(
                StatusCodes.Status409Conflict,
                "package_status_conflict",
                $"The package cannot be changed to {target}.");
        }
        return await GetPackageByIdAsync(packageId, driverUserId, includeNonPublic: true, cancellationToken);
    }

    public async Task<ServiceResult<IReadOnlyList<TourPackageLiveDto>>> GetDriverPackagesAsync(
        Guid driverUserId,
        CancellationToken cancellationToken)
    {
        var list = await ReadPackagesAsync(
            "dp.user_id=@userId",
            command => command.Parameters.AddWithValue("userId", driverUserId),
            cancellationToken);
        return ServiceResult<IReadOnlyList<TourPackageLiveDto>>.Ok(list);
    }

    public async Task<ServiceResult<IReadOnlyList<TourPackageLiveDto>>> GetPublicPackagesAsync(
        Guid? destinationId,
        DateTimeOffset? departureFrom,
        int? minimumSeats,
        CancellationToken cancellationToken)
    {
        var predicates = new List<string>
        {
            "tp.status='Active'",
            "tp.departure_at>now()"
        };
        if (destinationId is not null) predicates.Add("tp.destination_id=@destinationId");
        if (departureFrom is not null) predicates.Add("tp.departure_at>=@departureFrom");
        if (minimumSeats is not null) predicates.Add("tp.available_seats>=@minimumSeats");

        var list = await ReadPackagesAsync(
            string.Join(" AND ", predicates),
            command =>
            {
                if (destinationId is not null) command.Parameters.AddWithValue("destinationId", destinationId.Value);
                if (departureFrom is not null) command.Parameters.AddWithValue("departureFrom", departureFrom.Value.ToUniversalTime());
                if (minimumSeats is not null) command.Parameters.AddWithValue("minimumSeats", minimumSeats.Value);
            },
            cancellationToken);
        return ServiceResult<IReadOnlyList<TourPackageLiveDto>>.Ok(list);
    }

    public Task<ServiceResult<TourPackageLiveDto>> GetPublicPackageAsync(
        Guid packageId,
        CancellationToken cancellationToken) =>
        GetPackageByIdAsync(packageId, null, includeNonPublic: false, cancellationToken);

    public async Task<ServiceResult<PackageAvailabilityDto>> GetAvailabilityAsync(
        Guid packageId,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        return await ReadAvailabilityAsync(connection, null, packageId, cancellationToken);
    }

    public async Task<ServiceResult<PackageSeatHoldDto>> AcquireHoldAsync(
        Guid customerUserId,
        Guid packageId,
        AcquirePackageHoldRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.Serializable,
            cancellationToken);

        var package = await LockPackageAsync(connection, transaction, packageId, cancellationToken);
        if (package is null || package.Status != "Active" || package.DepartureAt <= DateTimeOffset.UtcNow)
        {
            return ServiceResult<PackageSeatHoldDto>.Fail(
                StatusCodes.Status409Conflict,
                "package_not_bookable",
                "This package is not currently available for booking.");
        }

        await ExpireHoldsAsync(connection, transaction, packageId, cancellationToken);
        var activeHeld = await GetActiveHeldSeatsAsync(connection, transaction, packageId, cancellationToken);
        var bookable = Math.Max(0, package.AvailableSeats - activeHeld);
        var seats = request.BookingType == BookingType.WholeVehicle
            ? package.TotalSeats
            : request.Seats;

        if (request.BookingType == BookingType.WholeVehicle)
        {
            if (package.AvailableSeats != package.TotalSeats || activeHeld > 0)
            {
                return ServiceResult<PackageSeatHoldDto>.Fail(
                    StatusCodes.Status409Conflict,
                    "whole_vehicle_unavailable",
                    "The whole vehicle is unavailable because seats are already booked or held.");
            }
        }
        else if (seats > bookable)
        {
            return ServiceResult<PackageSeatHoldDto>.Fail(
                StatusCodes.Status409Conflict,
                "insufficient_seats",
                $"Only {bookable} seat(s) are currently available.");
        }

        await using (var cancelOld = new NpgsqlCommand(
            "UPDATE udrive.package_seat_holds SET status='Cancelled', updated_at=now() WHERE tour_package_id=@packageId AND customer_user_id=@userId AND status='Active';",
            connection,
            transaction))
        {
            cancelOld.Parameters.AddWithValue("packageId", packageId);
            cancelOld.Parameters.AddWithValue("userId", customerUserId);
            await cancelOld.ExecuteNonQueryAsync(cancellationToken);
        }

        var amount = request.BookingType == BookingType.WholeVehicle
            ? package.WholeVehiclePrice
            : package.PricePerSeat * seats;
        var holdId = Guid.NewGuid();
        var expiresAt = DateTimeOffset.UtcNow.AddMinutes(10);
        const string insert = """
            INSERT INTO udrive.package_seat_holds
                (id, tour_package_id, customer_user_id, booking_type,
                 seats_held, quoted_amount, status, expires_at,
                 created_at, updated_at)
            VALUES
                (@id, @packageId, @userId, @bookingType,
                 @seats, @amount, 'Active', @expiresAt, now(), now());
            """;
        await using (var command = new NpgsqlCommand(insert, connection, transaction))
        {
            command.Parameters.AddWithValue("id", holdId);
            command.Parameters.AddWithValue("packageId", packageId);
            command.Parameters.AddWithValue("userId", customerUserId);
            command.Parameters.AddWithValue("bookingType", request.BookingType.ToString());
            command.Parameters.AddWithValue("seats", seats);
            command.Parameters.AddWithValue("amount", amount);
            command.Parameters.AddWithValue("expiresAt", expiresAt);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<PackageSeatHoldDto>.Created(new PackageSeatHoldDto(
            holdId,
            packageId,
            request.BookingType.ToString(),
            seats,
            amount,
            expiresAt,
            600),
            "Seats are held for ten minutes while you confirm the booking.");
    }

    public async Task<ServiceResult<BookingDto>> ConfirmHoldAsync(
        Guid customerUserId,
        Guid packageId,
        ConfirmPackageBookingRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.Serializable,
            cancellationToken);

        var package = await LockPackageAsync(connection, transaction, packageId, cancellationToken);
        if (package is null || package.Status != "Active")
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "package_not_bookable",
                "The package is not available.");
        }

        const string holdSql = """
            SELECT customer_user_id, booking_type, seats_held,
                   quoted_amount, status, expires_at
            FROM udrive.package_seat_holds
            WHERE id=@holdId AND tour_package_id=@packageId
            FOR UPDATE;
            """;
        Guid holdOwner;
        string bookingType;
        int seats;
        decimal totalAmount;
        string holdStatus;
        DateTimeOffset holdExpires;
        await using (var command = new NpgsqlCommand(holdSql, connection, transaction))
        {
            command.Parameters.AddWithValue("holdId", request.HoldId);
            command.Parameters.AddWithValue("packageId", packageId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<BookingDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "seat_hold_not_found",
                    "The seat hold was not found.");
            }
            holdOwner = reader.GetGuid(0);
            bookingType = reader.GetString(1);
            seats = reader.GetInt32(2);
            totalAmount = reader.GetDecimal(3);
            holdStatus = reader.GetString(4);
            holdExpires = reader.GetFieldValue<DateTimeOffset>(5);
        }

        if (holdOwner != customerUserId || holdStatus != "Active" || holdExpires <= DateTimeOffset.UtcNow)
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "seat_hold_expired",
                "The seat hold has expired. Please check availability again.");
        }
        if (package.AvailableSeats < seats)
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "insufficient_seats",
                "The requested seats are no longer available.");
        }

        return await CreatePackageBookingAsync(
            connection,
            transaction,
            customerUserId,
            package,
            bookingType,
            seats,
            totalAmount,
            request.AdvanceAmount,
            request.Passengers,
            request.HoldId,
            null,
            cancellationToken);
    }

    public async Task<ServiceResult<PackageOfferDto>> CreatePackageOfferAsync(
        Guid customerUserId,
        Guid packageId,
        CreatePackageOfferRequest request,
        CancellationToken cancellationToken)
    {
        var packageResult = await GetPublicPackageAsync(packageId, cancellationToken);
        if (!packageResult.Success || packageResult.Data is null)
        {
            return ServiceResult<PackageOfferDto>.Fail(
                packageResult.StatusCode,
                packageResult.ErrorCode ?? "package_not_found",
                packageResult.Message ?? "The package was not found.");
        }
        var package = packageResult.Data;
        if (!package.CustomerOffersAllowed)
        {
            return ServiceResult<PackageOfferDto>.Fail(
                StatusCodes.Status409Conflict,
                "offers_not_allowed",
                "This Driver is not accepting custom package offers.");
        }
        var seats = request.BookingType == BookingType.WholeVehicle
            ? package.TotalSeats
            : request.Seats;
        if (seats > package.AvailableSeats)
        {
            return ServiceResult<PackageOfferDto>.Fail(
                StatusCodes.Status409Conflict,
                "insufficient_seats",
                "The requested seats are not available.");
        }

        var id = Guid.NewGuid();
        var expiresAt = DateTimeOffset.UtcNow.AddHours(2);
        const string sql = """
            INSERT INTO udrive.package_offers
                (id, tour_package_id, customer_user_id, booking_type,
                 seats_requested, offered_amount, message, status,
                 expires_at, created_at, updated_at)
            VALUES
                (@id, @packageId, @userId, @bookingType, @seats,
                 @amount, @message, 'Pending', @expiresAt, now(), now())
            ON CONFLICT (tour_package_id, customer_user_id)
                WHERE status IN ('Pending','Countered','Accepted')
            DO UPDATE SET
                booking_type=EXCLUDED.booking_type,
                seats_requested=EXCLUDED.seats_requested,
                offered_amount=EXCLUDED.offered_amount,
                counter_amount=NULL, message=EXCLUDED.message,
                driver_message=NULL, status='Pending',
                expires_at=EXCLUDED.expires_at, updated_at=now()
            RETURNING id;
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("packageId", packageId);
        command.Parameters.AddWithValue("userId", customerUserId);
        command.Parameters.AddWithValue("bookingType", request.BookingType.ToString());
        command.Parameters.AddWithValue("seats", seats);
        command.Parameters.AddWithValue("amount", request.OfferedAmount);
        command.Parameters.Add(new NpgsqlParameter("message", NpgsqlDbType.Varchar) { Value = (object?)request.Message?.Trim() ?? DBNull.Value });
        command.Parameters.AddWithValue("expiresAt", expiresAt);
        id = (Guid)(await command.ExecuteScalarAsync(cancellationToken)
            ?? throw new InvalidOperationException("The package offer could not be saved."));
        return await GetPackageOfferByIdAsync(id, customerUserId, false, cancellationToken);
    }

    public async Task<ServiceResult<IReadOnlyList<PackageOfferDto>>> GetMyPackageOffersAsync(
        Guid userId,
        bool asDriver,
        CancellationToken cancellationToken)
    {
        var predicate = asDriver
            ? "dp.user_id=@userId"
            : "po.customer_user_id=@userId";
        var result = await ReadPackageOffersAsync(predicate, userId, cancellationToken);
        return ServiceResult<IReadOnlyList<PackageOfferDto>>.Ok(result);
    }

    public async Task<ServiceResult<PackageOfferDto>> ReviewPackageOfferAsync(
        Guid driverUserId,
        Guid offerId,
        ReviewPackageOfferRequest request,
        CancellationToken cancellationToken)
    {
        var decision = request.Decision.Trim().ToLowerInvariant();
        var target = decision switch
        {
            "accept" or "accepted" => "Accepted",
            "counter" or "countered" => "Countered",
            "reject" or "rejected" => "Rejected",
            _ => string.Empty
        };
        if (target.Length == 0 || (target == "Countered" && request.CounterAmount is null))
        {
            return ServiceResult<PackageOfferDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_decision",
                "Use Accept, Counter with an amount, or Reject.");
        }

        const string sql = """
            UPDATE udrive.package_offers po
            SET status=@target, counter_amount=@counterAmount,
                driver_message=@message,
                expires_at=CASE WHEN @target IN ('Accepted','Countered')
                                THEN now()+interval '30 minutes'
                                ELSE expires_at END,
                updated_at=now()
            FROM udrive.tour_packages tp
            JOIN udrive.driver_profiles dp ON dp.id=tp.driver_profile_id
            WHERE po.id=@offerId AND po.tour_package_id=tp.id
              AND dp.user_id=@userId
              AND po.status IN ('Pending','Countered','Accepted')
              AND po.expires_at>now()
            RETURNING po.id;
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("target", target);
        command.Parameters.Add(new NpgsqlParameter("counterAmount", NpgsqlDbType.Numeric) { Value = (object?)request.CounterAmount ?? DBNull.Value });
        command.Parameters.Add(new NpgsqlParameter("message", NpgsqlDbType.Varchar) { Value = (object?)request.Message?.Trim() ?? DBNull.Value });
        command.Parameters.AddWithValue("offerId", offerId);
        command.Parameters.AddWithValue("userId", driverUserId);
        if (await command.ExecuteScalarAsync(cancellationToken) is null)
        {
            return ServiceResult<PackageOfferDto>.Fail(
                StatusCodes.Status409Conflict,
                "package_offer_closed",
                "The package offer is unavailable or you do not own the package.");
        }
        return await GetPackageOfferByIdAsync(offerId, driverUserId, true, cancellationToken);
    }

    public async Task<ServiceResult<BookingDto>> ConfirmPackageOfferAsync(
        Guid customerUserId,
        Guid offerId,
        decimal advanceAmount,
        IReadOnlyList<PassengerRequest>? passengers,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.Serializable,
            cancellationToken);

        const string offerSql = """
            SELECT po.tour_package_id, po.customer_user_id, po.booking_type,
                   po.seats_requested, po.offered_amount, po.counter_amount,
                   po.status, po.expires_at
            FROM udrive.package_offers po
            WHERE po.id=@offerId
            FOR UPDATE;
            """;
        Guid packageId;
        Guid ownerId;
        string bookingType;
        int seats;
        decimal offeredAmount;
        decimal? counterAmount;
        string status;
        DateTimeOffset expiresAt;
        await using (var command = new NpgsqlCommand(offerSql, connection, transaction))
        {
            command.Parameters.AddWithValue("offerId", offerId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<BookingDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "package_offer_not_found",
                    "The package offer was not found.");
            }
            packageId = reader.GetGuid(0);
            ownerId = reader.GetGuid(1);
            bookingType = reader.GetString(2);
            seats = reader.GetInt32(3);
            offeredAmount = reader.GetDecimal(4);
            counterAmount = reader.IsDBNull(5) ? null : reader.GetDecimal(5);
            status = reader.GetString(6);
            expiresAt = reader.GetFieldValue<DateTimeOffset>(7);
        }
        if (ownerId != customerUserId || status is not ("Accepted" or "Countered") || expiresAt <= DateTimeOffset.UtcNow)
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "package_offer_not_confirmable",
                "The package offer is not ready for confirmation or has expired.");
        }

        var package = await LockPackageAsync(connection, transaction, packageId, cancellationToken);
        if (package is null || package.Status != "Active")
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "package_not_bookable",
                "The requested package is no longer available.");
        }
        await ExpireHoldsAsync(connection, transaction, packageId, cancellationToken);
        var activeHeld = await GetActiveHeldSeatsAsync(connection, transaction, packageId, cancellationToken);
        var bookable = Math.Max(0, package.AvailableSeats - activeHeld);
        var wholeVehicle = string.Equals(bookingType, "WholeVehicle", StringComparison.OrdinalIgnoreCase);
        if ((wholeVehicle && (package.AvailableSeats != package.TotalSeats || activeHeld > 0)) ||
            (!wholeVehicle && seats > bookable))
        {
            return ServiceResult<BookingDto>.Fail(
                StatusCodes.Status409Conflict,
                "insufficient_seats",
                "The requested package capacity is no longer available.");
        }
        var amount = counterAmount ?? offeredAmount;
        return await CreatePackageBookingAsync(
            connection,
            transaction,
            customerUserId,
            package,
            bookingType,
            seats,
            amount,
            advanceAmount,
            passengers,
            null,
            offerId,
            cancellationToken);
    }

    public async Task<ServiceResult<IReadOnlyList<BookingDto>>> GetDriverPackageBookingsAsync(
        Guid driverUserId,
        Guid? packageId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT b.id, b.booking_reference, b.booking_type, b.status,
                   b.seats_booked, b.total_amount, b.advance_amount,
                   b.remaining_amount, b.pickup_at, b.return_at,
                   tp.pickup_point, d.name_en, 'TourPackage',
                   du.full_name, du.phone_number,
                   concat_ws(' ', v.make, v.model, v.year::text),
                   v.registration_number,
                   b.ride_request_id, b.tour_package_id, pb.id,
                   b.created_at
            FROM udrive.bookings b
            JOIN udrive.tour_packages tp ON tp.id=b.tour_package_id
            JOIN udrive.destinations d ON d.id=tp.destination_id
            JOIN udrive.driver_profiles dp ON dp.id=tp.driver_profile_id
            JOIN udrive.users du ON du.id=dp.user_id
            JOIN udrive.vehicles v ON v.id=tp.vehicle_id
            JOIN udrive.package_bookings pb ON pb.booking_id=b.id
            WHERE dp.user_id=@userId
              AND (@packageId IS NULL OR tp.id=@packageId)
            ORDER BY b.created_at DESC;
            """;
        var result = new List<BookingDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", driverUserId);
        command.Parameters.Add(new NpgsqlParameter("packageId", NpgsqlDbType.Uuid) { Value = (object?)packageId ?? DBNull.Value });
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(ReadBooking(reader));
        }
        return ServiceResult<IReadOnlyList<BookingDto>>.Ok(result);
    }

    public async Task<ServiceResult<PackageWaitlistDto>> JoinWaitlistAsync(
        Guid customerUserId,
        Guid packageId,
        JoinPackageWaitlistRequest request,
        CancellationToken cancellationToken)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.Serializable,
            cancellationToken);

        var package = await LockPackageAsync(connection, transaction, packageId, cancellationToken);
        if (package is null || package.Status != "Active" || package.DepartureAt <= DateTimeOffset.UtcNow)
        {
            return ServiceResult<PackageWaitlistDto>.Fail(
                StatusCodes.Status409Conflict,
                "package_not_available",
                "This package is not accepting a waiting list entry.");
        }

        var requestedSeats = request.BookingType == BookingType.WholeVehicle
            ? package.TotalSeats
            : request.Seats;
        if (requestedSeats > package.TotalSeats)
        {
            return ServiceResult<PackageWaitlistDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_waitlist_seats",
                "Requested seats exceed the vehicle capacity.");
        }

        const string cancelPrevious = """
            UPDATE udrive.package_waitlist
            SET status='Cancelled', updated_at=now()
            WHERE tour_package_id=@packageId
              AND customer_user_id=@userId
              AND status IN ('Waiting','Notified');
            """;
        await using (var command = new NpgsqlCommand(cancelPrevious, connection, transaction))
        {
            command.Parameters.AddWithValue("packageId", packageId);
            command.Parameters.AddWithValue("userId", customerUserId);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        var id = Guid.NewGuid();
        const string insert = """
            INSERT INTO udrive.package_waitlist
                (id, tour_package_id, customer_user_id, booking_type,
                 seats_requested, status, notes, created_at, updated_at)
            VALUES
                (@id, @packageId, @userId, @bookingType,
                 @seats, 'Waiting', @notes, now(), now());
            """;
        await using (var command = new NpgsqlCommand(insert, connection, transaction))
        {
            command.Parameters.AddWithValue("id", id);
            command.Parameters.AddWithValue("packageId", packageId);
            command.Parameters.AddWithValue("userId", customerUserId);
            command.Parameters.AddWithValue("bookingType", request.BookingType.ToString());
            command.Parameters.AddWithValue("seats", requestedSeats);
            command.Parameters.Add(new NpgsqlParameter("notes", NpgsqlDbType.Varchar)
            {
                Value = (object?)request.Notes?.Trim() ?? DBNull.Value
            });
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        var result = await GetWaitlistByIdAsync(connectionString, id, cancellationToken);
        return result is null
            ? ServiceResult<PackageWaitlistDto>.Fail(
                StatusCodes.Status500InternalServerError,
                "waitlist_read_failed",
                "The waiting list entry was created but could not be read.")
            : ServiceResult<PackageWaitlistDto>.Created(
                result,
                "You are on the waiting list. Phase 11 notifications can alert you when seats become available.");
    }

    public async Task<ServiceResult<IReadOnlyList<PackageWaitlistDto>>> GetCustomerWaitlistAsync(
        Guid customerUserId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT w.id, w.tour_package_id, tp.title, d.name_en,
                   tp.departure_at, w.booking_type, w.seats_requested,
                   w.status, u.full_name, w.notes, w.created_at
            FROM udrive.package_waitlist w
            JOIN udrive.tour_packages tp ON tp.id=w.tour_package_id
            JOIN udrive.destinations d ON d.id=tp.destination_id
            JOIN udrive.users u ON u.id=w.customer_user_id
            WHERE w.customer_user_id=@userId
            ORDER BY w.created_at DESC;
            """;
        return ServiceResult<IReadOnlyList<PackageWaitlistDto>>.Ok(
            await ReadWaitlistAsync(sql, command =>
            {
                command.Parameters.AddWithValue("userId", customerUserId);
            }, cancellationToken));
    }

    public async Task<ServiceResult<IReadOnlyList<PackageWaitlistDto>>> GetDriverWaitlistAsync(
        Guid driverUserId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT w.id, w.tour_package_id, tp.title, d.name_en,
                   tp.departure_at, w.booking_type, w.seats_requested,
                   w.status, u.full_name, w.notes, w.created_at
            FROM udrive.package_waitlist w
            JOIN udrive.tour_packages tp ON tp.id=w.tour_package_id
            JOIN udrive.destinations d ON d.id=tp.destination_id
            JOIN udrive.driver_profiles dp ON dp.id=tp.driver_profile_id
            JOIN udrive.users u ON u.id=w.customer_user_id
            WHERE dp.user_id=@userId
              AND w.status IN ('Waiting','Notified')
            ORDER BY tp.departure_at, w.created_at;
            """;
        return ServiceResult<IReadOnlyList<PackageWaitlistDto>>.Ok(
            await ReadWaitlistAsync(sql, command =>
            {
                command.Parameters.AddWithValue("userId", driverUserId);
            }, cancellationToken));
    }

    public async Task<ServiceResult<PassengerManifestDto>> GetPassengerManifestAsync(
        Guid requestingUserId,
        Guid bookingId,
        CancellationToken cancellationToken)
    {
        const string accessSql = """
            SELECT b.booking_reference, b.seats_booked
            FROM udrive.bookings b
            LEFT JOIN udrive.driver_profiles dp ON dp.id=b.driver_profile_id
            LEFT JOIN udrive.tour_packages tp ON tp.id=b.tour_package_id
            LEFT JOIN udrive.driver_profiles package_driver ON package_driver.id=tp.driver_profile_id
            WHERE b.id=@bookingId
              AND (b.customer_user_id=@userId
                   OR dp.user_id=@userId
                   OR package_driver.user_id=@userId);
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        string reference;
        int seatsBooked;
        await using (var command = new NpgsqlCommand(accessSql, connection))
        {
            command.Parameters.AddWithValue("bookingId", bookingId);
            command.Parameters.AddWithValue("userId", requestingUserId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return ServiceResult<PassengerManifestDto>.Fail(
                    StatusCodes.Status404NotFound,
                    "manifest_not_found",
                    "The passenger manifest was not found or is not accessible.");
            }
            reference = reader.GetString(0);
            seatsBooked = reader.GetInt32(1);
        }

        const string passengerSql = """
            SELECT id, full_name, gender, age_group, phone_number_masked,
                   identity_verified, emergency_contact
            FROM udrive.booking_passengers
            WHERE booking_id=@bookingId
            ORDER BY created_at, full_name;
            """;
        var passengers = new List<PassengerManifestItemDto>();
        await using (var command = new NpgsqlCommand(passengerSql, connection))
        {
            command.Parameters.AddWithValue("bookingId", bookingId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                passengers.Add(new PassengerManifestItemDto(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.IsDBNull(2) ? null : reader.GetString(2),
                    reader.GetString(3),
                    reader.IsDBNull(4) ? null : reader.GetString(4),
                    reader.GetBoolean(5),
                    reader.GetBoolean(6)));
            }
        }

        return ServiceResult<PassengerManifestDto>.Ok(new PassengerManifestDto(
            bookingId,
            reference,
            seatsBooked,
            passengers));
    }

    public async Task<ServiceResult<IReadOnlyList<TourPackageLiveDto>>> GetPendingPackagesAsync(
        CancellationToken cancellationToken)
    {
        var list = await ReadPackagesAsync(
            "tp.status='PendingApproval'",
            _ => { },
            cancellationToken);
        return ServiceResult<IReadOnlyList<TourPackageLiveDto>>.Ok(list);
    }

    public async Task<ServiceResult<TourPackageLiveDto>> ReviewPackageAsync(
        Guid adminUserId,
        Guid packageId,
        AdminPackageReviewRequest request,
        CancellationToken cancellationToken)
    {
        var decision = request.Decision.Trim().ToLowerInvariant();
        var target = decision switch
        {
            "approve" or "approved" => "Active",
            "changes" or "changesrequired" => "ChangesRequired",
            "reject" or "rejected" => "Rejected",
            "suspend" or "suspended" => "Suspended",
            _ => string.Empty
        };
        if (target.Length == 0)
        {
            return ServiceResult<TourPackageLiveDto>.Fail(
                StatusCodes.Status400BadRequest,
                "invalid_decision",
                "Use Approve, Changes, Reject or Suspend.");
        }

        const string sql = """
            UPDATE udrive.tour_packages
            SET status=@target, reviewed_at=now(), reviewed_by_user_id=@adminUserId,
                review_notes=@notes, version=version+1, updated_at=now()
            WHERE id=@packageId
              AND ((status='PendingApproval' AND @target IN ('Active','ChangesRequired','Rejected'))
                   OR (@target='Suspended' AND status IN ('Active','Paused')))
            RETURNING id;
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("target", target);
        command.Parameters.AddWithValue("adminUserId", adminUserId);
        command.Parameters.Add(new NpgsqlParameter("notes", NpgsqlDbType.Text) { Value = (object?)request.Notes?.Trim() ?? DBNull.Value });
        command.Parameters.AddWithValue("packageId", packageId);
        if (await command.ExecuteScalarAsync(cancellationToken) is null)
        {
            return ServiceResult<TourPackageLiveDto>.Fail(
                StatusCodes.Status409Conflict,
                "package_review_conflict",
                "The package cannot be reviewed from its current status.");
        }
        return await GetPackageByIdAsync(packageId, null, includeNonPublic: true, cancellationToken);
    }

    private async Task<ServiceResult<BookingDto>> CreatePackageBookingAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid customerUserId,
        LockedPackage package,
        string bookingType,
        int seats,
        decimal totalAmount,
        decimal requestedAdvance,
        IReadOnlyList<PassengerRequest>? passengers,
        Guid? holdId,
        Guid? offerId,
        CancellationToken cancellationToken)
    {
        var advance = Math.Clamp(requestedAdvance, 0, totalAmount);
        var remaining = totalAmount - advance;
        var bookingId = Guid.NewGuid();
        var packageBookingId = Guid.NewGuid();
        var bookingReference = GenerateReference("PKG");
        var tripOtp = RandomNumberGenerator.GetInt32(1000, 10000).ToString();
        var otpHash = SecurityHashing.HashWithSecret(tripOtp, authOptions.OtpHashSecret);

        const string bookingSql = """
            INSERT INTO udrive.bookings
                (id, customer_user_id, driver_profile_id, vehicle_id,
                 ride_request_id, tour_package_id, booking_type, status,
                 seats_booked, total_amount, advance_amount, remaining_amount,
                 pickup_at, return_at, trip_otp_hash, booking_reference,
                 pickup_label, destination_label, party_type,
                 version, created_at, updated_at)
            VALUES
                (@bookingId, @userId, @driverProfileId, @vehicleId,
                 NULL, @packageId, @bookingType, 'Confirmed',
                 @seats, @total, @advance, @remaining,
                 @pickupAt, @returnAt, @otpHash, @reference,
                 @pickupLabel, @destinationLabel, 'TourPackage',
                 0, now(), now());

            INSERT INTO udrive.package_bookings
                (id, tour_package_id, customer_user_id, booking_type,
                 seats_booked, total_amount, status, booking_id,
                 booking_reference, hold_id, advance_amount, remaining_amount,
                 version, created_at, updated_at)
            VALUES
                (@packageBookingId, @packageId, @userId, @bookingType,
                 @seats, @total, 'Confirmed', @bookingId,
                 @reference, @holdId, @advance, @remaining,
                 0, now(), now());

            UPDATE udrive.tour_packages
            SET available_seats=available_seats-@seats,
                version=version+1, updated_at=now()
            WHERE id=@packageId;
            """;
        await using (var command = new NpgsqlCommand(bookingSql, connection, transaction))
        {
            command.Parameters.AddWithValue("bookingId", bookingId);
            command.Parameters.AddWithValue("packageBookingId", packageBookingId);
            command.Parameters.AddWithValue("userId", customerUserId);
            command.Parameters.AddWithValue("driverProfileId", package.DriverProfileId);
            command.Parameters.AddWithValue("vehicleId", package.VehicleId);
            command.Parameters.AddWithValue("packageId", package.Id);
            command.Parameters.AddWithValue("bookingType", bookingType);
            command.Parameters.AddWithValue("seats", seats);
            command.Parameters.AddWithValue("total", totalAmount);
            command.Parameters.AddWithValue("advance", advance);
            command.Parameters.AddWithValue("remaining", remaining);
            command.Parameters.AddWithValue("pickupAt", package.DepartureAt);
            command.Parameters.Add(new NpgsqlParameter("returnAt", NpgsqlDbType.TimestampTz) { Value = (object?)package.ReturnAt ?? DBNull.Value });
            command.Parameters.AddWithValue("otpHash", otpHash);
            command.Parameters.AddWithValue("reference", bookingReference);
            command.Parameters.AddWithValue("pickupLabel", package.PickupPoint);
            command.Parameters.AddWithValue("destinationLabel", package.Destination);
            command.Parameters.Add(new NpgsqlParameter("holdId", NpgsqlDbType.Uuid) { Value = (object?)holdId ?? DBNull.Value });
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        if (holdId is not null)
        {
            await using var updateHold = new NpgsqlCommand(
                "UPDATE udrive.package_seat_holds SET status='Converted', converted_booking_id=@bookingId, updated_at=now() WHERE id=@holdId;",
                connection,
                transaction);
            updateHold.Parameters.AddWithValue("bookingId", bookingId);
            updateHold.Parameters.AddWithValue("holdId", holdId.Value);
            await updateHold.ExecuteNonQueryAsync(cancellationToken);
        }
        if (offerId is not null)
        {
            await using var updateOffer = new NpgsqlCommand(
                "UPDATE udrive.package_offers SET status='Confirmed', confirmed_booking_id=@bookingId, updated_at=now() WHERE id=@offerId;",
                connection,
                transaction);
            updateOffer.Parameters.AddWithValue("bookingId", bookingId);
            updateOffer.Parameters.AddWithValue("offerId", offerId.Value);
            await updateOffer.ExecuteNonQueryAsync(cancellationToken);
        }

        if (passengers is not null)
        {
            foreach (var passenger in passengers.Take(seats))
            {
                await InsertPassengerAsync(connection, transaction, bookingId, passenger, cancellationToken);
            }
        }

        await BookingService.AddHistoryAsync(
            connection,
            transaction,
            "Booking",
            bookingId,
            bookingReference,
            null,
            "Confirmed",
            customerUserId,
            offerId is null
                ? "Customer confirmed package seats from a temporary hold."
                : "Customer confirmed a Driver-negotiated package offer.",
            $"{{\"packageId\":\"{package.Id}\",\"seats\":{seats}}}",
            cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return ServiceResult<BookingDto>.Created(new BookingDto(
            bookingId,
            bookingReference,
            bookingType,
            "Confirmed",
            seats,
            totalAmount,
            advance,
            remaining,
            package.DepartureAt,
            package.ReturnAt,
            package.PickupPoint,
            package.Destination,
            "TourPackage",
            package.DriverName,
            package.DriverPhone,
            package.Vehicle,
            package.RegistrationNumber,
            null,
            package.Id,
            packageBookingId,
            tripOtp,
            DateTimeOffset.UtcNow),
            "Tour package booking confirmed.");
    }

    private static async Task InsertPassengerAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid bookingId,
        PassengerRequest passenger,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO udrive.booking_passengers
                (id, booking_id, full_name, gender, age_group,
                 phone_number_masked, identity_verified,
                 emergency_contact, created_at, updated_at)
            VALUES
                (gen_random_uuid(), @bookingId, @fullName, @gender,
                 @ageGroup, @phone, false, @emergency, now(), now());
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("bookingId", bookingId);
        command.Parameters.AddWithValue("fullName", passenger.FullName.Trim());
        command.Parameters.Add(new NpgsqlParameter("gender", NpgsqlDbType.Varchar) { Value = (object?)passenger.Gender?.Trim() ?? DBNull.Value });
        command.Parameters.AddWithValue("ageGroup", passenger.AgeGroup.Trim());
        command.Parameters.Add(new NpgsqlParameter("phone", NpgsqlDbType.Varchar) { Value = (object?)MaskPhone(passenger.PhoneNumber) ?? DBNull.Value });
        command.Parameters.AddWithValue("emergency", passenger.EmergencyContact);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private async Task<ServiceResult<TourPackageLiveDto>> GetPackageByIdAsync(
        Guid packageId,
        Guid? userId,
        bool includeNonPublic,
        CancellationToken cancellationToken)
    {
        var predicate = includeNonPublic
            ? "tp.id=@packageId AND (@userId IS NULL OR dp.user_id=@userId OR tp.status IN ('Active','Approved'))"
            : "tp.id=@packageId AND tp.status='Active' AND tp.departure_at>now()";
        var list = await ReadPackagesAsync(
            predicate,
            command =>
            {
                command.Parameters.AddWithValue("packageId", packageId);
                if (includeNonPublic) command.Parameters.Add(new NpgsqlParameter("userId", NpgsqlDbType.Uuid) { Value = (object?)userId ?? DBNull.Value });
            },
            cancellationToken);
        return list.Count == 0
            ? ServiceResult<TourPackageLiveDto>.Fail(
                StatusCodes.Status404NotFound,
                "package_not_found",
                "The tour package was not found.")
            : ServiceResult<TourPackageLiveDto>.Ok(list[0]);
    }

    private async Task<List<TourPackageLiveDto>> ReadPackagesAsync(
        string predicate,
        Action<NpgsqlCommand> addParameters,
        CancellationToken cancellationToken)
    {
        var sql = $"""
            SELECT tp.id, tp.driver_profile_id, tp.vehicle_id,
                   tp.destination_id, tp.title, tp.starting_city,
                   tp.pickup_point, d.name_en, tp.departure_at, tp.return_at,
                   tp.total_seats, tp.available_seats,
                   COALESCE((SELECT sum(h.seats_held)::int
                             FROM udrive.package_seat_holds h
                             WHERE h.tour_package_id=tp.id
                               AND h.status='Active' AND h.expires_at>now()), 0),
                   tp.price_per_seat, tp.whole_vehicle_price,
                   tp.family_only, tp.women_only,
                   tp.customer_offers_allowed, tp.status,
                   tp.description, tp.cancellation_policy,
                   tp.passenger_policy, tp.luggage_allowance,
                   tp.route_stops, tp.inclusions, tp.exclusions,
                   tp.itinerary_json::text,
                   u.full_name, dp.average_rating, dp.safety_score,
                   concat_ws(' ', v.make, v.model, v.year::text),
                   v.registration_number, v.mountain_readiness_score,
                   tp.cover_image_url, tp.review_notes, tp.created_at
            FROM udrive.tour_packages tp
            JOIN udrive.driver_profiles dp ON dp.id=tp.driver_profile_id
            JOIN udrive.users u ON u.id=dp.user_id
            JOIN udrive.vehicles v ON v.id=tp.vehicle_id
            JOIN udrive.destinations d ON d.id=tp.destination_id
            WHERE {predicate}
            ORDER BY tp.departure_at, tp.created_at DESC;
            """;

        var result = new List<TourPackageLiveDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        addParameters(command);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(ReadPackage(reader));
        }
        return result;
    }

    private static async Task<PackageWaitlistDto?> GetWaitlistByIdAsync(
        string connectionString,
        Guid id,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT w.id, w.tour_package_id, tp.title, d.name_en,
                   tp.departure_at, w.booking_type, w.seats_requested,
                   w.status, u.full_name, w.notes, w.created_at
            FROM udrive.package_waitlist w
            JOIN udrive.tour_packages tp ON tp.id=w.tour_package_id
            JOIN udrive.destinations d ON d.id=tp.destination_id
            JOIN udrive.users u ON u.id=w.customer_user_id
            WHERE w.id=@id;
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? ReadWaitlist(reader)
            : null;
    }

    private async Task<IReadOnlyList<PackageWaitlistDto>> ReadWaitlistAsync(
        string sql,
        Action<NpgsqlCommand> bind,
        CancellationToken cancellationToken)
    {
        var result = new List<PackageWaitlistDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        bind(command);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(ReadWaitlist(reader));
        }
        return result;
    }

    private static PackageWaitlistDto ReadWaitlist(NpgsqlDataReader reader) => new(
        reader.GetGuid(0),
        reader.GetGuid(1),
        reader.GetString(2),
        reader.GetString(3),
        reader.GetFieldValue<DateTimeOffset>(4),
        reader.GetString(5),
        reader.GetInt32(6),
        reader.GetString(7),
        reader.GetString(8),
        reader.IsDBNull(9) ? null : reader.GetString(9),
        reader.GetFieldValue<DateTimeOffset>(10));

    private static TourPackageLiveDto ReadPackage(NpgsqlDataReader reader)
    {
        var itinerary = ParseItinerary(reader.GetString(26));
        return new TourPackageLiveDto(
            reader.GetGuid(0), reader.GetGuid(1), reader.GetGuid(2), reader.GetGuid(3),
            reader.GetString(4), reader.GetString(5), reader.GetString(6), reader.GetString(7),
            reader.GetFieldValue<DateTimeOffset>(8),
            reader.IsDBNull(9) ? null : reader.GetFieldValue<DateTimeOffset>(9),
            reader.GetInt32(10), reader.GetInt32(11), reader.GetInt32(12),
            reader.GetDecimal(13), reader.GetDecimal(14), reader.GetBoolean(15),
            reader.GetBoolean(16), reader.GetBoolean(17), reader.GetString(18),
            reader.IsDBNull(19) ? null : reader.GetString(19),
            reader.IsDBNull(20) ? null : reader.GetString(20),
            reader.GetString(21), reader.IsDBNull(22) ? null : reader.GetString(22),
            reader.GetFieldValue<string[]>(23), reader.GetFieldValue<string[]>(24),
            reader.GetFieldValue<string[]>(25), itinerary,
            reader.GetString(27), reader.GetDecimal(28), reader.GetInt32(29),
            reader.GetString(30), reader.GetString(31), reader.GetInt32(32),
            reader.IsDBNull(33) ? null : reader.GetString(33),
            reader.IsDBNull(34) ? null : reader.GetString(34),
            reader.GetFieldValue<DateTimeOffset>(35));
    }

    private async Task<ServiceResult<PackageAvailabilityDto>> ReadAvailabilityAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        Guid packageId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT tp.total_seats, tp.available_seats,
                   COALESCE((SELECT sum(h.seats_held)::int
                             FROM udrive.package_seat_holds h
                             WHERE h.tour_package_id=tp.id
                               AND h.status='Active' AND h.expires_at>now()), 0)
            FROM udrive.tour_packages tp
            WHERE tp.id=@packageId AND tp.status='Active' AND tp.departure_at>now();
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("packageId", packageId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return ServiceResult<PackageAvailabilityDto>.Fail(
                StatusCodes.Status404NotFound,
                "package_not_found",
                "The package is not currently bookable.");
        }
        var total = reader.GetInt32(0);
        var available = reader.GetInt32(1);
        var held = reader.GetInt32(2);
        return ServiceResult<PackageAvailabilityDto>.Ok(new PackageAvailabilityDto(
            packageId,
            total,
            available,
            held,
            Math.Max(0, available - held),
            available == total && held == 0,
            DateTimeOffset.UtcNow));
    }

    private async Task<LockedPackage?> LockPackageAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid packageId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT tp.id, tp.driver_profile_id, tp.vehicle_id,
                   tp.total_seats, tp.available_seats,
                   tp.price_per_seat, tp.whole_vehicle_price,
                   tp.status, tp.departure_at, tp.return_at,
                   tp.pickup_point, d.name_en, u.full_name, u.phone_number,
                   concat_ws(' ', v.make, v.model, v.year::text),
                   v.registration_number
            FROM udrive.tour_packages tp
            JOIN udrive.destinations d ON d.id=tp.destination_id
            JOIN udrive.driver_profiles dp ON dp.id=tp.driver_profile_id
            JOIN udrive.users u ON u.id=dp.user_id
            JOIN udrive.vehicles v ON v.id=tp.vehicle_id
            WHERE tp.id=@packageId
            FOR UPDATE OF tp;
            """;
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        command.Parameters.AddWithValue("packageId", packageId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return null;
        return new LockedPackage(
            reader.GetGuid(0), reader.GetGuid(1), reader.GetGuid(2),
            reader.GetInt32(3), reader.GetInt32(4), reader.GetDecimal(5),
            reader.GetDecimal(6), reader.GetString(7),
            reader.GetFieldValue<DateTimeOffset>(8),
            reader.IsDBNull(9) ? null : reader.GetFieldValue<DateTimeOffset>(9),
            reader.GetString(10), reader.GetString(11), reader.GetString(12),
            reader.GetString(13), reader.GetString(14), reader.GetString(15));
    }

    private static async Task ExpireHoldsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid packageId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            "UPDATE udrive.package_seat_holds SET status='Expired', updated_at=now() WHERE tour_package_id=@packageId AND status='Active' AND expires_at<=now();",
            connection,
            transaction);
        command.Parameters.AddWithValue("packageId", packageId);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<int> GetActiveHeldSeatsAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid packageId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            "SELECT COALESCE(sum(seats_held),0)::int FROM udrive.package_seat_holds WHERE tour_package_id=@packageId AND status='Active' AND expires_at>now();",
            connection,
            transaction);
        command.Parameters.AddWithValue("packageId", packageId);
        return Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken));
    }

    private async Task<DriverVehicleContext?> GetDriverVehicleContextAsync(
        Guid userId,
        Guid vehicleId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT dp.id, v.passenger_capacity, v.is_four_by_four,
                   v.mountain_readiness_score
            FROM udrive.driver_profiles dp
            JOIN udrive.vehicles v ON v.driver_profile_id=dp.id
            WHERE dp.user_id=@userId AND dp.verification_status='Approved'
              AND v.id=@vehicleId AND v.status='Verified';
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);
        command.Parameters.AddWithValue("vehicleId", vehicleId);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken)) return null;
        return new DriverVehicleContext(
            reader.GetGuid(0), reader.GetInt32(1), reader.GetBoolean(2), reader.GetInt32(3));
    }

    private async Task<ServiceResult<PackageOfferDto>> GetPackageOfferByIdAsync(
        Guid offerId,
        Guid userId,
        bool asDriver,
        CancellationToken cancellationToken)
    {
        var predicate = asDriver
            ? "po.id=@offerId AND dp.user_id=@userId"
            : "po.id=@offerId AND po.customer_user_id=@userId";
        var list = await ReadPackageOffersAsync(predicate, userId, cancellationToken, offerId);
        return list.Count == 0
            ? ServiceResult<PackageOfferDto>.Fail(
                StatusCodes.Status404NotFound,
                "package_offer_not_found",
                "The package offer was not found.")
            : ServiceResult<PackageOfferDto>.Ok(list[0]);
    }

    private async Task<List<PackageOfferDto>> ReadPackageOffersAsync(
        string predicate,
        Guid userId,
        CancellationToken cancellationToken,
        Guid? offerId = null)
    {
        var sql = $"""
            SELECT po.id, po.tour_package_id, tp.title,
                   po.customer_user_id, cu.full_name, po.booking_type,
                   po.seats_requested, po.offered_amount, po.counter_amount,
                   po.message, po.driver_message, po.status,
                   po.expires_at, po.created_at
            FROM udrive.package_offers po
            JOIN udrive.tour_packages tp ON tp.id=po.tour_package_id
            JOIN udrive.driver_profiles dp ON dp.id=tp.driver_profile_id
            JOIN udrive.users cu ON cu.id=po.customer_user_id
            WHERE {predicate}
            ORDER BY po.created_at DESC;
            """;
        var result = new List<PackageOfferDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("userId", userId);
        if (offerId is not null) command.Parameters.AddWithValue("offerId", offerId.Value);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        while (await reader.ReadAsync(cancellationToken))
        {
            result.Add(new PackageOfferDto(
                reader.GetGuid(0), reader.GetGuid(1), reader.GetString(2),
                reader.GetGuid(3), reader.GetString(4), reader.GetString(5),
                reader.GetInt32(6), reader.GetDecimal(7),
                reader.IsDBNull(8) ? null : reader.GetDecimal(8),
                reader.IsDBNull(9) ? null : reader.GetString(9),
                reader.IsDBNull(10) ? null : reader.GetString(10),
                reader.GetString(11), reader.GetFieldValue<DateTimeOffset>(12),
                reader.GetFieldValue<DateTimeOffset>(13)));
        }
        return result;
    }

    private static BookingDto ReadBooking(NpgsqlDataReader reader) => new(
        reader.GetGuid(0), reader.GetString(1), reader.GetString(2), reader.GetString(3),
        reader.GetInt32(4), reader.GetDecimal(5), reader.GetDecimal(6),
        reader.GetDecimal(7), reader.GetFieldValue<DateTimeOffset>(8),
        reader.IsDBNull(9) ? null : reader.GetFieldValue<DateTimeOffset>(9),
        reader.GetString(10), reader.GetString(11), reader.GetString(12),
        reader.IsDBNull(13) ? null : reader.GetString(13),
        reader.IsDBNull(14) ? null : reader.GetString(14),
        reader.IsDBNull(15) ? null : reader.GetString(15),
        reader.IsDBNull(16) ? null : reader.GetString(16),
        reader.IsDBNull(17) ? null : reader.GetGuid(17),
        reader.IsDBNull(18) ? null : reader.GetGuid(18),
        reader.IsDBNull(19) ? null : reader.GetGuid(19),
        null, reader.GetFieldValue<DateTimeOffset>(20));

    private static void AddPackageParameters(
        NpgsqlCommand command,
        CreateTourPackageRequest request,
        string[] routeStops,
        string[] inclusions,
        string[] exclusions,
        string itineraryJson)
    {
        command.Parameters.AddWithValue("vehicleId", request.VehicleId);
        command.Parameters.AddWithValue("destinationId", request.DestinationId);
        command.Parameters.AddWithValue("title", request.Title.Trim());
        command.Parameters.AddWithValue("startingCity", request.StartingCity.Trim());
        command.Parameters.AddWithValue("pickupPoint", request.PickupPoint.Trim());
        command.Parameters.AddWithValue("departureAt", request.DepartureAt.ToUniversalTime());
        command.Parameters.Add(new NpgsqlParameter("returnAt", NpgsqlDbType.TimestampTz) { Value = (object?)request.ReturnAt?.ToUniversalTime() ?? DBNull.Value });
        command.Parameters.AddWithValue("totalSeats", request.TotalSeats);
        command.Parameters.AddWithValue("pricePerSeat", request.PricePerSeat);
        command.Parameters.AddWithValue("wholeVehiclePrice", request.WholeVehiclePrice);
        command.Parameters.AddWithValue("familyOnly", request.FamilyOnly);
        command.Parameters.AddWithValue("womenOnly", request.WomenOnly);
        command.Parameters.AddWithValue("offersAllowed", request.CustomerOffersAllowed);
        command.Parameters.AddWithValue("inclusions", inclusions);
        command.Parameters.AddWithValue("exclusions", exclusions);
        command.Parameters.AddWithValue("itineraryJson", itineraryJson);
        command.Parameters.Add(new NpgsqlParameter("coverImageUrl", NpgsqlDbType.Text) { Value = (object?)request.CoverImageUrl?.Trim() ?? DBNull.Value });
        command.Parameters.Add(new NpgsqlParameter("description", NpgsqlDbType.Text) { Value = (object?)request.Description?.Trim() ?? DBNull.Value });
        command.Parameters.Add(new NpgsqlParameter("cancellationPolicy", NpgsqlDbType.Text) { Value = (object?)request.CancellationPolicy?.Trim() ?? DBNull.Value });
        command.Parameters.AddWithValue("passengerPolicy", request.PassengerPolicy?.Trim() ?? "Verified passengers only");
        command.Parameters.Add(new NpgsqlParameter("luggageAllowance", NpgsqlDbType.Varchar) { Value = (object?)request.LuggageAllowance?.Trim() ?? DBNull.Value });
        command.Parameters.AddWithValue("routeStops", routeStops);
        command.Parameters.AddWithValue("fuelIncluded", request.FuelIncluded);
        command.Parameters.AddWithValue("tollIncluded", request.TollIncluded);
        command.Parameters.AddWithValue("hotelIncluded", request.HotelIncluded);
        command.Parameters.AddWithValue("mealsIncluded", request.MealsIncluded);
        command.Parameters.AddWithValue("guideIncluded", request.GuideIncluded);
        command.Parameters.AddWithValue("jeepTransferIncluded", request.JeepTransferIncluded);
        command.Parameters.AddWithValue("driverAccommodationIncluded", request.DriverAccommodationIncluded);
    }

    private static (string Code, string Message)? ValidatePackage(
        CreateTourPackageRequest request,
        DriverVehicleContext vehicle)
    {
        if (request.DepartureAt <= DateTimeOffset.UtcNow.AddHours(6))
            return ("departure_too_soon", "Package departure must be at least six hours in the future.");
        if (request.ReturnAt is not null && request.ReturnAt <= request.DepartureAt)
            return ("invalid_return_time", "Return time must be after departure time.");
        if (request.TotalSeats > vehicle.PassengerCapacity)
            return ("vehicle_capacity_exceeded", $"This vehicle supports up to {vehicle.PassengerCapacity} passengers.");
        if (request.FamilyOnly && request.WomenOnly)
            return ("conflicting_package_rules", "A package cannot be both family-only and women-only.");
        if (vehicle.MountainReadinessScore < 60)
            return ("vehicle_not_tour_ready", "The selected vehicle does not meet the minimum tourism readiness score.");
        return null;
    }

    private static string[] SanitizeArray(
        string[]? values,
        int maxItems,
        int maxLength) =>
        (values ?? [])
            .Select(value => value.Trim())
            .Where(value => value.Length > 0)
            .Select(value => value[..Math.Min(value.Length, maxLength)])
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(maxItems)
            .ToArray();

    private static IReadOnlyList<string> ParseItinerary(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Array) return [];
            var result = new List<string>();
            foreach (var item in document.RootElement.EnumerateArray())
            {
                if (item.ValueKind == JsonValueKind.String)
                {
                    result.Add(item.GetString() ?? string.Empty);
                }
                else if (item.ValueKind == JsonValueKind.Object)
                {
                    var day = item.TryGetProperty("day", out var dayNode) ? $"Day {dayNode}" : "Day";
                    var route = item.TryGetProperty("route", out var routeNode) ? routeNode.GetString() : item.ToString();
                    result.Add($"{day}: {route}");
                }
            }
            return result;
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private static string? MaskPhone(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var digits = new string(value.Where(char.IsDigit).ToArray());
        return digits.Length < 4 ? "****" : $"*******{digits[^4..]}";
    }

    private static string GenerateReference(string prefix) =>
        $"{prefix}-{DateTimeOffset.UtcNow:yyMMdd}-{Convert.ToHexString(RandomNumberGenerator.GetBytes(3))}";

    private sealed record DriverVehicleContext(
        Guid DriverProfileId,
        int PassengerCapacity,
        bool IsFourByFour,
        int MountainReadinessScore);

    private sealed record LockedPackage(
        Guid Id,
        Guid DriverProfileId,
        Guid VehicleId,
        int TotalSeats,
        int AvailableSeats,
        decimal PricePerSeat,
        decimal WholeVehiclePrice,
        string Status,
        DateTimeOffset DepartureAt,
        DateTimeOffset? ReturnAt,
        string PickupPoint,
        string Destination,
        string DriverName,
        string DriverPhone,
        string Vehicle,
        string RegistrationNumber);
}
