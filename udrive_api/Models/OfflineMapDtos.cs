namespace UDrive.Api.Models;

public sealed record OfflineMapPointDto(double Latitude, double Longitude);
public sealed record OfflineMapBoundsDto(OfflineMapPointDto SouthWest, OfflineMapPointDto NorthEast);
public sealed record OfflineMapPackDto(
    string Id,
    string Name,
    string Region,
    OfflineMapBoundsDto Bounds,
    string FileUrl,
    long FileSize,
    string Version,
    string Checksum,
    DateTimeOffset? UpdatedAt,
    string Status,
    DateTimeOffset? PublishedAt,
    string? MinimumAppVersion);

public sealed record UpsertOfflineMapPackRequest(
    string Name,
    string Region,
    double SouthWestLatitude,
    double SouthWestLongitude,
    double NorthEastLatitude,
    double NorthEastLongitude,
    string? FileUrl,
    long FileSize,
    string Version,
    string? Checksum,
    string Status,
    DateTimeOffset? PublishedAt,
    string? MinimumAppVersion);
