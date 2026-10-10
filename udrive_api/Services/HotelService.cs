using System.Text.Json;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

public sealed class HotelService(string connectionString)
{
    /// <param name="callerUserId">
    /// Who is searching, or null when nobody is signed in.
    /// </param>
    /// <remarks>
    /// The caller's identity is needed for one reason only: the self-test
    /// harness creates and approves a hotel during a run, and that hotel must
    /// be visible to the self-test customer (so the run can assert the search
    /// finds it) and to nobody else. Search is otherwise anonymous and stays
    /// that way — nothing else in this method reads the parameter.
    /// </remarks>
    public async Task<ServiceResult<object>> SearchAsync(HotelSearchRequest request, Guid? callerUserId, CancellationToken ct)
    {
        var page = Math.Max(1, request.Page); var size = Math.Clamp(request.PageSize, 1, 30); var offset=(page-1)*size;
        await using var c=new NpgsqlConnection(connectionString); await c.OpenAsync(ct);
        await using var cmd=c.CreateCommand();
        cmd.CommandText="""
        SELECT h.id,h.name,h.address,h.city,h.district,h.latitude,h.longitude,
               h.contact_phone,h.rating,h.main_image_url,h.amenities,h.transport_available,
               COALESCE((
                   SELECT MIN(COALESCE(i.rate,r.base_rate))
                   FROM udrive.hotel_rooms r
                   LEFT JOIN udrive.hotel_room_inventory i
                     ON i.room_id=r.id AND i.inventory_date=@check_in
                   WHERE r.hotel_id=h.id AND r.is_active
               ),0) AS starting_rate,
               COALESCE((
                   SELECT SUM(COALESCE(i.available_rooms,r.total_rooms))
                   FROM udrive.hotel_rooms r
                   LEFT JOIN udrive.hotel_room_inventory i
                     ON i.room_id=r.id AND i.inventory_date=@check_in
                   WHERE r.hotel_id=h.id AND r.is_active
               ),0) AS available_rooms,
               COALESCE((SELECT o.email LIKE 'demo.%@udrive.local'
                         FROM udrive.users o WHERE o.id=h.owner_user_id), false) AS is_demo
        FROM udrive.hotels h
        WHERE lower(h.approval_status)='approved'
          AND h.is_active=true
          AND NOT EXISTS (SELECT 1 FROM udrive.listing_holds lh WHERE lh.kind='hotels' AND lh.entity_id=h.id AND lh.released_at IS NULL) AND COALESCE((SELECT hw.balance FROM udrive.hotel_wallets hw WHERE hw.owner_user_id=h.owner_user_id),0) >= COALESCE((SELECT (ss.value_json #>> '{}')::numeric FROM udrive.system_settings ss WHERE ss.key='hotel.wallet.minimum_balance'),0)
          AND (
                @query=''
                OR h.name ILIKE '%'||@query||'%'
                OR h.city ILIKE '%'||@query||'%'
                OR h.district ILIKE '%'||@query||'%'
                OR h.address ILIKE '%'||@query||'%'
              )
          AND (@city='' OR h.city ILIKE '%'||@city||'%' OR h.district ILIKE '%'||@city||'%')
          -- The self-test harness creates and approves a hotel during a run.
          -- It is visible to the self-test customer, so the run can assert this
          -- very search finds it, and to nobody else.
          AND (NOT EXISTS (SELECT 1 FROM udrive.users selftest_owner
                            WHERE selftest_owner.id=h.owner_user_id
                              AND selftest_owner.email LIKE 'selftest.%@udrive.local')
               OR EXISTS (SELECT 1 FROM udrive.users selftest_caller
                           WHERE selftest_caller.id=@caller_user_id
                             AND selftest_caller.email LIKE 'selftest.%@udrive.local'))
        ORDER BY h.rating DESC,h.created_at DESC
        LIMIT @limit OFFSET @offset;
        """;
        cmd.Parameters.AddWithValue("query",request.Query?.Trim()??"");
        cmd.Parameters.AddWithValue("city",request.City?.Trim()??"");
        cmd.Parameters.AddWithValue("check_in",request.CheckIn??DateOnly.FromDateTime(DateTime.UtcNow.Date));
        // Guid.Empty rather than NULL for an anonymous search: no users.id can
        // ever equal it, so the guard's EXISTS is false either way, and
        // AddWithValue does not have to infer a type for DBNull.
        cmd.Parameters.AddWithValue("caller_user_id",callerUserId??Guid.Empty);
        cmd.Parameters.AddWithValue("limit",size);
        cmd.Parameters.AddWithValue("offset",offset);
        var list=new List<object>(); await using var r=await cmd.ExecuteReaderAsync(ct); while(await r.ReadAsync(ct)) list.Add(MapHotel(r));
        return ServiceResult<object>.Ok(new {items=list,page,pageSize=size,hasMore=list.Count==size});
    }

    public async Task<ServiceResult<object>> GetAsync(Guid id, DateOnly? checkIn, DateOnly? checkOut, CancellationToken ct)
    {
        await using var c=new NpgsqlConnection(connectionString); await c.OpenAsync(ct);
        object? hotel=null; await using(var cmd=c.CreateCommand()) {cmd.CommandText="""SELECT h.id,h.name,h.address,h.city,h.district,h.latitude,h.longitude,h.contact_phone,h.rating,h.main_image_url,h.amenities,h.transport_available,h.description,0::numeric,0::bigint,COALESCE((SELECT o.email LIKE 'demo.%@udrive.local' FROM udrive.users o WHERE o.id=h.owner_user_id),false) AS is_demo FROM udrive.hotels h WHERE h.id=@id AND lower(h.approval_status)='approved' AND h.is_active AND NOT EXISTS (SELECT 1 FROM udrive.listing_holds lh WHERE lh.kind='hotels' AND lh.entity_id=h.id AND lh.released_at IS NULL) AND COALESCE((SELECT hw.balance FROM udrive.hotel_wallets hw WHERE hw.owner_user_id=h.owner_user_id),0) >= COALESCE((SELECT (ss.value_json #>> '{}')::numeric FROM udrive.system_settings ss WHERE ss.key='hotel.wallet.minimum_balance'),0)""";cmd.Parameters.AddWithValue("id",id);await using var r=await cmd.ExecuteReaderAsync(ct);if(await r.ReadAsync(ct))hotel=MapHotel(r,true);} if(hotel is null)return ServiceResult<object>.Fail(404,"hotel_not_found","Hotel not found.");
        var rooms=new List<object>(); await using(var cmd=c.CreateCommand()){cmd.CommandText="""SELECT r.id,r.room_type,r.description,r.capacity,r.total_rooms,r.base_rate,r.image_url,r.amenities,COALESCE(i.available_rooms,r.total_rooms),COALESCE(i.rate,r.base_rate) FROM udrive.hotel_rooms r LEFT JOIN udrive.hotel_room_inventory i ON i.room_id=r.id AND i.inventory_date=@d WHERE r.hotel_id=@id AND r.is_active ORDER BY r.base_rate""";cmd.Parameters.AddWithValue("id",id);cmd.Parameters.AddWithValue("d",(object?)checkIn??DateOnly.FromDateTime(DateTime.UtcNow));await using var rr=await cmd.ExecuteReaderAsync(ct);while(await rr.ReadAsync(ct))rooms.Add(new{id=rr.GetGuid(0),roomType=rr.GetString(1),description=rr.GetString(2),capacity=rr.GetInt32(3),totalRooms=rr.GetInt32(4),baseRate=rr.GetDecimal(5),imageUrl=rr.GetString(6),amenities=JsonSerializer.Deserialize<string[]>(rr.GetFieldValue<string>(7))??[],availableRooms=rr.GetInt32(8),rate=rr.GetDecimal(9)});}
        return ServiceResult<object>.Ok(new {hotel,rooms});
    }

    public async Task<ServiceResult<object>> MyHotelsAsync(Guid ownerId,CancellationToken ct){await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=c.CreateCommand();cmd.CommandText="""SELECT id,name,address,city,district,latitude,longitude,contact_phone,rating,main_image_url,amenities,transport_available,approval_status,rejection_reason,is_active,created_at FROM udrive.hotels WHERE owner_user_id=@u ORDER BY created_at DESC""";cmd.Parameters.AddWithValue("u",ownerId);var list=new List<object>();await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))list.Add(new{id=r.GetGuid(0),name=r.GetString(1),address=r.GetString(2),city=r.GetString(3),district=r.GetString(4),latitude=r.GetDouble(5),longitude=r.GetDouble(6),contactPhone=r.GetString(7),rating=r.GetDecimal(8),mainImageUrl=r.GetString(9),amenities=JsonSerializer.Deserialize<string[]>(r.GetFieldValue<string>(10))??[],transportAvailable=r.GetBoolean(11),approvalStatus=r.GetString(12),rejectionReason=r.IsDBNull(13)?null:r.GetString(13),isActive=r.GetBoolean(14),createdAt=r.GetDateTime(15)});return ServiceResult<object>.Ok(list);}

    public async Task<ServiceResult<object>> CreateAsync(Guid ownerId,CreateHotelRequest x,CancellationToken ct)
    {
        if(string.IsNullOrWhiteSpace(x.Name)||string.IsNullOrWhiteSpace(x.Address)||string.IsNullOrWhiteSpace(x.City))return ServiceResult<object>.Fail(400,"validation","Hotel name, address and city are required.");
        if(x.Latitude is < -90 or > 90 || x.Longitude is < -180 or > 180)return ServiceResult<object>.Fail(400,"coordinates","Enter a valid hotel map location.");
        await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var tx=await c.BeginTransactionAsync(ct);
        try
        {
            await using(var owner=c.CreateCommand())
            {
                owner.Transaction=tx;owner.CommandText="""
                    INSERT INTO udrive.hotel_owner_profiles(user_id,business_name,phone,status,created_at,updated_at)
                    VALUES(@u,@business,@phone,'Active',now(),now())
                    ON CONFLICT(user_id) DO UPDATE SET business_name=EXCLUDED.business_name,phone=EXCLUDED.phone,status='Active',updated_at=now();
                    INSERT INTO udrive.user_roles(user_id,role,created_at) VALUES(@u,'HotelOwner',now()) ON CONFLICT(user_id,role) DO NOTHING;
                    """;
                owner.Parameters.AddWithValue("u",ownerId);owner.Parameters.AddWithValue("business",x.Name.Trim());owner.Parameters.AddWithValue("phone",x.ContactPhone??"");await owner.ExecuteNonQueryAsync(ct);
            }
            await using var cmd=c.CreateCommand();cmd.Transaction=tx;cmd.CommandText="""INSERT INTO udrive.hotels(owner_user_id,name,description,address,city,district,latitude,longitude,contact_phone,main_image_url,amenities,transport_available) VALUES(@u,@n,@d,@a,@c,@di,@lat,@lng,@p,@img,@am::jsonb,@t) RETURNING id""";cmd.Parameters.AddWithValue("u",ownerId);cmd.Parameters.AddWithValue("n",x.Name.Trim());cmd.Parameters.AddWithValue("d",x.Description??"");cmd.Parameters.AddWithValue("a",x.Address.Trim());cmd.Parameters.AddWithValue("c",x.City.Trim());cmd.Parameters.AddWithValue("di",x.District??"");cmd.Parameters.AddWithValue("lat",x.Latitude);cmd.Parameters.AddWithValue("lng",x.Longitude);cmd.Parameters.AddWithValue("p",x.ContactPhone??"");cmd.Parameters.AddWithValue("img",x.MainImageUrl??"");cmd.Parameters.AddWithValue("am",JsonSerializer.Serialize(x.Amenities??[]));cmd.Parameters.AddWithValue("t",x.TransportAvailable);var id=(Guid)(await cmd.ExecuteScalarAsync(ct))!;await tx.CommitAsync(ct);return ServiceResult<object>.Ok(new{id,approvalStatus="Pending"});
        }
        catch{await tx.RollbackAsync(CancellationToken.None);throw;}
    }

    public async Task<ServiceResult<object>> AddRoomAsync(Guid ownerId,Guid hotelId,CreateHotelRoomRequest x,CancellationToken ct){await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=c.CreateCommand();cmd.CommandText="""INSERT INTO udrive.hotel_rooms(hotel_id,room_type,description,capacity,total_rooms,base_rate,image_url,amenities) SELECT @h,@rt,@d,@cap,@total,@rate,@img,@am::jsonb FROM udrive.hotels WHERE id=@h AND owner_user_id=@u RETURNING id""";cmd.Parameters.AddWithValue("h",hotelId);cmd.Parameters.AddWithValue("u",ownerId);cmd.Parameters.AddWithValue("rt",x.RoomType.Trim());cmd.Parameters.AddWithValue("d",x.Description??"");cmd.Parameters.AddWithValue("cap",x.Capacity);cmd.Parameters.AddWithValue("total",x.TotalRooms);cmd.Parameters.AddWithValue("rate",x.BaseRate);cmd.Parameters.AddWithValue("img",x.ImageUrl??"");cmd.Parameters.AddWithValue("am",JsonSerializer.Serialize(x.Amenities??[]));var o=await cmd.ExecuteScalarAsync(ct);return o is Guid id?ServiceResult<object>.Ok(new{id}):ServiceResult<object>.Fail(404,"hotel_not_found","Hotel not found.");}

    /// <remarks>
    /// The availability lock is <c>FOR UPDATE OF r</c>, not a bare
    /// <c>FOR UPDATE</c>. The query LEFT JOINs hotel_room_inventory, and
    /// PostgreSQL refuses to lock the nullable side of an outer join:
    /// "FOR UPDATE cannot be applied to the nullable side of an outer join"
    /// (SQLSTATE 0A000). A bare FOR UPDATE therefore threw on every call, so
    /// no room could ever be booked — the endpoint answered 500 whether or not
    /// the room existed, and the generic "temporarily unavailable" body hid the
    /// reason. Naming the room table locks the row that matters (the one whose
    /// available_rooms count is about to be read and acted on) and leaves the
    /// optional inventory row unlocked, which is all this transaction needs.
    /// The same shape is already used by BookingService's booking lock.
    /// </remarks>
    public async Task<ServiceResult<HotelBookingCreatedDto>> BookAsync(Guid userId,Guid hotelId,CreateHotelBookingRequest x,CancellationToken ct)
    {
        if(x.CheckOut<=x.CheckIn)return ServiceResult<HotelBookingCreatedDto>.Fail(400,"dates","Check-out must be after check-in.");
        if(x.Guests<1||x.Rooms<1)return ServiceResult<HotelBookingCreatedDto>.Fail(400,"guests","At least one guest and one room are needed.");
        if(await DemoListing.IsDemoHotelAsync(connectionString,hotelId,ct))return ServiceResult<HotelBookingCreatedDto>.Fail(409,DemoListing.ErrorCode,DemoListing.Message);

        // How the customer is getting there. Anything unknown is the customer's
        // own car, which is what the booking assumed before this was asked.
        var arrivalMode=(x.ArrivalMode??"").Trim() switch
        {
            "UDriveRide"=>"UDriveRide",
            "HotelTransport"=>"HotelTransport",
            _=>x.IncludeTransport?"HotelTransport":"OwnCar"
        };
        TimeOnly? arrivalTime=null;
        if(!string.IsNullOrWhiteSpace(x.ArrivalTime))
        {
            if(!TimeOnly.TryParseExact(x.ArrivalTime.Trim(),"HH:mm",System.Globalization.CultureInfo.InvariantCulture,System.Globalization.DateTimeStyles.None,out var parsed))
                return ServiceResult<HotelBookingCreatedDto>.Fail(400,"arrival_time","Arrival time must look like 14:00.");
            arrivalTime=parsed;
        }
        var carNumber=Clip(x.CarNumber,20);
        var guestName=Clip(x.GuestName,120);
        var guestPhone=Clip(x.GuestPhone,24);
        var includeTransport=x.IncludeTransport||arrivalMode=="HotelTransport";

        await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var tx=await c.BeginTransactionAsync(ct);
        try
        {
            decimal rate;int available;
            await using(var q=c.CreateCommand())
            {
                q.Transaction=tx;
                q.CommandText="""SELECT COALESCE(i.rate,r.base_rate),COALESCE(i.available_rooms,r.total_rooms) FROM udrive.hotel_rooms r JOIN udrive.hotels h ON h.id=r.hotel_id LEFT JOIN udrive.hotel_room_inventory i ON i.room_id=r.id AND i.inventory_date=@d WHERE r.id=@r AND h.id=@h AND lower(h.approval_status)='approved' AND h.is_active AND NOT EXISTS (SELECT 1 FROM udrive.listing_holds lh WHERE lh.kind='hotels' AND lh.entity_id=h.id AND lh.released_at IS NULL) AND COALESCE((SELECT hw.balance FROM udrive.hotel_wallets hw WHERE hw.owner_user_id=h.owner_user_id),0) >= COALESCE((SELECT (ss.value_json #>> '{}')::numeric FROM udrive.system_settings ss WHERE ss.key='hotel.wallet.minimum_balance'),0) AND r.is_active FOR UPDATE OF r""";
                q.Parameters.AddWithValue("d",x.CheckIn);q.Parameters.AddWithValue("r",x.RoomId);q.Parameters.AddWithValue("h",hotelId);
                await using var rr=await q.ExecuteReaderAsync(ct);
                if(!await rr.ReadAsync(ct))return ServiceResult<HotelBookingCreatedDto>.Fail(404,"room_not_found","Room is unavailable.");
                rate=rr.GetDecimal(0);available=rr.GetInt32(1);
            }
            if(available<x.Rooms)return ServiceResult<HotelBookingCreatedDto>.Fail(409,"rooms_unavailable","Not enough rooms are available.");

            // The name and number the hotel is told. What the customer typed on
            // the confirm screen, or their account's own when they left it.
            if(guestName is null||guestPhone is null)
            {
                await using var u=c.CreateCommand();u.Transaction=tx;
                u.CommandText="SELECT full_name,phone_number FROM udrive.users WHERE id=@u";
                u.Parameters.AddWithValue("u",userId);
                await using var ur=await u.ExecuteReaderAsync(ct);
                if(await ur.ReadAsync(ct)){guestName??=Clip(ur.GetString(0),120);guestPhone??=Clip(ur.GetString(1),24);}
            }

            var nights=x.CheckOut.DayNumber-x.CheckIn.DayNumber;var amount=rate*x.Rooms*nights;Guid bookingId;string reference;
            await using(var ins=c.CreateCommand())
            {
                ins.Transaction=tx;
                ins.CommandText="""
                    INSERT INTO udrive.hotel_bookings(customer_user_id,hotel_id,room_id,check_in,check_out,guests,rooms,amount,include_transport,
                                                      arrival_time,arrival_mode,car_number,guest_name,guest_phone)
                    VALUES(@u,@h,@r,@ci,@co,@g,@rooms,@a,@t,@at,@am,@car,@gn,@gp)
                    RETURNING id
                    """;
                ins.Parameters.AddWithValue("u",userId);ins.Parameters.AddWithValue("h",hotelId);ins.Parameters.AddWithValue("r",x.RoomId);ins.Parameters.AddWithValue("ci",x.CheckIn);ins.Parameters.AddWithValue("co",x.CheckOut);ins.Parameters.AddWithValue("g",x.Guests);ins.Parameters.AddWithValue("rooms",x.Rooms);ins.Parameters.AddWithValue("a",amount);ins.Parameters.AddWithValue("t",includeTransport);
                ins.Parameters.Add(new NpgsqlParameter("at",NpgsqlDbType.Time){Value=arrivalTime.HasValue?(object)arrivalTime.Value:DBNull.Value});
                ins.Parameters.AddWithValue("am",arrivalMode);
                ins.Parameters.Add(new NpgsqlParameter("car",NpgsqlDbType.Text){Value=(object?)carNumber??DBNull.Value});
                ins.Parameters.Add(new NpgsqlParameter("gn",NpgsqlDbType.Text){Value=(object?)guestName??DBNull.Value});
                ins.Parameters.Add(new NpgsqlParameter("gp",NpgsqlDbType.Text){Value=(object?)guestPhone??DBNull.Value});
                bookingId=(Guid)(await ins.ExecuteScalarAsync(ct))!;
            }
            // Read out to the guest and the hotel, so short and unambiguous: no
            // 0/O or 1/I confusion is possible in hex.
            reference="UDH-"+bookingId.ToString("N")[..8].ToUpperInvariant();
            await using(var upd=c.CreateCommand())
            {
                upd.Transaction=tx;upd.CommandText="UPDATE udrive.hotel_bookings SET booking_reference=@ref WHERE id=@id";
                upd.Parameters.AddWithValue("ref",reference);upd.Parameters.AddWithValue("id",bookingId);
                await upd.ExecuteNonQueryAsync(ct);
            }
            // The platform's commission, from the hotel owner's prepaid wallet.
            await HotelWalletService.ChargeBookingAsync(c,tx,bookingId,ct);
            await tx.CommitAsync(ct);
            return ServiceResult<HotelBookingCreatedDto>.Ok(new HotelBookingCreatedDto(bookingId,reference,amount,includeTransport,new{hotelId,latitude=(double?)null,longitude=(double?)null},nights,false));
        }
        catch{await tx.RollbackAsync(CancellationToken.None);throw;}
    }

    /// <summary>
    /// The WhatsApp message telling the hotel who is coming, or null when there
    /// is nobody to send it to.
    /// </summary>
    /// <remarks>
    /// The hotel's own contact number first, then the owner's account number.
    /// Self-test hotels are skipped: their numbers are not real and the run
    /// must not message anyone.
    /// </remarks>
    public async Task<HotelOwnerNotice?> OwnerNoticeAsync(Guid bookingId,CancellationToken ct)
    {
        await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=c.CreateCommand();
        cmd.CommandText="""
            SELECT h.name,COALESCE(NULLIF(trim(h.contact_phone),''),o.phone_number),o.email,
                   b.booking_reference,b.guest_name,b.guest_phone,b.guests,b.rooms,r.room_type,
                   b.check_in,b.check_out,b.arrival_time,b.arrival_mode,b.car_number,b.amount
            FROM udrive.hotel_bookings b
            JOIN udrive.hotels h ON h.id=b.hotel_id
            JOIN udrive.users o ON o.id=h.owner_user_id
            JOIN udrive.hotel_rooms r ON r.id=b.room_id
            WHERE b.id=@id
            """;
        cmd.Parameters.AddWithValue("id",bookingId);
        await using var r=await cmd.ExecuteReaderAsync(ct);
        if(!await r.ReadAsync(ct))return null;
        var to=r.IsDBNull(1)?"":r.GetString(1);
        var ownerEmail=r.IsDBNull(2)?"":r.GetString(2);
        if(string.IsNullOrWhiteSpace(to)||ownerEmail.StartsWith("selftest.",StringComparison.OrdinalIgnoreCase))return null;

        var checkIn=r.GetFieldValue<DateOnly>(9);var checkOut=r.GetFieldValue<DateOnly>(10);
        var nights=checkOut.DayNumber-checkIn.DayNumber;
        var arrival=r.IsDBNull(11)?"Not given":DateTime.Today.Add(r.GetFieldValue<TimeSpan>(11)).ToString("h:mm tt",System.Globalization.CultureInfo.InvariantCulture);
        var mode=r.GetString(12) switch{"UDriveRide"=>"UDrive ride","HotelTransport"=>"Hotel transport (please arrange pickup)",_=>"Own car"};
        var car=r.IsDBNull(13)?"":$" · {r.GetString(13)}";
        static string D(DateOnly d)=>d.ToString("ddd d MMM yyyy",System.Globalization.CultureInfo.InvariantCulture);

        var message=
            $"*New booking — {r.GetString(0)}*\n"+
            $"Booking: {(r.IsDBNull(3)?"":r.GetString(3))}\n\n"+
            $"Guest: {(r.IsDBNull(4)?"":r.GetString(4))}\n"+
            $"Mobile / WhatsApp: {(r.IsDBNull(5)?"":r.GetString(5))}\n"+
            $"Guests: {r.GetInt32(6)} · Rooms: {r.GetInt32(7)} ({r.GetString(8)})\n\n"+
            $"Check-in: {D(checkIn)}\n"+
            $"Arriving around: {arrival}\n"+
            $"Check-out: {D(checkOut)} ({nights} {(nights==1?"night":"nights")})\n\n"+
            $"Coming by: {mode}{car}\n"+
            $"Amount: PKR {r.GetDecimal(14):N0} — to be paid at the hotel\n\n"+
            "Please keep the room ready. To change or cancel, open the UDrive hotel panel.";
        return new HotelOwnerNotice(to,message);
    }

    /// <summary>Records whether the hotel's WhatsApp message went out.</summary>
    public async Task RecordOwnerNoticeAsync(Guid bookingId,bool sent,string? error,CancellationToken ct)
    {
        await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=c.CreateCommand();
        cmd.CommandText="UPDATE udrive.hotel_bookings SET owner_notified_at=CASE WHEN @sent THEN now() ELSE owner_notified_at END,owner_notify_error=@err,updated_at=now() WHERE id=@id";
        cmd.Parameters.AddWithValue("sent",sent);
        cmd.Parameters.Add(new NpgsqlParameter("err",NpgsqlDbType.Text){Value=(object?)Clip(error,300)??DBNull.Value});
        cmd.Parameters.AddWithValue("id",bookingId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    /// <summary>The customer's own hotel bookings, newest first: "My stays".</summary>
    public async Task<ServiceResult<object>> MyBookingsAsync(Guid userId,CancellationToken ct)
    {
        await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=c.CreateCommand();
        cmd.CommandText="""
            SELECT b.id,b.booking_reference,b.hotel_id,h.name,h.address,h.city,h.latitude,h.longitude,h.contact_phone,h.main_image_url,
                   r.room_type,b.check_in,b.check_out,b.guests,b.rooms,b.amount,b.status,b.arrival_time,b.arrival_mode,b.car_number,
                   b.owner_notified_at IS NOT NULL,b.created_at
            FROM udrive.hotel_bookings b
            JOIN udrive.hotels h ON h.id=b.hotel_id
            JOIN udrive.hotel_rooms r ON r.id=b.room_id
            WHERE b.customer_user_id=@u
            ORDER BY b.check_in DESC,b.created_at DESC
            LIMIT 100
            """;
        cmd.Parameters.AddWithValue("u",userId);
        var list=new List<object>();await using var rr=await cmd.ExecuteReaderAsync(ct);
        while(await rr.ReadAsync(ct))
        {
            var checkIn=rr.GetFieldValue<DateOnly>(11);var checkOut=rr.GetFieldValue<DateOnly>(12);
            list.Add(new
            {
                id=rr.GetGuid(0),
                reference=rr.IsDBNull(1)?null:rr.GetString(1),
                hotelId=rr.GetGuid(2),hotelName=rr.GetString(3),address=rr.GetString(4),city=rr.GetString(5),
                latitude=rr.GetDouble(6),longitude=rr.GetDouble(7),contactPhone=rr.GetString(8),mainImageUrl=rr.GetString(9),
                roomType=rr.GetString(10),checkIn,checkOut,nights=checkOut.DayNumber-checkIn.DayNumber,
                guests=rr.GetInt32(13),rooms=rr.GetInt32(14),amount=rr.GetDecimal(15),status=rr.GetString(16),
                arrivalTime=rr.IsDBNull(17)?null:TimeOnly.FromTimeSpan(rr.GetFieldValue<TimeSpan>(17)).ToString("HH:mm",System.Globalization.CultureInfo.InvariantCulture),
                arrivalMode=rr.GetString(18),carNumber=rr.IsDBNull(19)?null:rr.GetString(19),
                ownerNotified=rr.GetBoolean(20),createdAt=rr.GetDateTime(21)
            });
        }
        return ServiceResult<object>.Ok(list);
    }

    static string? Clip(string? value,int max){var v=value?.Trim();if(string.IsNullOrEmpty(v))return null;return v.Length>max?v[..max]:v;}

    /// <remarks>
    /// @h is bound as a typed uuid parameter, not with AddWithValue. The filter
    /// reads <c>(@h IS NULL OR h.id=@h)</c>, and AddWithValue on a DBNull sends
    /// the parameter with no type at all (Npgsql's "unspecified" type info), so
    /// PostgreSQL has to infer it from where it is used. It resolves the
    /// operands in order, reaches <c>@h IS NULL</c> first — where nothing can
    /// tell it the type — and gives up before it ever sees <c>h.id=@h</c>:
    /// "could not determine data type of parameter $2" (SQLSTATE 42P18). That
    /// made this endpoint answer 500 on exactly the call the app always makes,
    /// the one with no hotelId, so an Owner could never see their bookings.
    /// Declaring the type removes the guesswork and cannot be re-broken by
    /// reordering the SQL. Every other nullable parameter in this codebase is
    /// already bound this way.
    /// </remarks>
    public async Task<ServiceResult<object>> OwnerBookingsAsync(Guid ownerId,Guid? hotelId,CancellationToken ct){await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=c.CreateCommand();cmd.CommandText="""SELECT b.id,b.hotel_id,h.name,r.room_type,b.check_in,b.check_out,b.guests,b.rooms,b.amount,b.status,b.payment_status,b.include_transport,b.created_at FROM udrive.hotel_bookings b JOIN udrive.hotels h ON h.id=b.hotel_id JOIN udrive.hotel_rooms r ON r.id=b.room_id WHERE h.owner_user_id=@u AND (@h IS NULL OR h.id=@h) ORDER BY b.created_at DESC LIMIT 100""";cmd.Parameters.AddWithValue("u",ownerId);cmd.Parameters.Add(new NpgsqlParameter("h",NpgsqlDbType.Uuid){Value=(object?)hotelId??DBNull.Value});var list=new List<object>();await using var rr=await cmd.ExecuteReaderAsync(ct);while(await rr.ReadAsync(ct))list.Add(new{id=rr.GetGuid(0),hotelId=rr.GetGuid(1),hotelName=rr.GetString(2),roomType=rr.GetString(3),checkIn=rr.GetFieldValue<DateOnly>(4),checkOut=rr.GetFieldValue<DateOnly>(5),guests=rr.GetInt32(6),rooms=rr.GetInt32(7),amount=rr.GetDecimal(8),status=rr.GetString(9),paymentStatus=rr.GetString(10),includeTransport=rr.GetBoolean(11),createdAt=rr.GetDateTime(12)});return ServiceResult<object>.Ok(list);}

    public async Task<ServiceResult<object>> AdminListAsync(string? status,string? query,CancellationToken ct)
    {
        var normalizedStatus = string.IsNullOrWhiteSpace(status) || status.Equals("All",StringComparison.OrdinalIgnoreCase) ? "" : status.Trim();
        var normalizedQuery = query?.Trim() ?? "";
        await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=c.CreateCommand();
        cmd.CommandText="""
            SELECT h.id,h.name,h.description,h.address,h.city,h.district,h.latitude,h.longitude,
                   h.contact_phone,h.rating,h.main_image_url,h.transport_available,h.approval_status,
                   h.rejection_reason,h.is_active,h.created_at,h.updated_at,u.full_name,u.phone_number,
                   count(r.id) FILTER (WHERE r.is_active) room_types,
                   COALESCE(sum(r.total_rooms) FILTER (WHERE r.is_active),0) total_rooms
            FROM udrive.hotels h
            JOIN udrive.users u ON u.id=h.owner_user_id
            LEFT JOIN udrive.hotel_rooms r ON r.hotel_id=h.id
            WHERE h.approval_status<>'Draft'
              AND (@status='' OR h.approval_status=@status)
              AND (@query='' OR h.name ILIKE '%'||@query||'%' OR h.city ILIKE '%'||@query||'%'
                   OR h.address ILIKE '%'||@query||'%' OR u.full_name ILIKE '%'||@query||'%'
                   OR u.phone_number ILIKE '%'||@query||'%')
            GROUP BY h.id,u.full_name,u.phone_number
            ORDER BY CASE h.approval_status WHEN 'Pending' THEN 0 WHEN 'Approved' THEN 1 ELSE 2 END,
                     h.created_at DESC;
            """;
        cmd.Parameters.AddWithValue("status",normalizedStatus);cmd.Parameters.AddWithValue("query",normalizedQuery);
        var list=new List<object>();await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))list.Add(new
        {
            id=r.GetGuid(0),name=r.GetString(1),description=r.GetString(2),address=r.GetString(3),city=r.GetString(4),district=r.GetString(5),
            latitude=r.GetDouble(6),longitude=r.GetDouble(7),contactPhone=r.GetString(8),rating=r.GetDecimal(9),mainImageUrl=r.GetString(10),
            transportAvailable=r.GetBoolean(11),approvalStatus=r.GetString(12),rejectionReason=r.IsDBNull(13)?null:r.GetString(13),
            isActive=r.GetBoolean(14),createdAt=r.GetDateTime(15),updatedAt=r.GetDateTime(16),ownerName=r.GetString(17),ownerPhone=r.GetString(18),
            roomTypes=r.GetInt64(19),totalRooms=r.GetInt64(20)
        });
        return ServiceResult<object>.Ok(list);
    }

    public async Task<ServiceResult<object>> PendingAsync(CancellationToken ct){await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=c.CreateCommand();cmd.CommandText="""SELECT h.id,h.name,h.address,h.city,h.district,h.contact_phone,h.main_image_url,h.created_at,u.full_name owner_name,u.phone_number owner_phone FROM udrive.hotels h JOIN udrive.users u ON u.id=h.owner_user_id WHERE h.approval_status='Pending' ORDER BY h.created_at""";var list=new List<object>();await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))list.Add(new{id=r.GetGuid(0),name=r.GetString(1),address=r.GetString(2),city=r.GetString(3),district=r.GetString(4),contactPhone=r.GetString(5),mainImageUrl=r.GetString(6),createdAt=r.GetDateTime(7),ownerName=r.GetString(8),ownerPhone=r.GetString(9)});return ServiceResult<object>.Ok(list);}
    public async Task<ServiceResult<object>> ReviewAsync(Guid adminId,Guid id,ReviewHotelRequest x,CancellationToken ct)
    {
        if(!x.Approve&&string.IsNullOrWhiteSpace(x.Reason))return ServiceResult<object>.Fail(400,"rejection_reason_required","Add a reason before rejecting this hotel.");
        await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var tx=await c.BeginTransactionAsync(ct);
        try
        {
            await using var cmd=c.CreateCommand();cmd.Transaction=tx;
            cmd.CommandText="""UPDATE udrive.hotels SET approval_status=@s,rejection_reason=NULLIF(@r,''),approved_by=CASE WHEN @ok THEN @a ELSE NULL END,approved_at=CASE WHEN @ok THEN now() ELSE NULL END,updated_at=now() WHERE id=@id RETURNING id""";
            cmd.Parameters.AddWithValue("s",x.Approve?"Approved":"Rejected");cmd.Parameters.AddWithValue("r",x.Approve?"":x.Reason!.Trim());cmd.Parameters.AddWithValue("ok",x.Approve);cmd.Parameters.AddWithValue("a",adminId);cmd.Parameters.AddWithValue("id",id);
            var o=await cmd.ExecuteScalarAsync(ct);if(o is not Guid){await tx.RollbackAsync(ct);return ServiceResult<object>.Fail(404,"hotel_not_found","Hotel not found.");}
            await using var audit=c.CreateCommand();audit.Transaction=tx;audit.CommandText="""INSERT INTO udrive.audit_logs(id,actor_user_id,action,entity_type,entity_id,changes_json,created_at,updated_at) VALUES(gen_random_uuid(),@a,@action,'Hotel',CAST(@id AS text),jsonb_build_object('status',@status,'reason',NULLIF(@reason,'')),now(),now())""";audit.Parameters.AddWithValue("a",adminId);audit.Parameters.AddWithValue("action",x.Approve?"HotelApproved":"HotelRejected");audit.Parameters.AddWithValue("id",id);audit.Parameters.AddWithValue("status",x.Approve?"Approved":"Rejected");audit.Parameters.AddWithValue("reason",x.Reason?.Trim()??"");await audit.ExecuteNonQueryAsync(ct);
            // The hotel welcome credit, once per owner. Approving a hotel is also
            // the check of its owner's profile and CNIC (HotelOwnerService), so
            // the owner becomes Verified with their first approved hotel.
            if(x.Approve){await using var own=c.CreateCommand();own.Transaction=tx;own.CommandText="SELECT owner_user_id FROM udrive.hotels WHERE id=@id";own.Parameters.AddWithValue("id",id);if(await own.ExecuteScalarAsync(ct) is Guid ownerId){await HotelWalletService.CreditWelcomeAsync(c,tx,ownerId,id,ct);await using var verify=c.CreateCommand();verify.Transaction=tx;verify.CommandText="UPDATE udrive.hotel_owner_profiles SET verification_status='Verified',verification_note=NULL,verified_by=@a,verified_at=now(),updated_at=now() WHERE user_id=@o AND verification_status<>'Verified' AND cnic_front_url IS NOT NULL AND cnic_back_url IS NOT NULL";verify.Parameters.AddWithValue("a",adminId);verify.Parameters.AddWithValue("o",ownerId);await verify.ExecuteNonQueryAsync(ct);}}
            await tx.CommitAsync(ct);return ServiceResult<object>.Ok(new{id,status=x.Approve?"Approved":"Rejected"});
        }
        catch{await tx.RollbackAsync(CancellationToken.None);throw;}
    }

    public async Task<ServiceResult<object>> SetActiveAsync(Guid adminId,Guid id,bool isActive,CancellationToken ct)
    {
        await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var tx=await c.BeginTransactionAsync(ct);
        try
        {
            await using var cmd=c.CreateCommand();cmd.Transaction=tx;cmd.CommandText="UPDATE udrive.hotels SET is_active=@active,updated_at=now() WHERE id=@id RETURNING id";cmd.Parameters.AddWithValue("active",isActive);cmd.Parameters.AddWithValue("id",id);var o=await cmd.ExecuteScalarAsync(ct);if(o is not Guid){await tx.RollbackAsync(ct);return ServiceResult<object>.Fail(404,"hotel_not_found","Hotel not found.");}
            await using var audit=c.CreateCommand();audit.Transaction=tx;audit.CommandText="""INSERT INTO udrive.audit_logs(id,actor_user_id,action,entity_type,entity_id,changes_json,created_at,updated_at) VALUES(gen_random_uuid(),@a,'HotelVisibilityChanged','Hotel',CAST(@id AS text),jsonb_build_object('isActive',@active),now(),now())""";audit.Parameters.AddWithValue("a",adminId);audit.Parameters.AddWithValue("id",id);audit.Parameters.AddWithValue("active",isActive);await audit.ExecuteNonQueryAsync(ct);await tx.CommitAsync(ct);return ServiceResult<object>.Ok(new{id,isActive});
        }
        catch{await tx.RollbackAsync(CancellationToken.None);throw;}
    }

    static object MapHotel(NpgsqlDataReader r,bool detail=false)=>new{id=r.GetGuid(0),name=r.GetString(1),address=r.GetString(2),city=r.GetString(3),district=r.GetString(4),latitude=r.GetDouble(5),longitude=r.GetDouble(6),contactPhone=r.GetString(7),rating=r.GetDecimal(8),mainImageUrl=r.GetString(9),amenities=JsonSerializer.Deserialize<string[]>(r.GetFieldValue<string>(10))??[],transportAvailable=r.GetBoolean(11),description=detail?r.GetString(12):null,startingRate=detail?0:r.GetDecimal(12),availableRooms=detail?0:r.GetInt64(13),isDemo=IsDemoColumn(r)};
    static bool IsDemoColumn(NpgsqlDataReader r){for(var i=0;i<r.FieldCount;i++){if(r.GetName(i)=="is_demo")return !r.IsDBNull(i)&&r.GetBoolean(i);}return false;}
}
