using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Catalog;

/// <summary>Справочник жанров: админ-управление, назначение альбомам и трекам, публичный просмотр.</summary>
public sealed class GenreService(AppDbContext db, CatalogService catalog, PopularityService popularity)
{
    public const int GenrePageAlbums = 50;
    public const int GenrePopularTracks = 20;

    // ---------- Справочник ----------

    public async Task<IReadOnlyList<GenreListItemDto>> ListAsync(CancellationToken ct)
    {
        var rows = await db.Genres.AsNoTracking()
            .OrderBy(g => g.Name)
            .ThenBy(g => g.Id)
            .Select(g => new
            {
                g.Id,
                g.Name,
                Albums = db.AlbumGenres.Count(x => x.GenreId == g.Id),
                Tracks = db.TrackGenres.Count(x => x.GenreId == g.Id)
            })
            .ToListAsync(ct);
        return rows.Select(r => new GenreListItemDto(r.Id, r.Name, r.Albums, r.Tracks)).ToList();
    }

    public async Task<GenreRefDto> CreateAsync(UpsertGenreRequest req, CancellationToken ct)
    {
        var name = ValidName(req.Name);
        var slug = GenreNames.Slug(name);
        if (await db.Genres.AnyAsync(g => g.Slug == slug, ct))
        {
            throw Exists();
        }

        var genre = new Genre { Id = Guid.NewGuid(), Name = name, Slug = slug, CreatedAt = DateTimeOffset.UtcNow };
        db.Genres.Add(genre);
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            throw Exists();
        }

        return new GenreRefDto(genre.Id, genre.Name);
    }

    public async Task<GenreRefDto> RenameAsync(Guid id, UpsertGenreRequest req, CancellationToken ct)
    {
        var genre = await db.Genres.FirstOrDefaultAsync(g => g.Id == id, ct) ?? throw NotFound();
        var name = ValidName(req.Name);
        var slug = GenreNames.Slug(name);
        if (await db.Genres.AnyAsync(g => g.Slug == slug && g.Id != id, ct))
        {
            throw Exists();
        }

        genre.Name = name;
        genre.Slug = slug;
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            throw Exists();
        }

        return new GenreRefDto(genre.Id, genre.Name);
    }

    /// <summary>Удаляет жанр; связи уходят каскадом. Возвращает, у скольких треков и альбомов он был.</summary>
    public async Task<GenreRemovedDto> DeleteAsync(Guid id, CancellationToken ct)
    {
        var genre = await db.Genres.FirstOrDefaultAsync(g => g.Id == id, ct) ?? throw NotFound();
        var tracks = await db.TrackGenres.CountAsync(x => x.GenreId == id, ct);
        var albums = await db.AlbumGenres.CountAsync(x => x.GenreId == id, ct);
        db.Genres.Remove(genre);
        await db.SaveChangesAsync(ct);
        return new GenreRemovedDto(tracks, albums);
    }

    // ---------- Назначение ----------

    public async Task<IReadOnlyList<GenreRefDto>> SetAlbumGenresAsync(Guid albumId, SetGenresRequest req, CancellationToken ct)
    {
        if (!await db.Albums.AnyAsync(a => a.Id == albumId, ct))
        {
            throw NotFound();
        }

        var ids = await ValidIdsAsync(req, ct);
        var current = await db.AlbumGenres.Where(x => x.AlbumId == albumId).ToListAsync(ct);
        db.AlbumGenres.RemoveRange(current.Where(x => !ids.Contains(x.GenreId)));
        var have = current.Select(x => x.GenreId).ToHashSet();
        db.AlbumGenres.AddRange(ids.Where(g => !have.Contains(g)).Select(g => new AlbumGenre { AlbumId = albumId, GenreId = g }));
        await db.SaveChangesAsync(ct);
        return await GenresOfAlbumAsync(albumId, ct);
    }

    public async Task<IReadOnlyList<GenreRefDto>> SetTrackGenresAsync(Guid trackId, SetGenresRequest req, CancellationToken ct)
    {
        if (!await db.Tracks.AnyAsync(t => t.Id == trackId, ct))
        {
            throw NotFound();
        }

        var ids = await ValidIdsAsync(req, ct);
        var current = await db.TrackGenres.Where(x => x.TrackId == trackId).ToListAsync(ct);
        db.TrackGenres.RemoveRange(current.Where(x => !ids.Contains(x.GenreId)));
        var have = current.Select(x => x.GenreId).ToHashSet();
        db.TrackGenres.AddRange(ids.Where(g => !have.Contains(g)).Select(g => new TrackGenre { TrackId = trackId, GenreId = g }));
        await db.SaveChangesAsync(ct);
        return await GenresOfTrackAsync(trackId, ct);
    }

    public async Task<IReadOnlyList<GenreRefDto>> GenresOfAlbumAsync(Guid albumId, CancellationToken ct) =>
        await db.AlbumGenres.AsNoTracking()
            .Where(x => x.AlbumId == albumId)
            .OrderBy(x => x.Genre.Name)
            .Select(x => new GenreRefDto(x.GenreId, x.Genre.Name))
            .ToListAsync(ct);

    public async Task<IReadOnlyList<GenreRefDto>> GenresOfTrackAsync(Guid trackId, CancellationToken ct) =>
        await db.TrackGenres.AsNoTracking()
            .Where(x => x.TrackId == trackId)
            .OrderBy(x => x.Genre.Name)
            .Select(x => new GenreRefDto(x.GenreId, x.Genre.Name))
            .ToListAsync(ct);

    // ---------- Публичная страница жанра ----------

    public async Task<GenreDetailDto> GetAsync(Guid id, CancellationToken ct)
    {
        var genre = await db.Genres.AsNoTracking().FirstOrDefaultAsync(g => g.Id == id, ct) ?? throw NotFound();

        var albums = await db.AlbumGenres.AsNoTracking()
            .Where(x => x.GenreId == id)
            .OrderBy(x => x.Album.Title)
            .ThenBy(x => x.AlbumId)
            .Take(GenrePageAlbums)
            .Select(x => new
            {
                x.Album.Id,
                x.Album.Title,
                x.Album.Year,
                x.Album.CoverObjectKey,
                ArtistId = x.Album.Artist.Id,
                ArtistName = x.Album.Artist.Name
            })
            .ToListAsync(ct);

        var albumDtos = albums.Select(a =>
        {
            var cover = catalog.SignCover(a.CoverObjectKey);
            return new AlbumListItemDto(a.Id, a.Title, a.Year, a.CoverObjectKey, cover.Url, cover.ExpiresAt,
                new ArtistRefDto(a.ArtistId, a.ArtistName));
        }).ToList();

        // Треки жанра: помеченные им самим или лежащие в альбоме этого жанра.
        var tracks = db.Tracks.AsNoTracking().Where(t =>
            db.TrackGenres.Any(tg => tg.TrackId == t.Id && tg.GenreId == id) ||
            db.AlbumGenres.Any(ag => ag.AlbumId == t.AlbumId && ag.GenreId == id));
        var popular = await popularity.ForTracksAsync(tracks, null, GenrePopularTracks, ct);

        return new GenreDetailDto(genre.Id, genre.Name, albumDtos, catalog.ToPopularDtos(popular));
    }

    // ---------- Внутреннее ----------

    private static string ValidName(string? raw)
    {
        var name = GenreNames.Clean(raw);
        if (name is null)
        {
            var errors = CatalogValidation.NewErrors();
            CatalogValidation.Add(errors, "name",
                string.IsNullOrWhiteSpace(raw) ? CatalogValidation.Required : CatalogValidation.NameLength);
            CatalogValidation.ThrowIfAny(errors);
        }

        return name!;
    }

    private async Task<HashSet<Guid>> ValidIdsAsync(SetGenresRequest req, CancellationToken ct)
    {
        var ids = (req.GenreIds ?? []).Distinct().ToHashSet();
        var errors = CatalogValidation.NewErrors();
        if (ids.Count > GenreNames.MaxPerEntity)
        {
            CatalogValidation.Add(errors, "genreIds", "too_many");
        }

        CatalogValidation.ThrowIfAny(errors);
        if (ids.Count > 0)
        {
            var found = await db.Genres.CountAsync(g => ids.Contains(g.Id), ct);
            if (found != ids.Count)
            {
                throw NotFound();
            }
        }

        return ids;
    }

    private static ApiException NotFound() => new(404, "not_found", "Not found.");

    private static ApiException Exists() => new(409, "genre_exists", "A genre with this name already exists.");
}
