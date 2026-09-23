using Npgsql;
using UDrive.Api.Common;
using UDrive.Api.Models;

namespace UDrive.Api.Services;

public sealed class OfflineMapManifestService(string connectionString)
{
    public async Task<ServiceResult<IReadOnlyList<OfflineMapPackDto>>> ListAsync(bool includeInactive, CancellationToken ct)
    {
        const string sql = """
            SELECT id, name, region, south_west_latitude, south_west_longitude,
                   north_east_latitude, north_east_longitude, file_url, file_size,
                   version, checksum, updated_at, status, published_at, minimum_app_version
            FROM udrive.offline_map_packs
            WHERE (@include_inactive OR status = 'active')
            ORDER BY display_order, name;
            """;
        var items = new List<OfflineMapPackDto>();
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("include_inactive", includeInactive);
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct)) items.Add(Read(reader));
        return ServiceResult<IReadOnlyList<OfflineMapPackDto>>.Ok(items);
    }

    public async Task<ServiceResult<OfflineMapPackDto>> UpsertAsync(string id, UpsertOfflineMapPackRequest request, CancellationToken ct)
    {
        var validation = Validate(id, request);
        if (validation is not null) return ServiceResult<OfflineMapPackDto>.Fail(400, "invalid_map_pack", validation);
        const string sql = """
            INSERT INTO udrive.offline_map_packs
              (id,name,region,south_west_latitude,south_west_longitude,north_east_latitude,north_east_longitude,
               file_url,file_size,version,checksum,status,published_at,minimum_app_version,updated_at)
            VALUES
              (@id,@name,@region,@sw_lat,@sw_lon,@ne_lat,@ne_lon,@url,@size,@version,@checksum,@status,@published,@minimum,now())
            ON CONFLICT (id) DO UPDATE SET
              name=excluded.name, region=excluded.region,
              south_west_latitude=excluded.south_west_latitude, south_west_longitude=excluded.south_west_longitude,
              north_east_latitude=excluded.north_east_latitude, north_east_longitude=excluded.north_east_longitude,
              file_url=excluded.file_url, file_size=excluded.file_size, version=excluded.version,
              checksum=excluded.checksum, status=excluded.status, published_at=excluded.published_at,
              minimum_app_version=excluded.minimum_app_version, updated_at=now()
            RETURNING id,name,region,south_west_latitude,south_west_longitude,north_east_latitude,north_east_longitude,
                      file_url,file_size,version,checksum,updated_at,status,published_at,minimum_app_version;
            """;
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", id.Trim().ToLowerInvariant());
        command.Parameters.AddWithValue("name", request.Name.Trim());
        command.Parameters.AddWithValue("region", request.Region.Trim());
        command.Parameters.AddWithValue("sw_lat", request.SouthWestLatitude);
        command.Parameters.AddWithValue("sw_lon", request.SouthWestLongitude);
        command.Parameters.AddWithValue("ne_lat", request.NorthEastLatitude);
        command.Parameters.AddWithValue("ne_lon", request.NorthEastLongitude);
        command.Parameters.AddWithValue("url", (request.FileUrl ?? string.Empty).Trim());
        command.Parameters.AddWithValue("size", request.FileSize);
        command.Parameters.AddWithValue("version", request.Version.Trim());
        command.Parameters.AddWithValue("checksum", (request.Checksum ?? string.Empty).Trim().ToLowerInvariant());
        command.Parameters.AddWithValue("status", request.Status.Trim().ToLowerInvariant());
        command.Parameters.AddWithValue("published", (object?)request.PublishedAt ?? DBNull.Value);
        command.Parameters.AddWithValue("minimum", (object?)request.MinimumAppVersion?.Trim() ?? DBNull.Value);
        await using var reader = await command.ExecuteReaderAsync(ct);
        await reader.ReadAsync(ct);
        return ServiceResult<OfflineMapPackDto>.Ok(Read(reader), "Offline map pack saved.");
    }

    private static string? Validate(string id, UpsertOfflineMapPackRequest r)
    {
        if (string.IsNullOrWhiteSpace(id) || id.Length > 80) return "A valid map ID is required.";
        if (string.IsNullOrWhiteSpace(r.Name) || string.IsNullOrWhiteSpace(r.Region)) return "Name and region are required.";
        if (r.SouthWestLatitude >= r.NorthEastLatitude || r.SouthWestLongitude >= r.NorthEastLongitude) return "Map bounds are invalid.";
        if (r.SouthWestLatitude < -90 || r.NorthEastLatitude > 90 || r.SouthWestLongitude < -180 || r.NorthEastLongitude > 180) return "Map bounds are outside valid coordinates.";
        if (r.FileSize < 0) return "File size cannot be negative.";
        if (string.IsNullOrWhiteSpace(r.Version)) return "Version is required.";
        if (r.Status is not ("active" or "inactive")) return "Status must be active or inactive.";
        if (r.Status == "active" && (string.IsNullOrWhiteSpace(r.FileUrl) || r.FileSize <= 0 || string.IsNullOrWhiteSpace(r.Checksum))) return "Active map packs require URL, file size and checksum.";
        return null;
    }

    private static OfflineMapPackDto Read(NpgsqlDataReader r) => new(
        r.GetString(0), r.GetString(1), r.GetString(2),
        new OfflineMapBoundsDto(new(r.GetDouble(3), r.GetDouble(4)), new(r.GetDouble(5), r.GetDouble(6))),
        r.GetString(7), r.GetInt64(8), r.GetString(9), r.GetString(10),
        r.IsDBNull(11) ? null : r.GetFieldValue<DateTimeOffset>(11), r.GetString(12),
        r.IsDBNull(13) ? null : r.GetFieldValue<DateTimeOffset>(13), r.IsDBNull(14) ? null : r.GetString(14));
}
