using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Storage;

public sealed class PlaybackUrlSigner(IOptions<StorageOptions> storageOptions, IOptions<CdnOptions> cdnOptions, ObjectStorageClient storage)
{
    public SignedPlaybackUrl Sign(string bucketKey)
    {
        var storageCfg = storageOptions.Value;
        var cdn = cdnOptions.Value;
        var ttl = TimeSpan.FromSeconds(cdn.UrlTtlSeconds <= 0 ? 600 : cdn.UrlTtlSeconds);
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
        var presigned = storage.PresignGet(bucketKey, ttl);
        return new SignedPlaybackUrl(presigned, expiresAt);
    }

    private static string Md5Base64Url(string value)
    {
        var hash = MD5.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToBase64String(hash).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }
}

public sealed record SignedPlaybackUrl(string Url, DateTimeOffset ExpiresAt);
