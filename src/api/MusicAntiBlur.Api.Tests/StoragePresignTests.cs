using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Storage;
using Xunit;

namespace MusicAntiBlur.Api.Tests;

public sealed class StoragePresignTests
{
    [Fact]
    public void PresignGet_keeps_http_for_minio_endpoint()
    {
        using var storage = new ObjectStorageClient(
            Options.Create(new StorageOptions
            {
                Endpoint = "http://127.0.0.1:9000",
                Region = "us-east-1",
                Bucket = "music-anti-blur",
                AccessKey = "minio",
                SecretKey = "minio-local-only",
                ForcePathStyle = true
            }),
            NullLogger<ObjectStorageClient>.Instance);

        var url = storage.PresignGet("tracks/x/generations/y/source", TimeSpan.FromMinutes(10));
        Assert.StartsWith("http://127.0.0.1:9000/music-anti-blur/", url, StringComparison.Ordinal);
        Assert.DoesNotContain("https://", url, StringComparison.Ordinal);
    }
}
