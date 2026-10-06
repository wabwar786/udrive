using System.Globalization;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;

namespace UDrive.Api.Services;

// ─────────────────────────────────────────────────────────────── contracts

public sealed record ReportFilterDto(string Key, string Label, IReadOnlyList<string> Options, string Default);

public sealed record ReportCatalogItemDto(
    string Key, string Category, string Title, string Description, bool UsesDates, bool Trend,
    IReadOnlyList<ReportFilterDto> Filters);

public sealed record ReportAreaTehsilDto(Guid Id, string Name);

public sealed record ReportAreaDto(Guid Id, string Name, bool Selectable, IReadOnlyList<ReportAreaTehsilDto> Tehsils);

public sealed record ReportCatalogDto(
    bool SuperAdmin,
    bool AllAreas,
    string ScopeLabel,
    IReadOnlyList<string> Categories,
    IReadOnlyList<ReportCatalogItemDto> Reports,
    IReadOnlyList<ReportAreaDto> Areas);

public sealed record ReportTileDto(string Key, string Label, string Format, decimal? Value, decimal? Previous);

public sealed record ReportColumnDto(string Key, string Label, string Format, string? Total);

public sealed record ReportSeriesDto(string Key, string Label, string Kind);

public sealed record ReportChartDto(
    string Type, string Title, string LabelKey, IReadOnlyList<ReportSeriesDto> Series,
    IReadOnlyList<Dictionary<string, object?>> Points);

public sealed record ReportResultDto(
    string Key,
    string Category,
    string Title,
    string Description,
    string From,
    string To,
    string PreviousFrom,
    string PreviousTo,
    string ScopeLabel,
    IReadOnlyList<ReportTileDto> Tiles,
    ReportChartDto? Chart,
    IReadOnlyList<ReportColumnDto> Columns,
    IReadOnlyList<Dictionary<string, object?>> Rows,
    Dictionary<string, object?> Totals,
    bool Truncated);

public sealed record ReportQuery(string? From, string? To, Guid? Area, IReadOnlyDictionary<string, string> Filters);

public sealed record ReportAccessDto(
    Guid UserId,
    bool SuperAdmin,
    bool TeamUser,
    bool AllAreas,
    IReadOnlyList<Guid> AreaIds,
    IReadOnlyList<string> ReportKeys,
    IReadOnlyList<string> Categories,
    IReadOnlyList<ReportCatalogItemDto> Reports);

public sealed record SaveReportAccessRequest(IReadOnlyList<string>? ReportKeys, bool? AllAreas, IReadOnlyList<Guid>? AreaIds);

/// <summary>
/// The Reports Centre: about sixty reports over rides, drivers, money, tours,
/// rentals, hotels, safety and growth, each one limited to what the person
/// asking may see.
/// </summary>
/// <remarks>
/// <para><b>Who sees what.</b> SuperAdmin sees every report in every area.
/// Everyone else — Admin, Manager, Operations or a team user — sees only the
/// reports ticked for them (<c>staff_report_access</c>), and only for their
/// areas (<c>staff_areas</c>, or every area when <c>staff_profiles.all_areas</c>
/// is set). A district covers all its tehsils. The check is made here, on the
/// server, for every run; an area picked in the browser that is outside the
/// person's areas is refused, not filtered.</para>
///
/// <para><b>Where a row belongs.</b> A booking belongs to the tehsil of its
/// pickup (migration 074 keeps <c>bookings.territory_id</c>); a driver, vehicle,
/// hotel or business to its own area. Rows with no area are visible only to
/// people who see every area.</para>
///
/// <para><b>Shape.</b> Every report answers the same way: tiles (each with the
/// same figure for the previous period of equal length), one chart, and one
/// table with totals. A report is a definition below — its SQL and how to
/// present it — so a new report is one more entry, not a new endpoint.</para>
///
/// <para>Dates are Pakistan days. A range is at most 366 days, and a table
/// returns at most 2,000 rows (the result says when it was cut).</para>
/// </remarks>
public sealed class ReportsService(string connectionString)
{
    private const int MaxRows = 2000;
    private static readonly TimeSpan Pk = TimeSpan.FromHours(5);

    // ───────────────────────────────────────────── shared SQL pieces

    private const string BS = "(@all OR b.territory_id = ANY(@areas))";
    private const string RS = "(@all OR rr.territory_id = ANY(@areas))";
    private const string DS = "(@all OR dp.territory_id = ANY(@areas))";
    private const string VS = "(@all OR COALESCE(v.territory_id, dp.territory_id) = ANY(@areas))";
    private const string HS = "(@all OR h.territory_id = ANY(@areas))";

    private const string FROMB =
        "FROM udrive.bookings b LEFT JOIN udrive.trip_operations o ON o.booking_id = b.id " +
        "LEFT JOIN udrive.ride_requests rr ON rr.id = b.ride_request_id";

    private const string DONE = "(o.trip_status = 'TripCompleted' OR b.status = 'Completed')";
    private const string CANC = "(o.trip_status = 'Cancelled' OR b.status = 'Cancelled')";

    private const string KIND =
        "(CASE WHEN b.tour_package_id IS NOT NULL THEN 'Tour' " +
        "WHEN rr.id IS NOT NULL AND ST_Distance(rr.pickup_location, rr.destination_location) > 25000 THEN 'City-to-city' " +
        "ELSE 'City ride' END)";

    private const string KF = "(@f_kind = '' OR " + KIND + " = @f_kind)";

    private static string W(string column) => $"{column} >= @from AND {column} < @to";
    private static string TS(string column) => $"to_char({column} AT TIME ZONE 'Asia/Karachi', 'YYYY-MM-DD HH24:MI')";
    private static string DT(string column) => $"to_char({column} AT TIME ZONE 'Asia/Karachi', 'YYYY-MM-DD')";
    private static string B(string column) => $"udrive.report_bucket({column}, @gb)";

    private static readonly ReportFilterDto KindFilter =
        new("kind", "Ride type", ["City ride", "City-to-city", "Tour"], "");

    private static readonly ReportFilterDto LevelFilter =
        new("level", "Group by", ["tehsil", "district"], "tehsil");

    private static readonly ReportFilterDto MinTripsFilter =
        new("min", "Minimum trips", ["0", "1", "5", "10", "25"], "0");

    // ───────────────────────────────────────────── definitions

    private sealed record Col(string Key, string Label, string Format, string? Total = null);

    private sealed record Tile(string Key, string Label, string Format);

    private sealed record Chart(
        string Type, string Title, string LabelKey, (string Key, string Label, string Kind)[] Series,
        string? Sql = null, int Limit = 0);

    private sealed record Def(
        string Key,
        string Category,
        string Title,
        string Description,
        Tile[] Tiles,
        string TilesSql,
        Chart? Chart,
        Col[] Columns,
        string TableSql,
        ReportFilterDto[]? Filters = null,
        bool UsesDates = true,
        bool Trend = false,
        bool SuperOnly = false);

    public static readonly string[] Categories =
    [
        "Overview", "Rides", "Dispatch", "Drivers", "Vehicles", "Customers", "Finance",
        "Tours", "Rentals", "Hotels", "Safety & quality", "Verification", "Growth", "Team",
    ];

    private static readonly Def[] Defs = BuildDefs();

    public static IReadOnlyList<string> AllKeys => Defs.Select(d => d.Key).ToList();

    private static Def[] BuildDefs() =>
    [
        // ═════════════════════════════════════ Overview
        new("overview.summary", "Overview", "Summary dashboard",
            "The main figures for the period, with each area side by side.",
            [
                new("bookings", "Bookings", "int"), new("completed", "Completed", "int"),
                new("cancel_rate", "Cancellation rate", "pct"), new("revenue", "Revenue", "money"),
                new("commission", "Commission", "money"), new("drivers", "Active drivers", "int"),
                new("customers", "New customers", "int"), new("rating", "Average rating", "rating"),
            ],
            $$"""
            SELECT count(*) AS bookings,
                   count(*) FILTER (WHERE {{DONE}}) AS completed,
                   COALESCE(100.0 * count(*) FILTER (WHERE {{CANC}}) / NULLIF(count(*), 0), 0) AS cancel_rate,
                   COALESCE(sum(b.total_amount) FILTER (WHERE {{DONE}}), 0) AS revenue,
                   (SELECT COALESCE(sum(e.commission_amount), 0) FROM udrive.driver_earnings e
                      JOIN udrive.bookings b ON b.id = e.booking_id WHERE {{W("e.created_at")}} AND {{BS}}) AS commission,
                   count(DISTINCT b.driver_profile_id) FILTER (WHERE {{DONE}}) AS drivers,
                   count(DISTINCT b.customer_user_id) FILTER (WHERE NOT EXISTS (
                       SELECT 1 FROM udrive.bookings p WHERE p.customer_user_id = b.customer_user_id AND p.created_at < @from)) AS customers,
                   (SELECT avg(r.overall_rating) FROM udrive.trip_ratings r JOIN udrive.bookings b ON b.id = r.booking_id
                     WHERE r.reviewer_role = 'Customer' AND {{W("r.created_at")}} AND {{BS}}) AS rating
            {{FROMB}}
            WHERE {{W("b.created_at")}} AND {{BS}}
            """,
            new("line", "Bookings over time", "period",
                [("bookings", "Bookings", "line")],
                $$"""
                SELECT {{B("b.created_at")}} AS period, count(*) AS bookings,
                       COALESCE(sum(b.total_amount) FILTER (WHERE {{DONE}}), 0) AS revenue
                {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}} GROUP BY 1 ORDER BY 1
                """),
            [
                new("area", "Area", "text"), new("bookings", "Bookings", "int", "sum"),
                new("completed", "Completed", "int", "sum"), new("cancelled", "Cancelled", "int", "sum"),
                new("revenue", "Revenue", "money", "sum"), new("commission", "Commission", "money", "sum"),
                new("drivers", "Drivers", "int", "sum"), new("rating", "Rating", "rating", "avg"),
            ],
            $$"""
            SELECT udrive.area_label(b.territory_id) AS area, count(*) AS bookings,
                   count(*) FILTER (WHERE {{DONE}}) AS completed, count(*) FILTER (WHERE {{CANC}}) AS cancelled,
                   COALESCE(sum(b.total_amount) FILTER (WHERE {{DONE}}), 0) AS revenue,
                   COALESCE(sum(e.commission_amount), 0) AS commission,
                   count(DISTINCT b.driver_profile_id) FILTER (WHERE {{DONE}}) AS drivers,
                   avg(r.overall_rating) AS rating
            {{FROMB}}
            LEFT JOIN udrive.driver_earnings e ON e.booking_id = b.id
            LEFT JOIN udrive.trip_ratings r ON r.booking_id = b.id AND r.reviewer_role = 'Customer'
            WHERE {{W("b.created_at")}} AND {{BS}}
            GROUP BY b.territory_id ORDER BY revenue DESC
            """,
            Trend: true),

        new("overview.areas", "Overview", "Area comparison",
            "Every area in your scope against the others — by tehsil or by district.",
            [
                new("areas", "Areas with bookings", "int"), new("bookings", "Bookings", "int"),
                new("revenue", "Revenue", "money"), new("per_area", "Revenue per area", "money"),
            ],
            $$"""
            SELECT count(DISTINCT b.territory_id) AS areas, count(*) AS bookings,
                   COALESCE(sum(b.total_amount) FILTER (WHERE {{DONE}}), 0) AS revenue,
                   COALESCE(sum(b.total_amount) FILTER (WHERE {{DONE}}), 0) / NULLIF(count(DISTINCT b.territory_id), 0) AS per_area
            {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}}
            """,
            new("bar", "Revenue by area", "area", [("revenue", "Revenue", "bar")], Limit: 15),
            [
                new("area", "Area", "text"), new("bookings", "Bookings", "int", "sum"),
                new("completed_rate", "Completed %", "pct", "avg"), new("revenue", "Revenue", "money", "sum"),
                new("avg_fare", "Average fare", "money", "avg"), new("drivers", "Drivers", "int", "sum"),
                new("rating", "Rating", "rating", "avg"),
            ],
            $$"""
            SELECT udrive.area_label(x.area_id) AS area, count(*) AS bookings,
                   100.0 * count(*) FILTER (WHERE x.done) / NULLIF(count(*), 0) AS completed_rate,
                   COALESCE(sum(x.amount) FILTER (WHERE x.done), 0) AS revenue,
                   avg(x.amount) FILTER (WHERE x.done) AS avg_fare,
                   count(DISTINCT x.driver) FILTER (WHERE x.done) AS drivers,
                   avg(x.rating) AS rating
            FROM (
                SELECT CASE WHEN @f_level = 'district' THEN udrive.area_district(b.territory_id) ELSE b.territory_id END AS area_id,
                       {{DONE}} AS done, b.total_amount AS amount, b.driver_profile_id AS driver,
                       (SELECT avg(r.overall_rating) FROM udrive.trip_ratings r WHERE r.booking_id = b.id AND r.reviewer_role = 'Customer') AS rating
                {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}}
            ) x
            GROUP BY x.area_id ORDER BY revenue DESC
            """,
            [LevelFilter]),

        // ═════════════════════════════════════ Rides
        new("rides.trend", "Rides", "Rides trend",
            "Requests, bookings and completed rides by day, week or month.",
            [
                new("requests", "Ride requests", "int"), new("bookings", "Bookings", "int"),
                new("completed", "Completed", "int"), new("revenue", "Revenue", "money"),
            ],
            $$"""
            SELECT (SELECT count(*) FROM udrive.ride_requests rr WHERE {{W("rr.created_at")}} AND {{RS}}) AS requests,
                   count(*) AS bookings, count(*) FILTER (WHERE {{DONE}}) AS completed,
                   COALESCE(sum(b.total_amount) FILTER (WHERE {{DONE}}), 0) AS revenue
            {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}} AND {{KF}}
            """,
            new("line", "Rides over time", "period",
                [("requests", "Requests", "line"), ("bookings", "Bookings", "line"), ("completed", "Completed", "line")]),
            [
                new("period", "Period", "text"), new("requests", "Requests", "int", "sum"),
                new("bookings", "Bookings", "int", "sum"), new("completed", "Completed", "int", "sum"),
                new("cancelled", "Cancelled", "int", "sum"), new("noshow", "No-show", "int", "sum"),
                new("revenue", "Revenue", "money", "sum"),
            ],
            $$"""
            WITH bk AS (
                SELECT {{B("b.created_at")}} AS p, count(*) AS bookings,
                       count(*) FILTER (WHERE {{DONE}}) AS completed, count(*) FILTER (WHERE {{CANC}}) AS cancelled,
                       count(*) FILTER (WHERE o.trip_status = 'NoShow') AS noshow,
                       COALESCE(sum(b.total_amount) FILTER (WHERE {{DONE}}), 0) AS revenue
                {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}} AND {{KF}} GROUP BY 1),
            rq AS (
                SELECT {{B("rr.created_at")}} AS p, count(*) AS requests
                FROM udrive.ride_requests rr WHERE {{W("rr.created_at")}} AND {{RS}} GROUP BY 1)
            SELECT COALESCE(bk.p, rq.p) AS period, COALESCE(rq.requests, 0) AS requests,
                   COALESCE(bk.bookings, 0) AS bookings, COALESCE(bk.completed, 0) AS completed,
                   COALESCE(bk.cancelled, 0) AS cancelled, COALESCE(bk.noshow, 0) AS noshow,
                   COALESCE(bk.revenue, 0) AS revenue
            FROM bk FULL JOIN rq ON rq.p = bk.p ORDER BY 1
            """,
            [KindFilter], Trend: true),

        new("rides.status", "Rides", "Rides by status",
            "Where every booking of the period stands now.",
            [
                new("total", "Bookings", "int"), new("completed", "Completed", "int"),
                new("active", "In progress", "int"), new("cancelled", "Cancelled", "int"),
            ],
            $$"""
            SELECT count(*) AS total, count(*) FILTER (WHERE {{DONE}}) AS completed,
                   count(*) FILTER (WHERE o.trip_status IN ('DriverAccepted','DriverEnRoute','DriverArrived','TripStarted','Emergency')) AS active,
                   count(*) FILTER (WHERE {{CANC}}) AS cancelled
            {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}} AND {{KF}}
            """,
            new("donut", "Bookings by status", "status", [("count", "Bookings", "bar")]),
            [
                new("status", "Status", "badge"), new("count", "Bookings", "int", "sum"),
                new("share", "Share", "pct", "sum"), new("revenue", "Value", "money", "sum"),
            ],
            $$"""
            SELECT COALESCE(o.trip_status, b.status) AS status, count(*) AS count,
                   100.0 * count(*) / NULLIF(sum(count(*)) OVER (), 0) AS share,
                   COALESCE(sum(b.total_amount), 0) AS revenue
            {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}} AND {{KF}}
            GROUP BY 1 ORDER BY count DESC
            """,
            [KindFilter]),

        new("rides.type", "Rides", "Rides by type",
            "City rides, city-to-city, tours, rent-a-car and hotels side by side.",
            [
                new("bookings", "Bookings", "int"), new("completed", "Completed", "int"),
                new("revenue", "Revenue", "money"), new("avg_fare", "Average value", "money"),
            ],
            $$"""
            SELECT count(*) AS bookings, count(*) FILTER (WHERE done) AS completed,
                   COALESCE(sum(amount) FILTER (WHERE done), 0) AS revenue, avg(amount) FILTER (WHERE done) AS avg_fare
            FROM (
                SELECT {{DONE}} AS done, b.total_amount AS amount {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}}
                UNION ALL
                SELECT rb.status IN ('Returned','HandedOver','Confirmed'), rb.subtotal
                FROM udrive.rental_bookings rb JOIN udrive.vehicles v ON v.id = rb.vehicle_id
                LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                WHERE {{W("rb.created_at")}} AND {{VS}}
                UNION ALL
                SELECT hb.status NOT IN ('Cancelled','Rejected','Pending'), hb.amount
                FROM udrive.hotel_bookings hb JOIN udrive.hotels h ON h.id = hb.hotel_id
                WHERE {{W("hb.created_at")}} AND {{HS}}
            ) x
            """,
            new("bar", "Bookings by type", "kind",
                [("bookings", "Bookings", "bar")]),
            [
                new("kind", "Type", "text"), new("bookings", "Bookings", "int", "sum"),
                new("completed", "Completed", "int", "sum"), new("revenue", "Revenue", "money", "sum"),
                new("avg_fare", "Average value", "money", "avg"),
            ],
            $$"""
            SELECT kind, count(*) AS bookings, count(*) FILTER (WHERE done) AS completed,
                   COALESCE(sum(amount) FILTER (WHERE done), 0) AS revenue, avg(amount) FILTER (WHERE done) AS avg_fare
            FROM (
                SELECT {{KIND}} AS kind, {{DONE}} AS done, b.total_amount AS amount
                {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}}
                UNION ALL
                SELECT 'Rent-a-car', rb.status IN ('Returned','HandedOver','Confirmed'), rb.subtotal
                FROM udrive.rental_bookings rb JOIN udrive.vehicles v ON v.id = rb.vehicle_id
                LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                WHERE {{W("rb.created_at")}} AND {{VS}}
                UNION ALL
                SELECT 'Hotel', hb.status NOT IN ('Cancelled','Rejected','Pending'), hb.amount
                FROM udrive.hotel_bookings hb JOIN udrive.hotels h ON h.id = hb.hotel_id
                WHERE {{W("hb.created_at")}} AND {{HS}}
            ) x GROUP BY kind ORDER BY bookings DESC
            """),

        new("rides.cancellations", "Rides", "Cancellations",
            "Every cancelled ride: who cancelled, at which stage, and why.",
            [
                new("cancelled", "Cancelled", "int"), new("by_customer", "By customer", "int"),
                new("by_driver", "By driver", "int"), new("by_admin", "By UDrive", "int"),
                new("rate", "Cancellation rate", "pct"),
            ],
            $$"""
            WITH c AS (
                SELECT DISTINCT ON (h.booking_id) h.booking_id, h.source
                FROM udrive.trip_status_history h JOIN udrive.bookings b ON b.id = h.booking_id
                WHERE h.to_status = 'Cancelled' AND {{W("h.created_at")}} AND {{BS}}
                ORDER BY h.booking_id, h.created_at DESC)
            SELECT count(*) AS cancelled,
                   count(*) FILTER (WHERE source = 'Customer') AS by_customer,
                   count(*) FILTER (WHERE source = 'Driver') AS by_driver,
                   count(*) FILTER (WHERE source NOT IN ('Customer','Driver')) AS by_admin,
                   COALESCE(100.0 * count(*) / NULLIF((SELECT count(*) FROM udrive.bookings b WHERE {{W("b.created_at")}} AND {{BS}}), 0), 0) AS rate
            FROM c
            """,
            new("donut", "Who cancelled", "who", [("count", "Cancellations", "bar")],
                $$"""
                WITH c AS (
                    SELECT DISTINCT ON (h.booking_id) h.booking_id, h.source
                    FROM udrive.trip_status_history h JOIN udrive.bookings b ON b.id = h.booking_id
                    WHERE h.to_status = 'Cancelled' AND {{W("h.created_at")}} AND {{BS}}
                    ORDER BY h.booking_id, h.created_at DESC)
                SELECT CASE WHEN source IN ('Customer','Driver') THEN source ELSE 'UDrive' END AS who, count(*) AS count
                FROM c GROUP BY 1 ORDER BY 2 DESC
                """),
            [
                new("reference", "Booking", "text"), new("at", "Cancelled at", "datetime"),
                new("area", "Area", "text"), new("who", "By", "badge"), new("stage", "Stage", "text"),
                new("reason", "Reason", "text"), new("customer", "Customer", "text"), new("driver", "Driver", "text"),
            ],
            $$"""
            WITH c AS (
                SELECT DISTINCT ON (h.booking_id) h.booking_id, h.source, h.reason, h.from_status, h.created_at
                FROM udrive.trip_status_history h
                WHERE h.to_status = 'Cancelled' AND {{W("h.created_at")}}
                ORDER BY h.booking_id, h.created_at DESC)
            SELECT b.booking_reference AS reference, {{TS("c.created_at")}} AS at, udrive.area_label(b.territory_id) AS area,
                   CASE WHEN c.source IN ('Customer','Driver') THEN c.source ELSE 'UDrive' END AS who,
                   COALESCE(c.from_status, '—') AS stage,
                   COALESCE(NULLIF(c.reason, ''), NULLIF(b.cancellation_reason, ''), '—') AS reason,
                   cu.full_name AS customer, du.full_name AS driver
            FROM c JOIN udrive.bookings b ON b.id = c.booking_id
            LEFT JOIN udrive.users cu ON cu.id = b.customer_user_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = b.driver_profile_id
            LEFT JOIN udrive.users du ON du.id = dp.user_id
            WHERE {{BS}} ORDER BY c.created_at DESC
            """),

        new("rides.noshow", "Rides", "No-shows",
            "Rides where the customer did not come to the pickup.",
            [new("noshow", "No-shows", "int"), new("rate", "No-show rate", "pct")],
            $$"""
            SELECT count(*) FILTER (WHERE o.trip_status = 'NoShow') AS noshow,
                   COALESCE(100.0 * count(*) FILTER (WHERE o.trip_status = 'NoShow') / NULLIF(count(*), 0), 0) AS rate
            {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}}
            """,
            new("line", "No-shows over time", "period", [("noshow", "No-shows", "line")],
                $$"""
                SELECT {{B("b.created_at")}} AS period, count(*) FILTER (WHERE o.trip_status = 'NoShow') AS noshow
                {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}} GROUP BY 1 ORDER BY 1
                """),
            [
                new("reference", "Booking", "text"), new("pickup_at", "Pickup time", "datetime"),
                new("area", "Area", "text"), new("pickup", "Pickup", "text"),
                new("customer", "Customer", "text"), new("driver", "Driver", "text"),
            ],
            $$"""
            SELECT b.booking_reference AS reference, {{TS("b.pickup_at")}} AS pickup_at, udrive.area_label(b.territory_id) AS area,
                   COALESCE(b.pickup_label, '—') AS pickup, cu.full_name AS customer, du.full_name AS driver
            {{FROMB}}
            LEFT JOIN udrive.users cu ON cu.id = b.customer_user_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = b.driver_profile_id
            LEFT JOIN udrive.users du ON du.id = dp.user_id
            WHERE o.trip_status = 'NoShow' AND {{W("b.created_at")}} AND {{BS}} ORDER BY b.pickup_at DESC
            """,
            Trend: true),

        new("rides.routes", "Rides", "Top routes",
            "The most travelled from → to pairs among completed rides.",
            [new("routes", "Routes", "int"), new("rides", "Completed rides", "int"), new("avg_fare", "Average fare", "money")],
            $$"""
            SELECT count(DISTINCT (b.pickup_label, b.destination_label)) AS routes, count(*) AS rides, avg(b.total_amount) AS avg_fare
            {{FROMB}} WHERE {{DONE}} AND {{W("b.created_at")}} AND {{BS}} AND {{KF}}
            """,
            new("hbar", "Top 15 routes", "route", [("rides", "Rides", "bar")], Limit: 15),
            [
                new("route", "Route", "text"), new("rides", "Rides", "int", "sum"),
                new("revenue", "Revenue", "money", "sum"), new("avg_fare", "Average fare", "money", "avg"),
                new("avg_km", "Average km", "num", "avg"),
            ],
            $$"""
            SELECT COALESCE(NULLIF(b.pickup_label, ''), '—') || ' → ' || COALESCE(NULLIF(b.destination_label, ''), '—') AS route,
                   count(*) AS rides, COALESCE(sum(b.total_amount), 0) AS revenue, avg(b.total_amount) AS avg_fare,
                   avg(ST_Distance(rr.pickup_location, rr.destination_location) / 1000.0) AS avg_km
            {{FROMB}} WHERE {{DONE}} AND {{W("b.created_at")}} AND {{BS}} AND {{KF}}
            GROUP BY 1 ORDER BY rides DESC
            """,
            [KindFilter]),

        new("rides.pickups", "Rides", "Pickup areas",
            "Where ride requests start, and how many of them became bookings.",
            [new("requests", "Requests", "int"), new("bookings", "Became bookings", "int"), new("fulfilment", "Fulfilment", "pct")],
            $$"""
            SELECT count(*) AS requests, count(b.id) AS bookings, COALESCE(100.0 * count(b.id) / NULLIF(count(*), 0), 0) AS fulfilment
            FROM udrive.ride_requests rr LEFT JOIN udrive.bookings b ON b.ride_request_id = rr.id
            WHERE {{W("rr.created_at")}} AND {{RS}}
            """,
            new("bar", "Requests by pickup area", "area", [("requests", "Requests", "bar"), ("bookings", "Bookings", "bar")], Limit: 15),
            [
                new("area", "Pickup area", "text"), new("requests", "Requests", "int", "sum"),
                new("bookings", "Bookings", "int", "sum"), new("fulfilment", "Fulfilment", "pct", "avg"),
                new("avg_offer", "Average offer", "money", "avg"),
            ],
            $$"""
            SELECT udrive.area_label(rr.territory_id) AS area, count(*) AS requests, count(b.id) AS bookings,
                   100.0 * count(b.id) / NULLIF(count(*), 0) AS fulfilment, avg(rr.customer_offer) AS avg_offer
            FROM udrive.ride_requests rr LEFT JOIN udrive.bookings b ON b.ride_request_id = rr.id
            WHERE {{W("rr.created_at")}} AND {{RS}}
            GROUP BY rr.territory_id ORDER BY requests DESC
            """),

        new("rides.peak", "Rides", "Peak hours",
            "Ride requests by day of the week and hour of the day (Pakistan time).",
            [new("requests", "Requests", "int"), new("peak_hour", "Busiest hour", "hour"), new("peak_count", "Requests in that hour", "int")],
            $$"""
            WITH h AS (SELECT extract(hour FROM rr.created_at AT TIME ZONE 'Asia/Karachi')::int AS hr, count(*) AS n
                       FROM udrive.ride_requests rr WHERE {{W("rr.created_at")}} AND {{RS}} GROUP BY 1)
            SELECT (SELECT COALESCE(sum(n), 0) FROM h) AS requests,
                   (SELECT hr FROM h ORDER BY n DESC LIMIT 1) AS peak_hour,
                   (SELECT n FROM h ORDER BY n DESC LIMIT 1) AS peak_count
            """,
            new("heatmap", "Requests by day and hour", "day", [("value", "Requests", "bar")],
                $$"""
                SELECT extract(isodow FROM rr.created_at AT TIME ZONE 'Asia/Karachi')::int AS dow,
                       extract(hour FROM rr.created_at AT TIME ZONE 'Asia/Karachi')::int AS hour,
                       count(*) AS value
                FROM udrive.ride_requests rr WHERE {{W("rr.created_at")}} AND {{RS}} GROUP BY 1, 2
                """),
            [
                new("day", "Day", "text"), new("hour", "Hour", "int"),
                new("requests", "Requests", "int", "sum"), new("bookings", "Bookings", "int", "sum"),
            ],
            $$"""
            SELECT to_char(rr.created_at AT TIME ZONE 'Asia/Karachi', 'Dy') AS day,
                   extract(hour FROM rr.created_at AT TIME ZONE 'Asia/Karachi')::int AS hour,
                   count(*) AS requests, count(b.id) AS bookings
            FROM udrive.ride_requests rr LEFT JOIN udrive.bookings b ON b.ride_request_id = rr.id
            WHERE {{W("rr.created_at")}} AND {{RS}}
            GROUP BY extract(isodow FROM rr.created_at AT TIME ZONE 'Asia/Karachi'), 1, 2
            ORDER BY extract(isodow FROM rr.created_at AT TIME ZONE 'Asia/Karachi'), 2
            """),

        new("rides.duration", "Rides", "Trip time & distance",
            "How long completed trips took from start to finish, and how far they went.",
            [new("trips", "Trips", "int"), new("avg_minutes", "Average time", "minutes"), new("avg_km", "Average km", "num"), new("max_km", "Longest km", "num")],
            $$"""
            SELECT count(*) AS trips,
                   avg(extract(epoch FROM o.completed_at - o.started_at) / 60) AS avg_minutes,
                   avg(ST_Distance(rr.pickup_location, rr.destination_location) / 1000.0) AS avg_km,
                   max(ST_Distance(rr.pickup_location, rr.destination_location) / 1000.0) AS max_km
            {{FROMB}} WHERE o.completed_at IS NOT NULL AND o.started_at IS NOT NULL AND {{W("o.completed_at")}} AND {{BS}} AND {{KF}}
            """,
            new("bar", "Trips by duration", "band", [("trips", "Trips", "bar")],
                $$"""
                SELECT band, count(*) AS trips FROM (
                    SELECT CASE WHEN m < 15 THEN '1. under 15 min' WHEN m < 30 THEN '2. 15–30 min' WHEN m < 60 THEN '3. 30–60 min'
                                WHEN m < 120 THEN '4. 1–2 h' ELSE '5. over 2 h' END AS band
                    FROM (SELECT extract(epoch FROM o.completed_at - o.started_at) / 60 AS m
                          {{FROMB}} WHERE o.completed_at IS NOT NULL AND o.started_at IS NOT NULL AND {{W("o.completed_at")}} AND {{BS}} AND {{KF}}) t
                ) x GROUP BY band ORDER BY band
                """),
            [
                new("reference", "Booking", "text"), new("area", "Area", "text"), new("kind", "Type", "text"),
                new("started", "Started", "datetime"), new("completed", "Completed", "datetime"),
                new("minutes", "Minutes", "minutes", "avg"), new("km", "Km (straight line)", "num", "avg"),
            ],
            $$"""
            SELECT b.booking_reference AS reference, udrive.area_label(b.territory_id) AS area, {{KIND}} AS kind,
                   {{TS("o.started_at")}} AS started, {{TS("o.completed_at")}} AS completed,
                   extract(epoch FROM o.completed_at - o.started_at) / 60 AS minutes,
                   ST_Distance(rr.pickup_location, rr.destination_location) / 1000.0 AS km
            {{FROMB}} WHERE o.completed_at IS NOT NULL AND o.started_at IS NOT NULL AND {{W("o.completed_at")}} AND {{BS}} AND {{KF}}
            ORDER BY o.completed_at DESC
            """,
            [KindFilter]),

        // ═════════════════════════════════════ Dispatch
        new("dispatch.accept", "Dispatch", "Request → booking time",
            "Minutes from a customer's request to a confirmed booking.",
            [new("median", "Median", "minutes"), new("p90", "90% within", "minutes"), new("slow", "Over 5 minutes", "int"), new("count", "Booked requests", "int")],
            $$"""
            SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY m) AS median,
                   percentile_cont(0.9) WITHIN GROUP (ORDER BY m) AS p90,
                   count(*) FILTER (WHERE m > 5) AS slow, count(*) AS count
            FROM (SELECT extract(epoch FROM b.created_at - rr.created_at) / 60 AS m
                  FROM udrive.bookings b JOIN udrive.ride_requests rr ON rr.id = b.ride_request_id
                  WHERE {{W("rr.created_at")}} AND {{RS}}) x
            """,
            new("line", "Median minutes", "period", [("median", "Median minutes", "line")],
                $$"""
                SELECT {{B("rr.created_at")}} AS period,
                       percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM b.created_at - rr.created_at) / 60) AS median
                FROM udrive.bookings b JOIN udrive.ride_requests rr ON rr.id = b.ride_request_id
                WHERE {{W("rr.created_at")}} AND {{RS}} GROUP BY 1 ORDER BY 1
                """),
            [
                new("reference", "Booking", "text"), new("area", "Area", "text"),
                new("requested", "Requested", "datetime"), new("booked", "Booked", "datetime"),
                new("minutes", "Minutes", "minutes", "avg"), new("offers", "Offers received", "int", "avg"),
            ],
            $$"""
            SELECT b.booking_reference AS reference, udrive.area_label(rr.territory_id) AS area,
                   {{TS("rr.created_at")}} AS requested, {{TS("b.created_at")}} AS booked,
                   extract(epoch FROM b.created_at - rr.created_at) / 60 AS minutes,
                   (SELECT count(*) FROM udrive.driver_offers f WHERE f.ride_request_id = rr.id) AS offers
            FROM udrive.bookings b JOIN udrive.ride_requests rr ON rr.id = b.ride_request_id
            WHERE {{W("rr.created_at")}} AND {{RS}} ORDER BY minutes DESC
            """,
            Trend: true),

        new("dispatch.unfulfilled", "Dispatch", "Unfulfilled requests",
            "Ride requests that ended without a booking — usually no driver took them.",
            [new("requests", "Requests", "int"), new("unfulfilled", "Without a booking", "int"), new("rate", "Unfulfilled rate", "pct")],
            $$"""
            SELECT count(*) AS requests,
                   count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM udrive.bookings b WHERE b.ride_request_id = rr.id)
                                     AND (rr.status IN ('Expired','Cancelled','NoDriver') OR rr.expires_at < now())) AS unfulfilled,
                   COALESCE(100.0 * count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM udrive.bookings b WHERE b.ride_request_id = rr.id)
                                     AND (rr.status IN ('Expired','Cancelled','NoDriver') OR rr.expires_at < now())) / NULLIF(count(*), 0), 0) AS rate
            FROM udrive.ride_requests rr WHERE {{W("rr.created_at")}} AND {{RS}}
            """,
            new("bar", "Unfulfilled by area", "area", [("unfulfilled", "Unfulfilled", "bar")],
                $$"""
                SELECT udrive.area_label(rr.territory_id) AS area, count(*) AS unfulfilled
                FROM udrive.ride_requests rr
                WHERE {{W("rr.created_at")}} AND {{RS}}
                  AND NOT EXISTS (SELECT 1 FROM udrive.bookings b WHERE b.ride_request_id = rr.id)
                  AND (rr.status IN ('Expired','Cancelled','NoDriver') OR rr.expires_at < now())
                GROUP BY rr.territory_id ORDER BY 2 DESC LIMIT 15
                """),
            [
                new("requested", "Requested", "datetime"), new("area", "Area", "text"), new("route", "Pickup → drop", "text"),
                new("offer", "Customer offer", "money", "avg"), new("status", "Status", "badge"),
                new("offers", "Offers received", "int", "sum"), new("customer", "Customer", "text"),
            ],
            $$"""
            SELECT {{TS("rr.created_at")}} AS requested, udrive.area_label(rr.territory_id) AS area,
                   COALESCE(rr.pickup_label, '—') || ' → ' || COALESCE(rr.destination_label, '—') AS route,
                   rr.customer_offer AS offer, rr.status AS status,
                   (SELECT count(*) FROM udrive.driver_offers f WHERE f.ride_request_id = rr.id) AS offers,
                   cu.full_name AS customer
            FROM udrive.ride_requests rr LEFT JOIN udrive.users cu ON cu.id = rr.customer_user_id
            WHERE {{W("rr.created_at")}} AND {{RS}}
              AND NOT EXISTS (SELECT 1 FROM udrive.bookings b WHERE b.ride_request_id = rr.id)
              AND (rr.status IN ('Expired','Cancelled','NoDriver') OR rr.expires_at < now())
            ORDER BY rr.created_at DESC
            """),

        new("dispatch.offers", "Dispatch", "Driver offers",
            "Offers each driver sent on ride requests, and how many were chosen.",
            [new("sent", "Offers sent", "int"), new("chosen", "Chosen", "int"), new("expired", "Not chosen / expired", "int"), new("rate", "Chosen rate", "pct")],
            $$"""
            SELECT count(*) AS sent, count(*) FILTER (WHERE f.status = 'Selected') AS chosen,
                   count(*) FILTER (WHERE f.status IN ('Expired','Rejected','Declined','Withdrawn')) AS expired,
                   COALESCE(100.0 * count(*) FILTER (WHERE f.status = 'Selected') / NULLIF(count(*), 0), 0) AS rate
            FROM udrive.driver_offers f JOIN udrive.driver_profiles dp ON dp.id = f.driver_profile_id
            WHERE {{W("f.created_at")}} AND {{DS}}
            """,
            new("stacked", "Top 10 drivers by offers", "driver",
                [("chosen", "Chosen", "bar"), ("other", "Not chosen", "bar")], Limit: 10),
            [
                new("driver", "Driver", "text"), new("area", "Area", "text"), new("sent", "Sent", "int", "sum"),
                new("chosen", "Chosen", "int", "sum"), new("other", "Not chosen", "int", "sum"),
                new("rate", "Chosen %", "pct", "avg"), new("avg_amount", "Average offer", "money", "avg"),
            ],
            $$"""
            SELECT u.full_name AS driver, udrive.area_label(dp.territory_id) AS area, count(*) AS sent,
                   count(*) FILTER (WHERE f.status = 'Selected') AS chosen,
                   count(*) FILTER (WHERE f.status <> 'Selected') AS other,
                   100.0 * count(*) FILTER (WHERE f.status = 'Selected') / NULLIF(count(*), 0) AS rate,
                   avg(f.amount) AS avg_amount
            FROM udrive.driver_offers f JOIN udrive.driver_profiles dp ON dp.id = f.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE {{W("f.created_at")}} AND {{DS}}
            GROUP BY u.full_name, dp.territory_id ORDER BY sent DESC
            """),

        new("dispatch.admin_completed", "Dispatch", "Completed by UDrive",
            "Trips completed from the admin panel because the driver could not (no internet).",
            [new("count", "Trips", "int"), new("drivers", "Drivers", "int")],
            $$"""
            SELECT count(*) AS count, count(DISTINCT b.driver_profile_id) AS drivers
            FROM udrive.trip_status_history h JOIN udrive.bookings b ON b.id = h.booking_id
            WHERE h.to_status = 'TripCompleted' AND h.source = 'Admin' AND {{W("h.created_at")}} AND {{BS}}
            """,
            new("bar", "By area", "area", [("count", "Trips", "bar")],
                $$"""
                SELECT udrive.area_label(b.territory_id) AS area, count(*) AS count
                FROM udrive.trip_status_history h JOIN udrive.bookings b ON b.id = h.booking_id
                WHERE h.to_status = 'TripCompleted' AND h.source = 'Admin' AND {{W("h.created_at")}} AND {{BS}}
                GROUP BY b.territory_id ORDER BY 2 DESC
                """),
            [
                new("reference", "Booking", "text"), new("at", "Completed at", "datetime"), new("area", "Area", "text"),
                new("driver", "Driver", "text"), new("admin", "Completed by", "text"), new("reason", "Reason", "text"),
            ],
            $$"""
            SELECT b.booking_reference AS reference, {{TS("h.created_at")}} AS at, udrive.area_label(b.territory_id) AS area,
                   du.full_name AS driver, au.full_name AS admin, COALESCE(h.reason, '—') AS reason
            FROM udrive.trip_status_history h JOIN udrive.bookings b ON b.id = h.booking_id
            LEFT JOIN udrive.users au ON au.id = h.changed_by_user_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = b.driver_profile_id
            LEFT JOIN udrive.users du ON du.id = dp.user_id
            WHERE h.to_status = 'TripCompleted' AND h.source = 'Admin' AND {{W("h.created_at")}} AND {{BS}}
            ORDER BY h.created_at DESC
            """),

        new("dispatch.gps_gaps", "Dispatch", "GPS gaps",
            "Live trips where the driver's location stopped arriving for more than two minutes.",
            [new("trips", "Trips with a gap", "int"), new("avg_gap", "Average longest gap", "minutes"), new("max_gap", "Longest gap", "minutes")],
            $$"""
            WITH g AS (
                SELECT x.booking_id, max(x.gap) AS gap FROM (
                    SELECT l.booking_id, extract(epoch FROM l.server_timestamp - lag(l.server_timestamp)
                           OVER (PARTITION BY l.booking_id ORDER BY l.server_timestamp)) / 60 AS gap
                    FROM udrive.trip_location_history l WHERE {{W("l.server_timestamp")}}) x
                GROUP BY x.booking_id HAVING max(x.gap) > 2)
            SELECT count(*) AS trips, avg(g.gap) AS avg_gap, max(g.gap) AS max_gap
            FROM g JOIN udrive.bookings b ON b.id = g.booking_id WHERE {{BS}}
            """,
            new("bar", "Trips by longest gap", "band", [("trips", "Trips", "bar")],
                $$"""
                WITH g AS (
                    SELECT x.booking_id, max(x.gap) AS gap FROM (
                        SELECT l.booking_id, extract(epoch FROM l.server_timestamp - lag(l.server_timestamp)
                               OVER (PARTITION BY l.booking_id ORDER BY l.server_timestamp)) / 60 AS gap
                        FROM udrive.trip_location_history l WHERE {{W("l.server_timestamp")}}) x
                    GROUP BY x.booking_id HAVING max(x.gap) > 2)
                SELECT CASE WHEN gap < 5 THEN '1. 2–5 min' WHEN gap < 15 THEN '2. 5–15 min' WHEN gap < 60 THEN '3. 15–60 min' ELSE '4. over 1 h' END AS band,
                       count(*) AS trips
                FROM g JOIN udrive.bookings b ON b.id = g.booking_id WHERE {{BS}} GROUP BY 1 ORDER BY 1
                """),
            [
                new("reference", "Booking", "text"), new("area", "Area", "text"), new("driver", "Driver", "text"),
                new("gap", "Longest gap", "minutes", "avg"), new("gaps", "Gaps over 2 min", "int", "sum"),
                new("last_gps", "Last location", "datetime"),
            ],
            $$"""
            WITH x AS (
                SELECT l.booking_id, l.server_timestamp,
                       extract(epoch FROM l.server_timestamp - lag(l.server_timestamp)
                               OVER (PARTITION BY l.booking_id ORDER BY l.server_timestamp)) / 60 AS gap
                FROM udrive.trip_location_history l WHERE {{W("l.server_timestamp")}}),
            g AS (SELECT booking_id, max(gap) AS gap, count(*) FILTER (WHERE gap > 2) AS gaps, max(server_timestamp) AS last_at
                  FROM x GROUP BY booking_id HAVING max(gap) > 2)
            SELECT b.booking_reference AS reference, udrive.area_label(b.territory_id) AS area, du.full_name AS driver,
                   g.gap, g.gaps, {{TS("g.last_at")}} AS last_gps
            FROM g JOIN udrive.bookings b ON b.id = g.booking_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = b.driver_profile_id
            LEFT JOIN udrive.users du ON du.id = dp.user_id
            WHERE {{BS}} ORDER BY g.gap DESC
            """),

        // ═════════════════════════════════════ Drivers
        new("drivers.performance", "Drivers", "Driver performance",
            "Trips, earnings, reliability and rating for every driver in your area.",
            [
                new("drivers", "Active drivers", "int"), new("trips", "Completed trips", "int"),
                new("earnings", "Driver earnings", "money"), new("commission", "Commission", "money"),
                new("cancel_rate", "Cancellation rate", "pct"), new("rating", "Average rating", "rating"),
            ],
            $$"""
            SELECT count(DISTINCT b.driver_profile_id) FILTER (WHERE {{DONE}}) AS drivers,
                   count(*) FILTER (WHERE {{DONE}}) AS trips,
                   (SELECT COALESCE(sum(e.gross_amount), 0) FROM udrive.driver_earnings e JOIN udrive.driver_profiles dp ON dp.id = e.driver_profile_id
                     WHERE {{W("e.created_at")}} AND {{DS}}) AS earnings,
                   (SELECT COALESCE(sum(e.commission_amount), 0) FROM udrive.driver_earnings e JOIN udrive.driver_profiles dp ON dp.id = e.driver_profile_id
                     WHERE {{W("e.created_at")}} AND {{DS}}) AS commission,
                   COALESCE(100.0 * count(*) FILTER (WHERE {{CANC}}) / NULLIF(count(*), 0), 0) AS cancel_rate,
                   (SELECT avg(r.overall_rating) FROM udrive.trip_ratings r JOIN udrive.driver_profiles dp ON dp.user_id = r.reviewee_user_id
                     WHERE r.reviewer_role = 'Customer' AND {{W("r.created_at")}} AND {{DS}}) AS rating
            {{FROMB}} JOIN udrive.driver_profiles dp ON dp.id = b.driver_profile_id
            WHERE {{W("b.created_at")}} AND {{DS}}
            """,
            new("bar", "Top 10 drivers by completed trips", "driver",
                [("trips", "Trips", "bar")], Limit: 10),
            [
                new("driver", "Driver", "text"), new("vehicle", "Vehicle", "text"), new("area", "Area", "text"),
                new("trips", "Trips", "int", "sum"), new("earnings", "Earnings", "money", "sum"),
                new("commission", "Commission", "money", "sum"), new("cancel_rate", "Cancel %", "pct", "avg"),
                new("accept_rate", "Offer chosen %", "pct", "avg"), new("rating", "Rating", "rating", "avg"),
                new("online_hours", "Online hours", "hours", "sum"), new("status", "Status", "badge"),
            ],
            $$"""
            WITH t AS (SELECT b.driver_profile_id AS d, count(*) FILTER (WHERE {{DONE}}) AS trips,
                              count(*) FILTER (WHERE {{CANC}}) AS cancels, count(*) AS total
                       {{FROMB}} WHERE {{W("b.created_at")}} AND b.driver_profile_id IS NOT NULL GROUP BY 1),
                 e AS (SELECT driver_profile_id AS d, sum(gross_amount) AS gross, sum(commission_amount) AS commission
                       FROM udrive.driver_earnings WHERE {{W("created_at")}} GROUP BY 1),
                 f AS (SELECT driver_profile_id AS d, count(*) AS offers, count(*) FILTER (WHERE status = 'Selected') AS chosen
                       FROM udrive.driver_offers WHERE {{W("created_at")}} GROUP BY 1),
                 r AS (SELECT reviewee_user_id AS u, avg(overall_rating) AS rating
                       FROM udrive.trip_ratings WHERE reviewer_role = 'Customer' AND {{W("created_at")}} GROUP BY 1),
                 s AS (SELECT driver_profile_id AS d, sum(credited_seconds) / 3600.0 AS hours
                       FROM udrive.driver_online_sessions WHERE {{W("started_at")}} GROUP BY 1)
            SELECT u.full_name AS driver,
                   (SELECT concat(v.make, ' ', v.model, ' · ', v.registration_number) FROM udrive.vehicles v
                     WHERE v.driver_profile_id = dp.id ORDER BY v.created_at LIMIT 1) AS vehicle,
                   udrive.area_label(dp.territory_id) AS area,
                   COALESCE(t.trips, 0) AS trips, COALESCE(e.gross, 0) AS earnings, COALESCE(e.commission, 0) AS commission,
                   COALESCE(100.0 * t.cancels / NULLIF(t.total, 0), 0) AS cancel_rate,
                   100.0 * f.chosen / NULLIF(f.offers, 0) AS accept_rate,
                   r.rating, COALESCE(s.hours, 0) AS online_hours,
                   CASE WHEN r.rating IS NOT NULL AND r.rating < 4 THEN 'Low rating'
                        WHEN COALESCE(100.0 * t.cancels / NULLIF(t.total, 0), 0) > 8 THEN 'Watch'
                        ELSE 'Good' END AS status
            FROM udrive.driver_profiles dp JOIN udrive.users u ON u.id = dp.user_id
            LEFT JOIN t ON t.d = dp.id LEFT JOIN e ON e.d = dp.id LEFT JOIN f ON f.d = dp.id
            LEFT JOIN r ON r.u = dp.user_id LEFT JOIN s ON s.d = dp.id
            WHERE {{DS}} AND (t.d IS NOT NULL OR e.d IS NOT NULL OR s.d IS NOT NULL)
              AND COALESCE(t.trips, 0) >= COALESCE(NULLIF(@f_min, ''), '0')::int
            ORDER BY trips DESC, earnings DESC
            """,
            [MinTripsFilter]),

        new("drivers.earnings", "Drivers", "Earnings & commission",
            "What each driver earned on completed trips, and UDrive's share.",
            [new("gross", "Gross fares", "money"), new("commission", "Commission", "money"), new("net", "Driver net", "money"), new("drivers", "Drivers", "int")],
            $$"""
            SELECT COALESCE(sum(e.gross_amount), 0) AS gross, COALESCE(sum(e.commission_amount), 0) AS commission,
                   COALESCE(sum(e.net_amount), 0) AS net, count(DISTINCT e.driver_profile_id) AS drivers
            FROM udrive.driver_earnings e JOIN udrive.driver_profiles dp ON dp.id = e.driver_profile_id
            WHERE {{W("e.created_at")}} AND {{DS}}
            """,
            new("line", "Earnings over time", "period", [("gross", "Gross", "line"), ("commission", "Commission", "line")],
                $$"""
                SELECT {{B("e.created_at")}} AS period, COALESCE(sum(e.gross_amount), 0) AS gross, COALESCE(sum(e.commission_amount), 0) AS commission
                FROM udrive.driver_earnings e JOIN udrive.driver_profiles dp ON dp.id = e.driver_profile_id
                WHERE {{W("e.created_at")}} AND {{DS}} GROUP BY 1 ORDER BY 1
                """),
            [
                new("driver", "Driver", "text"), new("area", "Area", "text"), new("trips", "Trips", "int", "sum"),
                new("gross", "Gross", "money", "sum"), new("commission", "Commission", "money", "sum"),
                new("commission_pct", "Commission %", "pct", "avg"), new("net", "Net", "money", "sum"),
            ],
            $$"""
            SELECT u.full_name AS driver, udrive.area_label(dp.territory_id) AS area, count(*) AS trips,
                   sum(e.gross_amount) AS gross, sum(e.commission_amount) AS commission,
                   100.0 * sum(e.commission_amount) / NULLIF(sum(e.gross_amount), 0) AS commission_pct,
                   sum(e.net_amount) AS net
            FROM udrive.driver_earnings e JOIN udrive.driver_profiles dp ON dp.id = e.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE {{W("e.created_at")}} AND {{DS}}
            GROUP BY u.full_name, dp.territory_id ORDER BY gross DESC
            """,
            Trend: true),

        new("drivers.wallets", "Drivers", "Wallets & top-ups",
            "Each driver's wallet today, and the top-ups approved in the period.",
            [new("available", "Total available", "money"), new("topups", "Top-ups approved", "money"), new("negative", "Wallets below zero", "int"), new("frozen", "Frozen wallets", "int")],
            $$"""
            SELECT COALESCE(sum(w.available_balance), 0) AS available,
                   (SELECT COALESCE(sum(t.amount), 0) FROM udrive.driver_wallet_topups t JOIN udrive.driver_profiles dp ON dp.id = t.driver_profile_id
                     WHERE t.status = 'Approved' AND {{W("t.created_at")}} AND {{DS}}) AS topups,
                   count(*) FILTER (WHERE w.available_balance < 0) AS negative,
                   count(*) FILTER (WHERE w.is_frozen) AS frozen
            FROM udrive.driver_wallets w JOIN udrive.driver_profiles dp ON dp.id = w.driver_profile_id WHERE {{DS}}
            """,
            new("bar", "Top 10 balances", "driver", [("available", "Available", "bar")], Limit: 10),
            [
                new("driver", "Driver", "text"), new("area", "Area", "text"), new("available", "Available", "money", "sum"),
                new("pending", "Pending", "money", "sum"), new("commission_due", "Commission balance", "money", "sum"),
                new("topups", "Top-ups in period", "money", "sum"), new("last_topup", "Last top-up", "datetime"),
                new("state", "Wallet", "badge"),
            ],
            $$"""
            SELECT u.full_name AS driver, udrive.area_label(dp.territory_id) AS area, w.available_balance AS available,
                   w.pending_balance AS pending, w.commission_balance AS commission_due,
                   (SELECT COALESCE(sum(t.amount), 0) FROM udrive.driver_wallet_topups t
                     WHERE t.driver_profile_id = dp.id AND t.status = 'Approved' AND {{W("t.created_at")}}) AS topups,
                   (SELECT {{TS("max(t.created_at)")}} FROM udrive.driver_wallet_topups t
                     WHERE t.driver_profile_id = dp.id AND t.status = 'Approved') AS last_topup,
                   CASE WHEN w.is_frozen THEN 'Frozen' WHEN w.available_balance < 0 THEN 'Below zero' ELSE 'Active' END AS state
            FROM udrive.driver_wallets w JOIN udrive.driver_profiles dp ON dp.id = w.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE {{DS}} ORDER BY w.available_balance DESC
            """),

        new("drivers.payouts", "Drivers", "Payouts",
            "Payout requests from drivers and what was paid.",
            [new("requested", "Requested", "money"), new("paid", "Paid", "money"), new("pending", "Waiting", "money"), new("count", "Requests", "int")],
            $$"""
            SELECT COALESCE(sum(p.amount), 0) AS requested,
                   COALESCE(sum(p.amount) FILTER (WHERE p.status = 'Paid'), 0) AS paid,
                   COALESCE(sum(p.amount) FILTER (WHERE p.status IN ('Pending','Requested','Approved','Processing')), 0) AS pending,
                   count(*) AS count
            FROM udrive.driver_payout_requests p JOIN udrive.driver_profiles dp ON dp.id = p.driver_profile_id
            WHERE {{W("p.requested_at")}} AND {{DS}}
            """,
            new("line", "Requested and paid", "period", [("requested", "Requested", "line"), ("paid", "Paid", "line")],
                $$"""
                SELECT {{B("p.requested_at")}} AS period, COALESCE(sum(p.amount), 0) AS requested,
                       COALESCE(sum(p.amount) FILTER (WHERE p.status = 'Paid'), 0) AS paid
                FROM udrive.driver_payout_requests p JOIN udrive.driver_profiles dp ON dp.id = p.driver_profile_id
                WHERE {{W("p.requested_at")}} AND {{DS}} GROUP BY 1 ORDER BY 1
                """),
            [
                new("driver", "Driver", "text"), new("area", "Area", "text"), new("amount", "Amount", "money", "sum"),
                new("method", "Method", "text"), new("status", "Status", "badge"),
                new("requested", "Requested", "datetime"), new("paid", "Paid", "datetime"),
            ],
            $$"""
            SELECT u.full_name AS driver, udrive.area_label(dp.territory_id) AS area, p.amount, COALESCE(p.payout_method, '—') AS method,
                   p.status, {{TS("p.requested_at")}} AS requested, {{TS("p.paid_at")}} AS paid
            FROM udrive.driver_payout_requests p JOIN udrive.driver_profiles dp ON dp.id = p.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE {{W("p.requested_at")}} AND {{DS}} ORDER BY p.requested_at DESC
            """,
            Trend: true),

        new("drivers.signups", "Drivers", "Signups & verification",
            "Drivers who signed up in the period and how far they got.",
            [new("signups", "Signed up", "int"), new("submitted", "Submitted documents", "int"), new("approved", "Approved", "int"), new("rejected", "Rejected", "int")],
            $$"""
            SELECT count(*) AS signups, count(*) FILTER (WHERE dp.submitted_at IS NOT NULL) AS submitted,
                   count(*) FILTER (WHERE dp.verification_status = 'Approved') AS approved,
                   count(*) FILTER (WHERE dp.verification_status = 'Rejected') AS rejected
            FROM udrive.driver_profiles dp WHERE {{W("dp.created_at")}} AND {{DS}}
            """,
            new("bar", "Signup funnel", "stage", [("drivers", "Drivers", "bar")],
                $$"""
                SELECT stage, drivers FROM (
                    SELECT 1 AS o, 'Signed up' AS stage, count(*) AS drivers FROM udrive.driver_profiles dp WHERE {{W("dp.created_at")}} AND {{DS}}
                    UNION ALL SELECT 2, 'Submitted', count(*) FROM udrive.driver_profiles dp WHERE dp.submitted_at IS NOT NULL AND {{W("dp.created_at")}} AND {{DS}}
                    UNION ALL SELECT 3, 'Approved', count(*) FROM udrive.driver_profiles dp WHERE dp.verification_status = 'Approved' AND {{W("dp.created_at")}} AND {{DS}}
                    UNION ALL SELECT 4, 'First trip', count(*) FROM udrive.driver_profiles dp WHERE {{W("dp.created_at")}} AND {{DS}}
                        AND EXISTS (SELECT 1 FROM udrive.trip_operations o JOIN udrive.bookings b ON b.id = o.booking_id
                                    WHERE b.driver_profile_id = dp.id AND o.trip_status = 'TripCompleted')
                ) x ORDER BY o
                """),
            [
                new("driver", "Driver", "text"), new("phone", "Phone", "text"), new("area", "Area", "text"),
                new("signed_up", "Signed up", "datetime"), new("status", "Status", "badge"),
                new("days", "Days to approve", "num", "avg"),
            ],
            $$"""
            SELECT u.full_name AS driver, u.phone_number AS phone, udrive.area_label(dp.territory_id) AS area,
                   {{TS("dp.created_at")}} AS signed_up, dp.verification_status AS status,
                   extract(epoch FROM dp.approved_at - dp.created_at) / 86400 AS days
            FROM udrive.driver_profiles dp JOIN udrive.users u ON u.id = dp.user_id
            WHERE {{W("dp.created_at")}} AND {{DS}} ORDER BY dp.created_at DESC
            """),

        new("drivers.inactive", "Drivers", "Inactive drivers",
            "Approved drivers with no completed trip in the last 7 or 30 days (up to the end date).",
            [new("idle7", "No trip in 7 days", "int"), new("idle30", "No trip in 30 days", "int"), new("never", "Never had a trip", "int")],
            $$"""
            WITH x AS (
                SELECT dp.id, (SELECT max(o.completed_at) FROM udrive.trip_operations o JOIN udrive.bookings b ON b.id = o.booking_id
                               WHERE b.driver_profile_id = dp.id AND o.trip_status = 'TripCompleted' AND o.completed_at < @to) AS last_trip
                FROM udrive.driver_profiles dp WHERE dp.verification_status = 'Approved' AND {{DS}})
            SELECT count(*) FILTER (WHERE last_trip IS NULL OR last_trip < @to - interval '7 days') AS idle7,
                   count(*) FILTER (WHERE last_trip IS NULL OR last_trip < @to - interval '30 days') AS idle30,
                   count(*) FILTER (WHERE last_trip IS NULL) AS never
            FROM x
            """,
            new("bar", "Drivers by days without a trip", "band", [("drivers", "Drivers", "bar")],
                $$"""
                WITH x AS (
                    SELECT (SELECT max(o.completed_at) FROM udrive.trip_operations o JOIN udrive.bookings b ON b.id = o.booking_id
                            WHERE b.driver_profile_id = dp.id AND o.trip_status = 'TripCompleted' AND o.completed_at < @to) AS last_trip
                    FROM udrive.driver_profiles dp WHERE dp.verification_status = 'Approved' AND {{DS}})
                SELECT CASE WHEN last_trip IS NULL THEN '5. never'
                            WHEN last_trip >= @to - interval '7 days' THEN '1. active (0–7 days)'
                            WHEN last_trip >= @to - interval '14 days' THEN '2. 7–14 days'
                            WHEN last_trip >= @to - interval '30 days' THEN '3. 14–30 days'
                            ELSE '4. over 30 days' END AS band, count(*) AS drivers
                FROM x GROUP BY 1 ORDER BY 1
                """),
            [
                new("driver", "Driver", "text"), new("phone", "Phone", "text"), new("area", "Area", "text"),
                new("last_trip", "Last trip", "datetime"), new("days", "Days without a trip", "int", "avg"),
                new("online", "Online now", "badge"),
            ],
            $$"""
            WITH x AS (
                SELECT dp.id, dp.territory_id, dp.is_online, u.full_name, u.phone_number,
                       (SELECT max(o.completed_at) FROM udrive.trip_operations o JOIN udrive.bookings b ON b.id = o.booking_id
                        WHERE b.driver_profile_id = dp.id AND o.trip_status = 'TripCompleted' AND o.completed_at < @to) AS last_trip
                FROM udrive.driver_profiles dp JOIN udrive.users u ON u.id = dp.user_id
                WHERE dp.verification_status = 'Approved' AND {{DS}})
            SELECT full_name AS driver, phone_number AS phone, udrive.area_label(territory_id) AS area,
                   {{TS("last_trip")}} AS last_trip,
                   CASE WHEN last_trip IS NULL THEN NULL ELSE floor(extract(epoch FROM @to - last_trip) / 86400) END AS days,
                   CASE WHEN is_online THEN 'Online' ELSE 'Offline' END AS online
            FROM x WHERE last_trip IS NULL OR last_trip < @to - interval '7 days'
            ORDER BY last_trip NULLS FIRST
            """),

        new("drivers.documents", "Drivers", "Expiring documents",
            "Licences and documents that have expired or expire within 30 days.",
            [new("expired", "Expired", "int"), new("soon", "Expiring in 30 days", "int")],
            $$"""
            WITH d AS (
                SELECT dp.driving_licence_expiry AS expiry FROM udrive.driver_profiles dp
                 WHERE dp.driving_licence_expiry IS NOT NULL AND dp.verification_status = 'Approved' AND {{DS}}
                UNION ALL
                SELECT dd.expiry_date FROM udrive.driver_documents dd JOIN udrive.driver_profiles dp ON dp.id = dd.driver_profile_id
                 WHERE dd.expiry_date IS NOT NULL AND {{DS}}
                UNION ALL
                SELECT vd.expiry_date FROM udrive.vehicle_documents vd JOIN udrive.vehicles v ON v.id = vd.vehicle_id
                 LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                 WHERE vd.expiry_date IS NOT NULL AND {{VS}})
            SELECT count(*) FILTER (WHERE expiry < current_date) AS expired,
                   count(*) FILTER (WHERE expiry >= current_date AND expiry <= current_date + 30) AS soon
            FROM d
            """,
            new("bar", "By document", "document", [("expired", "Expired", "bar"), ("soon", "Within 30 days", "bar")],
                $$"""
                WITH d AS (
                    SELECT 'Driving licence' AS document, dp.driving_licence_expiry AS expiry FROM udrive.driver_profiles dp
                     WHERE dp.driving_licence_expiry IS NOT NULL AND dp.verification_status = 'Approved' AND {{DS}}
                    UNION ALL
                    SELECT dd.document_type, dd.expiry_date FROM udrive.driver_documents dd JOIN udrive.driver_profiles dp ON dp.id = dd.driver_profile_id
                     WHERE dd.expiry_date IS NOT NULL AND {{DS}}
                    UNION ALL
                    SELECT vd.document_type, vd.expiry_date FROM udrive.vehicle_documents vd JOIN udrive.vehicles v ON v.id = vd.vehicle_id
                     LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                     WHERE vd.expiry_date IS NOT NULL AND {{VS}})
                SELECT document, count(*) FILTER (WHERE expiry < current_date) AS expired,
                       count(*) FILTER (WHERE expiry >= current_date AND expiry <= current_date + 30) AS soon
                FROM d WHERE expiry <= current_date + 30 GROUP BY 1 ORDER BY 2 DESC
                """),
            [
                new("driver", "Driver", "text"), new("phone", "Phone", "text"), new("area", "Area", "text"),
                new("document", "Document", "text"), new("expiry", "Expiry", "date"), new("days_left", "Days left", "int"),
                new("state", "State", "badge"),
            ],
            $$"""
            WITH d AS (
                SELECT dp.id AS d, dp.territory_id AS t, 'Driving licence' AS document, dp.driving_licence_expiry AS expiry
                  FROM udrive.driver_profiles dp WHERE dp.driving_licence_expiry IS NOT NULL AND dp.verification_status = 'Approved' AND {{DS}}
                UNION ALL
                SELECT dp.id, dp.territory_id, dd.document_type, dd.expiry_date
                  FROM udrive.driver_documents dd JOIN udrive.driver_profiles dp ON dp.id = dd.driver_profile_id
                 WHERE dd.expiry_date IS NOT NULL AND {{DS}}
                UNION ALL
                SELECT dp.id, COALESCE(v.territory_id, dp.territory_id), vd.document_type || ' (' || v.registration_number || ')', vd.expiry_date
                  FROM udrive.vehicle_documents vd JOIN udrive.vehicles v ON v.id = vd.vehicle_id
                  LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                 WHERE vd.expiry_date IS NOT NULL AND {{VS}})
            SELECT u.full_name AS driver, u.phone_number AS phone, udrive.area_label(d.t) AS area, d.document,
                   to_char(d.expiry, 'YYYY-MM-DD') AS expiry, (d.expiry - current_date) AS days_left,
                   CASE WHEN d.expiry < current_date THEN 'Expired' ELSE 'Expiring' END AS state
            FROM d LEFT JOIN udrive.driver_profiles dp ON dp.id = d.d LEFT JOIN udrive.users u ON u.id = dp.user_id
            WHERE d.expiry <= current_date + 30 ORDER BY d.expiry
            """,
            UsesDates: false),

        new("drivers.low_rated", "Drivers", "Low-rated drivers",
            "Drivers whose average customer rating in the period is below 4.0.",
            [new("drivers", "Drivers below 4.0", "int"), new("ratings", "Their ratings", "int")],
            $$"""
            WITH r AS (SELECT dp.id, avg(t.overall_rating) AS rating, count(*) AS n
                       FROM udrive.trip_ratings t JOIN udrive.driver_profiles dp ON dp.user_id = t.reviewee_user_id
                       WHERE t.reviewer_role = 'Customer' AND {{W("t.created_at")}} AND {{DS}} GROUP BY dp.id)
            SELECT count(*) FILTER (WHERE rating < 4) AS drivers, COALESCE(sum(n) FILTER (WHERE rating < 4), 0) AS ratings FROM r
            """,
            new("bar", "Lowest ratings", "driver", [("rating", "Rating", "bar")], Limit: 10),
            [
                new("driver", "Driver", "text"), new("phone", "Phone", "text"), new("area", "Area", "text"),
                new("rating", "Rating", "rating", "avg"), new("ratings", "Ratings", "int", "sum"),
                new("low", "1–2 star ratings", "int", "sum"), new("incidents", "Safety reports", "int", "sum"),
            ],
            $$"""
            SELECT u.full_name AS driver, u.phone_number AS phone, udrive.area_label(dp.territory_id) AS area,
                   avg(t.overall_rating) AS rating, count(*) AS ratings, count(*) FILTER (WHERE t.overall_rating <= 2) AS low,
                   (SELECT count(*) FROM udrive.safety_incidents si JOIN udrive.bookings b ON b.id = si.booking_id
                     WHERE b.driver_profile_id = dp.id AND {{W("si.created_at")}}) AS incidents
            FROM udrive.trip_ratings t JOIN udrive.driver_profiles dp ON dp.user_id = t.reviewee_user_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE t.reviewer_role = 'Customer' AND {{W("t.created_at")}} AND {{DS}}
            GROUP BY dp.id, u.full_name, u.phone_number, dp.territory_id
            HAVING avg(t.overall_rating) < 4 ORDER BY rating
            """),

        // ═════════════════════════════════════ Vehicles
        new("vehicles.utilisation", "Vehicles", "Vehicle utilisation",
            "How much each vehicle worked: trips, revenue and days without a trip.",
            [new("vehicles", "Vehicles", "int"), new("trips", "Trips", "int"), new("per_vehicle", "Trips per vehicle", "num"), new("idle", "Vehicles with no trip", "int")],
            $$"""
            WITH t AS (SELECT b.vehicle_id, count(*) AS trips {{FROMB}} WHERE {{DONE}} AND {{W("b.created_at")}} GROUP BY 1)
            SELECT count(*) AS vehicles, COALESCE(sum(t.trips), 0) AS trips,
                   COALESCE(sum(t.trips), 0)::numeric / NULLIF(count(*), 0) AS per_vehicle,
                   count(*) FILTER (WHERE t.trips IS NULL) AS idle
            FROM udrive.vehicles v LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            LEFT JOIN t ON t.vehicle_id = v.id
            WHERE v.status IN ('Verified','Approved') AND {{VS}}
            """,
            new("bar", "Top 10 vehicles by trips", "vehicle", [("trips", "Trips", "bar")], Limit: 10),
            [
                new("vehicle", "Vehicle", "text"), new("plate", "Plate", "text"), new("category", "Category", "text"),
                new("area", "Area", "text"), new("owner", "Owner / driver", "text"),
                new("trips", "Trips", "int", "sum"), new("revenue", "Revenue", "money", "sum"),
                new("active_days", "Days with trips", "int", "sum"), new("idle_days", "Days without", "int", "sum"),
            ],
            $$"""
            WITH t AS (SELECT b.vehicle_id, count(*) AS trips, sum(b.total_amount) AS revenue,
                              count(DISTINCT (b.created_at AT TIME ZONE 'Asia/Karachi')::date) AS days
                       {{FROMB}} WHERE {{DONE}} AND {{W("b.created_at")}} GROUP BY 1)
            SELECT concat(v.make, ' ', v.model) AS vehicle, v.registration_number AS plate, v.category,
                   udrive.area_label(COALESCE(v.territory_id, dp.territory_id)) AS area, u.full_name AS owner,
                   COALESCE(t.trips, 0) AS trips, COALESCE(t.revenue, 0) AS revenue, COALESCE(t.days, 0) AS active_days,
                   GREATEST(0, ceil(extract(epoch FROM @to - @from) / 86400)::int - COALESCE(t.days, 0)) AS idle_days
            FROM udrive.vehicles v LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            LEFT JOIN udrive.users u ON u.id = dp.user_id LEFT JOIN t ON t.vehicle_id = v.id
            WHERE v.status IN ('Verified','Approved') AND {{VS}}
            ORDER BY trips DESC, revenue DESC
            """),

        new("vehicles.category", "Vehicles", "Vehicles by category",
            "Cars, jeeps, vans and coaches: how many there are and how much they earn.",
            [new("vehicles", "Vehicles", "int"), new("categories", "Categories", "int"), new("trips", "Trips", "int")],
            $$"""
            SELECT count(DISTINCT v.id) AS vehicles, count(DISTINCT v.category) AS categories,
                   (SELECT count(*) {{FROMB}} JOIN udrive.vehicles v ON v.id = b.vehicle_id LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                     WHERE {{DONE}} AND {{W("b.created_at")}} AND {{VS}}) AS trips
            FROM udrive.vehicles v LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id WHERE {{VS}}
            """,
            new("donut", "Vehicles by category", "category", [("vehicles", "Vehicles", "bar")]),
            [
                new("category", "Category", "text"), new("vehicles", "Vehicles", "int", "sum"),
                new("trips", "Trips", "int", "sum"), new("revenue", "Revenue", "money", "sum"),
                new("per_vehicle", "Revenue per vehicle", "money", "avg"),
            ],
            $$"""
            WITH t AS (SELECT b.vehicle_id, count(*) AS trips, sum(b.total_amount) AS revenue
                       {{FROMB}} WHERE {{DONE}} AND {{W("b.created_at")}} GROUP BY 1)
            SELECT COALESCE(v.category, '—') AS category, count(*) AS vehicles, COALESCE(sum(t.trips), 0) AS trips,
                   COALESCE(sum(t.revenue), 0) AS revenue, COALESCE(sum(t.revenue), 0) / NULLIF(count(*), 0) AS per_vehicle
            FROM udrive.vehicles v LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            LEFT JOIN t ON t.vehicle_id = v.id WHERE {{VS}}
            GROUP BY 1 ORDER BY vehicles DESC
            """),

        new("vehicles.verification", "Vehicles", "Vehicle verification status",
            "Every vehicle and where it stands for city rides, rent-a-car and tours (today).",
            [new("approved", "Approved (city)", "int"), new("pending", "Waiting", "int"), new("rejected", "Rejected", "int"), new("rent_live", "Live for rent", "int"), new("tour_live", "Live for tours", "int")],
            $$"""
            SELECT count(*) FILTER (WHERE v.status IN ('Verified','Approved')) AS approved,
                   count(*) FILTER (WHERE v.status IN ('PendingReview','Pending','Submitted') OR v.rent_review_status = 'Pending' OR v.tour_review_status = 'Pending') AS pending,
                   count(*) FILTER (WHERE v.status = 'Rejected') AS rejected,
                   count(*) FILTER (WHERE v.rent_review_status = 'Approved') AS rent_live,
                   count(*) FILTER (WHERE v.tour_review_status = 'Approved') AS tour_live
            FROM udrive.vehicles v LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id WHERE {{VS}}
            """,
            new("donut", "Vehicles by status", "status", [("vehicles", "Vehicles", "bar")],
                $$"""
                SELECT v.status, count(*) AS vehicles FROM udrive.vehicles v
                LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id WHERE {{VS}} GROUP BY 1 ORDER BY 2 DESC
                """),
            [
                new("vehicle", "Vehicle", "text"), new("plate", "Plate", "text"), new("area", "Area", "text"),
                new("owner", "Owner", "text"), new("city", "City rides", "badge"), new("rent", "Rent-a-car", "badge"),
                new("tour", "Tours", "badge"), new("added", "Added", "datetime"),
            ],
            $$"""
            SELECT concat(v.make, ' ', v.model) AS vehicle, v.registration_number AS plate,
                   udrive.area_label(COALESCE(v.territory_id, dp.territory_id)) AS area, u.full_name AS owner,
                   v.status AS city, v.rent_review_status AS rent, v.tour_review_status AS tour, {{TS("v.created_at")}} AS added
            FROM udrive.vehicles v LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            LEFT JOIN udrive.users u ON u.id = dp.user_id
            WHERE {{VS}} ORDER BY v.created_at DESC
            """,
            UsesDates: false),

        new("vehicles.rent_days", "Vehicles", "Rent-a-car days",
            "Days each vehicle was out on rent in the period, and what it earned.",
            [new("days", "Days rented", "int"), new("revenue", "Rental revenue", "money"), new("vehicles", "Vehicles rented", "int"), new("utilisation", "Average utilisation", "pct")],
            $$"""
            WITH r AS (
                SELECT rb.vehicle_id, GREATEST(0, LEAST(rb.end_date, ((@to - interval '1 day') AT TIME ZONE 'Asia/Karachi')::date)
                         - GREATEST(rb.start_date, (@from AT TIME ZONE 'Asia/Karachi')::date) + 1) AS days, rb.subtotal
                FROM udrive.rental_bookings rb JOIN udrive.vehicles v ON v.id = rb.vehicle_id
                LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                WHERE rb.status IN ('Confirmed','HandedOver','Returned')
                  AND rb.start_date <= ((@to - interval '1 day') AT TIME ZONE 'Asia/Karachi')::date
                  AND rb.end_date >= (@from AT TIME ZONE 'Asia/Karachi')::date AND {{VS}})
            SELECT COALESCE(sum(days), 0) AS days, COALESCE(sum(subtotal), 0) AS revenue, count(DISTINCT vehicle_id) AS vehicles,
                   100.0 * COALESCE(sum(days), 0) / NULLIF(count(DISTINCT vehicle_id) * ceil(extract(epoch FROM @to - @from) / 86400), 0) AS utilisation
            FROM r
            """,
            new("bar", "Days rented per vehicle", "vehicle", [("days", "Days", "bar")], Limit: 15),
            [
                new("vehicle", "Vehicle", "text"), new("plate", "Plate", "text"), new("area", "Area", "text"),
                new("owner", "Owner", "text"), new("bookings", "Rentals", "int", "sum"), new("days", "Days", "int", "sum"),
                new("utilisation", "Utilisation", "pct", "avg"), new("revenue", "Revenue", "money", "sum"),
            ],
            $$"""
            WITH r AS (
                SELECT rb.vehicle_id, GREATEST(0, LEAST(rb.end_date, ((@to - interval '1 day') AT TIME ZONE 'Asia/Karachi')::date)
                         - GREATEST(rb.start_date, (@from AT TIME ZONE 'Asia/Karachi')::date) + 1) AS days, rb.subtotal
                FROM udrive.rental_bookings rb
                WHERE rb.status IN ('Confirmed','HandedOver','Returned')
                  AND rb.start_date <= ((@to - interval '1 day') AT TIME ZONE 'Asia/Karachi')::date
                  AND rb.end_date >= (@from AT TIME ZONE 'Asia/Karachi')::date)
            SELECT concat(v.make, ' ', v.model) AS vehicle, v.registration_number AS plate,
                   udrive.area_label(COALESCE(v.territory_id, dp.territory_id)) AS area, u.full_name AS owner,
                   count(*) AS bookings, sum(r.days) AS days,
                   100.0 * sum(r.days) / NULLIF(ceil(extract(epoch FROM @to - @from) / 86400), 0) AS utilisation,
                   sum(r.subtotal) AS revenue
            FROM r JOIN udrive.vehicles v ON v.id = r.vehicle_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id LEFT JOIN udrive.users u ON u.id = dp.user_id
            WHERE {{VS}}
            GROUP BY v.id, v.make, v.model, v.registration_number, v.territory_id, dp.territory_id, u.full_name
            ORDER BY days DESC
            """),

        new("vehicles.tour", "Vehicles", "Tour vehicles",
            "Vehicles that ran tours in the period: departures, seats sold and revenue.",
            [new("vehicles", "Vehicles", "int"), new("departures", "Departures", "int"), new("seats", "Seats sold", "int"), new("revenue", "Revenue", "money")],
            $$"""
            SELECT count(DISTINCT tp.vehicle_id) AS vehicles, count(*) AS departures,
                   COALESCE(sum(tp.total_seats - tp.available_seats), 0) AS seats,
                   COALESCE(sum((SELECT sum(pb.total_amount) FROM udrive.package_bookings pb WHERE pb.tour_package_id = tp.id AND pb.status <> 'Cancelled')), 0) AS revenue
            FROM udrive.tour_packages tp LEFT JOIN udrive.vehicles v ON v.id = tp.vehicle_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
            WHERE {{W("tp.departure_at")}} AND {{VS}}
            """,
            new("bar", "Departures per vehicle", "vehicle", [("departures", "Departures", "bar")], Limit: 15),
            [
                new("vehicle", "Vehicle", "text"), new("plate", "Plate", "text"), new("area", "Area", "text"),
                new("departures", "Departures", "int", "sum"), new("seats", "Seats", "int", "sum"),
                new("sold", "Seats sold", "int", "sum"), new("occupancy", "Occupancy", "pct", "avg"),
                new("revenue", "Revenue", "money", "sum"),
            ],
            $$"""
            SELECT concat(v.make, ' ', v.model) AS vehicle, v.registration_number AS plate,
                   udrive.area_label(COALESCE(v.territory_id, dp.territory_id)) AS area,
                   count(*) AS departures, sum(tp.total_seats) AS seats, sum(tp.total_seats - tp.available_seats) AS sold,
                   100.0 * sum(tp.total_seats - tp.available_seats) / NULLIF(sum(tp.total_seats), 0) AS occupancy,
                   COALESCE(sum((SELECT sum(pb.total_amount) FROM udrive.package_bookings pb WHERE pb.tour_package_id = tp.id AND pb.status <> 'Cancelled')), 0) AS revenue
            FROM udrive.tour_packages tp JOIN udrive.vehicles v ON v.id = tp.vehicle_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
            WHERE {{W("tp.departure_at")}} AND {{VS}}
            GROUP BY v.id, v.make, v.model, v.registration_number, v.territory_id, dp.territory_id
            ORDER BY departures DESC
            """),

        // ═════════════════════════════════════ Customers
        new("customers.new_returning", "Customers", "New vs returning",
            "Customers booking for the first time against those coming back.",
            [new("new_customers", "New customers", "int"), new("returning", "Returning customers", "int"), new("repeat_rate", "Returning share", "pct")],
            $$"""
            WITH f AS (SELECT customer_user_id AS c, min(created_at) AS first_at FROM udrive.bookings GROUP BY 1),
                 x AS (SELECT DISTINCT b.customer_user_id AS c FROM udrive.bookings b WHERE {{W("b.created_at")}} AND {{BS}})
            SELECT count(*) FILTER (WHERE f.first_at >= @from) AS new_customers,
                   count(*) FILTER (WHERE f.first_at < @from) AS returning,
                   COALESCE(100.0 * count(*) FILTER (WHERE f.first_at < @from) / NULLIF(count(*), 0), 0) AS repeat_rate
            FROM x JOIN f ON f.c = x.c
            """,
            new("stacked", "Customers per period", "period", [("new_customers", "New", "bar"), ("returning", "Returning", "bar")]),
            [
                new("period", "Period", "text"), new("new_customers", "New", "int", "sum"),
                new("returning", "Returning", "int", "sum"), new("bookings", "Bookings", "int", "sum"),
            ],
            $$"""
            WITH f AS (SELECT customer_user_id AS c, min(created_at) AS first_at FROM udrive.bookings GROUP BY 1)
            SELECT {{B("b.created_at")}} AS period,
                   count(DISTINCT b.customer_user_id) FILTER (WHERE {{B("f.first_at")}} = {{B("b.created_at")}}) AS new_customers,
                   count(DISTINCT b.customer_user_id) FILTER (WHERE {{B("f.first_at")}} <> {{B("b.created_at")}}) AS returning,
                   count(*) AS bookings
            FROM udrive.bookings b JOIN f ON f.c = b.customer_user_id
            WHERE {{W("b.created_at")}} AND {{BS}} GROUP BY 1 ORDER BY 1
            """,
            Trend: true),

        new("customers.top", "Customers", "Top customers",
            "Customers who booked and spent the most in the period.",
            [new("customers", "Customers", "int"), new("spend", "Total spend", "money"), new("avg_spend", "Average per customer", "money")],
            $$"""
            SELECT count(DISTINCT b.customer_user_id) AS customers,
                   COALESCE(sum(b.total_amount) FILTER (WHERE {{DONE}}), 0) AS spend,
                   COALESCE(sum(b.total_amount) FILTER (WHERE {{DONE}}), 0) / NULLIF(count(DISTINCT b.customer_user_id), 0) AS avg_spend
            {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}}
            """,
            new("hbar", "Top 10 by spend", "customer", [("spend", "Spend", "bar")], Limit: 10),
            [
                new("customer", "Customer", "text"), new("phone", "Phone", "text"), new("area", "Main area", "text"),
                new("bookings", "Bookings", "int", "sum"), new("completed", "Completed", "int", "sum"),
                new("spend", "Spend", "money", "sum"), new("last", "Last booking", "datetime"),
            ],
            $$"""
            SELECT u.full_name AS customer, u.phone_number AS phone,
                   udrive.area_label(mode() WITHIN GROUP (ORDER BY b.territory_id)) AS area,
                   count(*) AS bookings, count(*) FILTER (WHERE {{DONE}}) AS completed,
                   COALESCE(sum(b.total_amount) FILTER (WHERE {{DONE}}), 0) AS spend, {{TS("max(b.created_at)")}} AS last
            {{FROMB}} JOIN udrive.users u ON u.id = b.customer_user_id
            WHERE {{W("b.created_at")}} AND {{BS}}
            GROUP BY u.id, u.full_name, u.phone_number ORDER BY spend DESC, bookings DESC
            """),

        new("customers.cancellations", "Customers", "Customer cancellations",
            "Customers who cancel often.",
            [new("customers", "Customers who cancelled", "int"), new("cancels", "Cancellations", "int")],
            $$"""
            SELECT count(DISTINCT b.customer_user_id) AS customers, count(*) AS cancels
            FROM udrive.trip_status_history h JOIN udrive.bookings b ON b.id = h.booking_id
            WHERE h.to_status = 'Cancelled' AND h.source = 'Customer' AND {{W("h.created_at")}} AND {{BS}}
            """,
            new("bar", "Most cancellations", "customer", [("cancels", "Cancellations", "bar")], Limit: 10),
            [
                new("customer", "Customer", "text"), new("phone", "Phone", "text"), new("cancels", "Cancelled", "int", "sum"),
                new("bookings", "Bookings", "int", "sum"), new("rate", "Cancel rate", "pct", "avg"),
            ],
            $$"""
            WITH c AS (SELECT b.customer_user_id AS c, count(DISTINCT b.id) AS cancels
                       FROM udrive.trip_status_history h JOIN udrive.bookings b ON b.id = h.booking_id
                       WHERE h.to_status = 'Cancelled' AND h.source = 'Customer' AND {{W("h.created_at")}} AND {{BS}} GROUP BY 1),
                 t AS (SELECT b.customer_user_id AS c, count(*) AS bookings FROM udrive.bookings b
                       WHERE {{W("b.created_at")}} AND {{BS}} GROUP BY 1)
            SELECT u.full_name AS customer, u.phone_number AS phone, c.cancels, COALESCE(t.bookings, 0) AS bookings,
                   100.0 * c.cancels / NULLIF(t.bookings, 0) AS rate
            FROM c JOIN udrive.users u ON u.id = c.c LEFT JOIN t ON t.c = c.c ORDER BY c.cancels DESC
            """),

        new("customers.complaints", "Customers", "Complaints & tickets",
            "Support tickets raised in the period.",
            [new("total", "Tickets", "int"), new("open", "Open", "int"), new("resolved", "Resolved", "int")],
            $$"""
            SELECT count(*) AS total, count(*) FILTER (WHERE st.resolved_at IS NULL AND st.status NOT IN ('Resolved','Closed')) AS open,
                   count(*) FILTER (WHERE st.resolved_at IS NOT NULL OR st.status IN ('Resolved','Closed')) AS resolved
            FROM udrive.support_tickets st LEFT JOIN udrive.bookings b ON b.id = st.booking_id
            WHERE {{W("st.created_at")}} AND {{BS}}
            """,
            new("bar", "Tickets by category", "category", [("tickets", "Tickets", "bar")],
                $$"""
                SELECT COALESCE(st.category, '—') AS category, count(*) AS tickets
                FROM udrive.support_tickets st LEFT JOIN udrive.bookings b ON b.id = st.booking_id
                WHERE {{W("st.created_at")}} AND {{BS}} GROUP BY 1 ORDER BY 2 DESC
                """),
            [
                new("reference", "Ticket", "text"), new("opened", "Opened", "datetime"), new("customer", "Raised by", "text"),
                new("category", "Category", "text"), new("priority", "Priority", "badge"), new("subject", "Subject", "text"),
                new("status", "Status", "badge"), new("booking", "Booking", "text"),
            ],
            $$"""
            SELECT st.reference, {{TS("st.created_at")}} AS opened, u.full_name AS customer, st.category, st.priority,
                   st.subject, st.status, b.booking_reference AS booking
            FROM udrive.support_tickets st LEFT JOIN udrive.bookings b ON b.id = st.booking_id
            LEFT JOIN udrive.users u ON u.id = st.created_by_user_id
            WHERE {{W("st.created_at")}} AND {{BS}} ORDER BY st.created_at DESC
            """),

        // ═════════════════════════════════════ Finance
        new("finance.revenue", "Finance", "Revenue",
            "Completed ride value, money collected and what is still owed.",
            [new("gross", "Completed value", "money"), new("collected", "Collected", "money"), new("outstanding", "Outstanding", "money"), new("refunded", "Refunded", "money")],
            $$"""
            SELECT COALESCE(sum(b.total_amount) FILTER (WHERE {{DONE}}), 0) AS gross,
                   (SELECT COALESCE(sum(p.amount), 0) FROM udrive.payments p JOIN udrive.bookings b ON b.id = p.booking_id
                     WHERE p.status IN ('Paid','Verified') AND {{W("p.created_at")}} AND {{BS}}) AS collected,
                   COALESCE(sum(b.remaining_amount) FILTER (WHERE NOT {{CANC}}), 0) AS outstanding,
                   (SELECT COALESCE(sum(p.refund_amount), 0) FROM udrive.payments p JOIN udrive.bookings b ON b.id = p.booking_id
                     WHERE {{W("p.created_at")}} AND {{BS}}) AS refunded
            {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}}
            """,
            new("line", "Revenue over time", "period", [("gross", "Completed value", "line"), ("collected", "Collected", "line")]),
            [
                new("period", "Period", "text"), new("bookings", "Bookings", "int", "sum"),
                new("gross", "Completed value", "money", "sum"), new("collected", "Collected", "money", "sum"),
                new("outstanding", "Outstanding", "money", "sum"),
            ],
            $$"""
            WITH bk AS (SELECT {{B("b.created_at")}} AS p, count(*) AS bookings,
                               COALESCE(sum(b.total_amount) FILTER (WHERE {{DONE}}), 0) AS gross,
                               COALESCE(sum(b.remaining_amount) FILTER (WHERE NOT {{CANC}}), 0) AS outstanding
                        {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}} GROUP BY 1),
                 pm AS (SELECT {{B("p.created_at")}} AS p, sum(p.amount) AS collected
                        FROM udrive.payments p JOIN udrive.bookings b ON b.id = p.booking_id
                        WHERE p.status IN ('Paid','Verified') AND {{W("p.created_at")}} AND {{BS}} GROUP BY 1)
            SELECT COALESCE(bk.p, pm.p) AS period, COALESCE(bk.bookings, 0) AS bookings, COALESCE(bk.gross, 0) AS gross,
                   COALESCE(pm.collected, 0) AS collected, COALESCE(bk.outstanding, 0) AS outstanding
            FROM bk FULL JOIN pm ON pm.p = bk.p ORDER BY 1
            """,
            Trend: true),

        new("finance.commission", "Finance", "Commission by area",
            "UDrive's share of completed trips in each area.",
            [new("trips", "Trips", "int"), new("gross", "Gross fares", "money"), new("commission", "Commission", "money"), new("pct", "Average commission", "pct")],
            $$"""
            SELECT count(*) AS trips, COALESCE(sum(e.gross_amount), 0) AS gross, COALESCE(sum(e.commission_amount), 0) AS commission,
                   100.0 * sum(e.commission_amount) / NULLIF(sum(e.gross_amount), 0) AS pct
            FROM udrive.driver_earnings e JOIN udrive.bookings b ON b.id = e.booking_id
            WHERE {{W("e.created_at")}} AND {{BS}}
            """,
            new("bar", "Commission by area", "area", [("commission", "Commission", "bar")], Limit: 15),
            [
                new("area", "Area", "text"), new("trips", "Trips", "int", "sum"), new("gross", "Gross", "money", "sum"),
                new("commission", "Commission", "money", "sum"), new("pct", "Commission %", "pct", "avg"),
            ],
            $$"""
            SELECT udrive.area_label(b.territory_id) AS area, count(*) AS trips, sum(e.gross_amount) AS gross,
                   sum(e.commission_amount) AS commission, 100.0 * sum(e.commission_amount) / NULLIF(sum(e.gross_amount), 0) AS pct
            FROM udrive.driver_earnings e JOIN udrive.bookings b ON b.id = e.booking_id
            WHERE {{W("e.created_at")}} AND {{BS}} GROUP BY b.territory_id ORDER BY commission DESC
            """),

        new("finance.refunds", "Finance", "Refunds",
            "Refund requests and what was paid back.",
            [new("count", "Requests", "int"), new("amount", "Requested", "money"), new("completed", "Refunded", "money"), new("fees", "Cancellation fees", "money")],
            $$"""
            SELECT count(*) AS count, COALESCE(sum(r.amount), 0) AS amount,
                   COALESCE(sum(r.amount) FILTER (WHERE r.completed_at IS NOT NULL), 0) AS completed,
                   COALESCE(sum(r.cancellation_fee), 0) AS fees
            FROM udrive.refund_requests r JOIN udrive.bookings b ON b.id = r.booking_id
            WHERE {{W("r.created_at")}} AND {{BS}}
            """,
            new("line", "Refunds over time", "period", [("amount", "Requested", "line"), ("completed", "Refunded", "line")],
                $$"""
                SELECT {{B("r.created_at")}} AS period, COALESCE(sum(r.amount), 0) AS amount,
                       COALESCE(sum(r.amount) FILTER (WHERE r.completed_at IS NOT NULL), 0) AS completed
                FROM udrive.refund_requests r JOIN udrive.bookings b ON b.id = r.booking_id
                WHERE {{W("r.created_at")}} AND {{BS}} GROUP BY 1 ORDER BY 1
                """),
            [
                new("booking", "Booking", "text"), new("requested", "Requested", "datetime"), new("area", "Area", "text"),
                new("amount", "Amount", "money", "sum"), new("fee", "Fee kept", "money", "sum"),
                new("reason", "Reason", "text"), new("method", "Method", "text"), new("status", "Status", "badge"),
                new("completed", "Completed", "datetime"),
            ],
            $$"""
            SELECT b.booking_reference AS booking, {{TS("r.created_at")}} AS requested, udrive.area_label(b.territory_id) AS area,
                   r.amount, r.cancellation_fee AS fee, COALESCE(r.reason, '—') AS reason, COALESCE(r.refund_method, '—') AS method,
                   r.status, {{TS("r.completed_at")}} AS completed
            FROM udrive.refund_requests r JOIN udrive.bookings b ON b.id = r.booking_id
            WHERE {{W("r.created_at")}} AND {{BS}} ORDER BY r.created_at DESC
            """,
            Trend: true),

        new("finance.methods", "Finance", "Payment methods",
            "How customers paid: cash, wallet, bank transfer and others.",
            [new("count", "Payments", "int"), new("amount", "Collected", "money"), new("methods", "Methods used", "int")],
            $$"""
            SELECT count(*) AS count, COALESCE(sum(p.amount), 0) AS amount, count(DISTINCT p.method) AS methods
            FROM udrive.payments p JOIN udrive.bookings b ON b.id = p.booking_id
            WHERE p.status IN ('Paid','Verified') AND {{W("p.created_at")}} AND {{BS}}
            """,
            new("donut", "Collected by method", "method", [("amount", "Collected", "bar")]),
            [
                new("method", "Method", "text"), new("count", "Payments", "int", "sum"),
                new("amount", "Collected", "money", "sum"), new("share", "Share", "pct", "sum"),
            ],
            $$"""
            SELECT COALESCE(p.method, '—') AS method, count(*) AS count, sum(p.amount) AS amount,
                   100.0 * sum(p.amount) / NULLIF(sum(sum(p.amount)) OVER (), 0) AS share
            FROM udrive.payments p JOIN udrive.bookings b ON b.id = p.booking_id
            WHERE p.status IN ('Paid','Verified') AND {{W("p.created_at")}} AND {{BS}}
            GROUP BY 1 ORDER BY amount DESC
            """),

        new("finance.reconciliation", "Finance", "Daily reconciliation",
            "Each day's bookings, collections, commission, driver earnings and refunds — the control totals.",
            [
                new("gross", "Booking value", "money"), new("collected", "Collected", "money"),
                new("commission", "Commission", "money"), new("earnings", "Driver earnings", "money"),
                new("refunds", "Refunded", "money"), new("outstanding", "Outstanding", "money"),
            ],
            $$"""
            SELECT COALESCE(sum(b.total_amount), 0) AS gross,
                   (SELECT COALESCE(sum(p.amount), 0) FROM udrive.payments p JOIN udrive.bookings b ON b.id = p.booking_id
                     WHERE p.status IN ('Paid','Verified') AND {{W("p.created_at")}} AND {{BS}}) AS collected,
                   (SELECT COALESCE(sum(e.commission_amount), 0) FROM udrive.driver_earnings e JOIN udrive.bookings b ON b.id = e.booking_id
                     WHERE {{W("e.created_at")}} AND {{BS}}) AS commission,
                   (SELECT COALESCE(sum(e.net_amount), 0) FROM udrive.driver_earnings e JOIN udrive.bookings b ON b.id = e.booking_id
                     WHERE {{W("e.created_at")}} AND {{BS}}) AS earnings,
                   (SELECT COALESCE(sum(p.refund_amount), 0) FROM udrive.payments p JOIN udrive.bookings b ON b.id = p.booking_id
                     WHERE {{W("p.created_at")}} AND {{BS}}) AS refunds,
                   COALESCE(sum(b.remaining_amount) FILTER (WHERE b.status NOT IN ('Cancelled','Refunded')), 0) AS outstanding
            FROM udrive.bookings b WHERE {{W("b.created_at")}} AND {{BS}}
            """,
            new("line", "Collected against booking value", "day", [("gross", "Booking value", "line"), ("collected", "Collected", "line")]),
            [
                new("day", "Date", "text"), new("bookings", "Bookings", "int", "sum"), new("completed", "Completed", "int", "sum"),
                new("cancelled", "Cancelled", "int", "sum"), new("gross", "Booking value", "money", "sum"),
                new("collected", "Collected", "money", "sum"), new("commission", "Commission", "money", "sum"),
                new("earnings", "Driver earnings", "money", "sum"), new("refunds", "Refunds", "money", "sum"),
            ],
            $$"""
            WITH d AS (SELECT generate_series((@from AT TIME ZONE 'Asia/Karachi')::date,
                                              ((@to - interval '1 day') AT TIME ZONE 'Asia/Karachi')::date, interval '1 day')::date AS day),
                 bk AS (SELECT (b.created_at AT TIME ZONE 'Asia/Karachi')::date AS day, count(*) AS bookings,
                               count(*) FILTER (WHERE {{DONE}}) AS completed, count(*) FILTER (WHERE {{CANC}}) AS cancelled,
                               sum(b.total_amount) AS gross
                        {{FROMB}} WHERE {{W("b.created_at")}} AND {{BS}} GROUP BY 1),
                 pm AS (SELECT (p.created_at AT TIME ZONE 'Asia/Karachi')::date AS day,
                               sum(p.amount) FILTER (WHERE p.status IN ('Paid','Verified')) AS collected, sum(p.refund_amount) AS refunds
                        FROM udrive.payments p JOIN udrive.bookings b ON b.id = p.booking_id
                        WHERE {{W("p.created_at")}} AND {{BS}} GROUP BY 1),
                 er AS (SELECT (e.created_at AT TIME ZONE 'Asia/Karachi')::date AS day, sum(e.commission_amount) AS commission, sum(e.net_amount) AS earnings
                        FROM udrive.driver_earnings e JOIN udrive.bookings b ON b.id = e.booking_id
                        WHERE {{W("e.created_at")}} AND {{BS}} GROUP BY 1)
            SELECT to_char(d.day, 'YYYY-MM-DD') AS day, COALESCE(bk.bookings, 0) AS bookings, COALESCE(bk.completed, 0) AS completed,
                   COALESCE(bk.cancelled, 0) AS cancelled, COALESCE(bk.gross, 0) AS gross, COALESCE(pm.collected, 0) AS collected,
                   COALESCE(er.commission, 0) AS commission, COALESCE(er.earnings, 0) AS earnings, COALESCE(pm.refunds, 0) AS refunds
            FROM d LEFT JOIN bk ON bk.day = d.day LEFT JOIN pm ON pm.day = d.day LEFT JOIN er ON er.day = d.day
            ORDER BY d.day DESC
            """),

        new("finance.mismatches", "Finance", "Reconciliation mismatches",
            "Bookings where booking value, money collected and refunds do not add up to what is still owed.",
            [new("count", "Bookings to review", "int"), new("difference", "Total difference", "money")],
            $$"""
            WITH m AS (
                SELECT b.total_amount - COALESCE(sum(p.amount) FILTER (WHERE p.status IN ('Paid','Verified')), 0)
                       + COALESCE(sum(p.refund_amount), 0) - b.remaining_amount AS diff
                FROM udrive.bookings b LEFT JOIN udrive.payments p ON p.booking_id = b.id
                WHERE {{W("b.created_at")}} AND {{BS}} AND b.status NOT IN ('Cancelled','Refunded')
                GROUP BY b.id, b.total_amount, b.remaining_amount)
            SELECT count(*) FILTER (WHERE abs(diff) > 0.01) AS count, COALESCE(sum(diff) FILTER (WHERE abs(diff) > 0.01), 0) AS difference FROM m
            """,
            null,
            [
                new("reference", "Booking", "text"), new("created", "Created", "datetime"), new("area", "Area", "text"),
                new("total", "Booking value", "money", "sum"), new("collected", "Collected", "money", "sum"),
                new("refunded", "Refunded", "money", "sum"), new("remaining", "Recorded as owed", "money", "sum"),
                new("difference", "Difference", "money", "sum"),
            ],
            $$"""
            SELECT b.booking_reference AS reference, {{TS("b.created_at")}} AS created, udrive.area_label(b.territory_id) AS area,
                   b.total_amount AS total,
                   COALESCE(sum(p.amount) FILTER (WHERE p.status IN ('Paid','Verified')), 0) AS collected,
                   COALESCE(sum(p.refund_amount), 0) AS refunded, b.remaining_amount AS remaining,
                   b.total_amount - COALESCE(sum(p.amount) FILTER (WHERE p.status IN ('Paid','Verified')), 0)
                     + COALESCE(sum(p.refund_amount), 0) - b.remaining_amount AS difference
            FROM udrive.bookings b LEFT JOIN udrive.payments p ON p.booking_id = b.id
            WHERE {{W("b.created_at")}} AND {{BS}} AND b.status NOT IN ('Cancelled','Refunded')
            GROUP BY b.id, b.booking_reference, b.created_at, b.territory_id, b.total_amount, b.remaining_amount
            HAVING abs(b.total_amount - COALESCE(sum(p.amount) FILTER (WHERE p.status IN ('Paid','Verified')), 0)
                       + COALESCE(sum(p.refund_amount), 0) - b.remaining_amount) > 0.01
            ORDER BY b.created_at DESC
            """),

        new("finance.driver_payable", "Finance", "Driver payable",
            "What each driver earned and was paid in the period, and what their wallet holds now.",
            [new("earned", "Earned (net)", "money"), new("paid", "Paid out", "money"), new("available", "Available now", "money")],
            $$"""
            SELECT (SELECT COALESCE(sum(e.net_amount), 0) FROM udrive.driver_earnings e JOIN udrive.driver_profiles dp ON dp.id = e.driver_profile_id
                     WHERE {{W("e.created_at")}} AND {{DS}}) AS earned,
                   (SELECT COALESCE(sum(p.amount), 0) FROM udrive.driver_payout_requests p JOIN udrive.driver_profiles dp ON dp.id = p.driver_profile_id
                     WHERE p.status = 'Paid' AND {{W("p.paid_at")}} AND {{DS}}) AS paid,
                   (SELECT COALESCE(sum(w.available_balance), 0) FROM udrive.driver_wallets w JOIN udrive.driver_profiles dp ON dp.id = w.driver_profile_id
                     WHERE {{DS}}) AS available
            """,
            new("bar", "Top 10 available balances", "driver", [("available", "Available", "bar")], Limit: 10),
            [
                new("driver", "Driver", "text"), new("area", "Area", "text"), new("earned", "Earned (net)", "money", "sum"),
                new("paid", "Paid out", "money", "sum"), new("available", "Available now", "money", "sum"),
                new("pending", "Pending", "money", "sum"),
            ],
            $$"""
            SELECT u.full_name AS driver, udrive.area_label(dp.territory_id) AS area,
                   (SELECT COALESCE(sum(e.net_amount), 0) FROM udrive.driver_earnings e WHERE e.driver_profile_id = dp.id AND {{W("e.created_at")}}) AS earned,
                   (SELECT COALESCE(sum(p.amount), 0) FROM udrive.driver_payout_requests p WHERE p.driver_profile_id = dp.id AND p.status = 'Paid' AND {{W("p.paid_at")}}) AS paid,
                   COALESCE(w.available_balance, 0) AS available, COALESCE(w.pending_balance, 0) AS pending
            FROM udrive.driver_profiles dp JOIN udrive.users u ON u.id = dp.user_id
            LEFT JOIN udrive.driver_wallets w ON w.driver_profile_id = dp.id
            WHERE {{DS}} AND (w.id IS NOT NULL OR EXISTS (SELECT 1 FROM udrive.driver_earnings e WHERE e.driver_profile_id = dp.id AND {{W("e.created_at")}}))
            ORDER BY available DESC
            """),

        new("finance.wallet_ledger", "Finance", "Wallet ledger",
            "Every credit and debit on driver wallets in the period.",
            [new("credits", "Credits", "money"), new("debits", "Debits", "money"), new("entries", "Entries", "int")],
            $$"""
            SELECT COALESCE(sum(we.amount) FILTER (WHERE we.amount > 0), 0) AS credits,
                   COALESCE(sum(we.amount) FILTER (WHERE we.amount < 0), 0) AS debits, count(*) AS entries
            FROM udrive.driver_wallet_entries we JOIN udrive.driver_wallets w ON w.id = we.wallet_id
            JOIN udrive.driver_profiles dp ON dp.id = w.driver_profile_id
            WHERE {{W("we.created_at")}} AND {{DS}}
            """,
            new("stacked", "Credits and debits", "period", [("credits", "Credits", "bar"), ("debits", "Debits", "bar")],
                $$"""
                SELECT {{B("we.created_at")}} AS period, COALESCE(sum(we.amount) FILTER (WHERE we.amount > 0), 0) AS credits,
                       COALESCE(-sum(we.amount) FILTER (WHERE we.amount < 0), 0) AS debits
                FROM udrive.driver_wallet_entries we JOIN udrive.driver_wallets w ON w.id = we.wallet_id
                JOIN udrive.driver_profiles dp ON dp.id = w.driver_profile_id
                WHERE {{W("we.created_at")}} AND {{DS}} GROUP BY 1 ORDER BY 1
                """),
            [
                new("at", "Date", "datetime"), new("driver", "Driver", "text"), new("area", "Area", "text"),
                new("type", "Type", "badge"), new("amount", "Amount", "money", "sum"), new("bucket", "Balance", "text"),
                new("description", "Description", "text"), new("reference", "Reference", "text"),
            ],
            $$"""
            SELECT {{TS("we.created_at")}} AS at, u.full_name AS driver, udrive.area_label(dp.territory_id) AS area,
                   we.entry_type AS type, we.amount, COALESCE(we.balance_bucket, '—') AS bucket,
                   COALESCE(we.description, '—') AS description, COALESCE(we.reference, '—') AS reference
            FROM udrive.driver_wallet_entries we JOIN udrive.driver_wallets w ON w.id = we.wallet_id
            JOIN udrive.driver_profiles dp ON dp.id = w.driver_profile_id JOIN udrive.users u ON u.id = dp.user_id
            WHERE {{W("we.created_at")}} AND {{DS}} ORDER BY we.created_at DESC
            """,
            Trend: true),

        new("finance.partners", "Finance", "Partner statements",
            "Monthly statements for area partners: rides, fares and their share.",
            [new("statements", "Statements", "int"), new("share", "Partner share", "money"), new("paid", "Paid", "money")],
            $$"""
            SELECT count(*) AS statements, COALESCE(sum(s.share_amount), 0) AS share,
                   COALESCE(sum(s.share_amount) FILTER (WHERE s.paid_at IS NOT NULL), 0) AS paid
            FROM udrive.partner_month_statements s JOIN udrive.partner_contracts c ON c.id = s.contract_id
            JOIN udrive.partners pt ON pt.id = c.partner_id
            WHERE s.period_start < (@to AT TIME ZONE 'Asia/Karachi')::date AND s.period_end >= (@from AT TIME ZONE 'Asia/Karachi')::date
              AND (@all OR pt.territory_id = ANY(@areas))
            """,
            new("bar", "Share by partner", "partner", [("share", "Share", "bar")], Limit: 15),
            [
                new("partner", "Partner", "text"), new("area", "Area", "text"), new("period", "Month", "text"),
                new("rides", "Rides", "int", "sum"), new("fares", "Fares", "money", "sum"),
                new("share_pct", "Share %", "pct", "avg"), new("share", "Share", "money", "sum"), new("status", "Status", "badge"),
            ],
            $$"""
            SELECT u.full_name AS partner, udrive.area_label(pt.territory_id) AS area, to_char(s.period_start, 'YYYY-MM') AS period,
                   s.completed_rides AS rides, s.gross_fares AS fares, s.share_pct, s.share_amount AS share, s.status
            FROM udrive.partner_month_statements s JOIN udrive.partner_contracts c ON c.id = s.contract_id
            JOIN udrive.partners pt ON pt.id = c.partner_id LEFT JOIN udrive.users u ON u.id = pt.user_id
            WHERE s.period_start < (@to AT TIME ZONE 'Asia/Karachi')::date AND s.period_end >= (@from AT TIME ZONE 'Asia/Karachi')::date
              AND (@all OR pt.territory_id = ANY(@areas))
            ORDER BY s.period_start DESC, share DESC
            """),

        // ═════════════════════════════════════ Tours
        new("tours.departures", "Tours", "Tour departures",
            "Every tour that left in the period: seats, sold and revenue.",
            [new("departures", "Departures", "int"), new("sold", "Seats sold", "int"), new("occupancy", "Occupancy", "pct"), new("revenue", "Revenue", "money")],
            $$"""
            SELECT count(*) AS departures, COALESCE(sum(tp.total_seats - tp.available_seats), 0) AS sold,
                   100.0 * sum(tp.total_seats - tp.available_seats) / NULLIF(sum(tp.total_seats), 0) AS occupancy,
                   COALESCE(sum((SELECT sum(pb.total_amount) FROM udrive.package_bookings pb WHERE pb.tour_package_id = tp.id AND pb.status <> 'Cancelled')), 0) AS revenue
            FROM udrive.tour_packages tp LEFT JOIN udrive.vehicles v ON v.id = tp.vehicle_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
            WHERE {{W("tp.departure_at")}} AND {{VS}}
            """,
            new("bar", "Seats sold per period", "period", [("sold", "Seats sold", "bar")],
                $$"""
                SELECT {{B("tp.departure_at")}} AS period, count(*) AS departures, COALESCE(sum(tp.total_seats - tp.available_seats), 0) AS sold
                FROM udrive.tour_packages tp LEFT JOIN udrive.vehicles v ON v.id = tp.vehicle_id
                LEFT JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
                WHERE {{W("tp.departure_at")}} AND {{VS}} GROUP BY 1 ORDER BY 1
                """),
            [
                new("departure", "Departs", "datetime"), new("title", "Tour", "text"), new("route", "From → to", "text"),
                new("vehicle", "Vehicle", "text"), new("driver", "Driver", "text"), new("seats", "Seats", "int", "sum"),
                new("sold", "Sold", "int", "sum"), new("occupancy", "Occupancy", "pct", "avg"),
                new("revenue", "Revenue", "money", "sum"), new("status", "Status", "badge"),
            ],
            $$"""
            SELECT {{TS("tp.departure_at")}} AS departure, tp.title,
                   COALESCE(tp.starting_city, '—') || ' → ' || COALESCE(d.name_en, '—') AS route,
                   concat(v.make, ' ', v.model, ' · ', v.registration_number) AS vehicle, u.full_name AS driver,
                   tp.total_seats AS seats, tp.total_seats - tp.available_seats AS sold,
                   100.0 * (tp.total_seats - tp.available_seats) / NULLIF(tp.total_seats, 0) AS occupancy,
                   COALESCE((SELECT sum(pb.total_amount) FROM udrive.package_bookings pb WHERE pb.tour_package_id = tp.id AND pb.status <> 'Cancelled'), 0) AS revenue,
                   tp.status
            FROM udrive.tour_packages tp LEFT JOIN udrive.vehicles v ON v.id = tp.vehicle_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id LEFT JOIN udrive.users u ON u.id = dp.user_id
            LEFT JOIN udrive.destinations d ON d.id = tp.destination_id
            WHERE {{W("tp.departure_at")}} AND {{VS}} ORDER BY tp.departure_at DESC
            """,
            Trend: true),

        new("tours.revenue", "Tours", "Tour revenue by destination",
            "Which destinations and tours sell.",
            [new("bookings", "Tour bookings", "int"), new("seats", "Seats booked", "int"), new("revenue", "Revenue", "money")],
            $$"""
            SELECT count(*) AS bookings, COALESCE(sum(pb.seats_booked), 0) AS seats, COALESCE(sum(pb.total_amount), 0) AS revenue
            FROM udrive.package_bookings pb JOIN udrive.tour_packages tp ON tp.id = pb.tour_package_id
            LEFT JOIN udrive.vehicles v ON v.id = tp.vehicle_id LEFT JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
            WHERE pb.status <> 'Cancelled' AND {{W("pb.created_at")}} AND {{VS}}
            """,
            new("hbar", "Revenue by destination", "destination", [("revenue", "Revenue", "bar")], Limit: 15),
            [
                new("destination", "Destination", "text"), new("tours", "Tours", "int", "sum"),
                new("bookings", "Bookings", "int", "sum"), new("seats", "Seats", "int", "sum"),
                new("revenue", "Revenue", "money", "sum"), new("per_seat", "Per seat", "money", "avg"),
            ],
            $$"""
            SELECT COALESCE(d.name_en, tp.title) AS destination, count(DISTINCT tp.id) AS tours, count(*) AS bookings,
                   sum(pb.seats_booked) AS seats, sum(pb.total_amount) AS revenue,
                   sum(pb.total_amount) / NULLIF(sum(pb.seats_booked), 0) AS per_seat
            FROM udrive.package_bookings pb JOIN udrive.tour_packages tp ON tp.id = pb.tour_package_id
            LEFT JOIN udrive.destinations d ON d.id = tp.destination_id
            LEFT JOIN udrive.vehicles v ON v.id = tp.vehicle_id LEFT JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
            WHERE pb.status <> 'Cancelled' AND {{W("pb.created_at")}} AND {{VS}}
            GROUP BY 1 ORDER BY revenue DESC
            """),

        new("tours.waitlist", "Tours", "Tour waitlist",
            "Customers waiting for a seat on a full tour.",
            [new("waiting", "Waiting", "int"), new("seats", "Seats wanted", "int")],
            $$"""
            SELECT count(*) FILTER (WHERE w.status IN ('Waiting','Pending','Active')) AS waiting,
                   COALESCE(sum(w.seats_requested) FILTER (WHERE w.status IN ('Waiting','Pending','Active')), 0) AS seats
            FROM udrive.package_waitlist w JOIN udrive.tour_packages tp ON tp.id = w.tour_package_id
            LEFT JOIN udrive.vehicles v ON v.id = tp.vehicle_id LEFT JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
            WHERE {{W("w.created_at")}} AND {{VS}}
            """,
            new("bar", "Waiting by tour", "tour", [("seats", "Seats wanted", "bar")], Limit: 15),
            [
                new("tour", "Tour", "text"), new("departure", "Departs", "datetime"), new("customer", "Customer", "text"),
                new("phone", "Phone", "text"), new("seats", "Seats", "int", "sum"), new("status", "Status", "badge"),
                new("added", "Joined", "datetime"),
            ],
            $$"""
            SELECT tp.title AS tour, {{TS("tp.departure_at")}} AS departure, u.full_name AS customer, u.phone_number AS phone,
                   w.seats_requested AS seats, w.status, {{TS("w.created_at")}} AS added
            FROM udrive.package_waitlist w JOIN udrive.tour_packages tp ON tp.id = w.tour_package_id
            LEFT JOIN udrive.users u ON u.id = w.customer_user_id
            LEFT JOIN udrive.vehicles v ON v.id = tp.vehicle_id LEFT JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
            WHERE {{W("w.created_at")}} AND {{VS}} ORDER BY w.created_at DESC
            """),

        // ═════════════════════════════════════ Rentals
        new("rentals.bookings", "Rentals", "Rent-a-car bookings",
            "Every rental booked in the period.",
            [new("bookings", "Rentals", "int"), new("days", "Days", "int"), new("revenue", "Value", "money"), new("cancelled", "Cancelled", "int")],
            $$"""
            SELECT count(*) AS bookings, COALESCE(sum(rb.days), 0) AS days,
                   COALESCE(sum(rb.subtotal) FILTER (WHERE rb.status <> 'Cancelled'), 0) AS revenue,
                   count(*) FILTER (WHERE rb.status IN ('Cancelled','Declined','Expired')) AS cancelled
            FROM udrive.rental_bookings rb JOIN udrive.vehicles v ON v.id = rb.vehicle_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
            WHERE {{W("rb.created_at")}} AND {{VS}}
            """,
            new("bar", "Rentals over time", "period", [("bookings", "Rentals", "bar")],
                $$"""
                SELECT {{B("rb.created_at")}} AS period, count(*) AS bookings,
                       COALESCE(sum(rb.subtotal) FILTER (WHERE rb.status <> 'Cancelled'), 0) AS revenue
                FROM udrive.rental_bookings rb JOIN udrive.vehicles v ON v.id = rb.vehicle_id
                LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                WHERE {{W("rb.created_at")}} AND {{VS}} GROUP BY 1 ORDER BY 1
                """),
            [
                new("reference", "Rental", "text"), new("vehicle", "Vehicle", "text"), new("area", "Area", "text"),
                new("customer", "Customer", "text"), new("dates", "Dates", "text"), new("mode", "Mode", "text"),
                new("days", "Days", "int", "sum"), new("amount", "Amount", "money", "sum"), new("status", "Status", "badge"),
            ],
            $$"""
            SELECT rb.booking_reference AS reference, concat(v.make, ' ', v.model, ' · ', v.registration_number) AS vehicle,
                   udrive.area_label(COALESCE(v.territory_id, dp.territory_id)) AS area, u.full_name AS customer,
                   to_char(rb.start_date, 'DD Mon') || ' – ' || to_char(rb.end_date, 'DD Mon YYYY') AS dates,
                   COALESCE(rb.rental_mode, '—') AS mode, rb.days, rb.subtotal AS amount, rb.status
            FROM udrive.rental_bookings rb JOIN udrive.vehicles v ON v.id = rb.vehicle_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id LEFT JOIN udrive.users u ON u.id = rb.customer_user_id
            WHERE {{W("rb.created_at")}} AND {{VS}} ORDER BY rb.created_at DESC
            """,
            Trend: true),

        new("rentals.attention", "Rentals", "Rentals needing attention",
            "Rentals still waiting for the owner, and cars not returned on time (today).",
            [new("pending_owner", "Waiting for owner", "int"), new("overdue", "Overdue returns", "int")],
            $$"""
            SELECT count(*) FILTER (WHERE rb.status = 'PendingOwner') AS pending_owner,
                   count(*) FILTER (WHERE rb.status = 'HandedOver' AND rb.end_date < (now() AT TIME ZONE 'Asia/Karachi')::date) AS overdue
            FROM udrive.rental_bookings rb JOIN udrive.vehicles v ON v.id = rb.vehicle_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id WHERE {{VS}}
            """,
            null,
            [
                new("reference", "Rental", "text"), new("vehicle", "Vehicle", "text"), new("owner", "Owner", "text"),
                new("owner_phone", "Owner phone", "text"), new("customer", "Customer", "text"), new("state", "Needs", "badge"),
                new("due", "Due", "datetime"), new("days_late", "Days late", "int", "sum"),
            ],
            $$"""
            SELECT rb.booking_reference AS reference, concat(v.make, ' ', v.model, ' · ', v.registration_number) AS vehicle,
                   ou.full_name AS owner, ou.phone_number AS owner_phone, cu.full_name AS customer,
                   CASE WHEN rb.status = 'PendingOwner' THEN 'Owner reply' ELSE 'Return overdue' END AS state,
                   CASE WHEN rb.status = 'PendingOwner' THEN {{TS("rb.owner_respond_by")}} ELSE to_char(rb.end_date, 'YYYY-MM-DD') END AS due,
                   CASE WHEN rb.status = 'HandedOver' THEN (now() AT TIME ZONE 'Asia/Karachi')::date - rb.end_date ELSE 0 END AS days_late
            FROM udrive.rental_bookings rb JOIN udrive.vehicles v ON v.id = rb.vehicle_id
            LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id LEFT JOIN udrive.users ou ON ou.id = dp.user_id
            LEFT JOIN udrive.users cu ON cu.id = rb.customer_user_id
            WHERE {{VS}} AND (rb.status = 'PendingOwner'
                   OR (rb.status = 'HandedOver' AND rb.end_date < (now() AT TIME ZONE 'Asia/Karachi')::date))
            ORDER BY days_late DESC, rb.created_at
            """,
            UsesDates: false),

        // ═════════════════════════════════════ Hotels
        new("hotels.bookings", "Hotels", "Hotel bookings",
            "Bookings, room nights and value for each hotel.",
            [new("bookings", "Bookings", "int"), new("nights", "Room nights", "int"), new("revenue", "Value", "money"), new("hotels", "Hotels booked", "int")],
            $$"""
            SELECT count(*) AS bookings, COALESCE(sum((hb.check_out - hb.check_in) * GREATEST(hb.rooms, 1)), 0) AS nights,
                   COALESCE(sum(hb.amount) FILTER (WHERE hb.status NOT IN ('Cancelled','Rejected')), 0) AS revenue,
                   count(DISTINCT hb.hotel_id) AS hotels
            FROM udrive.hotel_bookings hb JOIN udrive.hotels h ON h.id = hb.hotel_id
            WHERE {{W("hb.created_at")}} AND {{HS}}
            """,
            new("hbar", "Top 10 hotels by value", "hotel", [("revenue", "Value", "bar")], Limit: 10),
            [
                new("hotel", "Hotel", "text"), new("area", "Area", "text"), new("bookings", "Bookings", "int", "sum"),
                new("nights", "Room nights", "int", "sum"), new("guests", "Guests", "int", "sum"),
                new("revenue", "Value", "money", "sum"), new("cancelled", "Cancelled", "int", "sum"),
            ],
            $$"""
            SELECT h.name AS hotel, udrive.area_label(h.territory_id) AS area, count(*) AS bookings,
                   sum((hb.check_out - hb.check_in) * GREATEST(hb.rooms, 1)) AS nights, sum(hb.guests) AS guests,
                   COALESCE(sum(hb.amount) FILTER (WHERE hb.status NOT IN ('Cancelled','Rejected')), 0) AS revenue,
                   count(*) FILTER (WHERE hb.status IN ('Cancelled','Rejected')) AS cancelled
            FROM udrive.hotel_bookings hb JOIN udrive.hotels h ON h.id = hb.hotel_id
            WHERE {{W("hb.created_at")}} AND {{HS}}
            GROUP BY h.id, h.name, h.territory_id ORDER BY revenue DESC
            """),

        // ═════════════════════════════════════ Safety & quality
        new("safety.sos", "Safety & quality", "SOS & emergencies",
            "Emergency cases raised during trips and how fast UDrive responded.",
            [new("cases", "Cases", "int"), new("open", "Still open", "int"), new("response", "Average response", "minutes")],
            $$"""
            SELECT count(*) AS cases, count(*) FILTER (WHERE ec.resolved_at IS NULL) AS open,
                   avg(extract(epoch FROM ec.acknowledged_at - ec.created_at) / 60) AS response
            FROM udrive.emergency_cases ec LEFT JOIN udrive.bookings b ON b.id = ec.booking_id
            WHERE {{W("ec.created_at")}} AND {{BS}}
            """,
            new("line", "Cases over time", "period", [("cases", "Cases", "bar")],
                $$"""
                SELECT {{B("ec.created_at")}} AS period, count(*) AS cases
                FROM udrive.emergency_cases ec LEFT JOIN udrive.bookings b ON b.id = ec.booking_id
                WHERE {{W("ec.created_at")}} AND {{BS}} GROUP BY 1 ORDER BY 1
                """),
            [
                new("reference", "Case", "text"), new("at", "Raised", "datetime"), new("area", "Area", "text"),
                new("booking", "Booking", "text"), new("type", "Type", "text"), new("severity", "Severity", "badge"),
                new("status", "Status", "badge"), new("response", "Response (min)", "minutes", "avg"),
            ],
            $$"""
            SELECT ec.case_reference AS reference, {{TS("ec.created_at")}} AS at, udrive.area_label(b.territory_id) AS area,
                   b.booking_reference AS booking, ec.emergency_type AS type, ec.severity, ec.status,
                   extract(epoch FROM ec.acknowledged_at - ec.created_at) / 60 AS response
            FROM udrive.emergency_cases ec LEFT JOIN udrive.bookings b ON b.id = ec.booking_id
            WHERE {{W("ec.created_at")}} AND {{BS}} ORDER BY ec.created_at DESC
            """,
            Trend: true),

        new("safety.incidents", "Safety & quality", "Safety incidents",
            "Safety reports by type and severity.",
            [new("count", "Incidents", "int"), new("high", "High / critical", "int"), new("open", "Open", "int")],
            $$"""
            SELECT count(*) AS count, count(*) FILTER (WHERE si.severity IN ('High','Critical')) AS high,
                   count(*) FILTER (WHERE si.resolved_at IS NULL) AS open
            FROM udrive.safety_incidents si LEFT JOIN udrive.bookings b ON b.id = si.booking_id
            WHERE {{W("si.created_at")}} AND {{BS}}
            """,
            new("donut", "By severity", "severity", [("count", "Incidents", "bar")],
                $$"""
                SELECT si.severity, count(*) AS count FROM udrive.safety_incidents si LEFT JOIN udrive.bookings b ON b.id = si.booking_id
                WHERE {{W("si.created_at")}} AND {{BS}} GROUP BY 1 ORDER BY 2 DESC
                """),
            [
                new("at", "Reported", "datetime"), new("area", "Area", "text"), new("booking", "Booking", "text"),
                new("type", "Type", "text"), new("severity", "Severity", "badge"), new("status", "Status", "badge"),
                new("reporter", "Reported by", "text"),
            ],
            $$"""
            SELECT {{TS("si.created_at")}} AS at, udrive.area_label(b.territory_id) AS area, b.booking_reference AS booking,
                   si.incident_type AS type, si.severity, si.status, u.full_name AS reporter
            FROM udrive.safety_incidents si LEFT JOIN udrive.bookings b ON b.id = si.booking_id
            LEFT JOIN udrive.users u ON u.id = si.reported_by_user_id
            WHERE {{W("si.created_at")}} AND {{BS}} ORDER BY si.created_at DESC
            """),

        new("safety.disputes", "Safety & quality", "Disputes",
            "Fare and service disputes and how long they took to settle.",
            [new("count", "Disputes", "int"), new("open", "Open", "int"), new("avg_days", "Average days to resolve", "num"), new("amount", "Amount in dispute", "money")],
            $$"""
            SELECT count(*) AS count, count(*) FILTER (WHERE dc.resolved_at IS NULL AND dc.closed_at IS NULL) AS open,
                   avg(extract(epoch FROM COALESCE(dc.resolved_at, dc.closed_at) - dc.created_at) / 86400) AS avg_days,
                   COALESCE(sum(dc.disputed_amount), 0) AS amount
            FROM udrive.dispute_cases dc LEFT JOIN udrive.bookings b ON b.id = dc.booking_id
            WHERE {{W("dc.created_at")}} AND {{BS}}
            """,
            new("bar", "Disputes by category", "category", [("count", "Disputes", "bar")],
                $$"""
                SELECT COALESCE(dc.category, '—') AS category, count(*) AS count
                FROM udrive.dispute_cases dc LEFT JOIN udrive.bookings b ON b.id = dc.booking_id
                WHERE {{W("dc.created_at")}} AND {{BS}} GROUP BY 1 ORDER BY 2 DESC
                """),
            [
                new("reference", "Case", "text"), new("opened", "Opened", "datetime"), new("booking", "Booking", "text"),
                new("category", "Category", "text"), new("priority", "Priority", "badge"), new("amount", "Amount", "money", "sum"),
                new("status", "Status", "badge"), new("days", "Days", "num", "avg"),
            ],
            $$"""
            SELECT dc.case_reference AS reference, {{TS("dc.created_at")}} AS opened, b.booking_reference AS booking,
                   dc.category, dc.priority, dc.disputed_amount AS amount, dc.status,
                   extract(epoch FROM COALESCE(dc.resolved_at, dc.closed_at, now()) - dc.created_at) / 86400 AS days
            FROM udrive.dispute_cases dc LEFT JOIN udrive.bookings b ON b.id = dc.booking_id
            WHERE {{W("dc.created_at")}} AND {{BS}} ORDER BY dc.created_at DESC
            """),

        new("safety.tickets", "Safety & quality", "Support tickets (service level)",
            "How quickly tickets were resolved; the target is within 24 hours.",
            [new("count", "Tickets", "int"), new("open", "Open", "int"), new("avg_hours", "Average hours to resolve", "num"), new("breached", "Over 24 hours", "int")],
            $$"""
            SELECT count(*) AS count, count(*) FILTER (WHERE st.resolved_at IS NULL) AS open,
                   avg(extract(epoch FROM st.resolved_at - st.created_at) / 3600) AS avg_hours,
                   count(*) FILTER (WHERE COALESCE(st.resolved_at, now()) - st.created_at > interval '24 hours') AS breached
            FROM udrive.support_tickets st LEFT JOIN udrive.bookings b ON b.id = st.booking_id
            WHERE {{W("st.created_at")}} AND {{BS}}
            """,
            new("line", "Opened and resolved", "period", [("opened", "Opened", "line"), ("resolved", "Resolved", "line")],
                $$"""
                SELECT {{B("st.created_at")}} AS period, count(*) AS opened, count(*) FILTER (WHERE st.resolved_at IS NOT NULL) AS resolved
                FROM udrive.support_tickets st LEFT JOIN udrive.bookings b ON b.id = st.booking_id
                WHERE {{W("st.created_at")}} AND {{BS}} GROUP BY 1 ORDER BY 1
                """),
            [
                new("reference", "Ticket", "text"), new("opened", "Opened", "datetime"), new("category", "Category", "text"),
                new("priority", "Priority", "badge"), new("assigned", "Assigned to", "text"),
                new("resolved", "Resolved", "datetime"), new("hours", "Hours", "num", "avg"), new("sla", "Service level", "badge"),
            ],
            $$"""
            SELECT st.reference, {{TS("st.created_at")}} AS opened, st.category, st.priority, au.full_name AS assigned,
                   {{TS("st.resolved_at")}} AS resolved,
                   extract(epoch FROM COALESCE(st.resolved_at, now()) - st.created_at) / 3600 AS hours,
                   CASE WHEN COALESCE(st.resolved_at, now()) - st.created_at > interval '24 hours' THEN 'Breached'
                        WHEN st.resolved_at IS NULL THEN 'Open' ELSE 'Met' END AS sla
            FROM udrive.support_tickets st LEFT JOIN udrive.bookings b ON b.id = st.booking_id
            LEFT JOIN udrive.users au ON au.id = st.assigned_admin_user_id
            WHERE {{W("st.created_at")}} AND {{BS}} ORDER BY st.created_at DESC
            """,
            Trend: true),

        new("safety.ratings", "Safety & quality", "Ratings distribution",
            "How customers rated their drivers, star by star.",
            [new("count", "Ratings", "int"), new("avg", "Average", "rating"), new("five", "5-star share", "pct"), new("low", "1–2 star ratings", "int")],
            $$"""
            SELECT count(*) AS count, avg(r.overall_rating) AS avg,
                   COALESCE(100.0 * count(*) FILTER (WHERE r.overall_rating = 5) / NULLIF(count(*), 0), 0) AS five,
                   count(*) FILTER (WHERE r.overall_rating <= 2) AS low
            FROM udrive.trip_ratings r JOIN udrive.bookings b ON b.id = r.booking_id
            WHERE r.reviewer_role = 'Customer' AND {{W("r.created_at")}} AND {{BS}}
            """,
            new("bar", "Ratings by stars", "stars", [("count", "Ratings", "bar")]),
            [
                new("stars", "Stars", "text"), new("count", "Ratings", "int", "sum"), new("share", "Share", "pct", "sum"),
                new("driving", "Driving", "rating", "avg"), new("behaviour", "Behaviour", "rating", "avg"),
                new("cleanliness", "Cleanliness", "rating", "avg"), new("punctuality", "Punctuality", "rating", "avg"),
            ],
            $$"""
            SELECT r.overall_rating || ' ★' AS stars, count(*) AS count,
                   100.0 * count(*) / NULLIF(sum(count(*)) OVER (), 0) AS share,
                   avg(r.driving_rating) AS driving, avg(r.behaviour_rating) AS behaviour,
                   avg(r.cleanliness_rating) AS cleanliness, avg(r.punctuality_rating) AS punctuality
            FROM udrive.trip_ratings r JOIN udrive.bookings b ON b.id = r.booking_id
            WHERE r.reviewer_role = 'Customer' AND {{W("r.created_at")}} AND {{BS}}
            GROUP BY r.overall_rating ORDER BY r.overall_rating DESC
            """),

        // ═════════════════════════════════════ Verification
        new("verification.queue", "Verification", "Verification queue",
            "Everything waiting for UDrive to check, and how long it has waited (today).",
            [new("waiting", "Waiting", "int"), new("avg_days", "Average days waiting", "num"), new("old", "Waiting over 3 days", "int")],
            $$"""
            WITH q AS ({{QueueSql}})
            SELECT count(*) AS waiting, avg(days) AS avg_days, count(*) FILTER (WHERE days > 3) AS old FROM q
            """,
            new("bar", "Waiting by tab", "tab", [("waiting", "Waiting", "bar")],
                $$"""
                WITH q AS ({{QueueSql}})
                SELECT tab, count(*) AS waiting FROM q GROUP BY 1 ORDER BY 2 DESC
                """),
            [
                new("item", "Item", "text"), new("tab", "Tab", "badge"), new("area", "Area", "text"),
                new("person", "Person", "text"), new("submitted", "Submitted", "datetime"), new("days", "Days waiting", "num", "avg"),
            ],
            $$"""
            WITH q AS ({{QueueSql}})
            SELECT item, tab, udrive.area_label(area_id) AS area, person, {{TS("submitted_at")}} AS submitted, days
            FROM q ORDER BY days DESC
            """,
            UsesDates: false),

        new("verification.officers", "Verification", "Decisions by officer",
            "Approvals and rejections made by each person in the period.",
            [new("decisions", "Decisions", "int"), new("approved", "Approved", "int"), new("rejected", "Rejected", "int"), new("officers", "People", "int")],
            $$"""
            WITH d AS ({{DecisionSql}})
            SELECT count(*) AS decisions, count(*) FILTER (WHERE approved) AS approved,
                   count(*) FILTER (WHERE NOT approved) AS rejected, count(DISTINCT officer) AS officers FROM d
            """,
            new("stacked", "Decisions per person", "officer", [("approved", "Approved", "bar"), ("rejected", "Rejected", "bar")], Limit: 15),
            [
                new("officer", "Person", "text"), new("drivers", "Drivers", "int", "sum"), new("hotels", "Hotels", "int", "sum"),
                new("businesses", "Businesses", "int", "sum"), new("tours", "Tours", "int", "sum"),
                new("approved", "Approved", "int", "sum"), new("rejected", "Rejected", "int", "sum"),
            ],
            $$"""
            WITH d AS ({{DecisionSql}})
            SELECT COALESCE(u.full_name, '—') AS officer,
                   count(*) FILTER (WHERE d.kind = 'Driver') AS drivers, count(*) FILTER (WHERE d.kind = 'Hotel') AS hotels,
                   count(*) FILTER (WHERE d.kind = 'Business') AS businesses, count(*) FILTER (WHERE d.kind = 'Tour') AS tours,
                   count(*) FILTER (WHERE d.approved) AS approved, count(*) FILTER (WHERE NOT d.approved) AS rejected
            FROM d LEFT JOIN udrive.users u ON u.id = d.officer
            GROUP BY u.full_name ORDER BY count(*) DESC
            """),

        // ═════════════════════════════════════ Growth
        new("growth.campaigns", "Growth", "Driver campaigns",
            "Bonus campaigns: drivers taking part, qualifying and paid.",
            [new("campaigns", "Campaigns", "int"), new("joined", "Drivers taking part", "int"), new("qualified", "Qualified", "int"), new("paid", "Rewards paid", "money")],
            $$"""
            SELECT count(DISTINCT p.campaign_id) AS campaigns, count(DISTINCT p.driver_profile_id) AS joined,
                   count(*) FILTER (WHERE p.qualified_at IS NOT NULL) AS qualified,
                   COALESCE(sum(p.reward_amount) FILTER (WHERE p.credited_at IS NOT NULL), 0) AS paid
            FROM udrive.driver_campaign_progress p JOIN udrive.driver_profiles dp ON dp.id = p.driver_profile_id
            WHERE {{W("p.created_at")}} AND {{DS}}
            """,
            new("stacked", "By campaign", "campaign", [("qualified", "Qualified", "bar"), ("not_yet", "Not yet", "bar")], Limit: 10),
            [
                new("campaign", "Campaign", "text"), new("type", "Type", "text"), new("joined", "Drivers", "int", "sum"),
                new("qualified", "Qualified", "int", "sum"), new("not_yet", "Not yet", "int", "sum"),
                new("paid", "Paid", "money", "sum"), new("budget", "Budget", "money", "sum"),
            ],
            $$"""
            SELECT g.title AS campaign, g.campaign_type AS type, count(DISTINCT p.driver_profile_id) AS joined,
                   count(*) FILTER (WHERE p.qualified_at IS NOT NULL) AS qualified,
                   count(*) FILTER (WHERE p.qualified_at IS NULL) AS not_yet,
                   COALESCE(sum(p.reward_amount) FILTER (WHERE p.credited_at IS NOT NULL), 0) AS paid, g.total_budget AS budget
            FROM udrive.driver_campaign_progress p JOIN udrive.growth_campaigns g ON g.id = p.campaign_id
            JOIN udrive.driver_profiles dp ON dp.id = p.driver_profile_id
            WHERE {{W("p.created_at")}} AND {{DS}}
            GROUP BY g.id, g.title, g.campaign_type, g.total_budget ORDER BY joined DESC
            """),

        new("growth.referrals", "Growth", "Driver referrals",
            "Drivers who brought in other drivers, and how far those drivers got.",
            [new("referrals", "Referrals", "int"), new("verified", "Verified", "int"), new("first_ride", "Reached a first ride", "int")],
            $$"""
            SELECT count(*) AS referrals, count(*) FILTER (WHERE r.verified_at IS NOT NULL) AS verified,
                   count(*) FILTER (WHERE r.first_ride_at IS NOT NULL) AS first_ride
            FROM udrive.driver_referrals r JOIN udrive.driver_profiles dp ON dp.id = r.referrer_driver_profile_id
            WHERE {{W("r.created_at")}} AND {{DS}}
            """,
            new("bar", "Top referrers", "referrer", [("referrals", "Referrals", "bar")],
                $$"""
                SELECT u.full_name AS referrer, count(*) AS referrals
                FROM udrive.driver_referrals r JOIN udrive.driver_profiles dp ON dp.id = r.referrer_driver_profile_id
                JOIN udrive.users u ON u.id = dp.user_id
                WHERE {{W("r.created_at")}} AND {{DS}} GROUP BY u.full_name ORDER BY 2 DESC LIMIT 10
                """),
            [
                new("referrer", "Referred by", "text"), new("referred", "New driver", "text"), new("area", "Area", "text"),
                new("joined", "Joined", "datetime"), new("verified", "Verified", "datetime"),
                new("first_ride", "First ride", "datetime"), new("status", "Status", "badge"),
            ],
            $$"""
            SELECT ru.full_name AS referrer, nu.full_name AS referred, udrive.area_label(dp.territory_id) AS area,
                   {{TS("r.created_at")}} AS joined, {{TS("r.verified_at")}} AS verified, {{TS("r.first_ride_at")}} AS first_ride, r.status
            FROM udrive.driver_referrals r JOIN udrive.driver_profiles dp ON dp.id = r.referrer_driver_profile_id
            JOIN udrive.users ru ON ru.id = dp.user_id
            LEFT JOIN udrive.driver_profiles np ON np.id = r.referred_driver_profile_id LEFT JOIN udrive.users nu ON nu.id = np.user_id
            WHERE {{W("r.created_at")}} AND {{DS}} ORDER BY r.created_at DESC
            """),

        new("growth.founding", "Growth", "Founding drivers",
            "Drivers who hold founding status (today).",
            [new("active", "Founding drivers", "int"), new("revoked", "Revoked", "int")],
            $$"""
            SELECT count(*) FILTER (WHERE f.revoked_at IS NULL) AS active, count(*) FILTER (WHERE f.revoked_at IS NOT NULL) AS revoked
            FROM udrive.founding_drivers f JOIN udrive.driver_profiles dp ON dp.id = f.driver_profile_id WHERE {{DS}}
            """,
            null,
            [
                new("number", "No.", "int"), new("driver", "Driver", "text"), new("phone", "Phone", "text"),
                new("area", "Area", "text"), new("granted", "Granted", "datetime"), new("status", "Status", "badge"),
                new("trips", "Completed trips", "int", "sum"),
            ],
            $$"""
            SELECT f.sequence_no AS number, u.full_name AS driver, u.phone_number AS phone, udrive.area_label(dp.territory_id) AS area,
                   {{TS("f.granted_at")}} AS granted, CASE WHEN f.revoked_at IS NULL THEN 'Active' ELSE 'Revoked' END AS status,
                   dp.completed_trips AS trips
            FROM udrive.founding_drivers f JOIN udrive.driver_profiles dp ON dp.id = f.driver_profile_id
            JOIN udrive.users u ON u.id = dp.user_id
            WHERE {{DS}} ORDER BY f.sequence_no
            """,
            UsesDates: false),

        // ═════════════════════════════════════ Team (SuperAdmin only)
        new("team.actions", "Team", "Staff actions",
            "Everything portal users did in the period, from the audit log. SuperAdmin only.",
            [new("actions", "Actions", "int"), new("users", "People", "int")],
            $$"""
            SELECT count(*) AS actions, count(DISTINCT a.actor_user_id) AS users FROM udrive.audit_logs a WHERE {{W("a.created_at")}}
            """,
            new("hbar", "Actions per person", "person", [("actions", "Actions", "bar")],
                $$"""
                SELECT COALESCE(u.full_name, 'System') AS person, count(*) AS actions
                FROM udrive.audit_logs a LEFT JOIN udrive.users u ON u.id = a.actor_user_id
                WHERE {{W("a.created_at")}} GROUP BY 1 ORDER BY 2 DESC LIMIT 15
                """),
            [
                new("at", "When", "datetime"), new("person", "Person", "text"), new("action", "Action", "text"),
                new("entity", "Record", "text"), new("entity_id", "Record id", "text"), new("ip", "IP", "text"),
            ],
            $$"""
            SELECT {{TS("a.created_at")}} AS at, COALESCE(u.full_name, 'System') AS person, a.action, a.entity_type AS entity,
                   a.entity_id, COALESCE(a.ip_address, '—') AS ip
            FROM udrive.audit_logs a LEFT JOIN udrive.users u ON u.id = a.actor_user_id
            WHERE {{W("a.created_at")}} ORDER BY a.created_at DESC
            """,
            SuperOnly: true),
    ];

    /// <summary>Everything waiting for verification, with its area and age.</summary>
    private static string QueueSql => $$"""
        SELECT u.full_name AS item, 'City driver' AS tab, dp.territory_id AS area_id, u.phone_number AS person,
               COALESCE(dp.submitted_at, dp.created_at) AS submitted_at,
               extract(epoch FROM now() - COALESCE(dp.submitted_at, dp.created_at)) / 86400 AS days
          FROM udrive.driver_profiles dp JOIN udrive.users u ON u.id = dp.user_id
         WHERE dp.verification_status IN ('Submitted','UnderReview','Pending') AND {{DS}}
        UNION ALL
        SELECT concat(v.make, ' ', v.model, ' · ', v.registration_number), 'City vehicle', COALESCE(v.territory_id, dp.territory_id),
               u.full_name, v.created_at, extract(epoch FROM now() - v.created_at) / 86400
          FROM udrive.vehicles v LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id LEFT JOIN udrive.users u ON u.id = dp.user_id
         WHERE v.status IN ('PendingReview','Pending','Submitted') AND {{VS}}
        UNION ALL
        SELECT concat(v.make, ' ', v.model, ' · ', v.registration_number), 'Rent-a-car', COALESCE(v.territory_id, dp.territory_id),
               u.full_name, COALESCE(v.listing_submitted_at, v.created_at), extract(epoch FROM now() - COALESCE(v.listing_submitted_at, v.created_at)) / 86400
          FROM udrive.vehicles v LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id LEFT JOIN udrive.users u ON u.id = dp.user_id
         WHERE v.rent_review_status = 'Pending' AND {{VS}}
        UNION ALL
        SELECT concat(v.make, ' ', v.model, ' · ', v.registration_number), 'Tour vehicle', COALESCE(v.territory_id, dp.territory_id),
               u.full_name, COALESCE(v.listing_submitted_at, v.created_at), extract(epoch FROM now() - COALESCE(v.listing_submitted_at, v.created_at)) / 86400
          FROM udrive.vehicles v LEFT JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id LEFT JOIN udrive.users u ON u.id = dp.user_id
         WHERE v.tour_review_status = 'Pending' AND {{VS}}
        UNION ALL
        SELECT h.name, 'Hotel', h.territory_id, h.contact_phone, h.created_at, extract(epoch FROM now() - h.created_at) / 86400
          FROM udrive.hotels h WHERE h.approval_status = 'Pending' AND {{HS}}
        UNION ALL
        SELECT bz.name, 'Business', bz.territory_id, bz.phone, bz.created_at, extract(epoch FROM now() - bz.created_at) / 86400
          FROM udrive.businesses bz WHERE bz.approval_status = 'Pending' AND (@all OR bz.territory_id = ANY(@areas))
        """;

    /// <summary>Verification decisions with who made them, inside the period.</summary>
    private static string DecisionSql => $$"""
        SELECT 'Driver' AS kind, dp.reviewed_by_user_id AS officer, dp.verification_status = 'Approved' AS approved
          FROM udrive.driver_profiles dp
         WHERE dp.reviewed_by_user_id IS NOT NULL AND dp.verification_status IN ('Approved','Rejected')
           AND {{W("dp.reviewed_at")}} AND {{DS}}
        UNION ALL
        SELECT 'Hotel', h.approved_by, h.approval_status = 'Approved'
          FROM udrive.hotels h
         WHERE h.approved_by IS NOT NULL AND h.approval_status IN ('Approved','Rejected')
           AND {{W("COALESCE(h.approved_at, h.updated_at)")}} AND {{HS}}
        UNION ALL
        SELECT 'Business', bz.reviewed_by, bz.approval_status = 'Approved'
          FROM udrive.businesses bz
         WHERE bz.reviewed_by IS NOT NULL AND bz.approval_status IN ('Approved','Rejected')
           AND {{W("bz.reviewed_at")}} AND (@all OR bz.territory_id = ANY(@areas))
        UNION ALL
        SELECT 'Tour', tp.reviewed_by_user_id, tp.status NOT IN ('Rejected','ChangesRequired')
          FROM udrive.tour_packages tp LEFT JOIN udrive.vehicles v ON v.id = tp.vehicle_id
          LEFT JOIN udrive.driver_profiles dp ON dp.id = tp.driver_profile_id
         WHERE tp.reviewed_by_user_id IS NOT NULL AND {{W("tp.reviewed_at")}} AND {{VS}}
        """;

    // ───────────────────────────────────────────── scope

    private sealed record Scope(bool Super, HashSet<string> Keys, bool AllAreas, List<Guid> AreaIds);

    private static async Task<Scope> ScopeAsync(NpgsqlConnection cn, Guid userId, bool superAdmin, CancellationToken ct)
    {
        if (superAdmin) return new Scope(true, Defs.Select(d => d.Key).ToHashSet(), true, []);

        var keys = new HashSet<string>(StringComparer.Ordinal);
        await using (var cmd = new NpgsqlCommand("SELECT report_key FROM udrive.staff_report_access WHERE user_id = @id", cn))
        {
            cmd.Parameters.AddWithValue("id", userId);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct)) keys.Add(r.GetString(0));
        }
        keys.IntersectWith(Defs.Where(d => !d.SuperOnly).Select(d => d.Key));

        var all = false;
        await using (var cmd = new NpgsqlCommand("SELECT all_areas FROM udrive.staff_profiles WHERE user_id = @id", cn))
        {
            cmd.Parameters.AddWithValue("id", userId);
            all = await cmd.ExecuteScalarAsync(ct) is true;
        }

        var areas = new List<Guid>();
        await using (var cmd = new NpgsqlCommand("SELECT territory_id FROM udrive.staff_areas WHERE user_id = @id", cn))
        {
            cmd.Parameters.AddWithValue("id", userId);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct)) areas.Add(r.GetGuid(0));
        }

        return new Scope(false, keys, all, areas);
    }

    /// <summary>The ids themselves plus every tehsil under a district among them.</summary>
    private static async Task<List<Guid>> ExpandAsync(NpgsqlConnection cn, IReadOnlyCollection<Guid> ids, CancellationToken ct)
    {
        var list = new List<Guid>();
        if (ids.Count == 0) return list;
        await using var cmd = new NpgsqlCommand(
            "SELECT id FROM udrive.territories WHERE id = ANY(@ids) OR parent_id = ANY(@ids)", cn);
        cmd.Parameters.Add(new NpgsqlParameter("ids", NpgsqlDbType.Array | NpgsqlDbType.Uuid) { Value = ids.ToArray() });
        await using var r = await cmd.ExecuteReaderAsync(ct);
        while (await r.ReadAsync(ct)) list.Add(r.GetGuid(0));
        return list;
    }

    // ───────────────────────────────────────────── catalogue

    private static ReportCatalogItemDto Item(Def d) =>
        new(d.Key, d.Category, d.Title, d.Description, d.UsesDates, d.Trend, d.Filters ?? []);

    /// <summary>Every report, for the Team page's access boxes.</summary>
    public static IReadOnlyList<ReportCatalogItemDto> AssignableReports() =>
        Defs.Where(d => !d.SuperOnly).Select(Item).ToList();

    public async Task<ServiceResult<ReportCatalogDto>> CatalogAsync(Guid userId, bool superAdmin, CancellationToken ct)
    {
        await using var cn = new NpgsqlConnection(connectionString);
        await cn.OpenAsync(ct);
        var scope = await ScopeAsync(cn, userId, superAdmin, ct);
        var reports = Defs.Where(d => scope.Keys.Contains(d.Key) && (!d.SuperOnly || scope.Super)).Select(Item).ToList();

        // The area picker: every district for someone who sees all areas; for
        // anyone else, their districts (whole) and the tehsils they hold.
        var allowed = scope.AllAreas ? null : await ExpandAsync(cn, scope.AreaIds, ct);
        var areas = new List<ReportAreaDto>();
        var rows = new List<(Guid Id, Guid? Parent, string Kind, string Name)>();
        await using (var cmd = new NpgsqlCommand(
            "SELECT id, parent_id, kind, name FROM udrive.territories WHERE kind IN ('City','District','Tehsil') ORDER BY name", cn))
        {
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                rows.Add((r.GetGuid(0), r.IsDBNull(1) ? null : r.GetGuid(1), r.GetString(2), r.GetString(3)));
            }
        }

        foreach (var district in rows.Where(x => x.Kind != "Tehsil"))
        {
            var tehsils = rows.Where(x => x.Kind == "Tehsil" && x.Parent == district.Id)
                .Where(x => allowed is null || allowed.Contains(x.Id))
                .Select(x => new ReportAreaTehsilDto(x.Id, x.Name)).ToList();
            var whole = allowed is null || scope.AreaIds.Contains(district.Id);
            if (!whole && tehsils.Count == 0) continue;
            areas.Add(new ReportAreaDto(district.Id, district.Name, whole, tehsils));
        }

        var label = scope.AllAreas ? "All areas" : areas.Count == 0 ? "No areas assigned" : string.Join(", ",
            areas.Select(a => a.Selectable ? a.Name : a.Name + " › " + string.Join(", ", a.Tehsils.Select(t => t.Name))));

        return ServiceResult<ReportCatalogDto>.Ok(new ReportCatalogDto(
            scope.Super, scope.AllAreas, label, Categories.Where(c => reports.Any(r => r.Category == c)).ToList(), reports, areas));
    }

    // ───────────────────────────────────────────── run

    public async Task<ServiceResult<ReportResultDto>> RunAsync(
        Guid userId, bool superAdmin, string key, ReportQuery query, CancellationToken ct)
    {
        var def = Defs.FirstOrDefault(d => d.Key == key);
        if (def is null) return Fail<ReportResultDto>(404, "report_not_found", "That report does not exist.");

        // Dates: Pakistan days, inclusive. Default: this month so far.
        var today = DateOnly.FromDateTime((DateTimeOffset.UtcNow + Pk).DateTime);
        if (!TryDate(query.From, out var from)) from = new DateOnly(today.Year, today.Month, 1);
        if (!TryDate(query.To, out var to)) to = today;
        if (to < from) (from, to) = (to, from);
        if (to.DayNumber - from.DayNumber > 365)
        {
            return Fail<ReportResultDto>(400, "range_too_long", "Choose a period of one year or less.");
        }

        var start = new DateTimeOffset(from.ToDateTime(TimeOnly.MinValue), Pk);
        var end = new DateTimeOffset(to.AddDays(1).ToDateTime(TimeOnly.MinValue), Pk);
        var length = end - start;
        var prevStart = start - length;
        var prevEnd = start;

        await using var cn = new NpgsqlConnection(connectionString);
        await cn.OpenAsync(ct);
        var scope = await ScopeAsync(cn, userId, superAdmin, ct);
        if ((def.SuperOnly && !scope.Super) || !scope.Keys.Contains(def.Key))
        {
            return Fail<ReportResultDto>(403, "report_forbidden", "This report has not been given to you. Ask an admin.");
        }

        bool all;
        List<Guid> areas;
        string scopeLabel;
        if (query.Area is Guid area)
        {
            var wanted = await ExpandAsync(cn, [area], ct);
            if (wanted.Count == 0) return Fail<ReportResultDto>(400, "area_invalid", "That area does not exist.");
            if (!scope.AllAreas)
            {
                var allowed = await ExpandAsync(cn, scope.AreaIds, ct);
                if (!wanted.All(allowed.Contains))
                {
                    return Fail<ReportResultDto>(403, "area_forbidden", "That area is outside your areas.");
                }
            }
            all = false;
            areas = wanted;
            scopeLabel = await AreaLabelAsync(cn, area, ct);
        }
        else if (scope.AllAreas)
        {
            all = true;
            areas = [];
            scopeLabel = "All areas";
        }
        else
        {
            all = false;
            areas = await ExpandAsync(cn, scope.AreaIds, ct);
            scopeLabel = "Your areas";
        }

        var filters = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var f in def.Filters ?? [])
        {
            var value = query.Filters.TryGetValue(f.Key, out var v) ? (v ?? string.Empty).Trim() : f.Default;
            // Only a listed option (or "all") reaches the SQL.
            filters[f.Key] = value.Length == 0 || f.Options.Contains(value) ? value : f.Default;
        }
        var group = query.Filters.TryGetValue("gb", out var gb) && gb is "week" or "month" ? gb : "day";

        NpgsqlCommand Cmd(string sql, DateTimeOffset a, DateTimeOffset b)
        {
            var cmd = new NpgsqlCommand(sql, cn) { CommandTimeout = 60 };
            cmd.Parameters.AddWithValue("from", a);
            cmd.Parameters.AddWithValue("to", b);
            cmd.Parameters.AddWithValue("all", all);
            cmd.Parameters.Add(new NpgsqlParameter("areas", NpgsqlDbType.Array | NpgsqlDbType.Uuid) { Value = areas.ToArray() });
            cmd.Parameters.AddWithValue("gb", group);
            foreach (var (k, v) in filters) cmd.Parameters.AddWithValue("f_" + k, v);
            return cmd;
        }

        // Tiles, for this period and the one before.
        var current = await OneRowAsync(Cmd(def.TilesSql, start, end), ct);
        var previous = def.UsesDates ? await OneRowAsync(Cmd(def.TilesSql, prevStart, prevEnd), ct) : null;
        var tiles = def.Tiles.Select(t => new ReportTileDto(
            t.Key, t.Label, t.Format, Num(current, t.Key), previous is null ? null : Num(previous, t.Key))).ToList();

        // Table.
        var rows = await RowsAsync(Cmd(def.TableSql + "\nLIMIT " + (MaxRows + 1), start, end), ct);
        var truncated = rows.Count > MaxRows;
        if (truncated) rows.RemoveAt(rows.Count - 1);
        Normalise(rows, def.Columns);

        var totals = new Dictionary<string, object?>(StringComparer.Ordinal);
        var firstText = def.Columns.FirstOrDefault(c => c.Format is "text" or "badge");
        if (firstText is not null) totals[firstText.Key] = "Total";
        foreach (var c in def.Columns.Where(c => c.Total is not null))
        {
            var values = rows.Select(r => r.TryGetValue(c.Key, out var v) ? v as decimal? : null).Where(v => v is not null).Select(v => v!.Value).ToList();
            totals[c.Key] = values.Count == 0 ? null : c.Total == "sum" ? values.Sum() : Math.Round(values.Average(), 4);
        }

        // Chart: its own query, or the first rows of the table.
        ReportChartDto? chart = null;
        if (def.Chart is { } ch)
        {
            List<Dictionary<string, object?>> points;
            if (ch.Sql is not null)
            {
                points = await RowsAsync(Cmd(ch.Sql, start, end), ct);
            }
            else
            {
                points = ch.Limit > 0 ? rows.Take(ch.Limit).ToList() : rows;
            }
            chart = new ReportChartDto(ch.Type, ch.Title, ch.LabelKey,
                ch.Series.Select(s => new ReportSeriesDto(s.Key, s.Label, s.Kind)).ToList(),
                points.Select(p => p.ToDictionary(kv => kv.Key, kv => NumOrValue(kv.Value))).ToList());
        }

        return ServiceResult<ReportResultDto>.Ok(new ReportResultDto(
            def.Key, def.Category, def.Title, def.Description,
            from.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), to.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            DateOnly.FromDateTime(prevStart.DateTime).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            DateOnly.FromDateTime(prevEnd.DateTime).AddDays(-1).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            scopeLabel, tiles, chart,
            def.Columns.Select(c => new ReportColumnDto(c.Key, c.Label, c.Format, c.Total)).ToList(),
            rows, totals, truncated));
    }

    // ───────────────────────────────────────────── access (Team page)

    public async Task<ServiceResult<ReportAccessDto>> AccessAsync(Guid targetId, CancellationToken ct)
    {
        await using var cn = new NpgsqlConnection(connectionString);
        await cn.OpenAsync(ct);
        var (exists, super, team) = await RolesAsync(cn, targetId, ct);
        if (!exists) return Fail<ReportAccessDto>(404, "not_found", "That user was not found.");
        var scope = await ScopeAsync(cn, targetId, super, ct);
        return ServiceResult<ReportAccessDto>.Ok(new ReportAccessDto(
            targetId, super, team, scope.AllAreas, scope.AreaIds,
            super ? AllKeys : scope.Keys.OrderBy(k => k).ToList(), Categories.Where(c => c != "Team").ToList(), AssignableReports()));
    }

    /// <summary>
    /// Sets which reports a user may open. For someone who is not a team user
    /// (Admin, Manager, Operations) the areas are set here too; a team user's
    /// areas are the ones on the main Team form. A team user who manages the
    /// team can only hand out reports they hold themselves.
    /// </summary>
    public async Task<ServiceResult<ReportAccessDto>> SaveAccessAsync(
        Guid actorId, bool actorSuper, bool actorIsTeamUser, Guid targetId, SaveReportAccessRequest request, CancellationToken ct)
    {
        await using var cn = new NpgsqlConnection(connectionString);
        await cn.OpenAsync(ct);
        var (exists, super, team) = await RolesAsync(cn, targetId, ct);
        if (!exists) return Fail<ReportAccessDto>(404, "not_found", "That user was not found.");
        if (super) return Fail<ReportAccessDto>(409, "superadmin", "SuperAdmin always sees every report.");
        if (actorIsTeamUser && !team)
        {
            return Fail<ReportAccessDto>(403, "permission_denied", "Only an admin can change reports for this person.");
        }

        var valid = Defs.Where(d => !d.SuperOnly).Select(d => d.Key).ToHashSet(StringComparer.Ordinal);
        var keys = (request.ReportKeys ?? []).Where(valid.Contains).Distinct().ToList();
        if (actorIsTeamUser && !actorSuper)
        {
            var mine = (await ScopeAsync(cn, actorId, false, ct)).Keys;
            if (keys.Any(k => !mine.Contains(k)))
            {
                return Fail<ReportAccessDto>(403, "permission_denied", "You can only give reports you have yourself.");
            }
        }

        await using var tx = await cn.BeginTransactionAsync(ct);
        await using (var cmd = new NpgsqlCommand("DELETE FROM udrive.staff_report_access WHERE user_id = @id", cn, tx))
        {
            cmd.Parameters.AddWithValue("id", targetId);
            await cmd.ExecuteNonQueryAsync(ct);
        }
        foreach (var k in keys)
        {
            await using var cmd = new NpgsqlCommand(
                "INSERT INTO udrive.staff_report_access (user_id, report_key, granted_by) VALUES (@id, @key, @by)", cn, tx);
            cmd.Parameters.AddWithValue("id", targetId);
            cmd.Parameters.AddWithValue("key", k);
            cmd.Parameters.AddWithValue("by", actorId);
            await cmd.ExecuteNonQueryAsync(ct);
        }

        if (!team && request.AllAreas is bool allAreas)
        {
            await using (var cmd = new NpgsqlCommand(
                """
                INSERT INTO udrive.staff_profiles (user_id, template, all_areas, created_by, updated_by, created_at, updated_at)
                VALUES (@id, 'reports', @all, @by, @by, now(), now())
                ON CONFLICT (user_id) DO UPDATE SET all_areas = EXCLUDED.all_areas, updated_by = EXCLUDED.updated_by, updated_at = now()
                """, cn, tx))
            {
                cmd.Parameters.AddWithValue("id", targetId);
                cmd.Parameters.AddWithValue("all", allAreas);
                cmd.Parameters.AddWithValue("by", actorId);
                await cmd.ExecuteNonQueryAsync(ct);
            }
            await using (var cmd = new NpgsqlCommand("DELETE FROM udrive.staff_areas WHERE user_id = @id", cn, tx))
            {
                cmd.Parameters.AddWithValue("id", targetId);
                await cmd.ExecuteNonQueryAsync(ct);
            }
            if (!allAreas)
            {
                foreach (var a in (request.AreaIds ?? []).Distinct())
                {
                    await using var cmd = new NpgsqlCommand(
                        """
                        INSERT INTO udrive.staff_areas (user_id, territory_id)
                        SELECT @id, t.id FROM udrive.territories t WHERE t.id = @area
                        ON CONFLICT DO NOTHING
                        """, cn, tx);
                    cmd.Parameters.AddWithValue("id", targetId);
                    cmd.Parameters.AddWithValue("area", a);
                    await cmd.ExecuteNonQueryAsync(ct);
                }
            }
        }

        await using (var cmd = new NpgsqlCommand(
            """
            INSERT INTO udrive.audit_logs (id, actor_user_id, action, entity_type, entity_id, changes_json, created_at, updated_at)
            VALUES (gen_random_uuid(), @by, 'team.reports.saved', 'User', @id, @changes::jsonb, now(), now())
            """, cn, tx))
        {
            cmd.Parameters.AddWithValue("by", actorId);
            cmd.Parameters.AddWithValue("id", targetId.ToString());
            cmd.Parameters.AddWithValue("changes", System.Text.Json.JsonSerializer.Serialize(new { reports = keys, request.AllAreas, request.AreaIds }));
            await cmd.ExecuteNonQueryAsync(ct);
        }

        await tx.CommitAsync(ct);
        return await AccessAsync(targetId, ct);
    }

    private static async Task<(bool Exists, bool Super, bool Team)> RolesAsync(NpgsqlConnection cn, Guid id, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(
            """
            SELECT EXISTS (SELECT 1 FROM udrive.users WHERE id = @id),
                   EXISTS (SELECT 1 FROM udrive.user_roles WHERE user_id = @id AND role = 'SuperAdmin')
                     OR EXISTS (SELECT 1 FROM udrive.users WHERE id = @id AND role = 'SuperAdmin'),
                   EXISTS (SELECT 1 FROM udrive.user_roles WHERE user_id = @id AND role = 'Staff')
            """, cn);
        cmd.Parameters.AddWithValue("id", id);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        await r.ReadAsync(ct);
        return (r.GetBoolean(0), r.GetBoolean(1), r.GetBoolean(2));
    }

    // ───────────────────────────────────────────── helpers

    private static async Task<string> AreaLabelAsync(NpgsqlConnection cn, Guid id, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand("SELECT udrive.area_label(@id)", cn);
        cmd.Parameters.AddWithValue("id", id);
        return (await cmd.ExecuteScalarAsync(ct))?.ToString() ?? "—";
    }

    private static bool TryDate(string? value, out DateOnly date) =>
        DateOnly.TryParseExact(value ?? string.Empty, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out date);

    private static async Task<Dictionary<string, object?>?> OneRowAsync(NpgsqlCommand cmd, CancellationToken ct)
    {
        await using (cmd)
        {
            var rows = await RowsAsync(cmd, ct, dispose: false);
            return rows.FirstOrDefault();
        }
    }

    private static async Task<List<Dictionary<string, object?>>> RowsAsync(NpgsqlCommand cmd, CancellationToken ct, bool dispose = true)
    {
        var rows = new List<Dictionary<string, object?>>();
        try
        {
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                var row = new Dictionary<string, object?>(StringComparer.Ordinal);
                for (var i = 0; i < r.FieldCount; i++)
                {
                    row[r.GetName(i)] = r.IsDBNull(i) ? null : Plain(r.GetValue(i));
                }
                rows.Add(row);
            }
        }
        finally
        {
            if (dispose) await cmd.DisposeAsync();
        }
        return rows;
    }

    /// <summary>A database value as a JSON-friendly one: numbers as decimal, text as text.</summary>
    private static object? Plain(object value) => value switch
    {
        string s => s,
        decimal d => d,
        double d => double.IsFinite(d) ? (decimal)d : null,
        float f => float.IsFinite(f) ? (decimal)f : null,
        long l => (decimal)l,
        int i => (decimal)i,
        short s => (decimal)s,
        bool b => b,
        Guid g => g.ToString(),
        DateTime dt => dt.ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture),
        DateTimeOffset dto => dto.ToOffset(Pk).ToString("yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture),
        DateOnly d => d.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
        _ => value.ToString(),
    };

    private static readonly HashSet<string> NumericFormats =
        ["int", "money", "pct", "num", "rating", "minutes", "hours"];

    /// <summary>Numbers as numbers whatever the driver handed back.</summary>
    private static void Normalise(List<Dictionary<string, object?>> rows, Col[] columns)
    {
        foreach (var row in rows)
        {
            foreach (var c in columns)
            {
                if (!row.TryGetValue(c.Key, out var v) || v is null) continue;
                if (NumericFormats.Contains(c.Format) && v is not decimal)
                {
                    row[c.Key] = decimal.TryParse(v.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var d) ? d : null;
                }
                else if (!NumericFormats.Contains(c.Format) && v is not string)
                {
                    row[c.Key] = Convert.ToString(v, CultureInfo.InvariantCulture);
                }
            }
        }
    }

    private static object? NumOrValue(object? value) =>
        value is string s && decimal.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var d) ? d : value;

    private static decimal? Num(Dictionary<string, object?>? row, string key)
    {
        if (row is null || !row.TryGetValue(key, out var v) || v is null) return null;
        if (v is decimal d) return d;
        return decimal.TryParse(v.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var p) ? p : null;
    }

    private static ServiceResult<T> Fail<T>(int status, string code, string message) =>
        ServiceResult<T>.Fail(status, code, message);
}
