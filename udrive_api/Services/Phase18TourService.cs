using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

public sealed class Phase18TourService(string connectionString)
{
    public async Task<ServiceResult<TourPackageContentDto>> GetContentAsync(Guid packageId, CancellationToken ct)
    {
        await using var c = new NpgsqlConnection(connectionString); await c.OpenAsync(ct);
        var itinerary = new List<TourItineraryDayDto>();
        await using (var cmd = new NpgsqlCommand("SELECT id,day_number,title,location,activity,start_time,end_time,notes FROM udrive.tour_package_itinerary_days WHERE tour_package_id=@id ORDER BY day_number", c))
        { cmd.Parameters.AddWithValue("id", packageId); await using var r=await cmd.ExecuteReaderAsync(ct); while(await r.ReadAsync(ct)) itinerary.Add(new(r.GetGuid(0),r.GetInt32(1),r.GetString(2),r.GetString(3),r.GetString(4),r.IsDBNull(5)?null:TimeOnly.FromTimeSpan(r.GetTimeSpan(5)),r.IsDBNull(6)?null:TimeOnly.FromTimeSpan(r.GetTimeSpan(6)),r.IsDBNull(7)?null:r.GetString(7))); }
        var images = new List<TourImageDto>();
        await using (var cmd = new NpgsqlCommand("SELECT id,image_url,caption,sort_order,is_cover FROM udrive.tour_package_images WHERE tour_package_id=@id ORDER BY is_cover DESC,sort_order,id", c))
        { cmd.Parameters.AddWithValue("id", packageId); await using var r=await cmd.ExecuteReaderAsync(ct); while(await r.ReadAsync(ct)) images.Add(new(r.GetGuid(0),r.GetString(1),r.IsDBNull(2)?null:r.GetString(2),r.GetInt32(3),r.GetBoolean(4))); }
        var rules = new List<TourCancellationRuleDto>();
        await using (var cmd = new NpgsqlCommand("SELECT id,hours_before_departure,refund_percent,description FROM udrive.tour_cancellation_rules WHERE tour_package_id=@id ORDER BY hours_before_departure DESC", c))
        { cmd.Parameters.AddWithValue("id", packageId); await using var r=await cmd.ExecuteReaderAsync(ct); while(await r.ReadAsync(ct)) rules.Add(new(r.GetGuid(0),r.GetInt32(1),r.GetDecimal(2),r.IsDBNull(3)?null:r.GetString(3))); }
        await using var minCmd = new NpgsqlCommand("SELECT COALESCE(minimum_passengers,1) FROM udrive.tour_departures WHERE tour_package_id=@id ORDER BY departure_at LIMIT 1", c); minCmd.Parameters.AddWithValue("id",packageId); var min=Convert.ToInt32(await minCmd.ExecuteScalarAsync(ct) ?? 1);
        return ServiceResult<TourPackageContentDto>.Ok(new(packageId,itinerary,images,rules,min));
    }

    public async Task<ServiceResult<TourPackageContentDto>> ReplaceContentAsync(Guid driverUserId, Guid packageId, UpdateTourPackageContentRequest request, CancellationToken ct)
    {
        await using var c = new NpgsqlConnection(connectionString); await c.OpenAsync(ct); await using var tx=await c.BeginTransactionAsync(ct);
        await using (var own = new NpgsqlCommand("SELECT 1 FROM udrive.tour_packages tp JOIN udrive.driver_profiles dp ON dp.id=tp.driver_profile_id WHERE tp.id=@p AND dp.user_id=@u AND tp.status IN ('Draft','ChangesRequired','Rejected','Paused','Active')",c,tx)) { own.Parameters.AddWithValue("p",packageId);own.Parameters.AddWithValue("u",driverUserId);if(await own.ExecuteScalarAsync(ct) is null) return ServiceResult<TourPackageContentDto>.Fail(403,"package_not_editable","This package is not editable by the signed-in Driver."); }
        foreach(var table in new[]{"tour_package_itinerary_days","tour_package_images","tour_cancellation_rules"}) { await using var d=new NpgsqlCommand($"DELETE FROM udrive.{table} WHERE tour_package_id=@p",c,tx);d.Parameters.AddWithValue("p",packageId);await d.ExecuteNonQueryAsync(ct); }
        foreach(var x in request.Itinerary ?? []) { await using var cmd=new NpgsqlCommand("INSERT INTO udrive.tour_package_itinerary_days(tour_package_id,day_number,title,location,activity,start_time,end_time,notes) VALUES(@p,@d,@t,@l,@a,@s,@e,@n)",c,tx);cmd.Parameters.AddWithValue("p",packageId);cmd.Parameters.AddWithValue("d",x.DayNumber);cmd.Parameters.AddWithValue("t",x.Title.Trim());cmd.Parameters.AddWithValue("l",x.Location.Trim());cmd.Parameters.AddWithValue("a",x.Activity.Trim());cmd.Parameters.Add(new("s",NpgsqlDbType.Time){Value=(object?)x.StartTime?.ToTimeSpan()??DBNull.Value});cmd.Parameters.Add(new("e",NpgsqlDbType.Time){Value=(object?)x.EndTime?.ToTimeSpan()??DBNull.Value});cmd.Parameters.Add(new("n",NpgsqlDbType.Text){Value=(object?)x.Notes?.Trim()??DBNull.Value});await cmd.ExecuteNonQueryAsync(ct); }
        foreach(var x in request.Images ?? []) { await using var cmd=new NpgsqlCommand("INSERT INTO udrive.tour_package_images(tour_package_id,image_url,caption,sort_order,is_cover) VALUES(@p,@u,@c,@s,@i)",c,tx);cmd.Parameters.AddWithValue("p",packageId);cmd.Parameters.AddWithValue("u",x.ImageUrl.Trim());cmd.Parameters.Add(new("c",NpgsqlDbType.Varchar){Value=(object?)x.Caption?.Trim()??DBNull.Value});cmd.Parameters.AddWithValue("s",x.SortOrder);cmd.Parameters.AddWithValue("i",x.IsCover);await cmd.ExecuteNonQueryAsync(ct); }
        foreach(var x in request.CancellationRules ?? []) { await using var cmd=new NpgsqlCommand("INSERT INTO udrive.tour_cancellation_rules(tour_package_id,hours_before_departure,refund_percent,description) VALUES(@p,@h,@r,@d)",c,tx);cmd.Parameters.AddWithValue("p",packageId);cmd.Parameters.AddWithValue("h",x.HoursBeforeDeparture);cmd.Parameters.AddWithValue("r",x.RefundPercent);cmd.Parameters.Add(new("d",NpgsqlDbType.Varchar){Value=(object?)x.Description?.Trim()??DBNull.Value});await cmd.ExecuteNonQueryAsync(ct); }
        await using(var dep=new NpgsqlCommand("UPDATE udrive.tour_departures SET minimum_passengers=@m,updated_at=now() WHERE tour_package_id=@p",c,tx)){dep.Parameters.AddWithValue("m",request.MinimumPassengers);dep.Parameters.AddWithValue("p",packageId);await dep.ExecuteNonQueryAsync(ct);} await tx.CommitAsync(ct);
        return await GetContentAsync(packageId,ct);
    }

    public async Task<ServiceResult<IReadOnlyList<PackageBookingSummaryDto>>> GetCustomerPackageBookingsAsync(Guid userId,CancellationToken ct)
    {
        const string sql="""SELECT b.id,b.booking_reference,tp.id,tp.title,d.name,tp.departure_at,b.seats_booked,b.total_amount,b.remaining_amount,b.status,COALESCE(o.status,'Scheduled') FROM udrive.bookings b JOIN udrive.tour_packages tp ON tp.id=b.tour_package_id JOIN udrive.destinations d ON d.id=tp.destination_id LEFT JOIN udrive.tour_trip_operations o ON o.tour_package_id=tp.id WHERE b.customer_user_id=@u AND b.tour_package_id IS NOT NULL ORDER BY tp.departure_at DESC""";
        var list=new List<PackageBookingSummaryDto>(); await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=new NpgsqlCommand(sql,c);cmd.Parameters.AddWithValue("u",userId);await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))list.Add(new(r.GetGuid(0),r.GetString(1),r.GetGuid(2),r.GetString(3),r.GetString(4),r.GetFieldValue<DateTimeOffset>(5),r.GetInt32(6),r.GetDecimal(7),r.GetDecimal(8),r.GetString(9),r.GetString(10)));return ServiceResult<IReadOnlyList<PackageBookingSummaryDto>>.Ok(list);
    }

    public async Task<ServiceResult<IReadOnlyList<TourOperationDto>>> GetDriverOperationsAsync(Guid userId,CancellationToken ct)
    {
        await EnsureDriverOperationsAsync(userId, ct);
        const string sql="""SELECT o.id,tp.id,tp.title,o.departure_id,tp.departure_at,tp.return_at,o.status,COUNT(DISTINCT b.id)::int,COALESCE(SUM(DISTINCT b.seats_booked),0)::int,COUNT(DISTINCT ci.id) FILTER(WHERE ci.status IN('CheckedIn','Boarded'))::int,COUNT(DISTINCT ci.id) FILTER(WHERE ci.status='Boarded')::int,v.make||' '||v.model,v.registration_number,o.version FROM udrive.tour_trip_operations o JOIN udrive.tour_packages tp ON tp.id=o.tour_package_id JOIN udrive.driver_profiles dp ON dp.id=o.driver_profile_id JOIN udrive.vehicles v ON v.id=o.vehicle_id LEFT JOIN udrive.bookings b ON b.tour_package_id=tp.id AND b.status NOT IN('Cancelled','Refunded') LEFT JOIN udrive.tour_passenger_checkins ci ON ci.tour_operation_id=o.id WHERE dp.user_id=@u GROUP BY o.id,tp.id,tp.title,o.departure_id,tp.departure_at,tp.return_at,o.status,v.make,v.model,v.registration_number,o.version ORDER BY tp.departure_at DESC""";
        var list=new List<TourOperationDto>();await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=new NpgsqlCommand(sql,c);cmd.Parameters.AddWithValue("u",userId);await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))list.Add(new(r.GetGuid(0),r.GetGuid(1),r.GetString(2),r.IsDBNull(3)?null:r.GetGuid(3),r.GetFieldValue<DateTimeOffset>(4),r.IsDBNull(5)?null:r.GetFieldValue<DateTimeOffset>(5),r.GetString(6),r.GetInt32(7),r.GetInt32(8),r.GetInt32(9),r.GetInt32(10),r.GetString(11),r.GetString(12),r.GetInt32(13)));return ServiceResult<IReadOnlyList<TourOperationDto>>.Ok(list);
    }

    public async Task<ServiceResult<TourOperationDto>> ChangeStatusAsync(Guid userId,Guid operationId,UpdateTourStatusRequest request,CancellationToken ct)
    {
        var target=request.Status.Trim(); var allowed=new HashSet<string>(StringComparer.OrdinalIgnoreCase){"Scheduled","Boarding","Departed","InProgress","Completed","Cancelled"};if(!allowed.Contains(target))return ServiceResult<TourOperationDto>.Fail(400,"invalid_tour_status","Unsupported tour status.");
        await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var tx=await c.BeginTransactionAsync(ct);
        const string q="""SELECT o.status FROM udrive.tour_trip_operations o JOIN udrive.driver_profiles dp ON dp.id=o.driver_profile_id WHERE o.id=@id AND dp.user_id=@u AND o.version=@v FOR UPDATE""";string? old;await using(var cmd=new NpgsqlCommand(q,c,tx)){cmd.Parameters.AddWithValue("id",operationId);cmd.Parameters.AddWithValue("u",userId);cmd.Parameters.AddWithValue("v",request.ExpectedVersion);old=await cmd.ExecuteScalarAsync(ct) as string;}if(old is null)return ServiceResult<TourOperationDto>.Fail(409,"tour_status_conflict","Tour operation changed or is not accessible.");
        const string up="""UPDATE udrive.tour_trip_operations SET status=@s,boarding_opened_at=CASE WHEN @s='Boarding' THEN COALESCE(boarding_opened_at,now()) ELSE boarding_opened_at END,departed_at=CASE WHEN @s IN('Departed','InProgress') THEN COALESCE(departed_at,now()) ELSE departed_at END,completed_at=CASE WHEN @s='Completed' THEN now() ELSE completed_at END,cancelled_at=CASE WHEN @s='Cancelled' THEN now() ELSE cancelled_at END,cancellation_reason=CASE WHEN @s='Cancelled' THEN @n ELSE cancellation_reason END,version=version+1,updated_at=now() WHERE id=@id""";await using(var cmd=new NpgsqlCommand(up,c,tx)){cmd.Parameters.AddWithValue("s",target);cmd.Parameters.AddWithValue("n",(object?)request.Notes??DBNull.Value);cmd.Parameters.AddWithValue("id",operationId);await cmd.ExecuteNonQueryAsync(ct);}await using(var h=new NpgsqlCommand("INSERT INTO udrive.tour_status_history(tour_operation_id,from_status,to_status,changed_by_user_id,notes) VALUES(@i,@f,@t,@u,@n)",c,tx)){h.Parameters.AddWithValue("i",operationId);h.Parameters.AddWithValue("f",old);h.Parameters.AddWithValue("t",target);h.Parameters.AddWithValue("u",userId);h.Parameters.AddWithValue("n",(object?)request.Notes??DBNull.Value);await h.ExecuteNonQueryAsync(ct);}await tx.CommitAsync(ct);
        var all=await GetDriverOperationsAsync(userId,ct);return ServiceResult<TourOperationDto>.Ok(all.Data!.First(x=>x.Id==operationId));
    }

    public async Task<ServiceResult<TourCheckInDto>> CheckInAsync(Guid userId,Guid operationId,CheckInPassengerRequest request,CancellationToken ct)
    {
        var status=request.Status.Trim();if (status is not "CheckedIn" and not "Boarded" and not "NoShow")return ServiceResult<TourCheckInDto>.Fail(400,"invalid_checkin_status","Use CheckedIn, Boarded or NoShow.");
        const string auth="""SELECT bp.full_name,b.booking_reference FROM udrive.tour_trip_operations o JOIN udrive.driver_profiles dp ON dp.id=o.driver_profile_id JOIN udrive.bookings b ON b.id=@b AND b.tour_package_id=o.tour_package_id LEFT JOIN udrive.booking_passengers bp ON bp.id=@p AND bp.booking_id=b.id WHERE o.id=@o AND dp.user_id=@u""";
        await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);string name="Booking passenger";string reference;await using(var cmd=new NpgsqlCommand(auth,c)){cmd.Parameters.AddWithValue("b",request.BookingId);cmd.Parameters.Add(new("p",NpgsqlDbType.Uuid){Value=(object?)request.PassengerId??DBNull.Value});cmd.Parameters.AddWithValue("o",operationId);cmd.Parameters.AddWithValue("u",userId);await using var r=await cmd.ExecuteReaderAsync(ct);if(!await r.ReadAsync(ct))return ServiceResult<TourCheckInDto>.Fail(403,"checkin_not_allowed","Passenger is not part of this tour.");if(!r.IsDBNull(0))name=r.GetString(0);reference=r.GetString(1);}
        var id=Guid.NewGuid();const string sql="""INSERT INTO udrive.tour_passenger_checkins(id,tour_operation_id,booking_id,passenger_id,status,checked_in_at,boarded_at,checked_in_by_user_id,notes) VALUES(@id,@o,@b,@p,@s,CASE WHEN @s IN('CheckedIn','Boarded') THEN now() END,CASE WHEN @s='Boarded' THEN now() END,@u,@n) ON CONFLICT(tour_operation_id,booking_id,passenger_id) DO UPDATE SET status=excluded.status,checked_in_at=COALESCE(udrive.tour_passenger_checkins.checked_in_at,excluded.checked_in_at),boarded_at=COALESCE(udrive.tour_passenger_checkins.boarded_at,excluded.boarded_at),checked_in_by_user_id=excluded.checked_in_by_user_id,notes=excluded.notes,updated_at=now() RETURNING id,checked_in_at,boarded_at""";
        DateTimeOffset? check=null,board=null;await using(var cmd=new NpgsqlCommand(sql,c)){cmd.Parameters.AddWithValue("id",id);cmd.Parameters.AddWithValue("o",operationId);cmd.Parameters.AddWithValue("b",request.BookingId);cmd.Parameters.Add(new("p",NpgsqlDbType.Uuid){Value=(object?)request.PassengerId??DBNull.Value});cmd.Parameters.AddWithValue("s",status);cmd.Parameters.AddWithValue("u",userId);cmd.Parameters.Add(new("n",NpgsqlDbType.Varchar){Value=(object?)request.Notes??DBNull.Value});await using var r=await cmd.ExecuteReaderAsync(ct);await r.ReadAsync(ct);id=r.GetGuid(0);check=r.IsDBNull(1)?null:r.GetFieldValue<DateTimeOffset>(1);board=r.IsDBNull(2)?null:r.GetFieldValue<DateTimeOffset>(2);}return ServiceResult<TourCheckInDto>.Ok(new(id,request.BookingId,request.PassengerId,name,reference,status,check,board));
    }

    private async Task EnsureDriverOperationsAsync(Guid userId, CancellationToken ct)
    {
        const string sql = """
            INSERT INTO udrive.tour_departures(tour_package_id,departure_at,return_at,capacity,available_seats,status,minimum_passengers)
            SELECT tp.id,tp.departure_at,tp.return_at,tp.total_seats,tp.available_seats,'Scheduled',1
            FROM udrive.tour_packages tp JOIN udrive.driver_profiles dp ON dp.id=tp.driver_profile_id
            WHERE dp.user_id=@u AND tp.status IN ('Active','Paused')
            ON CONFLICT(tour_package_id,departure_at) DO NOTHING;
            INSERT INTO udrive.tour_trip_operations(tour_package_id,departure_id,driver_profile_id,vehicle_id,status)
            SELECT tp.id,td.id,tp.driver_profile_id,tp.vehicle_id,'Scheduled'
            FROM udrive.tour_packages tp JOIN udrive.driver_profiles dp ON dp.id=tp.driver_profile_id
            JOIN udrive.tour_departures td ON td.tour_package_id=tp.id AND td.departure_at=tp.departure_at
            WHERE dp.user_id=@u AND tp.status IN ('Active','Paused')
            ON CONFLICT(tour_package_id,departure_id) DO NOTHING;
            """;
        await using var c=new NpgsqlConnection(connectionString); await c.OpenAsync(ct);
        await using var cmd=new NpgsqlCommand(sql,c); cmd.Parameters.AddWithValue("u",userId); await cmd.ExecuteNonQueryAsync(ct);
    }

    public async Task<ServiceResult<IReadOnlyList<AdminPackageListItemDto>>> GetAdminPackagesAsync(string? status,CancellationToken ct)
    {
        const string sql="""SELECT tp.id,tp.title,tp.starting_city,d.name,tp.departure_at,tp.return_at,tp.status,tp.total_seats,tp.available_seats,tp.price_per_seat,tp.whole_vehicle_price,u.full_name,v.make||' '||v.model,v.registration_number,COUNT(DISTINCT b.id)::int,COALESCE(SUM(DISTINCT b.seats_booked),0)::int,COALESCE(SUM(DISTINCT b.total_amount),0) FROM udrive.tour_packages tp JOIN udrive.destinations d ON d.id=tp.destination_id JOIN udrive.driver_profiles dp ON dp.id=tp.driver_profile_id JOIN udrive.users u ON u.id=dp.user_id JOIN udrive.vehicles v ON v.id=tp.vehicle_id LEFT JOIN udrive.bookings b ON b.tour_package_id=tp.id AND b.status<>'Cancelled' WHERE (@s IS NULL OR tp.status=@s) GROUP BY tp.id,tp.title,tp.starting_city,d.name,tp.departure_at,tp.return_at,tp.status,tp.total_seats,tp.available_seats,tp.price_per_seat,tp.whole_vehicle_price,u.full_name,v.make,v.model,v.registration_number ORDER BY tp.departure_at DESC""";var list=new List<AdminPackageListItemDto>();await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=new NpgsqlCommand(sql,c);cmd.Parameters.Add(new("s",NpgsqlDbType.Varchar){Value=(object?)status??DBNull.Value});await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))list.Add(new(r.GetGuid(0),r.GetString(1),r.GetString(2),r.GetString(3),r.GetFieldValue<DateTimeOffset>(4),r.IsDBNull(5)?null:r.GetFieldValue<DateTimeOffset>(5),r.GetString(6),r.GetInt32(7),r.GetInt32(8),r.GetDecimal(9),r.GetDecimal(10),r.GetString(11),r.GetString(12),r.GetString(13),r.GetInt32(14),r.GetInt32(15),r.GetDecimal(16)));return ServiceResult<IReadOnlyList<AdminPackageListItemDto>>.Ok(list);
    }
}
