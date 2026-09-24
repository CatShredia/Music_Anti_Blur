using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Storage;

namespace MusicAntiBlur.Api.Catalog;

public sealed class CatalogService(
    AppDbContext db,
    PlaybackUrlSigner signer,
    ObjectStorageClient storage,
    IHttpContextAccessor http)
{
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public async Task<PageDto<ArtistListItemDto>> ListArtistsAsync(string? cursor, int? limit, CancellationToken ct)
    {
        var errors = CatalogValidation.NewErrors();
        var take = CatalogValidation.ParseLimit(limit, errors);
        var decoded = DecodeListCursor(cursor, errors);
        CatalogValidation.ThrowIfAny(errors);

        var query = db.Artists.AsNoTracking();
        if (decoded is { } c)
        {
            query = query.Where(a =>
                a.SortName.CompareTo(c.Sort) > 0 ||
                (a.SortName == c.Sort && a.Id.CompareTo(c.Id) > 0));
        }

        var rows = await query
            .OrderBy(a => a.SortName)
            .ThenBy(a => a.Id)
            .Take(take + 1)
            .Select(a => new { a.Id, a.Name, a.SortName })
            .ToListAsync(ct);

        var page = rows.Take(take).Select(a => new ArtistListItemDto(a.Id, a.Name)).ToList();
        string? next = null;
        if (rows.Count > take)
        {
            var last = rows[take - 1];
            next = EncodeListCursor(last.SortName, last.Id);
        }

        return new PageDto<ArtistListItemDto>(page, next);
    }

    public async Task<ArtistDetailDto> GetArtistAsync(Guid id, CancellationToken ct)
    {
        var artist = await db.Artists.AsNoTracking()
            .Where(a => a.Id == id)
            .Select(a => new
            {
                a.Id,
                a.Name,
                Albums = a.Albums
                    .OrderBy(x => x.Year)
                    .ThenBy(x => x.Title)
                    .ThenBy(x => x.Id)
                    .Select(x => new { x.Id, x.Title, x.Year, x.CoverObjectKey })
                    .ToList()
            })
            .FirstOrDefaultAsync(ct);

        if (artist is null)
        {
            throw NotFound();
        }

        return new ArtistDetailDto(
            artist.Id,
            artist.Name,
            artist.Albums.Select(x =>
            {
                var cover = SignCover(x.CoverObjectKey);
                return new ArtistAlbumItemDto(x.Id, x.Title, x.Year, x.CoverObjectKey, cover.Url, cover.ExpiresAt);
            }).ToList());
    }

    public async Task<PageDto<AlbumListItemDto>> ListAlbumsAsync(Guid? artistId, string? cursor, int? limit, CancellationToken ct)
    {
        var errors = CatalogValidation.NewErrors();
        var artist = CatalogValidation.AddRequiredId(errors, "artistId", artistId);
        var take = CatalogValidation.ParseLimit(limit, errors);
        var decoded = DecodeListCursor(cursor, errors);
        CatalogValidation.ThrowIfAny(errors);

        if (!await db.Artists.AsNoTracking().AnyAsync(a => a.Id == artist, ct))
        {
            throw NotFound();
        }

        var query = db.Albums.AsNoTracking().Where(a => a.ArtistId == artist);
        if (decoded is { } c)
        {
            query = query.Where(a =>
                a.Title.CompareTo(c.Sort) > 0 ||
                (a.Title == c.Sort && a.Id.CompareTo(c.Id) > 0));
        }

        var rows = await query
            .OrderBy(a => a.Title)
            .ThenBy(a => a.Id)
            .Take(take + 1)
            .Select(a => new
            {
                a.Id,
                a.Title,
                a.Year,
                a.CoverObjectKey,
                ArtistId = a.Artist.Id,
                ArtistName = a.Artist.Name
            })
            .ToListAsync(ct);

        var page = rows.Take(take)
            .Select(a =>
            {
                var cover = SignCover(a.CoverObjectKey);
                return new AlbumListItemDto(
                    a.Id, a.Title, a.Year, a.CoverObjectKey, cover.Url, cover.ExpiresAt,
                    new ArtistRefDto(a.ArtistId, a.ArtistName));
            })
            .ToList();
        string? next = null;
        if (rows.Count > take)
        {
            var last = rows[take - 1];
            next = EncodeListCursor(last.Title, last.Id);
        }

        return new PageDto<AlbumListItemDto>(page, next);
    }

    public async Task<AlbumDetailDto> GetAlbumAsync(Guid id, CancellationToken ct)
    {
        var album = await db.Albums.AsNoTracking()
            .Where(a => a.Id == id)
            .Select(a => new
            {
                a.Id,
                a.Title,
                a.Year,
                a.CoverObjectKey,
                ArtistId = a.Artist.Id,
                ArtistName = a.Artist.Name,
                Tracks = a.Tracks
                    .OrderBy(t => t.TrackNumber)
                    .ThenBy(t => t.Id)
                    .Select(t => new TrackListItemDto(t.Id, t.Title, t.TrackNumber, t.DurationMs, t.Isrc))
                    .ToList()
            })
            .FirstOrDefaultAsync(ct);

        if (album is null)
        {
            throw NotFound();
        }

        var cover = SignCover(album.CoverObjectKey);
        return new AlbumDetailDto(
            album.Id,
            album.Title,
            album.Year,
            album.CoverObjectKey,
            cover.Url,
            cover.ExpiresAt,
            new ArtistRefDto(album.ArtistId, album.ArtistName),
            album.Tracks);
    }

    public async Task<TrackDetailDto> GetTrackAsync(Guid id, CancellationToken ct)
    {
        var track = await db.Tracks.AsNoTracking()
            .Where(t => t.Id == id)
            .Select(t => new
            {
                t.Id,
                t.Title,
                t.TrackNumber,
                t.DurationMs,
                t.Isrc,
                ArtistId = t.Artist.Id,
                ArtistName = t.Artist.Name,
                AlbumId = t.Album.Id,
                AlbumTitle = t.Album.Title,
                CoverObjectKey = t.Album.CoverObjectKey
            })
            .FirstOrDefaultAsync(ct);

        if (track is null)
        {
            throw NotFound();
        }

        var qualities = await db.TrackRenditions.AsNoTracking()
            .Where(r => r.TrackId == id && r.Status == "ready" && r.Upload.IsActive && r.BitrateKbps != null)
            .OrderByDescending(r => r.BitrateKbps)
            .Select(r => new QualityDto(r.ProfileCode, r.BitrateKbps!.Value))
            .ToListAsync(ct);

        var cover = SignCover(track.CoverObjectKey);
        return new TrackDetailDto(
            track.Id,
            track.Title,
            track.TrackNumber,
            track.DurationMs,
            track.Isrc,
            new ArtistRefDto(track.ArtistId, track.ArtistName),
            new AlbumRefDto(track.AlbumId, track.AlbumTitle),
            qualities,
            cover.Url,
            cover.ExpiresAt);
    }

    public async Task<PageDto<SearchItemDto>> SearchAsync(string? q, string? cursor, int? limit, CancellationToken ct)
    {
        var errors = CatalogValidation.NewErrors();
        var query = CatalogValidation.ParseQuery(q, errors);
        var take = CatalogValidation.ParseLimit(limit, errors);
        var decoded = DecodeSearchCursor(cursor, errors);
        CatalogValidation.ThrowIfAny(errors);

        var like = "%" + CatalogValidation.EscapeLike(query) + "%";
        var minSim = CatalogValidation.SearchMinSimilarity;
        var rows = await db.Database.SqlQuery<SearchHitRow>($"""
            SELECT type, id, title, subtitle, rank
            FROM (
              SELECT 'artist'::text AS type, a.id, a.name AS title, NULL::text AS subtitle,
                     similarity(a.name, {query})::float8 AS rank
              FROM artists a
              WHERE similarity(a.name, {query}) > {minSim}
                 OR a.name % {query}
                 OR a.name ILIKE {like} ESCAPE E'\\'
              UNION ALL
              SELECT 'album', al.id, al.title, ar.name,
                     similarity(al.title, {query})::float8
              FROM albums al
              JOIN artists ar ON ar.id = al.artist_id
              WHERE similarity(al.title, {query}) > {minSim}
                 OR al.title % {query}
                 OR al.title ILIKE {like} ESCAPE E'\\'
              UNION ALL
              SELECT 'track', t.id, t.title, ar.name || ' · ' || al.title,
                     similarity(t.title, {query})::float8
              FROM tracks t
              JOIN artists ar ON ar.id = t.artist_id
              JOIN albums al ON al.id = t.album_id
              WHERE similarity(t.title, {query}) > {minSim}
                 OR t.title % {query}
                 OR t.title ILIKE {like} ESCAPE E'\\'
            ) s
            ORDER BY rank DESC, title, id
            """).ToListAsync(ct);

        IEnumerable<SearchHitRow> filtered = rows;
        if (decoded is { } c)
        {
            filtered = rows.Where(r =>
                r.Rank < c.Rank - 1e-9 ||
                (Math.Abs(r.Rank - c.Rank) < 1e-9 && (
                    string.CompareOrdinal(r.Title, c.Title) > 0 ||
                    (r.Title == c.Title && r.Id.CompareTo(c.Id) > 0))));
        }

        var pageRows = filtered.Take(take + 1).ToList();
        var page = pageRows.Take(take)
            .Select(r => new SearchItemDto(r.Type, r.Id, r.Title, r.Subtitle, r.Rank))
            .ToList();
        string? next = null;
        if (pageRows.Count > take)
        {
            var last = pageRows[take - 1];
            next = EncodeSearchCursor(last.Rank, last.Title, last.Id);
        }

        return new PageDto<SearchItemDto>(page, next);
    }

    public async Task<ArtistDetailDto> CreateArtistAsync(UpsertArtistRequest req, CancellationToken ct)
    {
        var errors = CatalogValidation.NewErrors();
        var name = CatalogValidation.AddName(errors, "name", req.Name);
        CatalogValidation.ThrowIfAny(errors);
        var now = DateTimeOffset.UtcNow;
        var artist = new Artist
        {
            Id = Guid.NewGuid(),
            Name = name!,
            SortName = CatalogValidation.SortName(name!, req.SortName),
            CreatedAt = now
        };
        db.Artists.Add(artist);
        await db.SaveChangesAsync(ct);
        return new ArtistDetailDto(artist.Id, artist.Name, []);
    }

    public async Task<ArtistDetailDto> UpdateArtistAsync(Guid id, UpsertArtistRequest req, CancellationToken ct)
    {
        var artist = await db.Artists.FirstOrDefaultAsync(a => a.Id == id, ct)
            ?? throw NotFound();
        var errors = CatalogValidation.NewErrors();
        var name = CatalogValidation.AddName(errors, "name", req.Name);
        CatalogValidation.ThrowIfAny(errors);
        artist.Name = name!;
        artist.SortName = CatalogValidation.SortName(name!, req.SortName);
        await db.SaveChangesAsync(ct);
        return await GetArtistAsync(id, ct);
    }

    public async Task<AlbumDetailDto> CreateAlbumAsync(UpsertAlbumRequest req, CancellationToken ct)
    {
        var errors = CatalogValidation.NewErrors();
        var artistId = CatalogValidation.AddRequiredId(errors, "artistId", req.ArtistId);
        var title = CatalogValidation.AddName(errors, "title", req.Title);
        var year = CatalogValidation.AddYear(errors, req.Year);
        var cover = CatalogValidation.AddCoverKey(errors, req.CoverObjectKey);
        CatalogValidation.ThrowIfAny(errors);
        if (!await db.Artists.AnyAsync(a => a.Id == artistId, ct))
        {
            throw NotFound();
        }

        var album = new Album
        {
            Id = Guid.NewGuid(),
            ArtistId = artistId,
            Title = title!,
            Year = year,
            CoverObjectKey = cover,
            CreatedAt = DateTimeOffset.UtcNow
        };
        db.Albums.Add(album);
        await db.SaveChangesAsync(ct);
        return await GetAlbumAsync(album.Id, ct);
    }

    public async Task<AlbumDetailDto> UpdateAlbumAsync(Guid id, UpsertAlbumRequest req, CancellationToken ct)
    {
        var album = await db.Albums.FirstOrDefaultAsync(a => a.Id == id, ct)
            ?? throw NotFound();
        var errors = CatalogValidation.NewErrors();
        var artistId = CatalogValidation.AddRequiredId(errors, "artistId", req.ArtistId);
        var title = CatalogValidation.AddName(errors, "title", req.Title);
        var year = CatalogValidation.AddYear(errors, req.Year);
        var cover = CatalogValidation.AddCoverKey(errors, req.CoverObjectKey);
        CatalogValidation.ThrowIfAny(errors);
        if (!await db.Artists.AnyAsync(a => a.Id == artistId, ct))
        {
            throw NotFound();
        }

        album.ArtistId = artistId;
        album.Title = title!;
        album.Year = year;
        album.CoverObjectKey = cover;
        await db.SaveChangesAsync(ct);
        return await GetAlbumAsync(id, ct);
    }

    public async Task<TrackDetailDto> CreateTrackAsync(UpsertTrackRequest req, CancellationToken ct)
    {
        var errors = CatalogValidation.NewErrors();
        var albumId = CatalogValidation.AddRequiredId(errors, "albumId", req.AlbumId);
        var artistId = CatalogValidation.AddRequiredId(errors, "artistId", req.ArtistId);
        var title = CatalogValidation.AddName(errors, "title", req.Title);
        var number = CatalogValidation.AddTrackNumber(errors, req.TrackNumber);
        var duration = CatalogValidation.AddDuration(errors, req.DurationMs);
        var isrc = CatalogValidation.AddIsrc(errors, req.Isrc);
        CatalogValidation.ThrowIfAny(errors);
        if (!await db.Albums.AnyAsync(a => a.Id == albumId, ct) ||
            !await db.Artists.AnyAsync(a => a.Id == artistId, ct))
        {
            throw NotFound();
        }

        var now = DateTimeOffset.UtcNow;
        var track = new Track
        {
            Id = Guid.NewGuid(),
            AlbumId = albumId,
            ArtistId = artistId,
            Title = title!,
            TrackNumber = number!.Value,
            DurationMs = duration,
            Isrc = isrc,
            CreatedAt = now,
            UpdatedAt = now
        };
        db.Tracks.Add(track);
        await db.SaveChangesAsync(ct);
        return await GetTrackAsync(track.Id, ct);
    }

    public async Task<TrackDetailDto> UpdateTrackAsync(Guid id, UpsertTrackRequest req, CancellationToken ct)
    {
        var track = await db.Tracks.FirstOrDefaultAsync(t => t.Id == id, ct)
            ?? throw NotFound();
        var errors = CatalogValidation.NewErrors();
        var albumId = CatalogValidation.AddRequiredId(errors, "albumId", req.AlbumId);
        var artistId = CatalogValidation.AddRequiredId(errors, "artistId", req.ArtistId);
        var title = CatalogValidation.AddName(errors, "title", req.Title);
        var number = CatalogValidation.AddTrackNumber(errors, req.TrackNumber);
        var duration = CatalogValidation.AddDuration(errors, req.DurationMs);
        var isrc = CatalogValidation.AddIsrc(errors, req.Isrc);
        CatalogValidation.ThrowIfAny(errors);
        if (!await db.Albums.AnyAsync(a => a.Id == albumId, ct) ||
            !await db.Artists.AnyAsync(a => a.Id == artistId, ct))
        {
            throw NotFound();
        }

        track.AlbumId = albumId;
        track.ArtistId = artistId;
        track.Title = title!;
        track.TrackNumber = number!.Value;
        track.DurationMs = duration;
        track.Isrc = isrc;
        track.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
        return await GetTrackAsync(id, ct);
    }

    public async Task<AlbumDetailDto> UploadCoverAsync(Guid id, IFormFile? file, CancellationToken ct)
    {
        var album = await db.Albums.FirstOrDefaultAsync(a => a.Id == id, ct)
            ?? throw NotFound();
        var errors = CatalogValidation.NewErrors();
        var parsed = CoverImageValidation.Read(file, errors);
        CatalogValidation.ThrowIfAny(errors);

        storage.EnsureConfigured();
        var key = ObjectKeys.Cover(id);
        var ext = parsed!.ContentType == "image/png" ? ".png" : ".jpg";
        var tmp = Path.Combine(Path.GetTempPath(), $"mab-cover-{id:D}{ext}");
        try
        {
            await File.WriteAllBytesAsync(tmp, parsed.Bytes, ct);
            await storage.PutFileAsync(key, tmp, parsed.ContentType, ct);
        }
        finally
        {
            if (File.Exists(tmp))
            {
                File.Delete(tmp);
            }
        }

        album.CoverObjectKey = key;
        await db.SaveChangesAsync(ct);
        return await GetAlbumAsync(id, ct);
    }

    private (string? Url, DateTimeOffset? ExpiresAt) SignCover(string? key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            return (null, null);
        }

        try
        {
            var signed = signer.Sign(key, http.HttpContext?.Request.Host.Host, CoverImageValidation.UrlTtl);
            return (signed.Url, signed.ExpiresAt);
        }
        catch (ApiException)
        {
            return (null, null);
        }
    }

    private static ApiException NotFound() => new(404, "not_found", "Not found.");

    private static string EncodeListCursor(string sort, Guid id) =>
        Encode(new ListCursor(sort, id));

    private static string EncodeSearchCursor(double rank, string title, Guid id) =>
        Encode(new SearchCursor(rank, title, id));

    private static string Encode<T>(T value)
    {
        var json = JsonSerializer.Serialize(value, JsonOpts);
        return Convert.ToBase64String(Encoding.UTF8.GetBytes(json))
            .TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    private static ListCursor? DecodeListCursor(string? cursor, Dictionary<string, string[]> errors)
    {
        if (string.IsNullOrWhiteSpace(cursor))
        {
            return null;
        }

        var parsed = Decode<ListCursor>(cursor);
        if (parsed is null)
        {
            CatalogValidation.Add(errors, "cursor", CatalogValidation.Required);
        }

        return parsed;
    }

    private static SearchCursor? DecodeSearchCursor(string? cursor, Dictionary<string, string[]> errors)
    {
        if (string.IsNullOrWhiteSpace(cursor))
        {
            return null;
        }

        var parsed = Decode<SearchCursor>(cursor);
        if (parsed is null)
        {
            CatalogValidation.Add(errors, "cursor", CatalogValidation.Required);
        }

        return parsed;
    }

    private static T? Decode<T>(string cursor)
    {
        try
        {
            var padded = cursor.Replace('-', '+').Replace('_', '/');
            padded = padded.PadRight(padded.Length + (4 - padded.Length % 4) % 4, '=');
            var json = Encoding.UTF8.GetString(Convert.FromBase64String(padded));
            return JsonSerializer.Deserialize<T>(json, JsonOpts);
        }
        catch
        {
            return default;
        }
    }

    private sealed record ListCursor(string Sort, Guid Id);

    private sealed record SearchCursor(double Rank, string Title, Guid Id);

    private sealed class SearchHitRow
    {
        public string Type { get; init; } = "";
        public Guid Id { get; init; }
        public string Title { get; init; } = "";
        public string? Subtitle { get; init; }
        public double Rank { get; init; }
    }
}
