namespace UDrive.Api.Models;

/// <summary>
/// The driver asking for the road to the current leg of a live ride.
/// </summary>
/// <param name="Latitude">Where the driver is now.</param>
/// <param name="Longitude">Where the driver is now.</param>
/// <param name="Reroute">
/// True when the driver's phone has seen them leave the stored road. False
/// returns the stored road whenever one exists, so opening the screen twice
/// never costs a second paid call.
/// </param>
public sealed record TripRouteRequest(double Latitude, double Longitude, bool Reroute);

/// <summary>One turn: what to do, where it starts and how long the stretch is.</summary>
/// <param name="Maneuver">
/// Google's maneuver name (TURN_LEFT, ROUNDABOUT_RIGHT, ...). The app maps it to
/// an arrow and an Urdu voice clip; the server does not translate anything.
/// </param>
/// <param name="DistanceMeters">Length of the stretch that starts with this turn.</param>
public sealed record TripRouteStepDto(
    string Maneuver,
    int DistanceMeters,
    double Latitude,
    double Longitude);

/// <summary>
/// The stored road for the current leg of a live ride, read by both apps.
/// </summary>
/// <param name="Available">False when there is no road to show yet.</param>
/// <param name="Reason">
/// Why there is no road, or why a reroute was not made: no_route_yet, no_key,
/// daily_cap, reroute_limit, cooldown, on_route, upstream_error, no_target.
/// Null when a new road was just computed or the stored one was returned as
/// asked.
/// </param>
public sealed record TripRouteDto(
    Guid? RouteId,
    string Leg,
    bool Available,
    string? Reason,
    int DistanceMeters,
    int DurationSeconds,
    string Polyline,
    IReadOnlyList<TripRouteStepDto> Steps,
    DateTimeOffset? CreatedAt,
    double? TargetLatitude,
    double? TargetLongitude,
    int ReroutesUsed,
    int ReroutesAllowed);
