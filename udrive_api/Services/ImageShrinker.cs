using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Webp;
using SixLabors.ImageSharp.Processing;

namespace UDrive.Api.Services;

/// <summary>
/// Turns an uploaded photo into a small WebP.
/// </summary>
/// <remarks>
/// The volume is 5 GB, and a phone photo (or the PNG the app used to send)
/// is 1–4 MB. Re-encoded as WebP, turned upright, its metadata (GPS, camera)
/// dropped and its long edge capped, the same photo is 80–200 KB and still
/// reads perfectly: a CNIC number, a number plate, a hotel room.
///
/// Never throws. A photo that cannot be decoded, or one that would not get
/// smaller, comes back as null and the caller keeps the original — a slightly
/// bigger file is a much smaller problem than a refused upload.
/// </remarks>
public static class ImageShrinker
{
    /// <summary>Documents are read closely (CNIC numbers), so they keep more pixels.</summary>
    private static readonly HashSet<string> DocumentCategories = new(StringComparer.OrdinalIgnoreCase)
    {
        "driverdocuments", "vehicledocuments", "wallettopups", "holdclaims",
        "customerdocuments", "disputes", "hotelownerdocuments",
    };

    public static (int MaxEdge, int Quality) ProfileFor(string category) =>
        DocumentCategories.Contains(category.Replace("-", string.Empty)) ? (1600, 80) : (1280, 75);

    public static bool IsImageExtension(string extension) =>
        extension.ToLowerInvariant() is ".jpg" or ".jpeg" or ".png" or ".webp";

    /// <returns>WebP bytes, or null to keep the original.</returns>
    public static async Task<byte[]?> ToWebpAsync(byte[] input, int maxEdge, int quality, CancellationToken ct)
    {
        try
        {
            using var image = Image.Load(input);
            image.Mutate(x => x.AutoOrient());
            if (Math.Max(image.Width, image.Height) > maxEdge)
            {
                image.Mutate(x => x.Resize(new ResizeOptions
                {
                    Mode = ResizeMode.Max,
                    Size = new Size(maxEdge, maxEdge),
                }));
            }

            // Location and camera details have no business on a server.
            image.Metadata.ExifProfile = null;
            image.Metadata.XmpProfile = null;
            image.Metadata.IptcProfile = null;

            await using var output = new MemoryStream();
            await image.SaveAsWebpAsync(output, new WebpEncoder
            {
                Quality = quality,
                FileFormat = WebpFileFormatType.Lossy,
            }, ct);
            var bytes = output.ToArray();
            return bytes.Length > 0 && bytes.Length < input.Length ? bytes : null;
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return null;
        }
    }

    /// <summary>The content type from the file's first bytes; null when unknown.</summary>
    /// <remarks>
    /// Old photos are shrunk in place, so a file named .jpg may hold WebP.
    /// Serving by the bytes keeps every stored link working.
    /// </remarks>
    public static string? Sniff(ReadOnlySpan<byte> head)
    {
        if (head.Length >= 12 && head[0] == 0x52 && head[1] == 0x49 && head[2] == 0x46 && head[3] == 0x46
            && head[8] == 0x57 && head[9] == 0x45 && head[10] == 0x42 && head[11] == 0x50) return "image/webp";
        if (head.Length >= 3 && head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF) return "image/jpeg";
        if (head.Length >= 4 && head[0] == 0x89 && head[1] == 0x50 && head[2] == 0x4E && head[3] == 0x47) return "image/png";
        if (head.Length >= 4 && head[0] == 0x25 && head[1] == 0x50 && head[2] == 0x44 && head[3] == 0x46) return "application/pdf";
        return null;
    }
}
