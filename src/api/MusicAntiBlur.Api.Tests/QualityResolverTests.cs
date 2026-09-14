using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Media;
using Xunit;

namespace MusicAntiBlur.Api.Tests;

public sealed class QualityResolverTests
{
    private static readonly ReadyQuality High = new("aac_256", 256, Guid.NewGuid(), 1000, "tracks/a/generations/b/aac_256.m4a");
    private static readonly ReadyQuality Low = new("aac_128", 128, High.GenerationId, 1000, "tracks/a/generations/b/aac_128.m4a");
    private static readonly ReadyQuality Src = new("src", 320, High.GenerationId, 1000, "tracks/a/generations/b/source");

    [Fact]
    public void Auto_prefers_aac_256()
    {
        var result = QualityResolver.Resolve([Low, High], "auto");
        Assert.True(result.Ok);
        Assert.Equal("aac_256", result.Chosen!.Code);
        Assert.Null(result.QualityFallbackFrom);
    }

    [Fact]
    public void Auto_falls_to_aac_128()
    {
        var result = QualityResolver.Resolve([Low], "auto");
        Assert.True(result.Ok);
        Assert.Equal("aac_128", result.Chosen!.Code);
    }

    [Fact]
    public void Auto_never_selects_src()
    {
        var result = QualityResolver.Resolve([Src], "auto");
        Assert.False(result.Ok);
        Assert.Equal("source_unavailable", result.ErrorCode);
    }

    [Fact]
    public void Explicit_aac_256_can_fall_down()
    {
        var result = QualityResolver.Resolve([Low], "aac_256");
        Assert.True(result.Ok);
        Assert.Equal("aac_128", result.Chosen!.Code);
        Assert.Equal("aac_256", result.QualityFallbackFrom);
    }

    [Fact]
    public void Explicit_aac_128_does_not_upscale()
    {
        var result = QualityResolver.Resolve([High], "aac_128");
        Assert.False(result.Ok);
        Assert.Equal("quality_unavailable", result.ErrorCode);
    }

    [Fact]
    public void Explicit_src_requires_src_row()
    {
        Assert.False(QualityResolver.Resolve([High, Low], "src").Ok);
        var ok = QualityResolver.Resolve([Src], "src");
        Assert.True(ok.Ok);
        Assert.Equal("src", ok.Chosen!.Code);
    }
}

public sealed class TranscodeProfilesTests
{
    [Fact]
    public void Encode_args_are_literal_list_without_shell()
    {
        var args = TranscodeProfiles.EncodeArgs(@"C:\in.mp3", @"C:\out.m4a", TranscodeProfiles.Aac128);
        Assert.Equal("-y", args[0]);
        Assert.DoesNotContain(args, a => a.Contains('|') || a.Contains('&') || a.Contains(';'));
        Assert.Contains("-b:a", args);
        Assert.Contains("128k", args);
        Assert.Equal(@"C:\out.m4a", args[^1]);
    }

    [Fact]
    public void Ffprobe_args_request_json()
    {
        var args = TranscodeProfiles.FfprobeArgs("file.flac");
        Assert.Contains("json", args);
        Assert.Equal("file.flac", args[^1]);
    }
}
