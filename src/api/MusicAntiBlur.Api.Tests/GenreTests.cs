using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Library;
using MusicAntiBlur.Api.Media;
using Xunit;

namespace MusicAntiBlur.Api.Tests;

public class GenreTests
{
    [Theory]
    [InlineData("  Rock  ", "Rock")]
    [InlineData("Alternative   Rock", "Alternative Rock")]
    [InlineData("R&B", "R&B")]
    public void Clean_trims_and_collapses_spaces(string raw, string expected) =>
        Assert.Equal(expected, GenreNames.Clean(raw));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Clean_rejects_empty(string? raw) => Assert.Null(GenreNames.Clean(raw));

    [Fact]
    public void Clean_rejects_names_over_the_limit()
    {
        Assert.NotNull(GenreNames.Clean(new string('x', 60)));
        Assert.Null(GenreNames.Clean(new string('x', 61)));
    }

    [Fact]
    public void Slug_ignores_case()
    {
        Assert.Equal(GenreNames.Slug("Hip-Hop"), GenreNames.Slug("hip-hop"));
    }

    [Theory]
    [InlineData("Rock; Alternative", new[] { "Rock", "Alternative" })]
    [InlineData("Rock/Pop", new[] { "Rock", "Pop" })]
    [InlineData("Nu Metal, Rap Rock", new[] { "Nu Metal", "Rap Rock" })]
    [InlineData("rock; ROCK ;Rock", new[] { "rock" })]
    [InlineData(";; ;", new string[0])]
    public void ParseTag_splits_and_deduplicates(string raw, string[] expected) =>
        Assert.Equal(expected, GenreNames.ParseTag(raw));

    [Fact]
    public void ParseTag_drops_oversized_parts_and_caps_the_count()
    {
        Assert.Equal(["Rock"], GenreNames.ParseTag("Rock;" + new string('x', 80)));

        var many = string.Join(';', Enumerable.Range(1, 25).Select(i => "G" + i));
        Assert.Equal(GenreNames.MaxPerEntity, GenreNames.ParseTag(many).Count);
    }

    [Fact]
    public void ParseTag_is_empty_for_null() => Assert.Empty(GenreNames.ParseTag(null));

    [Fact]
    public void ExtractGenreTags_reads_format_tags_case_insensitively()
    {
        const string json = """{"format":{"format_name":"mp3","tags":{"GENRE":"Rock; Pop","title":"x"}}}""";

        Assert.Equal(["Rock", "Pop"], FfprobeParser.ExtractGenreTags(json));
    }

    [Theory]
    [InlineData("""{"format":{"format_name":"mp3"}}""")]
    [InlineData("""{"format":{"tags":{"title":"x"}}}""")]
    [InlineData("""{"format":{"tags":{"genre":5}}}""")]
    [InlineData("not json")]
    public void ExtractGenreTags_is_empty_when_missing_or_broken(string json) =>
        Assert.Empty(FfprobeParser.ExtractGenreTags(json));

    [Fact]
    public void Search_history_normalization_ignores_case_and_spaces()
    {
        Assert.Equal("linkin park", SearchHistoryService.Normalize("  Linkin   PARK "));
        Assert.Equal(SearchHistoryService.Normalize("Meteora"), SearchHistoryService.Normalize("meteora"));
    }

    [Fact]
    public void Catalog_options_defaults()
    {
        var catalog = new CatalogOptions();
        var library = new LibraryOptions();

        Assert.Equal(0.8, catalog.GenreRankFactor);
        Assert.Equal(50, library.SearchHistoryMax);
    }
}
