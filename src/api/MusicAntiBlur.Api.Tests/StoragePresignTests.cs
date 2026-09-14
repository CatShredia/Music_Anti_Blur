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

    [Fact]
    public void PresignGet_uses_public_presign_endpoint()
    {
        using var storage = new ObjectStorageClient(
            Options.Create(new StorageOptions
            {
                Endpoint = "http://127.0.0.1:9000",
                PresignEndpoint = "http://10.0.2.2:9000",
                Region = "us-east-1",
                Bucket = "music-anti-blur",
                AccessKey = "minio",
                SecretKey = "minio-local-only",
                ForcePathStyle = true
            }),
            NullLogger<ObjectStorageClient>.Instance);

        var url = storage.PresignGet("tracks/x/generations/y/aac_256.m4a", TimeSpan.FromMinutes(10));
        Assert.StartsWith("http://10.0.2.2:9000/music-anti-blur/", url, StringComparison.Ordinal);
    }

    [Fact]
    public void PresignGet_override_endpoint_signs_that_host()
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

        var url = storage.PresignGet("tracks/x/generations/y/aac_256.m4a", TimeSpan.FromMinutes(10), "http://10.0.2.2:9000");
        Assert.StartsWith("http://10.0.2.2:9000/music-anti-blur/", url, StringComparison.Ordinal);
    }

    [Fact]
    public void ResolvePresignBase_maps_android_emulator_host()
    {
        var storage = new StorageOptions { Endpoint = "http://127.0.0.1:9000" };
        var endpoint = PlaybackUrlSigner.ResolvePresignBase(storage, "10.0.2.2");
        Assert.Equal("http://10.0.2.2:9000", endpoint);
    }

    [Fact]
    public void ResolvePresignBase_keeps_windows_loopback()
    {
        var storage = new StorageOptions { Endpoint = "http://127.0.0.1:9000" };
        Assert.Equal("http://127.0.0.1:9000", PlaybackUrlSigner.ResolvePresignBase(storage, "127.0.0.1"));
    }

    [Fact]
    public void ResolvePresignBase_explicit_presign_endpoint_wins()
    {
        var storage = new StorageOptions
        {
            Endpoint = "http://127.0.0.1:9000",
            PresignEndpoint = "http://10.0.2.2:9000"
        };
        Assert.Equal("http://10.0.2.2:9000", PlaybackUrlSigner.ResolvePresignBase(storage, "127.0.0.1"));
    }
}
