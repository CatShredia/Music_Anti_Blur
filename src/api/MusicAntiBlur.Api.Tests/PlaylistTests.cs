using Xunit;
using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Library;

namespace MusicAntiBlur.Api.Tests;

public class PlaylistTests
{
    private static Guid[] Ids(int n) => Enumerable.Range(0, n).Select(_ => Guid.NewGuid()).ToArray();

    [Fact]
    public void PlanAdd_appends_new_tracks_and_skips_existing()
    {
        var current = Ids(3);
        var fresh = Guid.NewGuid();

        var plan = PlaylistService.PlanAdd(current, [current[1], fresh], null, 1000);

        Assert.Equal([fresh], plan.Added);
        Assert.Equal([..current, fresh], plan.Order);
    }

    [Fact]
    public void PlanAdd_inserts_at_position_and_clamps_overflow()
    {
        var current = Ids(3);
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();

        var middle = PlaylistService.PlanAdd(current, [a], 1, 1000);
        Assert.Equal([current[0], a, current[1], current[2]], middle.Order);

        var past = PlaylistService.PlanAdd(current, [b], 99, 1000);
        Assert.Equal([..current, b], past.Order);
    }

    [Fact]
    public void PlanAdd_is_idempotent_when_everything_exists()
    {
        var current = Ids(2);

        var plan = PlaylistService.PlanAdd(current, current, 0, 1000);

        Assert.Empty(plan.Added);
        Assert.Equal(current, plan.Order);
    }

    [Fact]
    public void PlanAdd_throws_limit_reached()
    {
        var current = Ids(2);

        var ex = Assert.Throws<ApiException>(() => PlaylistService.PlanAdd(current, [Guid.NewGuid()], null, 2));

        Assert.Equal(409, ex.Status);
        Assert.Equal("limit_reached", ex.Code);
    }

    [Fact]
    public void SameSet_requires_identical_members_without_duplicates()
    {
        var current = Ids(3);

        Assert.True(PlaylistService.SameSet(current, [current[2], current[0], current[1]]));
        Assert.False(PlaylistService.SameSet(current, [current[0], current[1]]));
        Assert.False(PlaylistService.SameSet(current, [current[0], current[1], Guid.NewGuid()]));
        Assert.False(PlaylistService.SameSet(current, [current[0], current[0], current[1]]));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Title_is_required(string? raw)
    {
        var errors = CatalogValidation.NewErrors();

        Assert.Null(PlaylistService.NormalizeTitle(raw, errors));
        Assert.True(errors.ContainsKey("title"));
    }

    [Fact]
    public void Title_is_trimmed_and_limited()
    {
        var ok = CatalogValidation.NewErrors();
        Assert.Equal("Road", PlaylistService.NormalizeTitle("  Road ", ok));
        Assert.Empty(ok);

        var bad = CatalogValidation.NewErrors();
        Assert.Null(PlaylistService.NormalizeTitle(new string('x', 201), bad));
        Assert.True(bad.ContainsKey("title"));
    }

    [Fact]
    public void Description_is_optional_and_limited()
    {
        var errors = CatalogValidation.NewErrors();
        Assert.Null(PlaylistService.NormalizeDescription("  ", errors));
        Assert.Equal("text", PlaylistService.NormalizeDescription(" text ", errors));
        Assert.Empty(errors);

        Assert.Null(PlaylistService.NormalizeDescription(new string('x', 501), errors));
        Assert.True(errors.ContainsKey("description"));
    }

    [Theory]
    [InlineData("alice", "alice")]
    [InlineData("alice@example.com", "alice")]
    [InlineData(null, null)]
    [InlineData("  ", null)]
    public void Owner_name_never_exposes_email_domain(string? raw, string? expected) =>
        Assert.Equal(expected, PlaylistService.OwnerDisplayName(raw));

    [Fact]
    public void Library_order_pins_liked_then_newest_first()
    {
        var now = DateTimeOffset.UtcNow;
        var liked = new SavedLibraryService.Entry("playlist", Guid.NewGuid(), "Liked", "liked", true, now.AddDays(-30), true);
        var oldest = new SavedLibraryService.Entry("album", Guid.NewGuid(), "A", "album", false, now.AddDays(-5), false);
        var newest = new SavedLibraryService.Entry("playlist", Guid.NewGuid(), "B", "user", true, now, false);

        var ordered = SavedLibraryService.Order([oldest, newest, liked]);

        Assert.Equal([liked.Id, newest.Id, oldest.Id], ordered.Select(e => e.Id));
    }

    [Fact]
    public void Library_options_have_defaults()
    {
        var options = new LibraryOptions();

        Assert.Equal(100, options.MaxPlaylists);
        Assert.Equal(1000, options.MaxTracksPerPlaylist);
    }
}
