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
        var pathLooksEphemeral = string.IsNullOrWhiteSpace(configured)
            || Path.GetFullPath(configured)
                .StartsWith(Path.GetFullPath(AppContext.BaseDirectory),
                    StringComparison.OrdinalIgnoreCase);

        // The path test above is not enough on its own.
        //
        // The Dockerfile sets UPLOAD_ROOT=/data/uploads unconditionally, so the
        // string always looks right. If the Railway volume is not actually
        // mounted at /data, the entrypoint's `mkdir -p` still succeeds — into
        // the container's own writable layer, as root — the API writes there
        // happily, this check stayed false, and the warning never printed.
        // Every driver CNIC, licence, vehicle photo and payment screenshot was
        // then destroyed on the next deploy, leaving database rows pointing at
        // files that no longer existed.
        //
        // A mounted volume is a different filesystem from the image, so the two
        // have different device ids. That is what is compared here: it detects
        // the real condition instead of trusting the variable.
        StorageIsEphemeral = pathLooksEphemeral || !IsOnSeparateFilesystem(_uploadRoot);

        if (StorageIsEphemeral)
        {
            // Loud, once, at boot. This has already cost a set of verification
            // documents that had to be uploaded again.
            Console.WriteLine(
                $"WARNING: upload directory '{_uploadRoot}' is not on a mounted "
                + "volume — it is part of the container image. Every uploaded "
                + "file will be lost on the next deploy. Mount a volume and set "
                + "UPLOAD_ROOT=/data/uploads.");
        }
    }

    /// <summary>
    /// True when <paramref name="path"/> sits on a different filesystem from
    /// the container image, i.e. on a mounted volume.
    /// </summary>
    /// <remarks>
    /// Compares the st_dev of the path against the st_dev of the image root.
    /// Any failure to determine this returns true — "assume it is fine" — so a
    /// platform where the check cannot run does not produce a permanent false
    /// warning that people learn to scroll past. The path test above is the
    /// backstop in that case.
    /// </remarks>
    private static bool IsOnSeparateFilesystem(string path)
    {
        if (!OperatingSystem.IsLinux())
        {
            return true;
        }

        try
        {
            var mounts = File.ReadAllLines("/proc/mounts")
                .Select(line => line.Split(' '))
                .Where(parts => parts.Length > 1)
                .Select(parts => parts[1].Replace("\\040", " "))
                .Where(mountPoint => mountPoint.Length > 1)
                .ToArray();

            var full = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar);

            return mounts.Any(mountPoint =>
                full.Equals(mountPoint, StringComparison.Ordinal)
                || full.StartsWith(mountPoint + "/", StringComparison.Ordinal));
        }
        catch
        {
            return true;
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

        // Every photo is stored as a small WebP (see ImageShrinker). The 5 GB
        // volume holds roughly ten times as many documents this way.
        if (ImageShrinker.IsImageExtension(extension))
        {
            var (maxEdge, quality) = ImageShrinker.ProfileFor(safeCategory);
            var small = await ImageShrinker.ToWebpAsync(bytes, maxEdge, quality, cancellationToken);
            if (small is not null)
            {
                bytes = small;
                extension = ".webp";
            }
        }

        var owner = ownerId.ToString("N");
        var relativeFolder = Path.Combine(safeCategory, owner);
        var absoluteFolder = Path.Combine(_uploadRoot, relativeFolder);
        Directory.CreateDirectory(absoluteFolder);
        var fileName = $"{Guid.NewGuid():N}{extension}";
        var absolutePath = Path.Combine(absoluteFolder, fileName);
        await File.WriteAllBytesAsync(absolutePath, bytes, cancellationToken);

        var protectedUrl = $"/api/v1/admin/verification/files/{safeCategory}/{owner}/{fileName}";
        return new StoredFile(protectedUrl, bytes.Length, DetectContentType(extension));
    }

    /// <param name="allowLegacyFallback">
    /// When false, only the exact <c>{root}/{category}/{owner}/{file}</c> path
    /// resolves. The fallback below searches every storage root for a matching
    /// filename regardless of category or owner, which is what makes a route
    /// that accepts user-supplied segments dangerous — a caller who has been
    /// authorised for one specific file must not be able to reach another by
    /// name alone.
    /// </param>
    public ResolvedStoredFile? ResolveProtectedFile(
        string category, string owner, string fileName, bool allowLegacyFallback = true)
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

        return allowLegacyFallback ? FindLegacyFile(safeFile) : null;
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
                ContentTypeOf(path),
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
                        ContentTypeOf(match),
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
            ContentTypeOf(candidate),
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

    /// <summary>By the file's first bytes (old photos are shrunk in place), else by extension.</summary>
    internal static string ContentTypeOf(string path)
    {
        try
        {
            Span<byte> head = stackalloc byte[12];
            using var stream = File.OpenRead(path);
            var read = stream.Read(head);
            var sniffed = ImageShrinker.Sniff(head[..read]);
            if (sniffed is not null) return sniffed;
        }
        catch
        {
            // Fall back to the name.
        }

        return DetectContentType(Path.GetExtension(path));
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

    // ══════════════════════════════════ partner signature evidence
    //
    // A separate path from everything above, on purpose.
    //
    // `AllowedExtensions` is images and PDF, and the verification route that
    // serves them is open to every verification officer. Signature evidence is
    // neither of those things: it includes a video, and it is SuperAdmin-only.
    // Widening `AllowedExtensions` to fit the video would have let a video
    // through every other upload in the application, and reusing the
    // verification URL would have let every verification officer watch it.
    //
    // So these three methods stand alone. They share the upload root and nothing
    // else.

    private static readonly HashSet<string> EvidenceImageExtensions =
        new(StringComparer.OrdinalIgnoreCase) { ".jpg", ".jpeg", ".png", ".webp" };

    private static readonly HashSet<string> EvidenceVideoExtensions =
        new(StringComparer.OrdinalIgnoreCase) { ".mp4", ".m4v", ".mov", ".3gp", ".webm" };

    /// <summary>Where signature evidence lives, under the same upload root.</summary>
    private const string EvidenceCategory = "partner-signature";

    /// <param name="kind">"selfie" or "video".</param>
    /// <remarks>
    /// Twenty-five megabytes for the video, which is a minute of phone footage
    /// with room to spare, and ten for the photograph — both under the 30 MB
    /// request limit Kestrel applies by default, so a partner on a slow line gets
    /// a clear message from this method rather than a connection dropped by the
    /// server with nothing said.
    /// </remarks>
    public async Task<StoredFile> SaveSignatureEvidenceAsync(
        IFormFile file,
        Guid contractId,
        string kind,
        CancellationToken cancellationToken)
    {
        if (StorageFault is not null)
        {
            throw new InvalidOperationException(
                "The server cannot store files right now. "
                + $"Upload directory '{_uploadRoot}': {StorageFault}");
        }

        var isVideo = string.Equals(kind, "video", StringComparison.OrdinalIgnoreCase);
        var allowed = isVideo ? EvidenceVideoExtensions : EvidenceImageExtensions;
        var limit = isVideo ? 25 * 1024 * 1024 : 10 * 1024 * 1024;

        if (file.Length <= 0)
        {
            throw new InvalidDataException(
                isVideo
                    ? "The video did not record. Please try again."
                    : "The photograph did not save. Please take it again.");
        }

        if (file.Length > limit)
        {
            // Says the actual size, as the document upload above does. "Too
            // large" leaves somebody guessing whether a retake will help.
            throw new InvalidDataException(
                $"That file is {file.Length / (1024.0 * 1024.0):0.#} MB. The limit is "
                + $"{limit / (1024 * 1024)} MB — please "
                + (isVideo ? "record a shorter video." : "send a smaller photograph."));
        }

        var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (!allowed.Contains(extension))
        {
            throw new InvalidDataException(
                isVideo
                    ? "The video has to be an MP4 or WebM recording."
                    : "The photograph has to be a JPG, PNG or WebP image.");
        }

        await using var memory = new MemoryStream();
        await file.CopyToAsync(memory, cancellationToken);
        var bytes = memory.ToArray();

        // The extension is whatever the client typed. The first bytes are not.
        var signatureOk = isVideo
            ? LooksLikeVideo(bytes, extension)
            : MatchesSignature(bytes, extension);
        if (!signatureOk)
        {
            throw new InvalidDataException(
                "That file does not look like "
                + (isVideo ? "a video recording." : "an image."));
        }

        var folder = Path.Combine(_uploadRoot, EvidenceCategory, contractId.ToString("N"));
        Directory.CreateDirectory(folder);
        var fileName = $"{(isVideo ? "video" : "selfie")}-{Guid.NewGuid():N}{extension}";
        await File.WriteAllBytesAsync(Path.Combine(folder, fileName), bytes, cancellationToken);

        // SuperAdmin-only route, and the only one that serves these files.
        var url = $"/api/v1/admin/partners/evidence/{contractId:N}/{fileName}";
        return new StoredFile(url, file.Length, EvidenceContentType(extension));
    }

    /// <summary>
    /// Resolves one evidence file, by contract and exact filename only.
    /// </summary>
    /// <remarks>
    /// No legacy fallback and no search across roots: the caller has been
    /// authorised for one contract's evidence, and a filename-only search would
    /// let them reach another contract's video by guessing a name.
    /// </remarks>
    public ResolvedStoredFile? ResolveSignatureEvidence(Guid contractId, string fileName)
    {
        var safeFile = Path.GetFileName(fileName);
        if (safeFile != fileName || string.IsNullOrWhiteSpace(safeFile))
        {
            return null;
        }

        var extension = Path.GetExtension(safeFile);
        if (!EvidenceImageExtensions.Contains(extension)
            && !EvidenceVideoExtensions.Contains(extension))
        {
            return null;
        }

        foreach (var root in GetSearchRoots())
        {
            var candidate = Path.Combine(
                root, EvidenceCategory, contractId.ToString("N"), safeFile);
            if (File.Exists(candidate))
            {
                return new ResolvedStoredFile(
                    candidate, EvidenceContentType(extension), safeFile);
            }
        }

        return null;
    }

    /// <summary>Deletes one evidence file by the URL stored against the contract.</summary>
    public bool DeleteSignatureEvidence(string? storedUrl)
    {
        if (string.IsNullOrWhiteSpace(storedUrl))
        {
            return false;
        }

        // The URL this class wrote: .../partners/evidence/{contract}/{file}
        var parts = storedUrl.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2
            || !Guid.TryParse(parts[^2], out var contractId))
        {
            return false;
        }

        try
        {
            var resolved = ResolveSignatureEvidence(contractId, parts[^1]);
            if (resolved is null)
            {
                return false;
            }

            File.Delete(resolved.Path);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static string EvidenceContentType(string extension) =>
        extension.ToLowerInvariant() switch
        {
            ".jpg" or ".jpeg" => "image/jpeg",
            ".png" => "image/png",
            ".webp" => "image/webp",
            ".mp4" or ".m4v" => "video/mp4",
            ".mov" => "video/quicktime",
            ".3gp" => "video/3gpp",
            ".webm" => "video/webm",
            _ => "application/octet-stream",
        };

    /// <summary>
    /// The container signature, not the codec.
    /// </summary>
    /// <remarks>
    /// MP4, MOV and 3GP all carry an `ftyp` box at offset 4; WebM is a Matroska
    /// file and starts with the EBML magic number. That is as far as this goes —
    /// it is here to stop something that is not a video at all, not to validate
    /// the stream.
    /// </remarks>
    private static bool LooksLikeVideo(byte[] bytes, string extension)
    {
        if (bytes.Length < 12)
        {
            return false;
        }

        var isWebm = bytes[0] == 0x1A && bytes[1] == 0x45
            && bytes[2] == 0xDF && bytes[3] == 0xA3;

        var isIsoBmff = bytes[4] == 0x66 && bytes[5] == 0x74
            && bytes[6] == 0x79 && bytes[7] == 0x70;

        return extension.Equals(".webm", StringComparison.OrdinalIgnoreCase)
            ? isWebm
            : isIsoBmff;
    }
}
