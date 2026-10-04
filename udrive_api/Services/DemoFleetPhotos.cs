using Npgsql;

namespace UDrive.Api.Services;

/// <summary>
/// Photographs for the demo fleet, fetched once by the server and kept in its
/// own storage.
/// </summary>
/// <remarks>
/// The pictures are freely licensed photographs from Wikimedia Commons. They
/// are downloaded here, at the moment an admin presses "Add demo data", and
/// served from <c>/api/v1/vehicle-images/…</c> like any driver's own photo.
/// The customer's phone therefore never contacts Wikimedia — the Privacy
/// Policy does not name it, and a hotlink would hand it every customer's IP
/// address.
///
/// A picture that cannot be fetched is reported back in the portal's message
/// and the car keeps no photo; rentals without a photo are not listed, so the
/// button can simply be pressed again.
/// </remarks>
public sealed class DemoFleetPhotos(
    string connectionString,
    LocalFileStorageService storage,
    IHttpClientFactory httpClients,
    ILogger<DemoFleetPhotos> logger)
{
    public const string HttpClientName = "demo-photos";

    /// <summary>Model → Wikimedia Commons file name.</summary>
    private static readonly Dictionary<string, string> Sources = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Toyota Hiace"] = "Toyota Hiace H200 505.JPG",
        ["Toyota Coaster"] = "Toyota Coaster Mini Bus 2015.jpg",
        ["Toyota Land Cruiser Prado"] = "Toyota Land Cruiser Prado (J150), Bangladesh. (27817531677).jpg",
        ["Suzuki APV"] = "2013 Suzuki APV Arena SGX Luxury 1.5 DN42V (20190623).jpg",
        ["Toyota Corolla"] = "TOYOTA COROLLA SEDAN (E210) China (9).jpg",
        ["Honda Civic"] = "Honda CIVIC SEDAN (DBA-FC1) front.jpg",
        ["Suzuki Jimny"] = "Suzuki Jimny JB23 011.JPG",
        ["Toyota Hilux Revo"] = "2021 Toyota Hilux Revo GR Sport Double-Cab 2.8 4x4.jpg",
    };

    public sealed record Result(int Fitted, IReadOnlyList<string> Missing);

    /// <summary>Gives every demo vehicle without a photo its model's photo.</summary>
    public async Task<Result> FitAsync(CancellationToken ct)
    {
        var vehicles = new List<(Guid Id, string Model)>();
        await using (var connection = new NpgsqlConnection(connectionString))
        {
            await connection.OpenAsync(ct);
            await using var command = connection.CreateCommand();
            command.CommandText = """
                SELECT v.id, trim(concat_ws(' ', v.make, v.model))
                FROM udrive.vehicles v
                JOIN udrive.driver_profiles dp ON dp.id = v.driver_profile_id
                JOIN udrive.users u ON u.id = dp.user_id
                WHERE u.email LIKE @pattern
                  -- Only the cars demo_fleet.sql seeds. The old suspended fleet
                  -- from migration 010 is on demo.% accounts too and is left alone.
                  AND v.id::text LIKE '55000000-0000-0000-0000-%'
                """;
            command.Parameters.AddWithValue("pattern", DemoListing.EmailPattern);
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct)) vehicles.Add((reader.GetGuid(0), reader.GetString(1)));
        }

        var cache = new Dictionary<string, byte[]?>(StringComparer.OrdinalIgnoreCase);
        var missing = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);
        var fitted = 0;

        foreach (var (id, model) in vehicles)
        {
            var folder = Path.Combine(storage.UploadRoot, "vehicle-images", id.ToString("N"));
            var path = Path.Combine(folder, "demo.jpg");
            var url = $"/api/v1/vehicle-images/{id:N}/demo.jpg";

            if (!File.Exists(path))
            {
                if (!cache.TryGetValue(model, out var bytes))
                {
                    bytes = Sources.TryGetValue(model, out var file) ? await DownloadAsync(file, ct) : null;
                    cache[model] = bytes;
                }
                if (bytes is null)
                {
                    missing.Add(model);
                    continue;
                }
                Directory.CreateDirectory(folder);
                await File.WriteAllBytesAsync(path, bytes, ct);
            }

            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(ct);
            await using var update = connection.CreateCommand();
            update.CommandText = """
                UPDATE udrive.vehicles SET image_url = @url, updated_at = now() WHERE id = @id;
                UPDATE udrive.tour_packages SET cover_image_url = @url, updated_at = now() WHERE vehicle_id = @id;
                """;
            update.Parameters.AddWithValue("url", url);
            update.Parameters.AddWithValue("id", id);
            await update.ExecuteNonQueryAsync(ct);
            fitted++;
        }

        return new Result(fitted, missing.ToList());
    }

    /// <summary>Deletes the stored photos of these vehicles.</summary>
    public int Delete(IEnumerable<Guid> vehicleIds)
    {
        var removed = 0;
        foreach (var id in vehicleIds)
        {
            var folder = Path.Combine(storage.UploadRoot, "vehicle-images", id.ToString("N"));
            try
            {
                if (Directory.Exists(folder))
                {
                    Directory.Delete(folder, recursive: true);
                    removed++;
                }
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Could not delete demo photo folder {Folder}", folder);
            }
        }
        return removed;
    }

    private async Task<byte[]?> DownloadAsync(string commonsFile, CancellationToken ct)
    {
        var url = "https://commons.wikimedia.org/wiki/Special:FilePath/"
            + Uri.EscapeDataString(commonsFile) + "?width=900";
        try
        {
            var client = httpClients.CreateClient(HttpClientName);
            using var response = await client.GetAsync(url, ct);
            if (!response.IsSuccessStatusCode)
            {
                logger.LogWarning("Demo photo {File} returned {Status}", commonsFile, (int)response.StatusCode);
                return null;
            }
            var bytes = await response.Content.ReadAsByteArrayAsync(ct);
            // A JPEG, and a sensible size — anything else is an error page.
            var isJpeg = bytes.Length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
            if (!isJpeg || bytes.Length < 5_000 || bytes.Length > 8 * 1024 * 1024)
            {
                logger.LogWarning("Demo photo {File} was not a usable JPEG ({Length} bytes)", commonsFile, bytes.Length);
                return null;
            }
            return bytes;
        }
        catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException)
        {
            logger.LogWarning(exception, "Demo photo {File} could not be downloaded", commonsFile);
            return null;
        }
    }
}
