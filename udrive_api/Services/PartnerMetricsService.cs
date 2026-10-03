using Npgsql;
using NpgsqlTypes;

namespace UDrive.Api.Services;

/// <summary>
/// One territory, one month, all the numbers — and the only place they are
/// calculated.
/// </summary>
/// <remarks>
/// Three screens show these figures: the admin's partner detail, the partner's
/// own portal, and the monthly statement. If each worked them out for itself,
/// the partner and the admin would eventually be looking at two different
/// numbers for the same month, and there is no way to settle that argument
/// afterwards. So all three read this class.
///
/// <para><b>What counts as "in the territory"</b> is the part worth reading
/// twice. A driver belongs to a territory in one of two ways:</para>
///
/// <list type="bullet">
/// <item><c>territory_id</c> set — an admin has placed this driver in a specific
/// node (usually a tehsil). They count for that node and every node above it.</item>
/// <item><c>territory_id</c> null, <c>launch_city_id</c> set — which every driver
/// already has. They count for their city and its region, and for no tehsil.</item>
/// </list>
///
/// <para>That second rule is why a Tehsil Head's screen carries a sentence
/// rather than a zero. The schema has never known which tehsil a driver works
/// in, and inferring it from a GPS point would be a guess presented as a fact in
/// a document somebody signed.</para>
///
/// <para><b>The share base is commission, never the fare.</b> It is read from
/// <c>driver_earnings.commission_amount</c> — what the business actually kept on
/// that ride, after the driver's cut. A share of the fare looks like a smaller
/// number and is a far larger one.</para>
/// </remarks>
public sealed class PartnerMetricsService(string connectionString)
{
    /// <summary>Everything one territory did in one month.</summary>
    public sealed record TerritorySnapshot(
        int DriversTotal,
        int NewDrivers,
        int ActiveDrivers,
        int CompletedRides,
        decimal GrossFares,
        decimal CommissionBase,
        int NewSubPartners,
        // False for a tehsil with nobody assigned to it, which is the normal
        // state on day one and needs saying rather than showing as zero.
        bool HasAssignedDrivers);

    /// <summary>
    /// The driver set for a territory and everything beneath it.
    /// </summary>
    /// <remarks>
    /// Written once, as a constant, because it appeared in six queries while
    /// this was being built and two of them had drifted apart by the time the
    /// third was written.
    /// </remarks>
    public const string SubtreeCte = """
        WITH RECURSIVE sub AS (
            SELECT id, launch_city_id
            FROM udrive.territories
            WHERE id = @territory
            UNION ALL
            SELECT c.id, c.launch_city_id
            FROM udrive.territories c
            JOIN sub s ON c.parent_id = s.id
        ), drv AS (
            SELECT d.id
            FROM udrive.driver_profiles d
            WHERE d.territory_id IN (SELECT id FROM sub)
               OR (d.territory_id IS NULL
                   AND d.launch_city_id IN (
                       SELECT launch_city_id FROM sub WHERE launch_city_id IS NOT NULL))
        )
        """;

    private NpgsqlConnection Open() => new(connectionString);

    public async Task<TerritorySnapshot> SnapshotAsync(
        Guid territoryId,
        DateOnly periodStart,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        return await SnapshotAsync(connection, territoryId, periodStart, cancellationToken);
    }

    /// <param name="periodStart">
    /// The first of the month. The window used is [periodStart, +1 month), which
    /// is the only window that makes two adjacent months add up to the pair.
    /// </param>
    public static async Task<TerritorySnapshot> SnapshotAsync(
        NpgsqlConnection connection,
        Guid territoryId,
        DateOnly periodStart,
        CancellationToken cancellationToken)
    {
        // One round trip, scalar subqueries over the same two CTEs. Six
        // separate queries would each walk the tree again.
        //
        // `coalesce` on every sum: SUM() over no rows is NULL, not zero, and a
        // NULL reaching `reader.GetDecimal` is an exception on the first day of
        // a new month in a city with no rides yet.
        const string sql = SubtreeCte + """
            SELECT
                (SELECT count(*) FROM drv),
                (SELECT count(*) FROM udrive.driver_profiles d
                   WHERE d.id IN (SELECT id FROM drv)
                     AND d.approved_at >= @from AND d.approved_at < @to),
                (SELECT count(DISTINCT e.driver_profile_id)
                   FROM udrive.driver_earnings e
                   JOIN udrive.bookings b ON b.id = e.booking_id
                  WHERE e.driver_profile_id IN (SELECT id FROM drv)
                    AND b.status = 'Completed'
                    AND e.created_at >= @from AND e.created_at < @to),
                (SELECT count(*)
                   FROM udrive.driver_earnings e
                   JOIN udrive.bookings b ON b.id = e.booking_id
                  WHERE e.driver_profile_id IN (SELECT id FROM drv)
                    AND b.status = 'Completed'
                    AND e.created_at >= @from AND e.created_at < @to),
                (SELECT coalesce(sum(e.gross_amount), 0)
                   FROM udrive.driver_earnings e
                   JOIN udrive.bookings b ON b.id = e.booking_id
                  WHERE e.driver_profile_id IN (SELECT id FROM drv)
                    AND b.status = 'Completed'
                    AND e.created_at >= @from AND e.created_at < @to),
                (SELECT coalesce(sum(e.commission_amount), 0)
                   FROM udrive.driver_earnings e
                   JOIN udrive.bookings b ON b.id = e.booking_id
                  WHERE e.driver_profile_id IN (SELECT id FROM drv)
                    AND b.status = 'Completed'
                    AND e.created_at >= @from AND e.created_at < @to),
                -- Partners under this node, not this node itself: a Regional
                -- Head's commitment is the City and Tehsil Heads they bring.
                (SELECT count(*) FROM udrive.partners p
                  WHERE p.territory_id IN (SELECT id FROM sub WHERE id <> @territory)
                    AND p.started_at >= @from AND p.started_at < @to),
                (SELECT EXISTS(SELECT 1 FROM udrive.driver_profiles d
                                WHERE d.territory_id IN (SELECT id FROM sub)));
            """;

        var from = new DateTime(periodStart.Year, periodStart.Month, 1, 0, 0, 0, DateTimeKind.Utc);
        var to = from.AddMonths(1);

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("territory", territoryId);
        command.Parameters.AddWithValue("from", from);
        command.Parameters.AddWithValue("to", to);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return new TerritorySnapshot(0, 0, 0, 0, 0m, 0m, 0, false);
        }

        return new TerritorySnapshot(
            (int)reader.GetInt64(0),
            (int)reader.GetInt64(1),
            (int)reader.GetInt64(2),
            (int)reader.GetInt64(3),
            reader.GetDecimal(4),
            reader.GetDecimal(5),
            (int)reader.GetInt64(6),
            reader.GetBoolean(7));
    }

    public static decimal MetricValue(TerritorySnapshot snapshot, string metricKey) =>
        metricKey switch
        {
            "NewDrivers" => snapshot.NewDrivers,
            "ActiveDrivers" => snapshot.ActiveDrivers,
            "CompletedRides" => snapshot.CompletedRides,
            "NewSubPartners" => snapshot.NewSubPartners,
            // Manual, and anything a later migration adds that this build does
            // not know about. Returning zero here would quietly mark a
            // commitment missed; leaving it to the recorded value does not.
            _ => 0m,
        };

    public static bool IsManual(string metricKey) =>
        !(metricKey is "NewDrivers" or "ActiveDrivers" or "CompletedRides" or "NewSubPartners");

    public static DateOnly MonthStart(DateTimeOffset moment) =>
        new(moment.Year, moment.Month, 1);

    public static DateOnly MonthEnd(DateOnly start) =>
        start.AddMonths(1).AddDays(-1);

    /// <summary>
    /// Writes this month's commitment rows and statement for one contract, and
    /// closes off any earlier month still left Open.
    /// </summary>
    /// <remarks>
    /// Called from the admin's "Recompute" button, from the partner portal when
    /// it loads, and from the statement list. Safe to call repeatedly: every
    /// write is an upsert keyed on (commitment, month) or (contract, month).
    ///
    /// <para>Two rules it will not break:</para>
    /// <list type="bullet">
    /// <item>A period or statement that is no longer Open is never rewritten. A
    /// month an admin has agreed, or marked paid, is settled — recomputing it
    /// because somebody opened a screen would move a number somebody has already
    /// been paid against.</item>
    /// <item>A Manual commitment's <c>actual_value</c> is never touched. Nobody
    /// reported it; a computed zero would read as a reported zero.</item>
    /// </list>
    /// </remarks>
    public async Task RecomputeAsync(
        Guid contractId,
        CancellationToken cancellationToken)
    {
        await using var connection = Open();
        await connection.OpenAsync(cancellationToken);
        await RecomputeAsync(connection, contractId, cancellationToken);
    }

    public static async Task RecomputeAsync(
        NpgsqlConnection connection,
        Guid contractId,
        CancellationToken cancellationToken)
    {
        // The contract, its territory, and the months it has been running.
        const string headSql = """
            SELECT c.id, c.commission_share_pct, c.status,
                   coalesce(c.signed_at, c.sent_at, c.created_at),
                   c.ends_at, p.territory_id
            FROM udrive.partner_contracts c
            JOIN udrive.partners p ON p.id = c.partner_id
            WHERE c.id = @contract;
            """;

        Guid territoryId;
        decimal sharePct;
        DateTimeOffset startedAt;
        DateTimeOffset? endsAt;
        string status;

        await using (var head = new NpgsqlCommand(headSql, connection))
        {
            head.Parameters.AddWithValue("contract", contractId);
            await using var reader = await head.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return;
            }

            sharePct = reader.GetDecimal(1);
            status = reader.GetString(2);
            startedAt = reader.GetFieldValue<DateTimeOffset>(3);
            endsAt = reader.IsDBNull(4) ? null : reader.GetFieldValue<DateTimeOffset>(4);
            territoryId = reader.GetGuid(5);
        }

        // An unsigned contract has no months. Writing statements for a Draft
        // would show a partner money against an agreement they have not read.
        if (status is not ("Signed" or "Terminated"))
        {
            return;
        }

        var first = MonthStart(startedAt);
        var last = MonthStart(endsAt is not null && endsAt < DateTimeOffset.UtcNow
            ? endsAt.Value
            : DateTimeOffset.UtcNow);

        // A long-running contract still only needs the months nobody has agreed
        // yet. Twelve is a generous backstop against a job that has not run for
        // a while, and a cap against walking five years of history on a page load.
        var earliest = last.AddMonths(-11);
        if (first < earliest)
        {
            first = earliest;
        }

        for (var month = first; month <= last; month = month.AddMonths(1))
        {
            var snapshot = await SnapshotAsync(connection, territoryId, month, cancellationToken);
            var monthEnd = MonthEnd(month);
            var isCurrentMonth = month == MonthStart(DateTimeOffset.UtcNow);

            await UpsertPeriodsAsync(
                connection, contractId, month, monthEnd, snapshot, isCurrentMonth, cancellationToken);

            await UpsertStatementAsync(
                connection, contractId, month, monthEnd, snapshot, sharePct, cancellationToken);
        }
    }

    private static async Task UpsertPeriodsAsync(
        NpgsqlConnection connection,
        Guid contractId,
        DateOnly month,
        DateOnly monthEnd,
        TerritorySnapshot snapshot,
        bool isCurrentMonth,
        CancellationToken cancellationToken)
    {
        const string listSql = """
            SELECT id, metric_key, target_value
            FROM udrive.partner_commitments
            WHERE contract_id = @contract AND is_active
            ORDER BY sort_order, metric_key;
            """;

        var commitments = new List<(Guid Id, string Metric, decimal Target)>();
        await using (var list = new NpgsqlCommand(listSql, connection))
        {
            list.Parameters.AddWithValue("contract", contractId);
            await using var reader = await list.ExecuteReaderAsync(cancellationToken);
            while (await reader.ReadAsync(cancellationToken))
            {
                commitments.Add((reader.GetGuid(0), reader.GetString(1), reader.GetDecimal(2)));
            }
        }

        foreach (var (id, metric, target) in commitments)
        {
            var manual = IsManual(metric);
            var actual = MetricValue(snapshot, metric);

            // A month still running is Open whatever the number says — a target
            // reached on the 3rd can still be reached again by the 30th, and
            // marking it Met early makes the final figure look like a mistake.
            var computedStatus = isCurrentMonth
                ? "Open"
                : actual >= target ? "Met" : "Missed";

            const string upsertSql = """
                INSERT INTO udrive.partner_commitment_periods
                    (contract_id, commitment_id, period_start, period_end,
                     metric_key, target_value, actual_value, status, computed_at)
                VALUES (@contract, @commitment, @start, @end, @metric, @target,
                        @actual, @status, now())
                ON CONFLICT (commitment_id, period_start) DO UPDATE SET
                    -- Only a row still Open is recalculated, and a Manual
                    -- metric keeps whatever a person reported.
                    actual_value = CASE
                        WHEN udrive.partner_commitment_periods.status <> 'Open' THEN
                            udrive.partner_commitment_periods.actual_value
                        WHEN @manual THEN udrive.partner_commitment_periods.actual_value
                        ELSE excluded.actual_value END,
                    status = CASE
                        WHEN udrive.partner_commitment_periods.status <> 'Open' THEN
                            udrive.partner_commitment_periods.status
                        WHEN @manual THEN udrive.partner_commitment_periods.status
                        ELSE excluded.status END,
                    target_value = CASE
                        WHEN udrive.partner_commitment_periods.status <> 'Open' THEN
                            udrive.partner_commitment_periods.target_value
                        ELSE excluded.target_value END,
                    computed_at = now();
                """;

            await using var upsert = new NpgsqlCommand(upsertSql, connection);
            upsert.Parameters.AddWithValue("contract", contractId);
            upsert.Parameters.AddWithValue("commitment", id);
            AddDate(upsert, "start", month);
            AddDate(upsert, "end", monthEnd);
            upsert.Parameters.AddWithValue("metric", metric);
            upsert.Parameters.AddWithValue("target", target);
            upsert.Parameters.AddWithValue("actual", manual ? 0m : actual);
            upsert.Parameters.AddWithValue("status", manual ? "Open" : computedStatus);
            upsert.Parameters.AddWithValue("manual", manual);
            await upsert.ExecuteNonQueryAsync(cancellationToken);
        }
    }

    private static async Task UpsertStatementAsync(
        NpgsqlConnection connection,
        Guid contractId,
        DateOnly month,
        DateOnly monthEnd,
        TerritorySnapshot snapshot,
        decimal sharePct,
        CancellationToken cancellationToken)
    {
        // Rounded to whole rupees. A share of 1,124.9975 in one place and
        // 1,124.99 in another is the sort of difference that costs an hour on
        // the phone.
        var share = decimal.Round(snapshot.CommissionBase * sharePct / 100m, 2);

        const string sql = """
            INSERT INTO udrive.partner_month_statements
                (contract_id, period_start, period_end, completed_rides,
                 gross_fares, commission_base, share_pct, share_amount,
                 status, computed_at, created_at, updated_at)
            VALUES (@contract, @start, @end, @rides, @gross, @base, @pct, @share,
                    'Open', now(), now(), now())
            ON CONFLICT (contract_id, period_start) DO UPDATE SET
                completed_rides = CASE WHEN udrive.partner_month_statements.status = 'Open'
                    THEN excluded.completed_rides ELSE udrive.partner_month_statements.completed_rides END,
                gross_fares = CASE WHEN udrive.partner_month_statements.status = 'Open'
                    THEN excluded.gross_fares ELSE udrive.partner_month_statements.gross_fares END,
                commission_base = CASE WHEN udrive.partner_month_statements.status = 'Open'
                    THEN excluded.commission_base ELSE udrive.partner_month_statements.commission_base END,
                share_pct = CASE WHEN udrive.partner_month_statements.status = 'Open'
                    THEN excluded.share_pct ELSE udrive.partner_month_statements.share_pct END,
                share_amount = CASE WHEN udrive.partner_month_statements.status = 'Open'
                    THEN excluded.share_amount ELSE udrive.partner_month_statements.share_amount END,
                computed_at = now(),
                updated_at = now();
            """;

        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("contract", contractId);
        AddDate(command, "start", month);
        AddDate(command, "end", monthEnd);
        command.Parameters.AddWithValue("rides", snapshot.CompletedRides);
        command.Parameters.AddWithValue("gross", snapshot.GrossFares);
        command.Parameters.AddWithValue("base", snapshot.CommissionBase);
        command.Parameters.AddWithValue("pct", sharePct);
        command.Parameters.AddWithValue("share", share);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>
    /// A <c>date</c> parameter, typed rather than inferred.
    /// </summary>
    /// <remarks>
    /// The same helper the rental service uses. Npgsql can infer this, but a
    /// `DateOnly` inferred as a timestamp lands a day out in the wrong time
    /// zone, and the first of the month is exactly where that shows.
    /// </remarks>
    private static void AddDate(NpgsqlCommand command, string name, DateOnly value) =>
        command.Parameters.Add(new NpgsqlParameter(name, NpgsqlDbType.Date) { Value = value });
}
