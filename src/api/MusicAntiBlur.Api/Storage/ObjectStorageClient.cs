using System.Collections.Concurrent;
using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Storage;

public sealed class ObjectStorageClient : IDisposable
{
    private readonly StorageOptions _options;
    private readonly ILogger<ObjectStorageClient> _logger;
    private AmazonS3Client? _client;
    private readonly ConcurrentDictionary<string, AmazonS3Client> _presignClients = new(StringComparer.OrdinalIgnoreCase);

    public ObjectStorageClient(IOptions<StorageOptions> options, ILogger<ObjectStorageClient> logger)
    {
        _options = options.Value;
        _logger = logger;
    }

    public string Bucket => _options.Bucket;

    public bool IsConfigured => _options.IsConfigured;

    public void EnsureConfigured()
    {
        if (!_options.IsConfigured)
        {
            throw new ApiException(503, "dependency_unavailable", "Object storage is not configured.");
        }
    }

    public async Task<bool> HeadBucketAsync(CancellationToken ct)
    {
        if (!_options.IsConfigured)
        {
            return false;
        }

        try
        {
            await Client().HeadBucketAsync(new HeadBucketRequest { BucketName = _options.Bucket }, ct);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "HeadBucket failed.");
            return false;
        }
    }

    public async Task<string> InitiateMultipartAsync(string key, CancellationToken ct)
    {
        EnsureConfigured();
        var response = await Client().InitiateMultipartUploadAsync(new InitiateMultipartUploadRequest
        {
            BucketName = _options.Bucket,
            Key = key
        }, ct);
        return response.UploadId;
    }

    public string PresignUploadPart(string key, string uploadId, int partNumber, TimeSpan ttl, string? publicEndpoint = null)
    {
        EnsureConfigured();
        var endpoint = string.IsNullOrWhiteSpace(publicEndpoint)
            ? PresignEndpoint()
            : publicEndpoint.Trim().TrimEnd('/');
        var client = _presignClients.GetOrAdd(endpoint, CreatePresignClient);
        return client.GetPreSignedURL(new GetPreSignedUrlRequest
        {
            BucketName = _options.Bucket,
            Key = key,
            Verb = HttpVerb.PUT,
            Expires = DateTime.UtcNow.Add(ttl),
            UploadId = uploadId,
            PartNumber = partNumber,
            Protocol = PresignProtocol(endpoint)
        });
    }

    public string PresignGet(string key, TimeSpan ttl, string? publicEndpoint = null)
    {
        EnsureConfigured();
        var endpoint = string.IsNullOrWhiteSpace(publicEndpoint)
            ? PresignEndpoint()
            : publicEndpoint.Trim().TrimEnd('/');
        var client = _presignClients.GetOrAdd(endpoint, CreatePresignClient);
        return client.GetPreSignedURL(new GetPreSignedUrlRequest
        {
            BucketName = _options.Bucket,
            Key = key,
            Verb = HttpVerb.GET,
            Expires = DateTime.UtcNow.Add(ttl),
            Protocol = PresignProtocol(endpoint)
        });
    }

    public async Task CompleteMultipartAsync(string key, string uploadId, IReadOnlyList<(int PartNumber, string ETag)> parts, CancellationToken ct)
    {
        EnsureConfigured();
        var request = new CompleteMultipartUploadRequest
        {
            BucketName = _options.Bucket,
            Key = key,
            UploadId = uploadId
        };
        foreach (var (partNumber, etag) in parts.OrderBy(p => p.PartNumber))
        {
            request.AddPartETags(new PartETag(partNumber, NormalizeEtag(etag)));
        }

        await Client().CompleteMultipartUploadAsync(request, ct);
    }

    public async Task AbortMultipartAsync(string key, string uploadId, CancellationToken ct)
    {
        EnsureConfigured();
        try
        {
            await Client().AbortMultipartUploadAsync(new AbortMultipartUploadRequest
            {
                BucketName = _options.Bucket,
                Key = key,
                UploadId = uploadId
            }, ct);
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
        }
    }

    public async Task<ObjectHead?> HeadObjectAsync(string key, CancellationToken ct)
    {
        EnsureConfigured();
        try
        {
            var response = await Client().GetObjectMetadataAsync(_options.Bucket, key, ct);
            return new ObjectHead(response.ContentLength, response.Headers.ContentType);
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task PutFileAsync(string key, string filePath, string contentType, CancellationToken ct)
    {
        EnsureConfigured();
        var request = new PutObjectRequest
        {
            BucketName = _options.Bucket,
            Key = key,
            FilePath = filePath,
            ContentType = contentType
        };
        await Client().PutObjectAsync(request, ct);
    }

    public async Task<string> DownloadAndHashAsync(string key, string destinationPath, CancellationToken ct)
    {
        EnsureConfigured();
        using var response = await Client().GetObjectAsync(_options.Bucket, key, ct);
        Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
        await using var file = File.Create(destinationPath);
        using var sha = System.Security.Cryptography.IncrementalHash.CreateHash(System.Security.Cryptography.HashAlgorithmName.SHA256);
        var buffer = new byte[81920];
        int read;
        while ((read = await response.ResponseStream.ReadAsync(buffer.AsMemory(0, buffer.Length), ct)) > 0)
        {
            sha.AppendData(buffer.AsSpan(0, read));
            await file.WriteAsync(buffer.AsMemory(0, read), ct);
        }

        return Convert.ToHexString(sha.GetHashAndReset()).ToLowerInvariant();
    }

    public async Task<bool> RangeOkAsync(string key, CancellationToken ct)
    {
        EnsureConfigured();
        try
        {
            var request = new GetObjectRequest
            {
                BucketName = _options.Bucket,
                Key = key,
                ByteRange = new ByteRange(0, 1)
            };
            using var response = await Client().GetObjectAsync(request, ct);
            return (int)response.HttpStatusCode is 206 or 200;
        }
        catch
        {
            return false;
        }
    }

    public async Task DeleteObjectAsync(string key, CancellationToken ct)
    {
        EnsureConfigured();
        try
        {
            await Client().DeleteObjectAsync(_options.Bucket, key, ct);
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
        }
    }

    public void Dispose()
    {
        _client?.Dispose();
        foreach (var client in _presignClients.Values)
        {
            client.Dispose();
        }

        _presignClients.Clear();
    }

    private AmazonS3Client Client()
    {
        EnsureConfigured();
        if (_client is not null)
        {
            return _client;
        }

        _client = new AmazonS3Client(_options.AccessKey, _options.SecretKey, CreateS3Config(_options.Endpoint, _options));
        return _client;
    }

    private AmazonS3Client CreatePresignClient(string endpoint) =>
        new(_options.AccessKey, _options.SecretKey, CreateS3Config(endpoint, _options));

    private string PresignEndpoint() =>
        string.IsNullOrWhiteSpace(_options.PresignEndpoint) ? _options.Endpoint : _options.PresignEndpoint;

    internal static AmazonS3Config CreateS3Config(string endpointRaw, StorageOptions options)
    {
        var endpoint = endpointRaw.Trim().TrimEnd('/');
        var useHttp = endpoint.StartsWith("http://", StringComparison.OrdinalIgnoreCase);
        return new AmazonS3Config
        {
            ServiceURL = endpoint,
            ForcePathStyle = options.ForcePathStyle,
            AuthenticationRegion = string.IsNullOrWhiteSpace(options.Region) ? "us-east-1" : options.Region,
            UseHttp = useHttp,
            RequestChecksumCalculation = RequestChecksumCalculation.WHEN_REQUIRED,
            ResponseChecksumValidation = ResponseChecksumValidation.WHEN_REQUIRED
        };
    }

    private static Protocol PresignProtocol(string endpoint) =>
        endpoint.TrimStart().StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            ? Protocol.HTTP
            : Protocol.HTTPS;

    private static string NormalizeEtag(string etag)
    {
        var trimmed = etag.Trim();
        if (trimmed.Length >= 2 && trimmed.StartsWith('"') && trimmed.EndsWith('"'))
        {
            return trimmed;
        }

        return $"\"{trimmed.Trim('"')}\"";
    }
}

public sealed record ObjectHead(long ContentLength, string? ContentType);
