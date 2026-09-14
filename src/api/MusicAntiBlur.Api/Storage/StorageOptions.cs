namespace MusicAntiBlur.Api.Storage;

public sealed class StorageOptions
{
    public const string Section = "Storage";

    public string Endpoint { get; set; } = "";
    public string PresignEndpoint { get; set; } = "";
    public string Region { get; set; } = "us-east-1";
    public string Bucket { get; set; } = "";
    public string AccessKey { get; set; } = "";
    public string SecretKey { get; set; } = "";
    public bool ForcePathStyle { get; set; } = true;
    public bool UseCdn { get; set; }
    public long CatalogMaxSourceBytes { get; set; } = 104_857_600;

    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(Endpoint) &&
        !string.IsNullOrWhiteSpace(Bucket) &&
        !string.IsNullOrWhiteSpace(AccessKey) &&
        !string.IsNullOrWhiteSpace(SecretKey);
}

public sealed class CdnOptions
{
    public const string Section = "Cdn";

    public string BaseUrl { get; set; } = "";
    public string SecureTokenKey { get; set; } = "";
    public int UrlTtlSeconds { get; set; } = 600;
    public int CacheTtlSeconds { get; set; } = 480;

    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(BaseUrl) &&
        !string.IsNullOrWhiteSpace(SecureTokenKey);
}

public sealed class MediaOptions
{
    public const string Section = "Media";

    public string FfmpegPath { get; set; } = "ffmpeg";
    public string FfprobePath { get; set; } = "ffprobe";
}

public static class ObjectKeys
{
    public static string Source(Guid trackId, Guid generationId) =>
        $"tracks/{trackId:D}/generations/{generationId:D}/source";

    public static string Aac(Guid trackId, Guid generationId, string profileCode) =>
        $"tracks/{trackId:D}/generations/{generationId:D}/{profileCode}.m4a";
}
