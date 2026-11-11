using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;
using Xunit;

namespace MusicAntiBlur.Api.Tests;

public sealed class CascadeDeleteTests
{
    private static AppDbContext NewDb() =>
        new(new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options);

    private static AdminCatalogService Svc(AppDbContext db) =>
        new(db, null!, Options.Create(new CatalogOptions()));

    private static async Task<(Artist artist, Album album, Track track)> SeedAsync(AppDbContext db)
    {
        var now = DateTimeOffset.UtcNow;
        var artist = new Artist { Id = Guid.NewGuid(), Name = "A", SortName = "a", CreatedAt = now };
        var album = new Album { Id = Guid.NewGuid(), ArtistId = artist.Id, Title = "Al", CreatedAt = now };
        var track = new Track
        {
            Id = Guid.NewGuid(), AlbumId = album.Id, ArtistId = artist.Id, Title = "T", TrackNumber = 1,
            CreatedAt = now, UpdatedAt = now
        };
        db.AddRange(artist, album, track);
        await db.SaveChangesAsync();
        return (artist, album, track);
    }

    [Fact]
    public async Task Delete_artist_without_cascade_reports_counts()
    {
        await using var db = NewDb();
        var (artist, _, _) = await SeedAsync(db);

        var ex = await Assert.ThrowsAsync<ApiException>(() => Svc(db).DeleteArtistAsync(artist.Id, false, default));

        Assert.Equal("has_dependents", ex.Code);
        Assert.Equal(1, ex.Extras!["albums"]);
        Assert.Equal(1, ex.Extras["tracks"]);
    }

    [Fact]
    public async Task Cascade_delete_artist_hides_everything_and_keeps_rows_for_restore()
    {
        await using var db = NewDb();
        var (artist, album, track) = await SeedAsync(db);

        await Svc(db).DeleteArtistAsync(artist.Id, true, default);

        Assert.False(await db.Artists.AnyAsync(a => a.Id == artist.Id));
        Assert.False(await db.Albums.AnyAsync(a => a.Id == album.Id));
        Assert.False(await db.Tracks.AnyAsync(t => t.Id == track.Id));
        Assert.True(await db.Tracks.IgnoreQueryFilters().AnyAsync(t => t.Id == track.Id && t.DeletedAt != null));
        var deleted = await Svc(db).ListDeletedAlbumsAsync(default);
        Assert.Equal(album.Id, Assert.Single(deleted).Id);
        Assert.Equal(1, deleted[0].TrackCount);
    }

    [Fact]
    public async Task Restore_album_brings_back_artist_and_cascaded_tracks()
    {
        await using var db = NewDb();
        var (artist, album, track) = await SeedAsync(db);
        await Svc(db).DeleteArtistAsync(artist.Id, true, default);

        await Svc(db).RestoreAlbumAsync(album.Id, default);

        Assert.True(await db.Artists.AnyAsync(a => a.Id == artist.Id));
        Assert.True(await db.Albums.AnyAsync(a => a.Id == album.Id));
        Assert.True(await db.Tracks.AnyAsync(t => t.Id == track.Id));
    }

    [Fact]
    public async Task Cascade_delete_album_leaves_earlier_trashed_tracks_in_trash_on_restore()
    {
        await using var db = NewDb();
        var (_, album, track) = await SeedAsync(db);
        var earlier = DateTimeOffset.UtcNow.AddDays(-1);
        var old = new Track
        {
            Id = Guid.NewGuid(), AlbumId = album.Id, ArtistId = album.ArtistId, Title = "Old", TrackNumber = 2,
            CreatedAt = earlier, UpdatedAt = earlier, DeletedAt = earlier
        };
        db.Add(old);
        await db.SaveChangesAsync();

        await Svc(db).DeleteAlbumAsync(album.Id, true, default);
        await Svc(db).RestoreAlbumAsync(album.Id, default);

        Assert.True(await db.Tracks.AnyAsync(t => t.Id == track.Id));
        Assert.False(await db.Tracks.AnyAsync(t => t.Id == old.Id));
    }

    [Fact]
    public async Task Delete_empty_album_removes_it_immediately()
    {
        await using var db = NewDb();
        var (_, album, track) = await SeedAsync(db);
        db.Tracks.Remove(track);
        await db.SaveChangesAsync();

        await Svc(db).DeleteAlbumAsync(album.Id, false, default);

        Assert.False(await db.Albums.IgnoreQueryFilters().AnyAsync(a => a.Id == album.Id));
    }
}
