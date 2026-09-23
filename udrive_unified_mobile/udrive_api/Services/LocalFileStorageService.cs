namespace UDrive.Api.Services;

public sealed record StoredFile(string RelativeUrl, long Size, string ContentType);
public sealed record ResolvedStoredFile(string Path, string ContentType, string DownloadName);
/// <param name="Ephemeral">
/// True when uploads are being written inside the container image rather than a
/// mounted volume, so every deploy destroys them.
/// </param>
/// <param name="Fault">
/// Why the upload directory is unusable, or null when it is fine. Usually a
/// permission problem on the mounted volume.
/// </param>
public sealed record StorageDiagnostics(string UploadRoot, bool UploadRootExists, int FileCount, IReadOnlyList<string> SearchRoots, bool Ephemeral, string? Fault);

public sealed class LocalFileStorageService
{
    private static readonly HashSet<string> AllowedExtensions =
        new(StringComparer.OrdinalIgnoreCase) { ".jpg", ".jpeg", ".png", ".webp", ".pdf" };

    private readonly string _uploadRoot =
        Environment.GetEnvironmentVariable("UPLOAD_ROOT") ?? Path.Combine(AppContext.BaseDirectory, "uploads");

    /// <summary>True when uploads are going somewhere a deploy will erase.</summary>
    /// <remarks>
    /// Every uploaded document, vehicle photograph and payment screenshot lives
    /// on this path. If it is inside the container image rather than a mounted
    /// volume, all of it is destroyed on the next deploy — the database keeps
    /// the rows, so the admin portal shows a document that exists with a file
    /// that does not, and reports "this section or record is not available".
    ///
    /// Set <c>UPLOAD_ROOT=/data/uploads</c> and mount a volume there.
    /// </remarks>
    public bool StorageIsEphemeral { get; }

    /// <summary>Why the upload directory is unusable, or null when it is fine.</summary>
    public string? StorageFault { get; }

    public LocalFileStorageService()
    {
        // Never throws from the constructor.
        //
        // This service is injected into controllers that only *read* — the
        // driver documents list, for one — and a constructor that throws takes
        // the whole request down before it reaches any code. When the uploads
        // volume was mounted without write permission, `CreateDirectory` threw
        // `UnauthorizedAccessException` here, and every Driver opening My
        // documents was told their session was invalid.
        //
        // A broken upload directory should break uploads. It should not break
        // reading a list.
        try
        {
            Directory.CreateDirectory(_uploadRoot);
        }
        catch (Exception error)
        {
            StorageFault = error.Message;
            Console.WriteLine(
                $"WARNING: cannot use upload directory '{_uploadRoot}': "
                + $"{error.Message}. Uploads will fail until this is fixed.");
        }

        var configured = Environment.GetEnvironmentVariable("UPLOAD_ROOT");
        StorageIsEphemeral = string.IsNullOrWhiteSpace(configured)
            || Path.GetFullPath(configured)
                .StartsWith(Path.GetFullPath(AppContext.BaseDirectory),
                    StringComparison.OrdinalIgnoreCase);

        if (StorageIsEphemeral)
        {
            // Loud, once, at boot. This has already cost a set of verification
            // documents that had to be uploaded again.
            Console.WriteLine(
                "WARNING: UPLOAD_ROOT is unset or inside the container image "
                + $"('{_uploadRoot}'). Every uploaded file will be lost on the "
                + "next deploy. Mount a volume and set UPLOAD_ROOT=/data/uploads.");
        }
    }

    public string UploadRoot => _uploadRoot;

    public async Task<StoredFile> SaveAsync(
        IFormFile file,
        string category,
        Guid ownerId,
        CancellationToken cancellationToken)
    {
        if (StorageFault is not null)
        {
            // Named plainly. A Driver retrying an upload against a directory
            // the server cannot write to will retry for ever.
            throw new InvalidOperationException(
                "The server cannot store files right now. "
                + $"Upload directory '{_uploadRoot}': {StorageFault}");
        }

        if (file.Length <= 0)
        {
            throw new InvalidDataException(
                "That file is empty. Try taking the photograph again.");
        }

        if (file.Length > 10 * 1024 * 1024)
        {
            // Says the actual size, not just the limit. "Must be under 10 MB"
            // leaves someone guessing whether their file is 11 MB or 40, and
            // therefore whether cropping it will help.
            throw new InvalidDataException(
                $"That file is {file.Length / (1024.0 * 1024.0):0.#} MB. "
                + "The limit is 10 MB — please send a smaller photograph.");
        }

        var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (!AllowedExtensions.Contains(extension))
        {
            throw new InvalidDataException("Only JPG, PNG, WebP and PDF files are allowed.");
        }

        await using var memory = new MemoryStream((int)file.Length);
        await file.CopyToAsync(memory, cancellationToken);
        var bytes = memory.ToArray();
        if (!MatchesSignature(bytes, extension))
        {
            throw new InvalidDataException("The uploaded file content does not match its extension.");
        }

        var safeCategory = SanitizeSegment(category);
        var owner = ownerId.ToString("N");
        var relativeFolder = Path.Combine(safeCategory, owner);
        var absoluteFolder = Path.Combine(_uploadRoot, relativeFolder);
        Directory.CreateDirectory(absoluteFolder);
        var fileName = $"{Guid.NewGuid():N}{extension}";
        var absolutePath = Path.Combine(absoluteFolder, fileName);
        await File.WriteAllBytesAsync(absolutePath, bytes, cancellationToken);

        var protectedUrl = $"/api/v1/admin/verification/files/{safeCategory}/{owner}/{fileName}";
        return new StoredFile(protectedUrl, file.Length, DetectContentType(extension));
    }

    public ResolvedStoredFile? ResolveProtectedFile(string category, string owner, string fileName)
    {
        var safeCategory = SanitizeSegment(category);
        var safeOwner = SanitizeSegment(owner);
        var safeFile = Path.GetFileName(fileName);
        if (safeFile != fileName || !AllowedExtensions.Contains(Path.GetExtension(safeFile)))
        {
            return null;
        }

        foreach (var root in GetSearchRoots())
        {
            var resolved = TryResolveExact(root, safeCategory, safeOwner, safeFile);
            if (resolved is not null)
            {
                return resolved;
            }
        }

        return FindLegacyFile(safeFile);
    }

    public ResolvedStoredFile? ResolveStoredUrl(string? storedUrl)
    {
        if (string.IsNullOrWhiteSpace(storedUrl))
        {
            return null;
        }

        var value = storedUrl.Trim();
        var path = value;
        if (Uri.TryCreate(value, UriKind.Absolute, out var absoluteUri))
        {
            path = absoluteUri.IsFile ? absoluteUri.LocalPath : absoluteUri.AbsolutePath;
        }

        var segments = path
            .Split(new[] { '/', '\\' }, StringSplitOptions.RemoveEmptyEntries)
            .Select(Uri.UnescapeDataString)
            .ToArray();
        var filesIndex = Array.FindIndex(
            segments,
            segment => string.Equals(segment, "files", StringComparison.OrdinalIgnoreCase));

        if (filesIndex >= 0 && segments.Length >= filesIndex + 4)
        {
            var byRoute = ResolveProtectedFile(
                segments[filesIndex + 1],
                segments[filesIndex + 2],
                segments[filesIndex + 3]);
            if (byRoute is not null)
            {
                return byRoute;
            }
        }

        if (Path.IsPathRooted(path) && File.Exists(path) && IsAllowedFile(path))
        {
            return new ResolvedStoredFile(
                Path.GetFullPath(path),
                DetectContentType(Path.GetExtension(path)),
                Path.GetFileName(path));
        }

        var fileName = Path.GetFileName(path);
        return string.IsNullOrWhiteSpace(fileName) || !IsAllowedFile(fileName)
            ? null
            : FindLegacyFile(fileName);
    }

    public int DeleteProtectedFiles(IEnumerable<string> storedUrls)
    {
        var deleted = 0;
        foreach (var storedUrl in storedUrls.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (DeleteProtectedFile(storedUrl))
            {
                deleted++;
            }
        }
        return deleted;
    }

    public bool DeleteProtectedFile(string storedUrl)
    {
        try
        {
            var resolved = ResolveStoredUrl(storedUrl);
            if (resolved is null)
            {
                return false;
            }

            File.Delete(resolved.Path);
            var ownerDirectory = Path.GetDirectoryName(resolved.Path);
            if (!string.IsNullOrWhiteSpace(ownerDirectory) &&
                Directory.Exists(ownerDirectory) &&
                !Directory.EnumerateFileSystemEntries(ownerDirectory).Any())
            {
                Directory.Delete(ownerDirectory);
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    public StorageDiagnostics GetDiagnostics()
    {
        var roots = GetSearchRoots().ToArray();
        var count = 0;
        if (Directory.Exists(_uploadRoot))
        {
            try
            {
                count = Directory.EnumerateFiles(_uploadRoot, "*", SearchOption.AllDirectories).Count();
            }
            catch
            {
                count = -1;
            }
        }

        return new StorageDiagnostics(
            _uploadRoot,
            Directory.Exists(_uploadRoot),
            count,
            roots,
            StorageIsEphemeral,
            StorageFault);
    }

    private ResolvedStoredFile? FindLegacyFile(string fileName)
    {
        foreach (var root in GetSearchRoots())
        {
            if (!Directory.Exists(root))
            {
                continue;
            }

            try
            {
                var match = Directory
                    .EnumerateFiles(root, fileName, SearchOption.AllDirectories)
                    .FirstOrDefault(IsAllowedFile);
                if (match is not null)
                {
                    return new ResolvedStoredFile(
                        Path.GetFullPath(match),
                        DetectContentType(Path.GetExtension(match)),
                        Path.GetFileName(match));
                }
            }
            catch
            {
                // Continue through legacy roots. The configured root remains authoritative.
            }
        }
        return null;
    }

    private static ResolvedStoredFile? TryResolveExact(
        string root,
        string category,
        string owner,
        string fileName)
    {
        if (!Directory.Exists(root))
        {
            return null;
        }

        var fullRoot = Path.GetFullPath(root);
        var candidate = Path.GetFullPath(Path.Combine(fullRoot, category, owner, fileName));
        if (!candidate.StartsWith(fullRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
            !File.Exists(candidate) ||
            !IsAllowedFile(candidate))
        {
            return null;
        }

        return new ResolvedStoredFile(
            candidate,
            DetectContentType(Path.GetExtension(candidate)),
            Path.GetFileName(candidate));
    }

    private IEnumerable<string> GetSearchRoots()
    {
        return new[]
        {
            _uploadRoot,
            "/data/uploads",
            Path.Combine(AppContext.BaseDirectory, "uploads"),
            Path.Combine(Directory.GetCurrentDirectory(), "uploads"),
            "/app/uploads"
        }
        .Where(value => !string.IsNullOrWhiteSpace(value))
        .Select(Path.GetFullPath)
        .Distinct(StringComparer.OrdinalIgnoreCase);
    }

    private static bool IsAllowedFile(string path) =>
        AllowedExtensions.Contains(Path.GetExtension(path));

    private static string SanitizeSegment(string value)
    {
        var safe = new string(value.Where(char.IsLetterOrDigit).ToArray()).ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(safe))
        {
            throw new InvalidDataException("The storage path is invalid.");
        }
        return safe;
    }

    private static string DetectContentType(string extension) => extension.ToLowerInvariant() switch
    {
        ".pdf" => "application/pdf",
        ".png" => "image/png",
        ".webp" => "image/webp",
        _ => "image/jpeg"
    };

    private static bool MatchesSignature(byte[] bytes, string extension)
    {
        if (bytes.Length < 4)
        {
            return false;
        }

        return extension switch
        {
            ".pdf" => bytes.Length >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46,
            ".jpg" or ".jpeg" => bytes.Length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF,
            ".png" => bytes.Length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47,
            ".webp" => bytes.Length >= 12
                && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46
                && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50,
            _ => false
        };
    }
}
