namespace UDrive.Api.Services;

public sealed record StoredFile(string RelativeUrl, long Size, string ContentType);

public sealed class LocalFileStorageService
{
    private static readonly HashSet<string> AllowedExtensions =
        new(StringComparer.OrdinalIgnoreCase) { ".jpg", ".jpeg", ".png", ".webp", ".pdf" };

    private readonly string _uploadRoot =
        Environment.GetEnvironmentVariable("UPLOAD_ROOT") ?? Path.Combine(AppContext.BaseDirectory, "uploads");

    public LocalFileStorageService()
    {
        Directory.CreateDirectory(_uploadRoot);
    }

    public string UploadRoot => _uploadRoot;

    public async Task<StoredFile> SaveAsync(
        IFormFile file,
        string category,
        Guid ownerId,
        CancellationToken cancellationToken)
    {
        if (file.Length is <= 0 or > 10 * 1024 * 1024)
        {
            throw new InvalidDataException("The file must be between 1 byte and 10 MB.");
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

        // Files are intentionally served only through an authorized Admin endpoint.
        var protectedUrl = $"/api/v1/admin/verification/files/{safeCategory}/{owner}/{fileName}";
        return new StoredFile(protectedUrl, file.Length, DetectContentType(extension));
    }

    public (string Path, string ContentType, string DownloadName)? ResolveProtectedFile(
        string category,
        string owner,
        string fileName)
    {
        var safeCategory = SanitizeSegment(category);
        var safeOwner = SanitizeSegment(owner);
        var safeFile = Path.GetFileName(fileName);
        if (safeFile != fileName || !AllowedExtensions.Contains(Path.GetExtension(safeFile)))
        {
            return null;
        }

        var root = Path.GetFullPath(_uploadRoot);
        var candidate = Path.GetFullPath(Path.Combine(root, safeCategory, safeOwner, safeFile));
        if (!candidate.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.Ordinal) || !File.Exists(candidate))
        {
            return null;
        }

        return (candidate, DetectContentType(Path.GetExtension(candidate)), safeFile);
    }

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
