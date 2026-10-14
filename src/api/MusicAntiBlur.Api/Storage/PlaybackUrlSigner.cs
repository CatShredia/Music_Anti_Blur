using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Storage;

public sealed class PlaybackUrlSigner(IOptions<StorageOptions> storageOptions, IOptions<CdnOptions> cdnOptions, ObjectStorageClient storage)
{
    public SignedPlaybackUrl Sign(string bucketKey, string? clientHost = null, TimeSpan? ttlOverride = null)
    {
        var storageCfg = storageOptions.Value;
        var cdn = cdnOptions.Value;
        var ttl = ttlOverride ?? TimeSpan.FromSeconds(cdn.UrlTtlSeconds <= 0 ? 600 : cdn.UrlTtlSeconds);
        var expiresAt = DateTimeOffset.UtcNow.Add(ttl);

        if (storageCfg.UseCdn)
        {
            if (!cdn.IsConfigured)
            {
                throw new ApiException(503, "dependency_unavailable", "CDN is not configured.");
            }

            var path = "/" + bucketKey.TrimStart('/');
            var expiresUnix = expiresAt.ToUnixTimeSeconds();
            var token = Md5Base64Url(cdn.SecureTokenKey + path + expiresUnix);
            var baseUrl = cdn.BaseUrl.TrimEnd('/');
            var url = $"{baseUrl}{path}?md5={token}&expires={expiresUnix}";
            return new SignedPlaybackUrl(url, expiresAt);
        }

        storage.EnsureConfigured();
        var endpoint = ResolvePresignBase(storageCfg, clientHost);
        var presigned = storage.PresignGet(bucketKey, ttl, endpoint);
        return new SignedPlaybackUrl(presigned, expiresAt);
    }

    public string CachePartition(string? clientHost)
    {
        var storageCfg = storageOptions.Value;
        return storageCfg.UseCdn ? "cdn" : ResolvePresignBase(storageCfg, clientHost).ToLowerInvariant();
    }

    public static string ResolvePresignBase(StorageOptions storage, string? clientHost)
    {
        if (!string.IsNullOrWhiteSpace(storage.PresignEndpoint))
        {
            return storage.PresignEndpoint.Trim().TrimEnd('/');
        }

        var fallback = (storage.Endpoint ?? "").Trim().TrimEnd('/');
        if (string.IsNullOrWhiteSpace(clientHost) || !Uri.TryCreate(fallback, UriKind.Absolute, out var minio))
        {
            return fallback;
        }

        var host = clientHost.Trim();
        if (!IsLoopbackMinioHost(minio.Host) || !IsEmulatorOrLanHost(host))
        {
            return fallback;
        }

        return $"{minio.Scheme}://{host}:{minio.Port}";
    }

    internal static bool IsLoopbackMinioHost(string host) =>
        host.Equals("localhost", StringComparison.OrdinalIgnoreCase) ||
        host.Equals("127.0.0.1", StringComparison.OrdinalIgnoreCase) ||
        host.Equals("::1", StringComparison.OrdinalIgnoreCase) ||
        host.Equals("0.0.0.0", StringComparison.OrdinalIgnoreCase);

    internal static bool IsEmulatorOrLanHost(string host)
    {
        if (host.Equals("localhost", StringComparison.OrdinalIgnoreCase) ||
            host.Equals("10.0.2.2", StringComparison.OrdinalIgnoreCase) ||
            host.Equals("10.0.3.2", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (!IPAddress.TryParse(host, out var ip))
        {
            return false;
        }

        if (IPAddress.IsLoopback(ip))
        {
            return true;
        }

        if (ip.AddressFamily != AddressFamily.InterNetwork)
        {
            return false;
        }

        var bytes = ip.GetAddressBytes();
        return bytes[0] == 10 ||
               (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
               (bytes[0] == 192 && bytes[1] == 168);
    }

    private static string Md5Base64Url(string value)
    {
        var hash = MD5.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToBase64String(hash).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }
}

public sealed record SignedPlaybackUrl(string Url, DateTimeOffset ExpiresAt);
