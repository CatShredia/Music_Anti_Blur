using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Library;

/// <summary>Библиотека пользователя: свои и сохранённые плейлисты, сохранённые альбомы.</summary>
public sealed class SavedLibraryService(AppDbContext db, LibraryService library, CatalogService catalog)
{
    public const string TypeAll = "all";
    public const string TypePlaylists = "playlists";
    public const string TypeAlbums = "albums";

    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    // ---------- Сохранение ----------

    public async Task SavePlaylistAsync(Guid userId, Guid playlistId, CancellationToken ct)
    {
        var playlist = await db.Playlists.AsNoTracking()
            .Where(p => p.Id == playlistId)
            .Select(p => new { p.UserId, p.IsPublic, p.Kind })
            .FirstOrDefaultAsync(ct);
        if (playlist is null || playlist.Kind != Playlist.KindUser || (!playlist.IsPublic && playlist.UserId != userId))
        {
            throw NotFound();
        }

        if (playlist.UserId == userId)
        {
            throw new ApiException(409, "own_playlist", "Your own playlist is already in the library.");
        }

        if (await db.SavedPlaylists.AnyAsync(s => s.UserId == userId && s.PlaylistId == playlistId, ct))
        {
            return;
        }

        db.SavedPlaylists.Add(new SavedPlaylist { UserId = userId, PlaylistId = playlistId, AddedAt = DateTimeOffset.UtcNow });
        await SaveIgnoringDuplicateAsync(ct);
    }

    public async Task RemovePlaylistAsync(Guid userId, Guid playlistId, CancellationToken ct)
    {
        var row = await db.SavedPlaylists.FirstOrDefaultAsync(s => s.UserId == userId && s.PlaylistId == playlistId, ct);
        if (row is null)
        {
            return;
        }

        db.SavedPlaylists.Remove(row);
        await db.SaveChangesAsync(ct);
    }

    public async Task SaveAlbumAsync(Guid userId, Guid albumId, CancellationToken ct)
    {
        if (!await db.Albums.AsNoTracking().AnyAsync(a => a.Id == albumId, ct))
        {
            throw NotFound();
        }

        if (await db.SavedAlbums.AnyAsync(s => s.UserId == userId && s.AlbumId == albumId, ct))
        {
            return;
        }

        db.SavedAlbums.Add(new SavedAlbum { UserId = userId, AlbumId = albumId, AddedAt = DateTimeOffset.UtcNow });
        await SaveIgnoringDuplicateAsync(ct);
    }

    public async Task RemoveAlbumAsync(Guid userId, Guid albumId, CancellationToken ct)
    {
        var row = await db.SavedAlbums.FirstOrDefaultAsync(s => s.UserId == userId && s.AlbumId == albumId, ct);
        if (row is null)
        {
            return;
        }

        db.SavedAlbums.Remove(row);
        await db.SaveChangesAsync(ct);
    }

    public async Task<InLibraryDto> AlbumStatusAsync(Guid userId, Guid albumId, CancellationToken ct)
    {
        if (!await db.Albums.AsNoTracking().AnyAsync(a => a.Id == albumId, ct))
        {
            throw NotFound();
        }

        return new InLibraryDto(await db.SavedAlbums.AsNoTracking()
            .AnyAsync(s => s.UserId == userId && s.AlbumId == albumId, ct));
    }

    // ---------- Лента ----------

    public async Task<LibraryPageDto> ListAsync(Guid userId, string? type, string? cursor, int? limit, CancellationToken ct)
    {
        var errors = CatalogValidation.NewErrors();
        var take = CatalogValidation.ParseLimit(limit, errors);
        var offset = DecodeOffset(cursor, errors);
        var kind = (type ?? TypeAll).ToLowerInvariant();
        if (kind is not (TypeAll or TypePlaylists or TypeAlbums))
        {
            CatalogValidation.Add(errors, "type", CatalogValidation.Required);
        }

        CatalogValidation.ThrowIfAny(errors);

        await library.EnsureLikedPlaylistAsync(userId, ct);

        var entries = new List<Entry>();
        if (kind is TypeAll or TypePlaylists)
        {
            // Свои плейлисты (liked включительно) и сохранённые чужие, которые всё ещё публичны.
            var own = await db.Playlists.AsNoTracking()
                .Where(p => p.UserId == userId)
                .Select(p => new { p.Id, p.Title, p.Kind, SortAt = p.UpdatedAt })
                .ToListAsync(ct);
            entries.AddRange(own.Select(p => new Entry(
                "playlist", p.Id, p.Title, p.Kind, true, p.SortAt, p.Kind == Playlist.KindLiked)));

            var saved = await db.SavedPlaylists.AsNoTracking()
                .Where(s => s.UserId == userId && s.Playlist.IsPublic && s.Playlist.Kind == Playlist.KindUser)
                .Select(s => new
                {
                    s.PlaylistId,
                    s.Playlist.Title,
                    Owner = s.Playlist.User.Login ?? s.Playlist.User.Email,
                    s.AddedAt
                })
                .ToListAsync(ct);
            entries.AddRange(saved.Select(s => new Entry(
                "playlist", s.PlaylistId, s.Title, "saved", false, s.AddedAt, false,
                OwnerName: PlaylistService.OwnerDisplayName(s.Owner))));
        }

        if (kind is TypeAll or TypeAlbums)
        {
            var albums = await db.SavedAlbums.AsNoTracking()
                .Where(s => s.UserId == userId)
                .Select(s => new { s.AlbumId, s.Album.Title, Artist = s.Album.Artist.Name, s.AddedAt })
                .ToListAsync(ct);
            entries.AddRange(albums.Select(a => new Entry(
                "album", a.AlbumId, a.Title, "album", false, a.AddedAt, false, Subtitle: a.Artist)));
        }

        var ordered = Order(entries);
        var page = ordered.Skip(offset).Take(take).ToList();
        var items = new List<LibraryItemDto>(page.Count);
        foreach (var e in page)
        {
            items.Add(await ToItemAsync(e, ct));
        }

        var next = offset + take < ordered.Count ? EncodeOffset(offset + take) : null;
        return new LibraryPageDto(items, next);
    }

    // ---------- Чистая логика ----------

    public sealed record Entry(
        string Type,
        Guid Id,
        string Title,
        string Kind,
        bool IsOwn,
        DateTimeOffset SortAt,
        bool Pinned,
        string? OwnerName = null,
        string? Subtitle = null);

    /// <summary>«Мне нравится» всегда первый, остальное по убыванию даты, затем по id.</summary>
    public static List<Entry> Order(IEnumerable<Entry> entries) =>
        entries.OrderBy(e => e.Pinned ? 0 : 1)
            .ThenByDescending(e => e.SortAt)
            .ThenBy(e => e.Id)
            .ToList();

    // ---------- Внутреннее ----------

    private async Task<LibraryItemDto> ToItemAsync(Entry e, CancellationToken ct)
    {
        if (e.Type == "album")
        {
            var cover = await db.Albums.AsNoTracking()
                .Where(a => a.Id == e.Id)
                .Select(a => a.CoverObjectKey)
                .FirstOrDefaultAsync(ct);
            var url = catalog.SignCover(cover).Url;
            var trackCount = await db.Tracks.AsNoTracking().CountAsync(t => t.AlbumId == e.Id, ct);
            return new LibraryItemDto(
                e.Type, e.Id, e.Title, e.Subtitle, e.Kind, false, null, trackCount,
                url is null ? [] : [url], e.SortAt);
        }

        var keys = await db.PlaylistTracks.AsNoTracking()
            .Where(x => x.PlaylistId == e.Id && db.Tracks.Any(t => t.Id == x.TrackId))
            .OrderBy(x => x.Position)
            .Select(x => x.Track.Album.CoverObjectKey)
            .Take(PlaylistService.CollageSize * 4)
            .ToListAsync(ct);
        var count = await db.PlaylistTracks.AsNoTracking()
            .CountAsync(x => x.PlaylistId == e.Id && db.Tracks.Any(t => t.Id == x.TrackId), ct);
        return new LibraryItemDto(
            e.Type, e.Id, e.Title, null, e.Kind, e.IsOwn, e.OwnerName, count,
            PlaylistService.CollageFromKeys(keys, catalog), e.SortAt);
    }

    private async Task SaveIgnoringDuplicateAsync(CancellationToken ct)
    {
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            // Параллельный повторный запрос уже добавил запись — операция идемпотентна.
            db.ChangeTracker.Clear();
        }
    }

    private static ApiException NotFound() => new(404, "not_found", "Not found.");

    private static int DecodeOffset(string? cursor, Dictionary<string, string[]> errors)
    {
        if (string.IsNullOrWhiteSpace(cursor))
        {
            return 0;
        }

        try
        {
            var json = Encoding.UTF8.GetString(Convert.FromBase64String(cursor));
            var dto = JsonSerializer.Deserialize<OffsetCursor>(json, JsonOpts);
            if (dto is null || dto.Offset < 0)
            {
                CatalogValidation.Add(errors, "cursor", CatalogValidation.Required);
                return 0;
            }

            return dto.Offset;
        }
        catch
        {
            CatalogValidation.Add(errors, "cursor", CatalogValidation.Required);
            return 0;
        }
    }

    private static string EncodeOffset(int offset) =>
        Convert.ToBase64String(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new OffsetCursor(offset), JsonOpts)));

    private sealed record OffsetCursor(int Offset);
}
