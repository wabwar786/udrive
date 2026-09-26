namespace UDrive.Api.Services;

/// <summary>
/// The four accounts the self-test signs in as.
/// </summary>
/// <remarks>
/// These constants are used to create, find and clean up the accounts.
///
/// The four queries that hide self-test traffic from real users do NOT read
/// them — a C# <c>const</c> SQL string cannot have a constant interpolated into
/// the middle of it without being cut in half first, so each of those writes
/// <c>'selftest.%@udrive.local'</c> out by hand. They are in
/// <c>BookingService.GetEligibleRideRequestsAsync</c>,
/// <c>MarketplacePricingService.GetAvailableVehiclesAsync</c> and
/// <c>GetNearbyVehiclesAsync</c>, and <c>HotelService.SearchAsync</c>. If
/// <see cref="EmailPattern"/> ever changes, those four change with it.
///
/// The prefix is <c>selftest.</c> rather than <c>demo.</c> on purpose.
/// <see cref="MarketplacePricingService"/> carries an <c>IsDemo</c> flag keyed
/// on <c>demo.%@udrive.local</c>, and reusing that prefix would have made the
/// self-test driver a demo vehicle in the customer app.
/// </remarks>
public static class SelfTestAccounts
{
    public const string CustomerEmail = "selftest.customer@udrive.local";
    public const string DriverEmail = "selftest.driver@udrive.local";
    public const string HotelOwnerEmail = "selftest.hotel@udrive.local";

    /// <summary>The account that approves the hotel and the tour package.</summary>
    /// <remarks>
    /// <c>Admin</c>, never <c>SuperAdmin</c>. The run needs exactly two admin
    /// endpoints — hotel review and package review — and both accept Admin. A
    /// SuperAdmin account standing in a production database would carry every
    /// other privilege in the platform for no reason at all.
    ///
    /// It has no password, so the admin portal's sign-in cannot reach it, and it
    /// is <c>Suspended</c> except during a run, so a token for it is refused by
    /// the JWT handler even if one existed.
    /// </remarks>
    public const string AdminEmail = "selftest.admin@udrive.local";

    /// <summary>Numbers reserved for the harness, outside any range in real use.</summary>
    /// <remarks>
    /// +92 300 000 00xx is the block the Play reviewer account already sits in
    /// (+923000000001, from migration 003), so it is understood across the
    /// project to mean "not a person". These are 51 to 54; nothing else uses
    /// them.
    /// </remarks>
    public const string CustomerPhone = "+923000000051";
    public const string DriverPhone = "+923000000052";
    public const string HotelOwnerPhone = "+923000000053";
    public const string AdminPhone = "+923000000054";

    public const string EmailPattern = "selftest.%@udrive.local";

    public const string CustomerName = "Self-test Customer";
    public const string DriverName = "Self-test Driver";
    public const string HotelOwnerName = "Self-test Hotel Owner";
    public const string AdminName = "Self-test Admin";

    /// <summary>The registration plate on the harness vehicle.</summary>
    /// <remarks>
    /// Says what it is on the plate itself, so anyone who finds this vehicle in
    /// a database or an admin list knows immediately that it is not a car.
    /// </remarks>
    public const string VehicleRegistration = "AJK-SELFTEST-01";

    public static readonly string[] AllEmails =
        [CustomerEmail, DriverEmail, HotelOwnerEmail, AdminEmail];
}
