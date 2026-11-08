using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Library;

/// <summary>Пользовательские плейлисты: CRUD, состав, порядок, просмотр публичных чужих.</summary>
public sealed class PlaylistService(
    AppDbContext db,
    LibraryService library,
    CatalogService catalog,
    IOptions<LibraryOptions> options)
{
    public const int DescriptionMax = 500;
    public const int CollageSize = 4;

    /// <summary>Сдвиг позиций при переупорядочивании: уникальный индекс (playlist, position) не даёт писать «поверх».</summary>
    private const int OrderShift = 1_000_000;

    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    // ---------- CRUD ----------

    public async Task<PlaylistListItemDto> CreateAsync(Guid userId, CreatePlaylistRequest req, CancellationToken ct)
    {
        var errors = CatalogValidation.NewErrors();
        var title = NormalizeTitle(req.Title, errors);
        var description = NormalizeDescription(req.Description, errors);
        CatalogValidation.ThrowIfAny(errors);

        var count = await db.Playlists.AsNoTracking()
            .CountAsync(p => p.UserId == userId && p.Kind == Playlist.KindUser, ct);
        if (count >= options.Value.MaxPlaylists)
        {
            throw LimitReached("playlists", options.Value.MaxPlaylists);
        }

        var now = DateTimeOffset.UtcNow;
        var playlist = new Playlist
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Title = title!,
            Description = description,
            IsPublic = req.IsPublic ?? false,
            Kind = Playlist.KindUser,
            CreatedAt = now,
            UpdatedAt = now
        };
        db.Playlists.Add(playlist);
        await db.SaveChangesAsync(ct);
        return new PlaylistListItemDto(playlist.Id, playlist.Title, playlist.Kind, 0, now, playlist.IsPublic);
    }

    public async Task<PlaylistListItemDto> UpdateAsync(Guid userId, Guid id, UpdatePlaylistRequest req, CancellationToken ct)
    {
        var playlist = await OwnUserPlaylistAsync(userId, id, ct);

        var errors = CatalogValidation.NewErrors();
        if (req.Title is not null)
        {
            var title = NormalizeTitle(req.Title, errors);
            if (title is not null)
            {
                playlist.Title = title;
            }
        }

        if (req.Description is not null)
        {
            // Пустая строка очищает описание.
            playlist.Description = NormalizeDescription(req.Description, errors);
        }

        CatalogValidation.ThrowIfAny(errors);

        if (req.IsPublic is { } isPublic)
        {
            playlist.IsPublic = isPublic;
        }

        playlist.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        var count = await CountVisibleAsync(playlist.Id, ct);
        return new PlaylistListItemDto(playlist.Id, playlist.Title, playlist.Kind, count, playlist.UpdatedAt, playlist.IsPublic);
    }

    public async Task DeleteAsync(Guid userId, Guid id, CancellationToken ct)
    {
        var playlist = await OwnUserPlaylistAsync(userId, id, ct);
        db.Playlists.Remove(playlist);
        await db.SaveChangesAsync(ct);
    }

    // ---------- Просмотр ----------

    /// <summary>Свой плейлист (в т.ч. liked) или чужой публичный. Остальное — 404 без утечки.</summary>
    public async Task<PlaylistDetailDto> GetAsync(Guid viewerId, Guid id, string? cursor, int? limit, CancellationToken ct)
    {
        var playlist = await db.Playlists.AsNoTracking()
            .Where(p => p.Id == id)
            .Select(p => new
            {
                p.Id,
                p.UserId,
                p.Title,
                p.Kind,
                p.Description,
                p.IsPublic,
                p.CreatedAt,
                p.UpdatedAt,
                Owner = p.User.Login ?? p.User.Email
            })
            .FirstOrDefaultAsync(ct);

        var isOwner = playlist?.UserId == viewerId;
        if (playlist is null || (!isOwner && !(playlist.IsPublic && playlist.Kind == Playlist.KindUser)))
        {
            throw NotFound();
        }

        if (playlist.Kind == Playlist.KindLiked)
        {
            var liked = await library.GetLikedPlaylistAsync(viewerId, cursor, limit, ct);
            var likedCovers = await CollageUrlsAsync(playlist.Id, ct);
            return liked with { IsOwner = true, CoverUrls = likedCovers };
        }

        var errors = CatalogValidation.NewErrors();
        var take = CatalogValidation.ParseLimit(limit, errors);
        var after = DecodePositionCursor(cursor, errors);
        CatalogValidation.ThrowIfAny(errors);

        var query = db.PlaylistTracks.AsNoTracking()
            .Where(x => x.PlaylistId == id && db.Tracks.Any(t => t.Id == x.TrackId));
        if (after is { } position)
        {
            query = query.Where(x => x.Position > position);
        }

        var rows = await query
            .OrderBy(x => x.Position)
            .Take(take + 1)
            .Select(x => new
            {
                x.Position,
                x.AddedAt,
                x.TrackId,
                x.Track.Title,
                x.Track.TrackNumber,
                x.Track.DurationMs,
                ArtistId = x.Track.Artist.Id,
                ArtistName = x.Track.Artist.Name,
                AlbumId = x.Track.Album.Id,
                AlbumTitle = x.Track.Album.Title
            })
            .ToListAsync(ct);

        var page = rows.Take(take).ToList();
        var tracks = page.Select(r => new PlaylistTrackDto(
            r.TrackId, r.Title, r.TrackNumber, r.DurationMs,
            r.ArtistId, r.ArtistName, r.AlbumId, r.AlbumTitle, r.AddedAt)).ToList();
        string? next = rows.Count > take ? EncodePositionCursor(page[^1].Position) : null;

        var inLibrary = !isOwner && await db.SavedPlaylists.AsNoTracking()
            .AnyAsync(s => s.UserId == viewerId && s.PlaylistId == id, ct);

        return new PlaylistDetailDto(
            playlist.Id,
            playlist.Title,
            playlist.Kind,
            await CountVisibleAsync(id, ct),
            playlist.CreatedAt,
            playlist.UpdatedAt,
            tracks,
            next,
            playlist.Description,
            playlist.IsPublic,
            isOwner,
            OwnerDisplayName(playlist.Owner),
            inLibrary,
            await CollageUrlsAsync(id, ct));
    }

    // ---------- Состав ----------

    public async Task<AddedTracksDto> AddTracksAsync(
        Guid userId, Guid id, AddPlaylistTracksRequest req, CancellationToken ct)
    {
        var playlist = await OwnUserPlaylistAsync(userId, id, ct);

        var errors = CatalogValidation.NewErrors();
        var requested = (req.TrackIds ?? []).Distinct().ToList();
        if (requested.Count == 0 || requested.Count > options.Value.MaxTracksPerPlaylist)
        {
            CatalogValidation.Add(errors, "trackIds", CatalogValidation.Required);
        }

        if (req.Position is < 0)
        {
            CatalogValidation.Add(errors, "position", CatalogValidation.Required);
        }

        CatalogValidation.ThrowIfAny(errors);

        var existingTracks = await db.Tracks.AsNoTracking()
            .Where(t => requested.Contains(t.Id))
            .Select(t => t.Id)
            .ToListAsync(ct);
        if (existingTracks.Count != requested.Count)
        {
            throw NotFound();
        }

        var current = await VisibleOrderAsync(id, ct);
        var toAdd = PlanAdd(current, requested, req.Position, options.Value.MaxTracksPerPlaylist);

        if (toAdd.Added.Count > 0)
        {
            var now = DateTimeOffset.UtcNow;
            var hiddenMax = await db.PlaylistTracks.AsNoTracking()
                .Where(x => x.PlaylistId == id)
                .Select(x => (int?)x.Position)
                .MaxAsync(ct) ?? -1;

            // Новые строки получают уникальные позиции в хвосте, затем порядок переписывается целиком.
            var next = hiddenMax + 1;
            foreach (var trackId in toAdd.Added)
            {
                db.PlaylistTracks.Add(new PlaylistTrack
                {
                    PlaylistId = id,
                    TrackId = trackId,
                    Position = next++,
                    AddedAt = now
                });
            }

            playlist.UpdatedAt = now;
            await db.SaveChangesAsync(ct);

            if (req.Position is not null)
            {
                await RewriteOrderAsync(id, toAdd.Order, ct);
            }
        }

        return new AddedTracksDto(toAdd.Added.Count, await CountVisibleAsync(id, ct));
    }

    public async Task RemoveTrackAsync(Guid userId, Guid id, Guid trackId, CancellationToken ct)
    {
        var playlist = await OwnUserPlaylistAsync(userId, id, ct);
        var entry = await db.PlaylistTracks
            .FirstOrDefaultAsync(x => x.PlaylistId == id && x.TrackId == trackId, ct);
        if (entry is null)
        {
            return;
        }

        db.PlaylistTracks.Remove(entry);
        playlist.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
    }

    public async Task ReorderAsync(Guid userId, Guid id, ReorderPlaylistRequest req, CancellationToken ct)
    {
        var playlist = await OwnUserPlaylistAsync(userId, id, ct);
        var requested = req.TrackIds ?? [];
        var current = await VisibleOrderAsync(id, ct);

        if (!SameSet(current, requested))
        {
            throw new ApiException(409, "order_mismatch", "Playlist content changed; reload and retry.");
        }

        await RewriteOrderAsync(id, requested, ct);
        playlist.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
    }

    // ---------- Чистая логика (покрыта тестами) ----------

    public sealed record AddPlan(IReadOnlyList<Guid> Added, IReadOnlyList<Guid> Order);

    /// <summary>Какие треки реально добавятся (без уже имеющихся) и итоговый порядок.</summary>
    public static AddPlan PlanAdd(IReadOnlyList<Guid> current, IReadOnlyList<Guid> requested, int? position, int maxTracks)
    {
        var have = current.ToHashSet();
        var added = requested.Where(t => !have.Contains(t)).Distinct().ToList();
        if (current.Count + added.Count > maxTracks)
        {
            throw LimitReached("tracks", maxTracks);
        }

        var order = current.ToList();
        var index = position is { } p ? Math.Min(p, order.Count) : order.Count;
        order.InsertRange(index, added);
        return new AddPlan(added, order);
    }

    public static bool SameSet(IReadOnlyList<Guid> current, IReadOnlyList<Guid> requested) =>
        current.Count == requested.Count
        && requested.Distinct().Count() == requested.Count
        && current.ToHashSet().SetEquals(requested);

    public static string? NormalizeTitle(string? raw, Dictionary<string, string[]> errors)
    {
        var title = raw?.Trim();
        if (string.IsNullOrEmpty(title))
        {
            CatalogValidation.Add(errors, "title", CatalogValidation.Required);
            return null;
        }

        if (title.Length > CatalogValidation.NameMax)
        {
            CatalogValidation.Add(errors, "title", CatalogValidation.TitleLength);
            return null;
        }

        return title;
    }

    public static string? NormalizeDescription(string? raw, Dictionary<string, string[]> errors)
    {
        var text = raw?.Trim();
        if (string.IsNullOrEmpty(text))
        {
            return null;
        }

        if (text.Length > DescriptionMax)
        {
            CatalogValidation.Add(errors, "description", CatalogValidation.TitleLength);
            return null;
        }

        return text;
    }

    public static string? OwnerDisplayName(string? loginOrEmail)
    {
        if (string.IsNullOrWhiteSpace(loginOrEmail))
        {
            return null;
        }

        var at = loginOrEmail.IndexOf('@');
        return at > 0 ? loginOrEmail[..at] : loginOrEmail;
    }

    // ---------- Внутреннее ----------

    private async Task<Playlist> OwnUserPlaylistAsync(Guid userId, Guid id, CancellationToken ct)
    {
        var playlist = await db.Playlists.FirstOrDefaultAsync(p => p.Id == id && p.UserId == userId, ct)
            ?? throw NotFound();
        if (playlist.Kind == Playlist.KindLiked)
        {
            throw new ApiException(409, "system_playlist", "The liked playlist cannot be changed this way.");
        }

        return playlist;
    }

    private Task<int> CountVisibleAsync(Guid playlistId, CancellationToken ct) =>
        db.PlaylistTracks.AsNoTracking()
            .CountAsync(x => x.PlaylistId == playlistId && db.Tracks.Any(t => t.Id == x.TrackId), ct);

    private Task<List<Guid>> VisibleOrderAsync(Guid playlistId, CancellationToken ct) =>
        db.PlaylistTracks.AsNoTracking()
            .Where(x => x.PlaylistId == playlistId && db.Tracks.Any(t => t.Id == x.TrackId))
            .OrderBy(x => x.Position)
            .Select(x => x.TrackId)
            .ToListAsync(ct);

    /// <summary>Записывает порядок видимых треков; строки скрытых (удалённых) треков уходят в хвост.</summary>
    private async Task RewriteOrderAsync(Guid playlistId, IReadOnlyList<Guid> ordered, CancellationToken ct)
    {
        await using var tx = await db.Database.BeginTransactionAsync(ct);

        await db.PlaylistTracks.Where(x => x.PlaylistId == playlistId)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.Position, x => x.Position + OrderShift), ct);

        var rows = await db.PlaylistTracks.Where(x => x.PlaylistId == playlistId).ToListAsync(ct);
        var index = ordered.Select((id, i) => (id, i)).ToDictionary(x => x.id, x => x.i);
        var tail = ordered.Count;
        foreach (var row in rows.OrderBy(r => r.Position))
        {
            row.Position = index.TryGetValue(row.TrackId, out var i) ? i : tail++;
        }

        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
    }

    private async Task<IReadOnlyList<string>> CollageUrlsAsync(Guid playlistId, CancellationToken ct)
    {
        var keys = await db.PlaylistTracks.AsNoTracking()
            .Where(x => x.PlaylistId == playlistId && db.Tracks.Any(t => t.Id == x.TrackId))
            .OrderBy(x => x.Position)
            .Select(x => x.Track.Album.CoverObjectKey)
            .Take(CollageSize * 4)
            .ToListAsync(ct);
        return CollageFromKeys(keys, catalog);
    }

    internal static IReadOnlyList<string> CollageFromKeys(IEnumerable<string?> keys, CatalogService catalog) =>
        keys.Where(k => !string.IsNullOrWhiteSpace(k))
            .Select(k => k!)
            .Distinct()
            .Take(CollageSize)
            .Select(k => catalog.SignCover(k).Url)
            .Where(u => u is not null)
            .Select(u => u!)
            .ToList();

    private static ApiException NotFound() => new(404, "not_found", "Not found.");

    private static ApiException LimitReached(string what, int max) =>
        new(409, "limit_reached", $"Limit reached: {what} (max {max}).");

    private static int? DecodePositionCursor(string? cursor, Dictionary<string, string[]> errors)
    {
        if (string.IsNullOrWhiteSpace(cursor))
        {
            return null;
        }

        try
        {
            var json = Encoding.UTF8.GetString(Convert.FromBase64String(cursor));
            var dto = JsonSerializer.Deserialize<PositionCursor>(json, JsonOpts);
            if (dto is null || dto.Position < 0)
            {
                CatalogValidation.Add(errors, "cursor", CatalogValidation.Required);
                return null;
            }

            return dto.Position;
        }
        catch
        {
            CatalogValidation.Add(errors, "cursor", CatalogValidation.Required);
            return null;
        }
    }

    private static string EncodePositionCursor(int position) =>
        Convert.ToBase64String(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new PositionCursor(position), JsonOpts)));

    private sealed record PositionCursor(int Position);
}
