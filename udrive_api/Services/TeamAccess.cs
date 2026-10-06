using System.Security.Claims;
using Microsoft.Extensions.Caching.Memory;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Security;

namespace UDrive.Api.Services;

/// <summary>A module of the admin portal and the API routes that belong to it.</summary>
/// <param name="Actions">Which of view / edit / approve / delete make sense for it.</param>
public sealed record TeamModule(string Key, string Label, string Group, string[] Actions, string[] ApiPrefixes, string[] PortalRoutes);

/// <summary>What one team user may do. Null modules = full access (SuperAdmin, Admin and older roles).</summary>
public sealed record TeamGrant(
    bool FullAccess,
    IReadOnlyDictionary<string, TeamModuleGrant> Modules,
    bool AllAreas,
    IReadOnlyList<Guid> Areas);

public sealed record TeamModuleGrant(bool View, bool Edit, bool Approve, bool Delete)
{
    public bool Allows(string action) => action switch
    {
        "view" => View,
        "edit" => Edit,
        "approve" => Approve,
        "delete" => Delete,
        _ => false,
    };
}

/// <summary>
/// The module catalogue and the per-request check for team users (role Staff).
/// </summary>
/// <remarks>
/// <para>
/// Every admin API route belongs to one module, by path prefix. A team user's
/// request is let through only when they hold the needed action on that
/// module; it then carries the Admin role claim for this one request so the
/// existing [Authorize(Roles = …)] attributes accept it. Routes that need
/// SuperAdmin stay closed to them.
/// </para>
/// <para>
/// The verification modules are also limited by area: list routes are
/// filtered (the allowed areas travel in HttpContext.Items), and a route that
/// names one record is refused when that record is outside the user's areas.
/// </para>
/// </remarks>
public static class TeamAccess
{
    public const string StaffRole = "Staff";
    public const string AreasItem = "team.areas";

    private static readonly string[] All4 = ["view", "edit", "approve", "delete"];

    public static readonly TeamModule[] Modules =
    [
        new("verification.city", "City rides (drivers + vehicles)", "Verification", All4,
            ["/api/v1/admin/verification/drivers", "/api/v1/admin/verification/vehicles",
             "/api/v1/admin/verification/driver-documents", "/api/v1/admin/verification/vehicle-documents"],
            ["/verification"]),
        new("verification.tour", "Tour vehicles", "Verification", ["view", "edit", "approve"],
            ["/api/v1/admin/verify/tour"], ["/verification"]),
        new("verification.rent", "Rent-a-car vehicles", "Verification", ["view", "edit", "approve"],
            ["/api/v1/admin/verify/rent"], ["/verification"]),
        new("verification.hotels", "Hotels", "Verification", ["view", "edit", "approve"],
            ["/api/v1/admin/verify/hotels", "/api/v1/hotels/admin"], ["/verification", "/hotels"]),
        new("verification.businesses", "Businesses (Near me)", "Verification", ["view", "edit", "approve"],
            ["/api/v1/admin/verify/businesses", "/api/v1/admin/businesses"], ["/verification", "/businesses"]),
        new("operations", "Rides, bookings & dispatch", "Operations", ["view", "edit"],
            ["/api/v1/admin/operations/bookings", "/api/v1/admin/operations/ride-requests",
             "/api/v1/admin/operations/dashboard", "/api/v1/admin/operations/drivers",
             "/api/v1/admin/operations/vehicles", "/api/v1/admin/trip-operations", "/api/v1/tracking/admin"],
            ["/", "/ride-requests", "/bookings", "/operations", "/live-tracking", "/drivers", "/vehicles"]),
        new("rentals", "Car rentals", "Operations", ["view", "edit"],
            ["/api/v1/admin/rentals"], ["/rentals"]),
        new("customers", "Customers", "Operations", ["view", "edit"],
            ["/api/v1/admin/operations/users"], ["/customers"]),
        new("tourism", "Tour packages, destinations & routes", "Tourism", All4,
            ["/api/v1/admin/packages", "/api/v1/admin/tour-marketplace", "/api/v1/admin/operations/destinations",
             "/api/v1/admin/operations/routes", "/api/v1/admin/operations/advisories", "/api/v1/admin/places"],
            ["/packages", "/destinations", "/routes", "/advisories"]),
        new("finance", "Finance & payments", "Money", ["view", "edit", "approve"],
            ["/api/v1/admin/finance", "/api/v1/admin/wallet-topups", "/api/v1/admin/operations/payments", "/api/v1/payments/"],
            ["/finance", "/payments", "/wallet-topups"]),
        new("pricing", "Pricing & fares", "Money", ["view", "edit", "delete"],
            ["/api/v1/admin/pricing-rules", "/api/v1/admin/seat-fares", "/api/v1/admin/fare"],
            ["/pricing", "/fare-zones", "/fuel-prices", "/rate-insights"]),
        new("growth", "Growth & partners", "Growth", ["view", "edit", "approve"],
            ["/api/v1/admin/growth", "/api/v1/admin/partners"],
            ["/campaigns", "/launch-cities", "/partners", "/territories", "/driver-updates", "/fraud-flags"]),
        new("safety", "Safety, complaints & support", "Trust", ["view", "edit"],
            ["/api/v1/admin/safety", "/api/v1/admin/operations/safety-incidents", "/api/v1/admin/disputes",
             "/api/v1/admin/operations/tickets", "/api/v1/admin/operations/notifications"],
            ["/safety", "/disputes", "/support", "/notifications"]),
        // The Reports Centre (/reports) is not here: each report is given on its
        // own on the Team page (staff_report_access), not through a module.
        new("reports", "Executive operations & audit log", "Reports", ["view"],
            ["/api/v1/admin/executive", "/api/v1/admin/operations/audit-logs"],
            ["/executive-operations", "/audit"]),
        new("settings", "Settings & areas", "Setup", ["view", "edit"],
            ["/api/v1/admin/services", "/api/v1/admin/settings", "/api/v1/admin/operations/settings",
             "/api/v1/admin/areas", "/api/v1/admin/vehicle-images"],
            ["/services", "/settings", "/areas"]),
        new("team", "Team", "Setup", ["view", "edit", "delete"],
            ["/api/v1/admin/team"], ["/team"]),
        new("data", "Data management", "Setup", ["view", "edit", "delete"],
            ["/api/v1/admin/data"], ["/data-management"]),
    ];

    /// <summary>Ready-made sets of permissions; the form starts from one and any box can change.</summary>
    public static readonly IReadOnlyDictionary<string, (string Label, Dictionary<string, string[]> Grants)> Templates =
        new Dictionary<string, (string, Dictionary<string, string[]>)>
        {
            ["verification_officer"] = ("Verification officer", new()
            {
                ["verification.city"] = ["view", "edit", "approve"],
                ["verification.tour"] = ["view", "edit", "approve"],
                ["verification.rent"] = ["view", "edit", "approve"],
                ["verification.hotels"] = ["view", "edit", "approve"],
                ["verification.businesses"] = ["view", "edit", "approve"],
            }),
            ["support"] = ("Support", new()
            {
                ["operations"] = ["view"],
                ["rentals"] = ["view"],
                ["customers"] = ["view"],
                ["safety"] = ["view", "edit"],
            }),
            ["finance"] = ("Finance", new()
            {
                ["finance"] = ["view", "edit", "approve"],
                ["pricing"] = ["view"],
                ["reports"] = ["view"],
            }),
            ["operations_manager"] = ("Operations manager", new()
            {
                ["operations"] = ["view", "edit"],
                ["rentals"] = ["view", "edit"],
                ["customers"] = ["view", "edit"],
                ["tourism"] = ["view", "edit", "approve"],
                ["safety"] = ["view", "edit"],
                ["reports"] = ["view"],
                ["verification.city"] = ["view"],
                ["verification.tour"] = ["view"],
                ["verification.rent"] = ["view"],
                ["verification.hotels"] = ["view"],
                ["verification.businesses"] = ["view"],
            }),
            ["custom"] = ("Custom", new()),
        };

    private static readonly string[] FullAccessRoles =
    [
        "SuperAdmin", "Admin", "Manager", "Operations", "VerificationOfficer",
        "SupportAgent", "FinanceOfficer", "SafetyOfficer", "TourismManager",
    ];

    /// <summary>Is this request from a team user (Staff and nothing broader)?</summary>
    public static bool IsTeamUser(ClaimsPrincipal user) =>
        user.IsInRole(StaffRole) && !FullAccessRoles.Any(user.IsInRole);

    /// <summary>Which module and action a request needs, or null when it is not an admin route.</summary>
    public static (string? Module, string Action, bool AnyVerification)? Resolve(string path, string method)
    {
        var p = path.TrimEnd('/');

        // The Reports Centre checks each report and area itself (ReportsService):
        // a team user needs no module grant to reach it, only reports given to them.
        if (p.StartsWith("/api/v1/admin/reports", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        // Sharing a trip's live location from the Live tracking page.
        if (System.Text.RegularExpressions.Regex.IsMatch(p, "^/api/v1/tracking/[0-9a-fA-F-]{36}/link$"))
        {
            return ("operations", "edit", false);
        }

        if (!(p.StartsWith("/api/v1/admin", StringComparison.OrdinalIgnoreCase)
              || p.StartsWith("/api/v1/hotels/admin", StringComparison.OrdinalIgnoreCase)
              || p.StartsWith("/api/v1/tracking/admin", StringComparison.OrdinalIgnoreCase)
              || (p.StartsWith("/api/v1/payments/", StringComparison.OrdinalIgnoreCase)
                  && p.EndsWith("/confirm", StringComparison.OrdinalIgnoreCase))))
        {
            return null;
        }

        var action = method.ToUpperInvariant() switch
        {
            "GET" or "HEAD" => "view",
            "DELETE" => "delete",
            _ => ApproveSuffix(p) ? "approve" : "edit",
        };

        // Shared verification routes.
        if (p.Equals("/api/v1/admin/verify/summary", StringComparison.OrdinalIgnoreCase)
            || p.StartsWith("/api/v1/admin/verification/files", StringComparison.OrdinalIgnoreCase))
        {
            return (null, "view", true);
        }

        var location = System.Text.RegularExpressions.Regex.Match(
            p, "^/api/v1/admin/verify/([a-z-]+)/[0-9a-fA-F-]{36}/location$", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        if (location.Success)
        {
            var kind = location.Groups[1].Value.ToLowerInvariant();
            var module = kind is "city-driver" or "city-vehicle" ? "verification.city" : "verification." + kind;
            return (module, "edit", false);
        }

        // An owner's drivers and staff listings belong to both tour and rent.
        if (p.StartsWith("/api/v1/admin/fleet-drivers", StringComparison.OrdinalIgnoreCase)
            || p.StartsWith("/api/v1/admin/listings", StringComparison.OrdinalIgnoreCase))
        {
            return ("verification.tour|verification.rent", action, false);
        }

        var best = Modules
            .SelectMany(m => m.ApiPrefixes.Select(prefix => (m.Key, prefix)))
            .Where(x => p.StartsWith(x.prefix, StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(x => x.prefix.Length)
            .FirstOrDefault();
        return best.Key is null ? (null, action, false) : (best.Key, action, false);
    }

    private static bool ApproveSuffix(string p) =>
        p.EndsWith("/approve", StringComparison.OrdinalIgnoreCase)
        || p.EndsWith("/reject", StringComparison.OrdinalIgnoreCase)
        || p.EndsWith("/review", StringComparison.OrdinalIgnoreCase)
        || p.EndsWith("/decision", StringComparison.OrdinalIgnoreCase)
        || p.EndsWith("/request-info", StringComparison.OrdinalIgnoreCase)
        || p.EndsWith("/confirm", StringComparison.OrdinalIgnoreCase);

    /// <summary>Loads a team user's grant; cached for 30 seconds so a change applies within half a minute.</summary>
    public static async Task<TeamGrant> GrantAsync(
        string connectionString, IMemoryCache cache, Guid userId, CancellationToken ct)
    {
        if (cache.TryGetValue("team.grant." + userId, out TeamGrant? cached) && cached is not null) return cached;

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        var grant = await LoadGrantAsync(connection, userId, ct);
        cache.Set("team.grant." + userId, grant, TimeSpan.FromSeconds(30));
        return grant;
    }

    public static void Forget(IMemoryCache cache, Guid userId) => cache.Remove("team.grant." + userId);

    internal static async Task<TeamGrant> LoadGrantAsync(NpgsqlConnection connection, Guid userId, CancellationToken ct)
    {
        var modules = new Dictionary<string, TeamModuleGrant>();
        await using (var command = new NpgsqlCommand(
            "SELECT module, can_view, can_edit, can_approve, can_delete FROM udrive.staff_permissions WHERE user_id = @id;",
            connection))
        {
            command.Parameters.AddWithValue("id", userId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                modules[reader.GetString(0)] = new TeamModuleGrant(
                    reader.GetBoolean(1), reader.GetBoolean(2), reader.GetBoolean(3), reader.GetBoolean(4));
            }
        }

        var allAreas = false;
        await using (var command = new NpgsqlCommand(
            "SELECT all_areas FROM udrive.staff_profiles WHERE user_id = @id;", connection))
        {
            command.Parameters.AddWithValue("id", userId);
            allAreas = await command.ExecuteScalarAsync(ct) is true;
        }

        var areas = new List<Guid>();
        await using (var command = new NpgsqlCommand(
            "SELECT territory_id FROM udrive.staff_areas WHERE user_id = @id;", connection))
        {
            command.Parameters.AddWithValue("id", userId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct)) areas.Add(reader.GetGuid(0));
        }

        return new TeamGrant(false, modules, allAreas, areas);
    }

    /// <summary>
    /// For a route that names one verification record: the table lookup that
    /// gives its tehsil, or null when the route names none.
    /// </summary>
    public static (string Sql, Guid Id)? RecordArea(string path)
    {
        var m = System.Text.RegularExpressions.Regex.Match(path,
            "^/api/v1/(?:admin/verification/(drivers|vehicles)|admin/verify/(tour|rent|hotels|businesses|city-driver|city-vehicle)|admin/fleet-drivers|admin/businesses|hotels/admin)/([0-9a-fA-F-]{36})",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        if (!m.Success || !Guid.TryParse(m.Groups[3].Value, out var id)) return null;
        var kind = (m.Groups[1].Success && m.Groups[1].Value.Length > 0 ? m.Groups[1].Value
                   : m.Groups[2].Success && m.Groups[2].Value.Length > 0 ? m.Groups[2].Value
                   : path.Contains("/fleet-drivers/", StringComparison.OrdinalIgnoreCase) ? "fleet"
                   : path.Contains("/businesses/", StringComparison.OrdinalIgnoreCase) ? "businesses"
                   : "hotels").ToLowerInvariant();
        var sql = kind switch
        {
            "drivers" or "city-driver" => "SELECT territory_id FROM udrive.driver_profiles WHERE id = @id",
            "vehicles" or "city-vehicle" or "tour" or "rent" =>
                "SELECT COALESCE(v.territory_id, dp.territory_id) FROM udrive.vehicles v JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id WHERE v.id = @id",
            "fleet" => "SELECT dp.territory_id FROM udrive.fleet_drivers fd JOIN udrive.driver_profiles dp ON dp.id = fd.owner_profile_id WHERE fd.id = @id",
            "businesses" => "SELECT territory_id FROM udrive.businesses WHERE id = @id",
            _ => "SELECT territory_id FROM udrive.hotels WHERE id = @id",
        };
        return (sql, id);
    }

    /// <summary>Whether a record's tehsil is inside the allowed districts / tehsils.</summary>
    public static async Task<bool> RecordInAreasAsync(
        NpgsqlConnection connection, (string Sql, Guid Id) record, IReadOnlyList<Guid> allowed, CancellationToken ct)
    {
        await using var command = new NpgsqlCommand(
            $"""
            SELECT EXISTS (
                SELECT 1 FROM udrive.territories t
                WHERE t.id = ({record.Sql})
                  AND (t.id = ANY(@allowed) OR t.parent_id = ANY(@allowed)));
            """, connection);
        command.Parameters.AddWithValue("id", record.Id);
        command.Parameters.Add(new NpgsqlParameter("allowed", NpgsqlDbType.Array | NpgsqlDbType.Uuid) { Value = allowed.ToArray() });
        return await command.ExecuteScalarAsync(ct) is true;
    }

    /// <summary>The allowed areas a controller should filter by, or null for all.</summary>
    public static IReadOnlyList<Guid>? AllowedAreas(HttpContext context) =>
        context.Items.TryGetValue(AreasItem, out var value) ? value as IReadOnlyList<Guid> : null;
}

/// <summary>Runs <see cref="TeamAccess"/> on every request between authentication and authorisation.</summary>
public sealed class TeamAccessMiddleware(RequestDelegate next, string connectionString)
{
    public async Task InvokeAsync(HttpContext context, IMemoryCache cache)
    {
        var user = context.User;
        if (user.Identity?.IsAuthenticated != true || !TeamAccess.IsTeamUser(user))
        {
            await next(context);
            return;
        }

        var path = context.Request.Path.Value ?? string.Empty;

        // A team user may always read their own permissions.
        if (path.TrimEnd('/').Equals("/api/v1/admin/team/me", StringComparison.OrdinalIgnoreCase))
        {
            await next(context);
            return;
        }

        var need = TeamAccess.Resolve(path, context.Request.Method);
        if (need is null)
        {
            await next(context);
            return;
        }

        var userId = user.GetRequiredUserId();
        var grant = await TeamAccess.GrantAsync(connectionString, cache, userId, context.RequestAborted);
        var (module, action, anyVerification) = need.Value;

        bool Allowed(string key) => grant.Modules.TryGetValue(key, out var g) && g.Allows(action);
        var ok = anyVerification
            ? grant.Modules.Any(kv => kv.Key.StartsWith("verification.", StringComparison.Ordinal) && kv.Value.View)
            : module is not null && module.Split('|').Any(Allowed);

        if (!ok)
        {
            await Deny(context, "You do not have permission for this. Ask an admin to give you access.");
            return;
        }

        var verification = anyVerification || (module?.StartsWith("verification.", StringComparison.Ordinal) ?? false);
        if (verification && !grant.AllAreas)
        {
            context.Items[TeamAccess.AreasItem] = grant.Areas;
            var record = TeamAccess.RecordArea(path);
            if (record is not null)
            {
                await using var connection = new NpgsqlConnection(connectionString);
                await connection.OpenAsync(context.RequestAborted);
                if (!await TeamAccess.RecordInAreasAsync(connection, record.Value, grant.Areas, context.RequestAborted))
                {
                    await Deny(context, "This is outside your areas.");
                    return;
                }
            }
        }

        // For this request only: the Admin role, so existing [Authorize(Roles)] accept it.
        var identity = new ClaimsIdentity([new Claim(ClaimTypes.Role, "Admin")], "team");
        context.User.AddIdentity(identity);
        await next(context);
    }

    private static async Task Deny(HttpContext context, string message)
    {
        context.Response.StatusCode = StatusCodes.Status403Forbidden;
        await context.Response.WriteAsJsonAsync(new { success = false, error = "permission_denied", message });
    }
}
