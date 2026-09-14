using System.Security.Cryptography;
using System.Text.RegularExpressions;
using MusicAntiBlur.Api.Auth;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Uploads;

public static class UploadValidation
{
    public const long MinPartBytes = 5L * 1024 * 1024;
    public const long TargetPartBytes = 8L * 1024 * 1024;
    public const long MaxPartBytes = 16L * 1024 * 1024;
    public const int MaxParts = 10_000;

    private static readonly HashSet<string> ContentTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "audio/mpeg", "audio/mp3", "audio/mp4", "audio/aac", "audio/x-m4a", "audio/m4a",
        "audio/flac", "audio/x-flac", "audio/wav", "audio/x-wav", "audio/wave",
        "audio/ogg", "audio/opus", "application/octet-stream"
    };

    public static Guid RequireIdempotencyKey(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw) || !Guid.TryParse(raw, out var key))
        {
            throw new ApiException(400, "validation_failed", "Validation failed.",
                new Dictionary<string, string[]> { ["idempotencyKey"] = [AuthValidation.Required] });
        }

        return key;
    }

    public static (long Size, string ContentType, string Checksum, string FileName) ValidateInitiate(
        InitiateUploadRequest req, long maxBytes)
    {
        var errors = AuthValidation.NewErrors();
        var fileName = (req.FileName ?? "").Trim();
        if (fileName.Length is < 1 or > 255)
        {
            AuthValidation.Add(errors, "fileName", fileName.Length == 0 ? AuthValidation.Required : "name_length");
        }

        if (fileName.Contains('/') || fileName.Contains('\\') || fileName.Contains(".."))
        {
            AuthValidation.Add(errors, "fileName", "name_length");
        }

        if (req.SizeBytes is null or <= 0)
        {
            AuthValidation.Add(errors, "sizeBytes", AuthValidation.Required);
        }
        else if (req.SizeBytes.Value > maxBytes)
        {
            throw new ApiException(413, "file_too_large", "File is too large.");
        }

        var contentType = (req.ContentType ?? "").Trim();
        if (contentType.Length == 0)
        {
            AuthValidation.Add(errors, "contentType", AuthValidation.Required);
        }
        else if (!ContentTypes.Contains(contentType))
        {
            AuthValidation.Add(errors, "contentType", "unsupported_audio");
        }

        string? checksum = null;
        try
        {
            checksum = NormalizeChecksum(req.ChecksumSha256);
        }
        catch
        {
            AuthValidation.Add(errors, "checksumSha256", AuthValidation.Required);
        }

        AuthValidation.ThrowIfAny(errors);
        return (req.SizeBytes!.Value, contentType, checksum!, fileName);
    }

    public static string NormalizeChecksum(string? raw)
    {
        var value = (raw ?? "").Trim();
        if (value.Length == 0)
        {
            throw new FormatException("empty");
        }

        if (Regex.IsMatch(value, "^[0-9a-fA-F]{64}$"))
        {
            return value.ToLowerInvariant();
        }

        var bytes = Convert.FromBase64String(value);
        if (bytes.Length != 32)
        {
            throw new FormatException("length");
        }

        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    public static (long PartSize, int PartCount) SplitParts(long sizeBytes)
    {
        if (sizeBytes <= MaxPartBytes)
        {
            return (sizeBytes, 1);
        }

        var partSize = TargetPartBytes;
        var count = (int)Math.Ceiling(sizeBytes / (double)partSize);
        if (count > MaxParts)
        {
            throw new ApiException(413, "file_too_large", "File is too large.");
        }

        return (partSize, count);
    }
}
