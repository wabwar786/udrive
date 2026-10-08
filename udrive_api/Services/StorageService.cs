using System.Collections.Concurrent;
using System.Text.RegularExpressions;
using Npgsql;
using UDrive.Api.Common;

namespace UDrive.Api.Services;

public sealed record StorageFolderDto(string Name, int Files, long Bytes);

public sealed record StorageSummaryDto(
    string UploadRoot,
    bool Ephemeral,
    long UsedBytes,
    int Files,
    long? VolumeTotalBytes,
    long? VolumeFreeBytes,
    long TrashBytes,
    int TrashFiles,
    IReadOnlyList<StorageFolderDto> Folders);

public sealed record StorageShrinkDto(int Shrunk, long SavedBytes, int Remaining);

public sealed record StorageOrphansDto(int Files, long Bytes, IReadOnlyList<string> Sample, int Moved);

/// <summary>
/// Settings → Storage: how full the upload volume is, shrinking old photos in
/// place, and moving files nothing points at into a trash that empties itself.
/// </summary>
/// <remarks>
/// Old photos keep their file names when shrunk (the stored links stay valid;
/// files are served by their bytes, not their names). Nothing is deleted
/// outright: unreferenced files go to <c>_trash</c> and are removed 30 days
/// later, so a mistake can be undone by moving a file back.
/// </remarks>
public sealed partial class StorageService(string connectionString, LocalFileStorageService storage)
{
    public const string TrashFolder = "_trash";
    private const string EvidenceFolder = "partner-signature";
    private const long ShrinkAbove = 220 * 1024;

    // Files that did not get smaller, so a second batch does not try them again.
    private static readonly ConcurrentDictionary<string, byte> Skip = new();

    [GeneratedRegex(@"^[0-9a-f]{32}\.(jpe?g|png|webp|pdf)$", RegexOptions.IgnoreCase)]
    private static partial Regex StoredName();

    public ServiceResult<StorageSummaryDto> Summary()
    {
        var root = storage.UploadRoot;
        var folders = new List<StorageFolderDto>();
        long used = 0, trash = 0;
        int files = 0, trashFiles = 0;
        if (Directory.Exists(root))
        {
            foreach (var dir in Directory.EnumerateDirectories(root))
            {
                var name = Path.GetFileName(dir);
                int count = 0;
                long bytes = 0;
                foreach (var file in SafeFiles(dir))
                {
                    count++;
                    bytes += SafeLength(file);
                }

                if (name == TrashFolder)
                {
                    trash = bytes;
                    trashFiles = count;
                }
                else
                {
                    folders.Add(new StorageFolderDto(name, count, bytes));
                }

                used += bytes;
                files += count;
            }
        }

        long? total = null, free = null;
        try
        {
            var drive = new DriveInfo(Path.GetFullPath(root));
            total = drive.TotalSize;
            free = drive.AvailableFreeSpace;
        }
        catch
        {
            // Not every platform can say.
        }

        return ServiceResult<StorageSummaryDto>.Ok(new StorageSummaryDto(
            root, storage.StorageIsEphemeral, used, files, total, free, trash, trashFiles,
            folders.OrderByDescending(f => f.Bytes).ToList()));
    }

    /// <summary>Shrinks up to <paramref name="limit"/> big photos in place.</summary>
    public async Task<ServiceResult<StorageShrinkDto>> ShrinkAsync(int limit, CancellationToken ct)
    {
        limit = Math.Clamp(limit, 1, 300);
        var candidates = PhotoCandidates().ToList();
        int shrunk = 0;
        long saved = 0;
        foreach (var path in candidates.Take(limit))
        {
            ct.ThrowIfCancellationRequested();
            var before = SafeLength(path);
            var bytes = await File.ReadAllBytesAsync(path, ct);
            var category = Path.GetFileName(Path.GetDirectoryName(Path.GetDirectoryName(path)) ?? string.Empty);
            var (maxEdge, quality) = ImageShrinker.ProfileFor(category);
            var small = await ImageShrinker.ToWebpAsync(bytes, maxEdge, quality, ct);
            if (small is null || small.Length > before * 85 / 100)
            {
                Skip[path] = 0;
                continue;
            }

            var temp = path + ".tmp";
            await File.WriteAllBytesAsync(temp, small, ct);
            File.Move(temp, path, overwrite: true);
            shrunk++;
            saved += before - small.Length;
        }

        return ServiceResult<StorageShrinkDto>.Ok(new StorageShrinkDto(
            shrunk, saved, Math.Max(0, candidates.Count - Math.Min(limit, candidates.Count))));
    }

    /// <summary>Files on disk that no database row points at (older than 2 days).</summary>
    /// <param name="move">True: move them to the trash.</param>
    public async Task<ServiceResult<StorageOrphansDto>> OrphansAsync(bool move, CancellationToken ct)
    {
        var referenced = await ReferencedNamesAsync(ct);
        var root = storage.UploadRoot;
        var cutoff = DateTime.UtcNow.AddDays(-2);
        var orphans = new List<string>();
        if (Directory.Exists(root))
        {
            foreach (var dir in Directory.EnumerateDirectories(root))
            {
                var name = Path.GetFileName(dir);
                if (name is TrashFolder or EvidenceFolder) continue;
                foreach (var file in SafeFiles(dir))
                {
                    var fileName = Path.GetFileName(file);
                    if (!StoredName().IsMatch(fileName)) continue;
                    if (referenced.Contains(fileName.ToLowerInvariant())) continue;
                    if (File.GetLastWriteTimeUtc(file) > cutoff) continue;
                    orphans.Add(file);
                }
            }
        }

        long bytes = orphans.Sum(SafeLength);
        var moved = 0;
        if (move)
        {
            var day = DateTime.UtcNow.ToString("yyyyMMdd");
            foreach (var file in orphans)
            {
                try
                {
                    var relative = Path.GetRelativePath(root, file);
                    var target = Path.Combine(root, TrashFolder, day, relative);
                    Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                    File.Move(file, target, overwrite: true);
                    moved++;
                }
                catch
                {
                    // Left where it is; the next run tries again.
                }
            }
        }

        return ServiceResult<StorageOrphansDto>.Ok(new StorageOrphansDto(
            orphans.Count, bytes,
            orphans.Take(8).Select(f => Path.GetRelativePath(root, f)).ToList(), moved));
    }

    /// <summary>The daily clean-up: trash older than 30 days, old top-up screenshots, old test screenshots, old usage rows.</summary>
    public async Task<int> DailyAsync(CancellationToken ct)
    {
        var removed = 0;
        var trashRoot = Path.Combine(storage.UploadRoot, TrashFolder);
        if (Directory.Exists(trashRoot))
        {
            foreach (var dayDir in Directory.EnumerateDirectories(trashRoot))
            {
                if (DateTime.TryParseExact(Path.GetFileName(dayDir), "yyyyMMdd", null,
                        System.Globalization.DateTimeStyles.AssumeUniversal, out var day)
                    && day < DateTime.UtcNow.AddDays(-30))
                {
                    try
                    {
                        removed += SafeFiles(dayDir).Count();
                        Directory.Delete(dayDir, recursive: true);
                    }
                    catch
                    {
                        // Tomorrow.
                    }
                }
            }
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);

        // Top-up screenshots: needed while an Admin checks the payment, not for ever.
        var urls = new List<string>();
        await using (var read = new NpgsqlCommand(
            """
            SELECT id, screenshot_url FROM udrive.driver_wallet_topups
            WHERE screenshot_url IS NOT NULL AND status <> 'Pending' AND created_at < now() - interval '90 days'
            LIMIT 500;
            """, connection))
        {
            await using var reader = await read.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct)) urls.Add(reader.GetString(1));
        }

        if (urls.Count > 0)
        {
            removed += storage.DeleteProtectedFiles(urls);
            await using var clear = new NpgsqlCommand(
                "UPDATE udrive.driver_wallet_topups SET screenshot_url = NULL, updated_at = now() WHERE screenshot_url = ANY(@urls);",
                connection);
            clear.Parameters.AddWithValue("urls", urls.ToArray());
            await clear.ExecuteNonQueryAsync(ct);
        }

        // Test screenshots: a week is enough to look at them.
        var shots = new List<string>();
        await using (var read = new NpgsqlCommand(
            // A screenshot an improvement points at stays until the improvement is gone.
            """
            SELECT s.screenshot_url FROM udrive.test_steps s
            WHERE s.screenshot_url IS NOT NULL AND s.created_at < now() - interval '7 days'
              AND NOT EXISTS (SELECT 1 FROM udrive.test_improvements i WHERE i.screenshot_url = s.screenshot_url)
            LIMIT 2000;
            """,
            connection))
        {
            await using var reader = await read.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct)) shots.Add(reader.GetString(0));
        }

        if (shots.Count > 0)
        {
            removed += storage.DeleteProtectedFiles(shots);
            await using var clear = new NpgsqlCommand(
                "UPDATE udrive.test_steps SET screenshot_url = NULL WHERE screenshot_url = ANY(@urls);", connection);
            clear.Parameters.AddWithValue("urls", shots.ToArray());
            await clear.ExecuteNonQueryAsync(ct);
        }

        // Usage history: 90 days.
        await using (var prune = new NpgsqlCommand(
            """
            DELETE FROM udrive.app_sessions WHERE started_at < now() - interval '90 days';
            DELETE FROM udrive.app_devices WHERE last_seen_at < now() - interval '180 days';
            DELETE FROM udrive.ip_geo WHERE looked_up_at < now() - interval '60 days';
            """, connection))
        {
            await prune.ExecuteNonQueryAsync(ct);
        }

        return removed;
    }

    /// <summary>Every stored file name any text column in the database mentions.</summary>
    private async Task<HashSet<string>> ReferencedNamesAsync(CancellationToken ct)
    {
        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(ct);
        var columns = new List<(string Table, string Column)>();
        await using (var command = new NpgsqlCommand(
            """
            SELECT c.table_name, c.column_name
            FROM information_schema.columns c
            JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
            WHERE c.table_schema = 'udrive' AND t.table_type = 'BASE TABLE'
              AND (c.data_type IN ('text', 'character varying', 'jsonb', 'json') OR c.udt_name IN ('_text', '_varchar'));
            """, connection))
        {
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct)) columns.Add((reader.GetString(0), reader.GetString(1)));
        }

        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (table, column) in columns)
        {
            // Identifiers come from the catalogue and are quoted.
            var t = table.Replace("\"", "\"\"");
            var c = column.Replace("\"", "\"\"");
            var sql = $$"""
                SELECT DISTINCT lower((regexp_matches(t."{{c}}"::text,
                       '([0-9a-f]{32}\.(?:jpe?g|png|webp|pdf))', 'gi'))[1])
                FROM udrive."{{t}}" t
                WHERE t."{{c}}"::text ~* '[0-9a-f]{32}\.(jpe?g|png|webp|pdf)';
                """;
            await using var command = new NpgsqlCommand(sql, connection) { CommandTimeout = 120 };
            await using var reader = await command.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                if (!reader.IsDBNull(0)) names.Add(reader.GetString(0));
            }
        }

        return names;
    }

    private IEnumerable<string> PhotoCandidates()
    {
        var root = storage.UploadRoot;
        if (!Directory.Exists(root)) yield break;
        foreach (var dir in Directory.EnumerateDirectories(root))
        {
            var name = Path.GetFileName(dir);
            if (name is TrashFolder or EvidenceFolder) continue;
            foreach (var file in SafeFiles(dir))
            {
                if (!ImageShrinker.IsImageExtension(Path.GetExtension(file))) continue;
                if (SafeLength(file) <= ShrinkAbove) continue;
                if (Skip.ContainsKey(file)) continue;
                yield return file;
            }
        }
    }

    private static IEnumerable<string> SafeFiles(string dir)
    {
        try
        {
            return Directory.EnumerateFiles(dir, "*", SearchOption.AllDirectories).ToList();
        }
        catch
        {
            return [];
        }
    }

    private static long SafeLength(string file)
    {
        try
        {
            return new FileInfo(file).Length;
        }
        catch
        {
            return 0;
        }
    }
}

/// <summary>Runs <see cref="StorageService.DailyAsync"/> once a day.</summary>
public sealed class StorageMaintenanceWorker(StorageService storage, ILogger<StorageMaintenanceWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // A little after start, then every 24 hours.
        try
        {
            await Task.Delay(TimeSpan.FromMinutes(10), stoppingToken);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var removed = await storage.DailyAsync(stoppingToken);
                if (removed > 0) logger.LogInformation("Storage clean-up removed {Count} files.", removed);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Storage clean-up failed; will try again tomorrow.");
            }

            try
            {
                await Task.Delay(TimeSpan.FromHours(24), stoppingToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }
}
