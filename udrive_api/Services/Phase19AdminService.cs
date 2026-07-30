using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

public sealed class Phase19AdminService(string connectionString)
{
    public async Task<ServiceResult<ExecutiveDashboardDto>> DashboardAsync(DateTimeOffset? from, DateTimeOffset? to, CancellationToken ct)
    {
        var end = to ?? DateTimeOffset.UtcNow;
        var start = from ?? end.AddDays(-7);
        var duration = end - start;
        var previousStart = start - duration;
        await using var c = new NpgsqlConnection(connectionString); await c.OpenAsync(ct);
        async Task<decimal> Scalar(string sql, DateTimeOffset a, DateTimeOffset b)
        { await using var cmd=new NpgsqlCommand(sql,c);cmd.Parameters.AddWithValue("a",a);cmd.Parameters.AddWithValue("b",b);return Convert.ToDecimal(await cmd.ExecuteScalarAsync(ct)??0); }
        static decimal Change(decimal current,decimal previous)=>previous==0?(current==0?0:100):Math.Round((current-previous)/previous*100,1);
        var definitions = new (string Label,string Sql,string Tone)[]
        {
            ("Bookings","SELECT count(*) FROM udrive.bookings WHERE created_at>=@a AND created_at<@b","blue"),
            ("Completed trips","SELECT count(*) FROM udrive.bookings WHERE status IN ('TripCompleted','Completed') AND updated_at>=@a AND updated_at<@b","green"),
            ("Gross booking value","SELECT COALESCE(sum(total_amount),0) FROM udrive.bookings WHERE created_at>=@a AND created_at<@b","purple"),
            ("Amount collected","SELECT COALESCE(sum(amount-refund_amount),0) FROM udrive.payments WHERE status IN ('Paid','Verified') AND created_at>=@a AND created_at<@b","green"),
            ("Platform commission","SELECT COALESCE(sum(commission_amount),0) FROM udrive.driver_earnings WHERE created_at>=@a AND created_at<@b","orange"),
            ("Driver earnings","SELECT COALESCE(sum(net_amount),0) FROM udrive.driver_earnings WHERE created_at>=@a AND created_at<@b","blue")
        };
        var metrics=new List<ExecutiveMetricDto>();
        foreach(var d in definitions){var current=await Scalar(d.Sql,start,end);var previous=await Scalar(d.Sql,previousStart,start);metrics.Add(new(d.Label,current,previous,Change(current,previous),d.Tone));}
        var statuses=new Dictionary<string,int>(StringComparer.OrdinalIgnoreCase);
        await using(var cmd=new NpgsqlCommand("SELECT status,count(*)::int FROM udrive.bookings GROUP BY status ORDER BY count(*) DESC",c)){await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))statuses[r.GetString(0)]=r.GetInt32(1);}
        var queues=new Dictionary<string,int>();
        var queueSql="""SELECT
          (SELECT count(*)::int FROM udrive.driver_profiles WHERE verification_status IN ('Pending','Submitted','ChangesRequired')),
          (SELECT count(*)::int FROM udrive.vehicles WHERE verification_status IN ('Pending','Submitted','ChangesRequired')),
          (SELECT count(*)::int FROM udrive.tour_packages WHERE status IN ('Pending','Submitted')),
          (SELECT count(*)::int FROM udrive.driver_payout_requests WHERE status='Pending'),
          (SELECT count(*)::int FROM udrive.refund_requests WHERE status='Pending'),
          (SELECT count(*)::int FROM udrive.dispute_cases WHERE status NOT IN ('Resolved','Rejected','Closed')),
          (SELECT count(*)::int FROM udrive.emergency_cases WHERE status NOT IN ('Resolved','FalseAlarm'))""";
        await using(var cmd=new NpgsqlCommand(queueSql,c)){await using var r=await cmd.ExecuteReaderAsync(ct);if(await r.ReadAsync(ct)){queues["drivers"]=r.GetInt32(0);queues["vehicles"]=r.GetInt32(1);queues["packages"]=r.GetInt32(2);queues["payouts"]=r.GetInt32(3);queues["refunds"]=r.GetInt32(4);queues["disputes"]=r.GetInt32(5);queues["emergencies"]=r.GetInt32(6);}}
        var activity=new List<ExecutiveActivityDto>();
        const string activitySql="""SELECT type,title,subtitle,status,occurred_at FROM (
          SELECT 'Booking' type,'Booking '||COALESCE(booking_reference,left(id::text,8)) title,booking_type||' · '||status subtitle,status,updated_at occurred_at FROM udrive.bookings
          UNION ALL SELECT 'Emergency',case_reference,emergency_type||' · '||status,status,updated_at FROM udrive.emergency_cases
          UNION ALL SELECT 'Dispute',reference,category||' · '||status,status,updated_at FROM udrive.dispute_cases
        ) x ORDER BY occurred_at DESC LIMIT 12""";
        await using(var cmd=new NpgsqlCommand(activitySql,c)){await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))activity.Add(new(r.GetString(0),r.GetString(1),r.GetString(2),r.GetString(3),r.GetFieldValue<DateTimeOffset>(4)));}
        return ServiceResult<ExecutiveDashboardDto>.Ok(new(metrics,statuses,queues,activity));
    }

    public async Task<ServiceResult<IReadOnlyList<LiveOperationDto>>> LiveOperationsAsync(CancellationToken ct)
    {
        const string sql="""SELECT b.id,COALESCE(b.booking_reference,left(b.id::text,8)),b.booking_type,b.status,cu.full_name,du.full_name,
          CASE WHEN v.id IS NULL THEN NULL ELSE trim(v.make||' '||v.model) END,v.registration_number,
          COALESCE(rr.pickup_label,tp.starting_city,'Pickup')||' → '||COALESCE(rr.destination_label,d.name,'Destination'),b.pickup_at,
          ST_Y(ll.location::geometry),ST_X(ll.location::geometry),ll.recorded_at,
          (ll.recorded_at IS NULL OR ll.recorded_at < now()-interval '60 seconds'),
          EXISTS(SELECT 1 FROM udrive.emergency_cases ec WHERE ec.booking_id=b.id AND ec.status NOT IN('Resolved','FalseAlarm'))
        FROM udrive.bookings b JOIN udrive.users cu ON cu.id=b.customer_user_id
        LEFT JOIN udrive.driver_profiles dp ON dp.id=b.driver_profile_id LEFT JOIN udrive.users du ON du.id=dp.user_id LEFT JOIN udrive.vehicles v ON v.id=b.vehicle_id
        LEFT JOIN udrive.ride_requests rr ON rr.id=b.ride_request_id LEFT JOIN udrive.tour_packages tp ON tp.id=b.tour_package_id LEFT JOIN udrive.destinations d ON d.id=tp.destination_id
        LEFT JOIN LATERAL(SELECT location,recorded_at FROM udrive.live_locations WHERE booking_id=b.id ORDER BY recorded_at DESC LIMIT 1)ll ON true
        WHERE b.status IN('DriverAssigned','DriverAccepted','DriverEnRoute','DriverArrived','TripStarted','Emergency','Boarding','Departed','InProgress') ORDER BY b.pickup_at""";
        var list=new List<LiveOperationDto>();await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=new NpgsqlCommand(sql,c);await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))list.Add(new(r.GetGuid(0),r.GetString(1),r.GetString(2),r.GetString(3),r.GetString(4),r.IsDBNull(5)?null:r.GetString(5),r.IsDBNull(6)?null:r.GetString(6),r.IsDBNull(7)?null:r.GetString(7),r.GetString(8),r.GetFieldValue<DateTimeOffset>(9),r.IsDBNull(10)?null:r.GetDouble(10),r.IsDBNull(11)?null:r.GetDouble(11),r.IsDBNull(12)?null:r.GetFieldValue<DateTimeOffset>(12),r.GetBoolean(13),r.GetBoolean(14)));return ServiceResult<IReadOnlyList<LiveOperationDto>>.Ok(list);
    }

    public async Task<ServiceResult<IReadOnlyList<AdminBookingRowDto>>> BookingsAsync(string? search,string? status,DateTimeOffset? from,DateTimeOffset? to,CancellationToken ct)
    {
        const string sql="""SELECT b.id,COALESCE(b.booking_reference,left(b.id::text,8)),b.booking_type,b.status,cu.full_name,du.full_name,
          CASE WHEN v.id IS NULL THEN NULL ELSE trim(v.make||' '||v.model) END,
          COALESCE(rr.pickup_label,tp.starting_city,'Pickup')||' → '||COALESCE(rr.destination_label,d.name,'Destination'),b.seats_booked,b.total_amount,
          COALESCE((SELECT sum(amount-refund_amount) FROM udrive.payments p WHERE p.booking_id=b.id AND p.status IN('Paid','Verified')),0),b.remaining_amount,b.pickup_at,b.created_at
        FROM udrive.bookings b JOIN udrive.users cu ON cu.id=b.customer_user_id LEFT JOIN udrive.driver_profiles dp ON dp.id=b.driver_profile_id LEFT JOIN udrive.users du ON du.id=dp.user_id LEFT JOIN udrive.vehicles v ON v.id=b.vehicle_id LEFT JOIN udrive.ride_requests rr ON rr.id=b.ride_request_id LEFT JOIN udrive.tour_packages tp ON tp.id=b.tour_package_id LEFT JOIN udrive.destinations d ON d.id=tp.destination_id
        WHERE (@s IS NULL OR b.status=@s) AND (@f IS NULL OR b.created_at>=@f) AND (@t IS NULL OR b.created_at<@t) AND (@q IS NULL OR COALESCE(b.booking_reference,'') ILIKE @q OR cu.full_name ILIKE @q OR COALESCE(du.full_name,'') ILIKE @q OR COALESCE(v.registration_number,'') ILIKE @q) ORDER BY b.created_at DESC LIMIT 500""";
        var list=new List<AdminBookingRowDto>();await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=new NpgsqlCommand(sql,c);cmd.Parameters.Add(new("s",NpgsqlDbType.Varchar){Value=(object?)status??DBNull.Value});cmd.Parameters.Add(new("f",NpgsqlDbType.TimestampTz){Value=(object?)from??DBNull.Value});cmd.Parameters.Add(new("t",NpgsqlDbType.TimestampTz){Value=(object?)to??DBNull.Value});cmd.Parameters.Add(new("q",NpgsqlDbType.Varchar){Value=string.IsNullOrWhiteSpace(search)?DBNull.Value:$"%{search.Trim()}%"});await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))list.Add(new(r.GetGuid(0),r.GetString(1),r.GetString(2),r.GetString(3),r.GetString(4),r.IsDBNull(5)?null:r.GetString(5),r.IsDBNull(6)?null:r.GetString(6),r.GetString(7),r.GetInt32(8),r.GetDecimal(9),r.GetDecimal(10),r.GetDecimal(11),r.GetFieldValue<DateTimeOffset>(12),r.GetFieldValue<DateTimeOffset>(13)));return ServiceResult<IReadOnlyList<AdminBookingRowDto>>.Ok(list);
    }

    public async Task<ServiceResult<FinanceReconciliationDto>> FinanceAsync(DateTimeOffset? from,DateTimeOffset? to,CancellationToken ct)
    {
        await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);var f=from??DateTimeOffset.UtcNow.AddDays(-30);var t=to??DateTimeOffset.UtcNow;
        const string totals="""SELECT
          COALESCE((SELECT sum(total_amount) FROM udrive.bookings WHERE created_at>=@f AND created_at<@t),0),
          COALESCE((SELECT sum(amount) FROM udrive.payments WHERE status IN('Paid','Verified') AND created_at>=@f AND created_at<@t),0),
          COALESCE((SELECT sum(refund_amount) FROM udrive.payments WHERE created_at>=@f AND created_at<@t),0),
          COALESCE((SELECT sum(commission_amount) FROM udrive.driver_earnings WHERE created_at>=@f AND created_at<@t),0),
          COALESCE((SELECT sum(net_amount) FROM udrive.driver_earnings WHERE created_at>=@f AND created_at<@t),0),
          COALESCE((SELECT sum(amount) FROM udrive.driver_payout_requests WHERE status='Paid' AND paid_at>=@f AND paid_at<@t),0),
          COALESCE((SELECT sum(remaining_amount) FROM udrive.bookings WHERE status NOT IN('Cancelled','Refunded') AND created_at>=@f AND created_at<@t),0)""";
        decimal gross,collected,refunded,commission,earnings,paidout,outstanding;await using(var cmd=new NpgsqlCommand(totals,c)){cmd.Parameters.AddWithValue("f",f);cmd.Parameters.AddWithValue("t",t);await using var r=await cmd.ExecuteReaderAsync(ct);await r.ReadAsync(ct);gross=r.GetDecimal(0);collected=r.GetDecimal(1);refunded=r.GetDecimal(2);commission=r.GetDecimal(3);earnings=r.GetDecimal(4);paidout=r.GetDecimal(5);outstanding=r.GetDecimal(6);}
        var mismatches=new List<FinanceMismatchDto>();const string mismatchSql="""SELECT b.id,COALESCE(b.booking_reference,left(b.id::text,8)),b.total_amount,COALESCE(sum(p.amount) FILTER(WHERE p.status IN('Paid','Verified')),0),COALESCE(sum(p.refund_amount),0),COALESCE(de.net_amount,0),b.total_amount-COALESCE(sum(p.amount) FILTER(WHERE p.status IN('Paid','Verified')),0)+COALESCE(sum(p.refund_amount),0) FROM udrive.bookings b LEFT JOIN udrive.payments p ON p.booking_id=b.id LEFT JOIN udrive.driver_earnings de ON de.booking_id=b.id WHERE b.created_at>=@f AND b.created_at<@t GROUP BY b.id,b.booking_reference,b.total_amount,de.net_amount HAVING abs(b.total_amount-COALESCE(sum(p.amount) FILTER(WHERE p.status IN('Paid','Verified')),0)+COALESCE(sum(p.refund_amount),0)-b.remaining_amount)>0.01 ORDER BY b.created_at DESC LIMIT 100""";await using(var cmd=new NpgsqlCommand(mismatchSql,c)){cmd.Parameters.AddWithValue("f",f);cmd.Parameters.AddWithValue("t",t);await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))mismatches.Add(new(r.GetGuid(0),r.GetString(1),r.GetDecimal(2),r.GetDecimal(3),r.GetDecimal(4),r.GetDecimal(5),r.GetDecimal(6)));}
        var difference=gross-collected+refunded-outstanding;return ServiceResult<FinanceReconciliationDto>.Ok(new(gross,collected,refunded,commission,earnings,paidout,outstanding,difference,mismatches));
    }

    public async Task<ServiceResult<IReadOnlyList<ReportRowDto>>> ReportAsync(DateTimeOffset? from,DateTimeOffset? to,CancellationToken ct)
    {
        const string sql="""SELECT to_char(date_trunc('day',b.created_at),'YYYY-MM-DD'),count(*)::int,count(*) FILTER(WHERE b.status IN('Completed','TripCompleted'))::int,count(*) FILTER(WHERE b.status='Cancelled')::int,sum(b.total_amount),COALESCE(sum(p.paid),0),COALESCE(sum(de.commission_amount),0),COALESCE(sum(de.net_amount),0),COALESCE(sum(p.refunded),0) FROM udrive.bookings b LEFT JOIN LATERAL(SELECT sum(amount) FILTER(WHERE status IN('Paid','Verified')) paid,sum(refund_amount) refunded FROM udrive.payments WHERE booking_id=b.id)p ON true LEFT JOIN udrive.driver_earnings de ON de.booking_id=b.id WHERE b.created_at>=@f AND b.created_at<@t GROUP BY date_trunc('day',b.created_at) ORDER BY date_trunc('day',b.created_at) DESC""";
        var list=new List<ReportRowDto>();await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=new NpgsqlCommand(sql,c);cmd.Parameters.AddWithValue("f",from??DateTimeOffset.UtcNow.AddDays(-30));cmd.Parameters.AddWithValue("t",to??DateTimeOffset.UtcNow);await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))list.Add(new(r.GetString(0),r.GetInt32(1),r.GetInt32(2),r.GetInt32(3),r.GetDecimal(4),r.GetDecimal(5),r.GetDecimal(6),r.GetDecimal(7),r.GetDecimal(8)));return ServiceResult<IReadOnlyList<ReportRowDto>>.Ok(list);
    }

    public async Task<ServiceResult<DiagnosticsDto>> DiagnosticsAsync(CancellationToken ct)
    {
        await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);const string sql="""SELECT
          COALESCE((SELECT migration_id FROM public.schema_migrations ORDER BY applied_at DESC LIMIT 1),'None'),
          COALESCE((SELECT count(*)::int FROM udrive.notifications WHERE delivery_status='Failed'),0),
          COALESCE((SELECT count(DISTINCT b.id)::int FROM udrive.bookings b LEFT JOIN LATERAL(SELECT recorded_at FROM udrive.live_locations WHERE booking_id=b.id ORDER BY recorded_at DESC LIMIT 1)ll ON true WHERE b.status IN('DriverEnRoute','DriverArrived','TripStarted','Emergency') AND (ll.recorded_at IS NULL OR ll.recorded_at<now()-interval '60 seconds')),0),
          COALESCE((SELECT count(*)::int FROM udrive.emergency_cases WHERE status NOT IN('Resolved','FalseAlarm')),0),
          COALESCE((SELECT count(*)::int FROM udrive.dispute_cases WHERE status NOT IN('Resolved','Rejected','Closed')),0)""";await using var cmd=new NpgsqlCommand(sql,c);await using var r=await cmd.ExecuteReaderAsync(ct);await r.ReadAsync(ct);return ServiceResult<DiagnosticsDto>.Ok(new("Healthy","Connected",r.GetString(0),0,r.GetInt32(1),r.GetInt32(2),r.GetInt32(3),r.GetInt32(4),DateTimeOffset.UtcNow));
    }

    public async Task<ServiceResult<IReadOnlyList<AuditRowDto>>> AuditAsync(string? search,CancellationToken ct)
    {
        const string sql="""SELECT a.id,u.full_name,a.action,a.entity_type,a.entity_id,a.changes_json::text,a.created_at FROM udrive.audit_logs a LEFT JOIN udrive.users u ON u.id=a.actor_user_id WHERE (@q IS NULL OR a.action ILIKE @q OR a.entity_type ILIKE @q OR a.entity_id ILIKE @q OR COALESCE(u.full_name,'') ILIKE @q) ORDER BY a.created_at DESC LIMIT 500""";var list=new List<AuditRowDto>();await using var c=new NpgsqlConnection(connectionString);await c.OpenAsync(ct);await using var cmd=new NpgsqlCommand(sql,c);cmd.Parameters.Add(new("q",NpgsqlDbType.Varchar){Value=string.IsNullOrWhiteSpace(search)?DBNull.Value:$"%{search.Trim()}%"});await using var r=await cmd.ExecuteReaderAsync(ct);while(await r.ReadAsync(ct))list.Add(new(r.GetGuid(0),r.IsDBNull(1)?null:r.GetString(1),r.GetString(2),r.GetString(3),r.GetString(4),r.GetString(5),r.GetFieldValue<DateTimeOffset>(6)));return ServiceResult<IReadOnlyList<AuditRowDto>>.Ok(list);
    }
}
