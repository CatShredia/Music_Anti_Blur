using Microsoft.AspNetCore.Http;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Catalog;

public sealed record CoverImageBytes(byte[] Bytes, string ContentType);

public static class CoverImageValidation
{
    public const int MaxBytes = 5 * 1024 * 1024;
    public const int MaxRequestBytes = MaxBytes + 256 * 1024;
    public static readonly TimeSpan UrlTtl = TimeSpan.FromHours(1);

    private static readonly byte[] JpegMagic = [0xFF, 0xD8, 0xFF];
    private static readonly byte[] PngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    public static CoverImageBytes? Read(IFormFile? file, Dictionary<string, string[]> errors)
    {
        if (file is null || file.Length <= 0)
        {
            CatalogValidation.Add(errors, "file", CatalogValidation.Required);
            return null;
        }

        if (file.Length > MaxBytes)
        {
            CatalogValidation.Add(errors, "file", CatalogValidation.FileTooLarge);
            return null;
        }

        using var stream = file.OpenReadStream();
        using var memory = new MemoryStream((int)file.Length);
        stream.CopyTo(memory);
        var bytes = memory.ToArray();
        var contentType = Sniff(bytes);
        if (contentType is null)
        {
            CatalogValidation.Add(errors, "file", CatalogValidation.CoverType);
            return null;
        }

        return new CoverImageBytes(bytes, contentType);
    }

    public static string? Sniff(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length >= JpegMagic.Length && bytes.StartsWith(JpegMagic))
        {
            return "image/jpeg";
        }

        if (bytes.Length >= PngMagic.Length && bytes.StartsWith(PngMagic))
        {
            return "image/png";
        }

        return null;
    }
}
