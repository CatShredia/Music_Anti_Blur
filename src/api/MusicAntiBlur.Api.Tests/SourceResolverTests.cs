using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Storage;
using Xunit;

namespace MusicAntiBlur.Api.Tests;

public sealed class SourceResolverTests
{
    [Fact]
    public void Auto_picks_local_first()
    {
        var result = SourceResolver.Resolve("auto", localAvailable: true, privateReady: true, catalogReady: true);
        Assert.True(result.Ok);
        Assert.Equal("local", result.Chosen);
        Assert.Null(result.FallbackReason);
    }

    [Fact]
    public void Auto_without_local_picks_private()
    {
        var result = SourceResolver.Resolve("auto", false, true, true);
        Assert.Equal("private", result.Chosen);
    }

    [Fact]
    public void Auto_falls_to_catalog()
    {
        var result = SourceResolver.Resolve("auto", false, false, true);
        Assert.Equal("catalog", result.Chosen);
    }

    [Fact]
    public void Catalog_ignores_local_file()
    {
        var result = SourceResolver.Resolve("catalog", localAvailable: true, privateReady: true, catalogReady: true);
        Assert.Equal("catalog", result.Chosen);
        Assert.Null(result.FallbackReason);
    }

    [Fact]
    public void Catalog_without_rendition_is_unavailable()
    {
        var result = SourceResolver.Resolve("catalog", true, true, catalogReady: false);
        Assert.False(result.Ok);
        Assert.Equal("source_unavailable", result.ErrorCode);
    }

    [Fact]
    public void Local_unavailable_falls_to_private()
    {
        var result = SourceResolver.Resolve("local", false, true, true);
        Assert.Equal("private", result.Chosen);
        Assert.Equal("local_unavailable", result.FallbackReason);
    }

    [Fact]
    public void Private_not_ready_falls_to_local()
    {
        var result = SourceResolver.Resolve("private", true, false, true);
        Assert.Equal("local", result.Chosen);
        Assert.Equal("private_not_ready", result.FallbackReason);
    }

    [Fact]
    public void Nothing_playable_is_unavailable()
    {
        var result = SourceResolver.Resolve("auto", false, false, false);
        Assert.False(result.Ok);
    }
}

public sealed class ObjectKeysTests
{
    [Fact]
    public void Private_keys_use_users_prefix_not_tracks()
    {
        var user = Guid.Parse("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
        var track = Guid.Parse("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb");
        var gen = Guid.Parse("cccccccc-cccc-4ccc-8ccc-cccccccccccc");
        var source = ObjectKeys.PrivateSource(user, track, gen);
        var aac = ObjectKeys.PrivateAac(user, track, gen, "aac_256");
        Assert.StartsWith("users/", source, StringComparison.Ordinal);
        Assert.StartsWith("users/", aac, StringComparison.Ordinal);
        Assert.DoesNotContain("tracks/", source, StringComparison.Ordinal);
        Assert.Contains($"/overrides/{track:D}/generations/{gen:D}/source", source, StringComparison.Ordinal);
        Assert.EndsWith("aac_256.m4a", aac, StringComparison.Ordinal);
    }

    [Fact]
    public void Catalog_keys_stay_under_tracks()
    {
        var track = Guid.Parse("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb");
        var gen = Guid.Parse("cccccccc-cccc-4ccc-8ccc-cccccccccccc");
        Assert.StartsWith("tracks/", ObjectKeys.Source(track, gen), StringComparison.Ordinal);
    }
}
