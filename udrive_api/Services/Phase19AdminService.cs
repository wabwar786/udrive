using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

public sealed class Phase19AdminService(string connectionString)
{
    public async Task<ServiceResult<ExecutiveDashboardDto>> DashboardAsync(
        DateTimeOffset? from,
        DateTimeOffset? to,
        CancellationToken ct)
    {
        var end = to ?? DateTimeOffset.UtcNow;
        var start = from ?? end.AddDays(-7);
        var duration = end - start;
        var previousStart = start - duration;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);

        async Task<decimal> ScalarAsync(string sql, DateTimeOffset rangeStart, DateTimeOffset rangeEnd)
        {
            await using var command = new NpgsqlCommand(sql, connection);
            command.Parameters.AddWithValue("a", rangeStart);
            command.Parameters.AddWithValue("b", rangeEnd);
            return Convert.ToDecimal(await command.ExecuteScalarAsync(ct) ?? 0);
        }

        static decimal CalculateChange(decimal current, decimal previous) =>
            previous == 0
                ? current == 0 ? 0 : 100
                : Math.Round((current - previous) / previous * 100, 1);

        var definitions = new (string Label, string Sql, string Tone)[]
        {
            ("Bookings", "SELECT count(*) FROM udrive.bookings WHERE created_at >= @a AND created_at < @b", "blue"),
            ("Completed trips", "SELECT count(*) FROM udrive.bookings WHERE status IN ('TripCompleted','Completed') AND updated_at >= @a AND updated_at < @b", "green"),
            ("Gross booking value", "SELECT COALESCE(sum(total_amount),0) FROM udrive.bookings WHERE created_at >= @a AND created_at < @b", "purple"),
            ("Amount collected", "SELECT COALESCE(sum(amount-refund_amount),0) FROM udrive.payments WHERE status IN ('Paid','Verified') AND created_at >= @a AND created_at < @b", "green"),
            ("Platform commission", "SELECT COALESCE(sum(commission_amount),0) FROM udrive.driver_earnings WHERE created_at >= @a AND created_at < @b", "orange"),
            ("Driver earnings", "SELECT COALESCE(sum(net_amount),0) FROM udrive.driver_earnings WHERE created_at >= @a AND created_at < @b", "blue")
        };

        var metrics = new List<ExecutiveMetricDto>();
        foreach (var definition in definitions)
        {
            var current = await ScalarAsync(definition.Sql, start, end);
            var previous = await ScalarAsync(definition.Sql, previousStart, start);
            metrics.Add(new ExecutiveMetricDto(
                definition.Label,
                current,
                previous,
                CalculateChange(current, previous),
                definition.Tone));
        }

        var statuses = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        const string statusSql = "SELECT status, count(*)::int FROM udrive.bookings GROUP BY status ORDER BY count(*) DESC";
        await using (var command = new NpgsqlCommand(statusSql, connection))
        await using (var reader = await command.ExecuteReaderAsync(ct))
        {
            while (await reader.ReadAsync(ct))
            {
                statuses[reader.GetString(0)] = reader.GetInt32(1);
            }
        }

        var queues = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        const string queueSql = @"
SELECT
    (SELECT count(*)::int FROM udrive.driver_profiles WHERE verification_status IN ('Pending','Submitted','ChangesRequired')),
    (SELECT count(*)::int FROM udrive.vehicles WHERE verification_status IN ('Pending','Submitted','ChangesRequired')),
    (SELECT count(*)::int FROM udrive.tour_packages WHERE status IN ('Pending','Submitted')),
    (SELECT count(*)::int FROM udrive.driver_payout_requests WHERE status = 'Pending'),
    (SELECT count(*)::int FROM udrive.refund_requests WHERE status = 'Pending'),
    (SELECT count(*)::int FROM udrive.dispute_cases WHERE status NOT IN ('Resolved','Rejected','Closed')),
    (SELECT count(*)::int FROM udrive.emergency_cases WHERE status NOT IN ('Resolved','FalseAlarm'));";

        await using (var command = new NpgsqlCommand(queueSql, connection))
        await using (var reader = await command.ExecuteReaderAsync(ct))
        {
            if (await reader.ReadAsync(ct))
            {
                queues["drivers"] = reader.GetInt32(0);
                queues["vehicles"] = reader.GetInt32(1);
                queues["packages"] = reader.GetInt32(2);
                queues["payouts"] = reader.GetInt32(3);
                queues["refunds"] = reader.GetInt32(4);
                queues["disputes"] = reader.GetInt32(5);
                queues["emergencies"] = reader.GetInt32(6);
            }
        }

        var activity = new List<ExecutiveActivityDto>();
        const string activitySql = @"
SELECT type, title, subtitle, status, occurred_at
FROM (
    SELECT
        'Booking' AS type,
        'Booking ' || COALESCE(booking_reference, left(id::text, 8)) AS title,
        booking_type || ' · ' || status AS subtitle,
        status,
        updated_at AS occurred_at
    FROM udrive.bookings
    UNION ALL
    SELECT 'Emergency', case_reference, emergency_type || ' · ' || status, status, updated_at
    FROM udrive.emergency_cases
    UNION ALL
    SELECT 'Dispute', reference, category || ' · ' || status, status, updated_at
    FROM udrive.dispute_cases
) AS activity
ORDER BY occurred_at DESC
LIMIT 12;";

        await using (var command = new NpgsqlCommand(activitySql, connection))
        await using (var reader = await command.ExecuteReaderAsync(ct))
        {
            while (await reader.ReadAsync(ct))
            {
                activity.Add(new ExecutiveActivityDto(
                    reader.GetString(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetFieldValue<DateTimeOffset>(4)));
            }
        }

        return ServiceResult<ExecutiveDashboardDto>.Ok(
            new ExecutiveDashboardDto(metrics, statuses, queues, activity));
    }

    public async Task<ServiceResult<IReadOnlyList<LiveOperationDto>>> LiveOperationsAsync(CancellationToken ct)
    {
        const string sql = @"
SELECT
    b.id,
    COALESCE(b.booking_reference, left(b.id::text, 8)),
    b.booking_type,
    b.status,
    customer.full_name,
    driver.full_name,
    CASE WHEN vehicle.id IS NULL THEN NULL ELSE trim(vehicle.make || ' ' || vehicle.model) END,
    vehicle.registration_number,
    COALESCE(request.pickup_label, package.starting_city, 'Pickup') || ' → ' ||
        COALESCE(request.destination_label, destination.name, 'Destination'),
    b.pickup_at,
    ST_Y(location.location::geometry),
    ST_X(location.location::geometry),
    location.recorded_at,
    (location.recorded_at IS NULL OR location.recorded_at < now() - interval '60 seconds'),
    EXISTS (
        SELECT 1
        FROM udrive.emergency_cases emergency
        WHERE emergency.booking_id = b.id
          AND emergency.status NOT IN ('Resolved','FalseAlarm')
    )
FROM udrive.bookings b
JOIN udrive.users customer ON customer.id = b.customer_user_id
LEFT JOIN udrive.driver_profiles profile ON profile.id = b.driver_profile_id
LEFT JOIN udrive.users driver ON driver.id = profile.user_id
LEFT JOIN udrive.vehicles vehicle ON vehicle.id = b.vehicle_id
LEFT JOIN udrive.ride_requests request ON request.id = b.ride_request_id
LEFT JOIN udrive.tour_packages package ON package.id = b.tour_package_id
LEFT JOIN udrive.destinations destination ON destination.id = package.destination_id
LEFT JOIN LATERAL (
    SELECT live.location, live.recorded_at
    FROM udrive.live_locations live
    WHERE live.booking_id = b.id
    ORDER BY live.recorded_at DESC
    LIMIT 1
) location ON true
WHERE b.status IN (
    'DriverAssigned','DriverAccepted','DriverEnRoute','DriverArrived',
    'TripStarted','Emergency','Boarding','Departed','InProgress'
)
ORDER BY b.pickup_at;";

        var list = new List<LiveOperationDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(ct);

        while (await reader.ReadAsync(ct))
        {
            list.Add(new LiveOperationDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetString(6),
                reader.IsDBNull(7) ? null : reader.GetString(7),
                reader.GetString(8),
                reader.GetFieldValue<DateTimeOffset>(9),
                reader.IsDBNull(10) ? null : reader.GetDouble(10),
                reader.IsDBNull(11) ? null : reader.GetDouble(11),
                reader.IsDBNull(12) ? null : reader.GetFieldValue<DateTimeOffset>(12),
                reader.GetBoolean(13),
                reader.GetBoolean(14)));
        }

        return ServiceResult<IReadOnlyList<LiveOperationDto>>.Ok(list);
    }

    public async Task<ServiceResult<IReadOnlyList<AdminBookingRowDto>>> BookingsAsync(
        string? search,
        string? status,
        DateTimeOffset? from,
        DateTimeOffset? to,
        CancellationToken ct)
    {
        const string sql = @"
SELECT
    b.id,
    COALESCE(b.booking_reference, left(b.id::text, 8)),
    b.booking_type,
    b.status,
    customer.full_name,
    driver.full_name,
    CASE WHEN vehicle.id IS NULL THEN NULL ELSE trim(vehicle.make || ' ' || vehicle.model) END,
    COALESCE(request.pickup_label, package.starting_city, 'Pickup') || ' → ' ||
        COALESCE(request.destination_label, destination.name, 'Destination'),
    b.seats_booked,
    b.total_amount,
    COALESCE((
        SELECT sum(payment.amount - payment.refund_amount)
        FROM udrive.payments payment
        WHERE payment.booking_id = b.id
          AND payment.status IN ('Paid','Verified')
    ), 0),
    b.remaining_amount,
    b.pickup_at,
    b.created_at
FROM udrive.bookings b
JOIN udrive.users customer ON customer.id = b.customer_user_id
LEFT JOIN udrive.driver_profiles profile ON profile.id = b.driver_profile_id
LEFT JOIN udrive.users driver ON driver.id = profile.user_id
LEFT JOIN udrive.vehicles vehicle ON vehicle.id = b.vehicle_id
LEFT JOIN udrive.ride_requests request ON request.id = b.ride_request_id
LEFT JOIN udrive.tour_packages package ON package.id = b.tour_package_id
LEFT JOIN udrive.destinations destination ON destination.id = package.destination_id
WHERE (@status IS NULL OR b.status = @status)
  AND (@from IS NULL OR b.created_at >= @from)
  AND (@to IS NULL OR b.created_at < @to)
  AND (
      @query IS NULL
      OR COALESCE(b.booking_reference, '') ILIKE @query
      OR customer.full_name ILIKE @query
      OR COALESCE(driver.full_name, '') ILIKE @query
      OR COALESCE(vehicle.registration_number, '') ILIKE @query
  )
ORDER BY b.created_at DESC
LIMIT 500;";

        var list = new List<AdminBookingRowDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.Add(new NpgsqlParameter("status", NpgsqlDbType.Varchar)
        {
            Value = (object?)status ?? DBNull.Value
        });
        command.Parameters.Add(new NpgsqlParameter("from", NpgsqlDbType.TimestampTz)
        {
            Value = (object?)from ?? DBNull.Value
        });
        command.Parameters.Add(new NpgsqlParameter("to", NpgsqlDbType.TimestampTz)
        {
            Value = (object?)to ?? DBNull.Value
        });
        command.Parameters.Add(new NpgsqlParameter("query", NpgsqlDbType.Varchar)
        {
            Value = string.IsNullOrWhiteSpace(search)
                ? DBNull.Value
                : $"%{search.Trim()}%"
        });

        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            list.Add(new AdminBookingRowDto(
                reader.GetGuid(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetString(4),
                reader.IsDBNull(5) ? null : reader.GetString(5),
                reader.IsDBNull(6) ? null : reader.GetString(6),
                reader.GetString(7),
                reader.GetInt32(8),
                reader.GetDecimal(9),
                reader.GetDecimal(10),
                reader.GetDecimal(11),
                reader.GetFieldValue<DateTimeOffset>(12),
                reader.GetFieldValue<DateTimeOffset>(13)));
        }

        return ServiceResult<IReadOnlyList<AdminBookingRowDto>>.Ok(list);
    }

    public async Task<ServiceResult<FinanceReconciliationDto>> FinanceAsync(
        DateTimeOffset? from,
        DateTimeOffset? to,
        CancellationToken ct)
    {
        var rangeStart = from ?? DateTimeOffset.UtcNow.AddDays(-30);
        var rangeEnd = to ?? DateTimeOffset.UtcNow;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);

        const string totalsSql = @"
SELECT
    COALESCE((SELECT sum(total_amount) FROM udrive.bookings WHERE created_at >= @from AND created_at < @to), 0),
    COALESCE((SELECT sum(amount) FROM udrive.payments WHERE status IN ('Paid','Verified') AND created_at >= @from AND created_at < @to), 0),
    COALESCE((SELECT sum(refund_amount) FROM udrive.payments WHERE created_at >= @from AND created_at < @to), 0),
    COALESCE((SELECT sum(commission_amount) FROM udrive.driver_earnings WHERE created_at >= @from AND created_at < @to), 0),
    COALESCE((SELECT sum(net_amount) FROM udrive.driver_earnings WHERE created_at >= @from AND created_at < @to), 0),
    COALESCE((SELECT sum(amount) FROM udrive.driver_payout_requests WHERE status = 'Paid' AND paid_at >= @from AND paid_at < @to), 0),
    COALESCE((SELECT sum(remaining_amount) FROM udrive.bookings WHERE status NOT IN ('Cancelled','Refunded') AND created_at >= @from AND created_at < @to), 0);";

        decimal gross;
        decimal collected;
        decimal refunded;
        decimal commission;
        decimal earnings;
        decimal paidOut;
        decimal outstanding;

        await using (var command = new NpgsqlCommand(totalsSql, connection))
        {
            command.Parameters.AddWithValue("from", rangeStart);
            command.Parameters.AddWithValue("to", rangeEnd);
            await using var reader = await command.ExecuteReaderAsync(ct);
            await reader.ReadAsync(ct);
            gross = reader.GetDecimal(0);
            collected = reader.GetDecimal(1);
            refunded = reader.GetDecimal(2);
            commission = reader.GetDecimal(3);
            earnings = reader.GetDecimal(4);
            paidOut = reader.GetDecimal(5);
            outstanding = reader.GetDecimal(6);
        }

        const string mismatchSql = @"
SELECT
    b.id,
    COALESCE(b.booking_reference, left(b.id::text, 8)),
    b.total_amount,
    COALESCE(sum(payment.amount) FILTER (WHERE payment.status IN ('Paid','Verified')), 0),
    COALESCE(sum(payment.refund_amount), 0),
    COALESCE(earning.net_amount, 0),
    b.total_amount
        - COALESCE(sum(payment.amount) FILTER (WHERE payment.status IN ('Paid','Verified')), 0)
        + COALESCE(sum(payment.refund_amount), 0)
FROM udrive.bookings b
LEFT JOIN udrive.payments payment ON payment.booking_id = b.id
LEFT JOIN udrive.driver_earnings earning ON earning.booking_id = b.id
WHERE b.created_at >= @from AND b.created_at < @to
GROUP BY b.id, b.booking_reference, b.total_amount, b.remaining_amount, earning.net_amount
HAVING abs(
    b.total_amount
    - COALESCE(sum(payment.amount) FILTER (WHERE payment.status IN ('Paid','Verified')), 0)
    + COALESCE(sum(payment.refund_amount), 0)
    - b.remaining_amount
) > 0.01
ORDER BY b.created_at DESC
LIMIT 100;";

        var mismatches = new List<FinanceMismatchDto>();
        await using (var command = new NpgsqlCommand(mismatchSql, connection))
        {
            command.Parameters.AddWithValue("from", rangeStart);
            command.Parameters.AddWithValue("to", rangeEnd);
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                mismatches.Add(new FinanceMismatchDto(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.GetDecimal(2),
                    reader.GetDecimal(3),
                    reader.GetDecimal(4),
                    reader.GetDecimal(5),
                    reader.GetDecimal(6)));
            }
        }

        var difference = gross - collected + refunded - outstanding;
        return ServiceResult<FinanceReconciliationDto>.Ok(
            new FinanceReconciliationDto(
                gross,
                collected,
                refunded,
                commission,
                earnings,
                paidOut,
                outstanding,
                difference,
                mismatches));
    }

    public async Task<ServiceResult<IReadOnlyList<ReportRowDto>>> ReportAsync(
        DateTimeOffset? from,
        DateTimeOffset? to,
        CancellationToken ct)
    {
        const string sql = @"
SELECT
    to_char(date_trunc('day', booking.created_at), 'YYYY-MM-DD'),
    count(*)::int,
    count(*) FILTER (WHERE booking.status IN ('Completed','TripCompleted'))::int,
    count(*) FILTER (WHERE booking.status = 'Cancelled')::int,
    COALESCE(sum(booking.total_amount), 0),
    COALESCE(sum(payment.paid), 0),
    COALESCE(sum(earning.commission_amount), 0),
    COALESCE(sum(earning.net_amount), 0),
    COALESCE(sum(payment.refunded), 0)
FROM udrive.bookings booking
LEFT JOIN LATERAL (
    SELECT
        sum(amount) FILTER (WHERE status IN ('Paid','Verified')) AS paid,
        sum(refund_amount) AS refunded
    FROM udrive.payments
    WHERE booking_id = booking.id
) payment ON true
LEFT JOIN udrive.driver_earnings earning ON earning.booking_id = booking.id
WHERE booking.created_at >= @from AND booking.created_at < @to
GROUP BY date_trunc('day', booking.created_at)
ORDER BY date_trunc('day', booking.created_at) DESC;";

        var list = new List<ReportRowDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("from", from ?? DateTimeOffset.UtcNow.AddDays(-30));
        command.Parameters.AddWithValue("to", to ?? DateTimeOffset.UtcNow);
        await using var reader = await command.ExecuteReaderAsync(ct);

        while (await reader.ReadAsync(ct))
        {
            list.Add(new ReportRowDto(
                reader.GetString(0),
                reader.GetInt32(1),
                reader.GetInt32(2),
                reader.GetInt32(3),
                reader.GetDecimal(4),
                reader.GetDecimal(5),
                reader.GetDecimal(6),
                reader.GetDecimal(7),
                reader.GetDecimal(8)));
        }

        return ServiceResult<IReadOnlyList<ReportRowDto>>.Ok(list);
    }

    public async Task<ServiceResult<DiagnosticsDto>> DiagnosticsAsync(CancellationToken ct)
    {
        const string sql = @"
SELECT
    COALESCE((SELECT migration_id FROM public.schema_migrations ORDER BY applied_at DESC LIMIT 1), 'None'),
    COALESCE((SELECT count(*)::int FROM udrive.notifications WHERE delivery_status = 'Failed'), 0),
    COALESCE((
        SELECT count(DISTINCT booking.id)::int
        FROM udrive.bookings booking
        LEFT JOIN LATERAL (
            SELECT recorded_at
            FROM udrive.live_locations
            WHERE booking_id = booking.id
            ORDER BY recorded_at DESC
            LIMIT 1
        ) location ON true
        WHERE booking.status IN ('DriverEnRoute','DriverArrived','TripStarted','Emergency')
          AND (location.recorded_at IS NULL OR location.recorded_at < now() - interval '60 seconds')
    ), 0),
    COALESCE((SELECT count(*)::int FROM udrive.emergency_cases WHERE status NOT IN ('Resolved','FalseAlarm')), 0),
    COALESCE((SELECT count(*)::int FROM udrive.dispute_cases WHERE status NOT IN ('Resolved','Rejected','Closed')), 0);";

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        await using var reader = await command.ExecuteReaderAsync(ct);
        await reader.ReadAsync(ct);

        return ServiceResult<DiagnosticsDto>.Ok(new DiagnosticsDto(
            "Healthy",
            "Connected",
            reader.GetString(0),
            0,
            reader.GetInt32(1),
            reader.GetInt32(2),
            reader.GetInt32(3),
            reader.GetInt32(4),
            DateTimeOffset.UtcNow));
    }

    public async Task<ServiceResult<IReadOnlyList<AuditRowDto>>> AuditAsync(
        string? search,
        CancellationToken ct)
    {
        const string sql = @"
SELECT
    audit.id,
    actor.full_name,
    audit.action,
    audit.entity_type,
    audit.entity_id,
    audit.changes_json::text,
    audit.created_at
FROM udrive.audit_logs audit
LEFT JOIN udrive.users actor ON actor.id = audit.actor_user_id
WHERE (
    @query IS NULL
    OR audit.action ILIKE @query
    OR audit.entity_type ILIKE @query
    OR audit.entity_id ILIKE @query
    OR COALESCE(actor.full_name, '') ILIKE @query
)
ORDER BY audit.created_at DESC
LIMIT 500;";

        var list = new List<AuditRowDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.Add(new NpgsqlParameter("query", NpgsqlDbType.Varchar)
        {
            Value = string.IsNullOrWhiteSpace(search)
                ? DBNull.Value
                : $"%{search.Trim()}%"
        });
        await using var reader = await command.ExecuteReaderAsync(ct);

        while (await reader.ReadAsync(ct))
        {
            list.Add(new AuditRowDto(
                reader.GetGuid(0),
                reader.IsDBNull(1) ? null : reader.GetString(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.GetString(4),
                reader.GetString(5),
                reader.GetFieldValue<DateTimeOffset>(6)));
        }

        return ServiceResult<IReadOnlyList<AuditRowDto>>.Ok(list);
    }
}
