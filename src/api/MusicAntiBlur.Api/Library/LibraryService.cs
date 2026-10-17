using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Library;

public sealed class LibraryService(AppDbContext db)
{
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public async Task<LikeStatusDto> GetLikeAsync(Guid userId, Guid trackId, CancellationToken ct)
    {
        await EnsureTrackExistsAsync(trackId, ct);
        var liked = await db.LikedTracks.AsNoTracking()
            .AnyAsync(x => x.UserId == userId && x.TrackId == trackId, ct);
        return new LikeStatusDto(liked);
    }

    public async Task<LikeStatusDto> LikeAsync(Guid userId, Guid trackId, CancellationToken ct)
    {
        await EnsureTrackExistsAsync(trackId, ct);
        var playlist = await EnsureLikedPlaylistAsync(userId, ct);

        var existing = await db.LikedTracks
            .FirstOrDefaultAsync(x => x.UserId == userId && x.TrackId == trackId, ct);
        if (existing is not null)
        {
            return new LikeStatusDto(true);
        }

        var now = DateTimeOffset.UtcNow;
        var maxPosition = await db.PlaylistTracks.AsNoTracking()
            .Where(x => x.PlaylistId == playlist.Id)
            .Select(x => (int?)x.Position)
            .MaxAsync(ct) ?? -1;

        db.LikedTracks.Add(new LikedTrack
        {
            UserId = userId,
            TrackId = trackId,
            LikedAt = now
        });
        db.PlaylistTracks.Add(new PlaylistTrack
        {
            PlaylistId = playlist.Id,
            TrackId = trackId,
            Position = maxPosition + 1,
            AddedAt = now
        });
        playlist.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
        return new LikeStatusDto(true);
    }

    public async Task UnlikeAsync(Guid userId, Guid trackId, CancellationToken ct)
    {
        await EnsureTrackExistsAsync(trackId, ct);
        var liked = await db.LikedTracks
            .FirstOrDefaultAsync(x => x.UserId == userId && x.TrackId == trackId, ct);
        if (liked is null)
        {
            return;
        }

        db.LikedTracks.Remove(liked);

        var playlist = await db.Playlists
            .FirstOrDefaultAsync(p => p.UserId == userId && p.Kind == Playlist.KindLiked, ct);
        if (playlist is not null)
        {
            var entry = await db.PlaylistTracks
                .FirstOrDefaultAsync(x => x.PlaylistId == playlist.Id && x.TrackId == trackId, ct);
            if (entry is not null)
            {
                db.PlaylistTracks.Remove(entry);
            }

            playlist.UpdatedAt = DateTimeOffset.UtcNow;
        }

        await db.SaveChangesAsync(ct);
    }

    public async Task<IReadOnlyList<PlaylistListItemDto>> ListPlaylistsAsync(Guid userId, CancellationToken ct)
    {
        await EnsureLikedPlaylistAsync(userId, ct);

        var rows = await db.Playlists.AsNoTracking()
            .Where(p => p.UserId == userId)
            .OrderBy(p => p.Kind == Playlist.KindLiked ? 0 : 1)
            .ThenBy(p => p.Title)
            .ThenBy(p => p.Id)
            .Select(p => new
            {
                p.Id,
                p.Title,
                p.Kind,
                p.UpdatedAt,
                TrackCount = p.Kind == Playlist.KindLiked
                    ? db.LikedTracks.Count(l => l.UserId == userId)
                    : p.Tracks.Count
            })
            .ToListAsync(ct);

        return rows
            .Select(p => new PlaylistListItemDto(p.Id, p.Title, p.Kind, p.TrackCount, p.UpdatedAt))
            .ToList();
    }

    public async Task<PlaylistDetailDto> GetLikedPlaylistAsync(Guid userId, string? cursor, int? limit, CancellationToken ct)
    {
        var playlist = await EnsureLikedPlaylistAsync(userId, ct);
        return await GetPlaylistDetailAsync(userId, playlist.Id, cursor, limit, ct);
    }

    public async Task<PlaylistDetailDto> GetPlaylistAsync(Guid userId, Guid playlistId, string? cursor, int? limit, CancellationToken ct)
    {
        return await GetPlaylistDetailAsync(userId, playlistId, cursor, limit, ct);
    }

    public static Playlist CreateLikedPlaylist(Guid userId, DateTimeOffset now) => new()
    {
        Id = Guid.NewGuid(),
        UserId = userId,
        Title = Playlist.LikedTitle,
        Kind = Playlist.KindLiked,
        CreatedAt = now,
        UpdatedAt = now
    };

    private async Task<PlaylistDetailDto> GetPlaylistDetailAsync(
        Guid userId, Guid playlistId, string? cursor, int? limit, CancellationToken ct)
    {
        var errors = CatalogValidation.NewErrors();
        var take = CatalogValidation.ParseLimit(limit, errors);
        var decoded = DecodeLikedCursor(cursor, errors);
        CatalogValidation.ThrowIfAny(errors);

        var playlist = await db.Playlists.AsNoTracking()
            .Where(p => p.Id == playlistId && p.UserId == userId)
            .Select(p => new { p.Id, p.Title, p.Kind, p.CreatedAt, p.UpdatedAt })
            .FirstOrDefaultAsync(ct);

        if (playlist is null)
        {
            throw NotFound();
        }

        if (playlist.Kind != Playlist.KindLiked)
        {
            throw NotFound();
        }

        var query = db.LikedTracks.AsNoTracking()
            .Where(l => l.UserId == userId);

        if (decoded is { } c)
        {
            query = query.Where(l =>
                l.LikedAt < c.LikedAt ||
                (l.LikedAt == c.LikedAt && l.TrackId.CompareTo(c.TrackId) < 0));
        }

        var rows = await query
            .OrderByDescending(l => l.LikedAt)
            .ThenByDescending(l => l.TrackId)
            .Take(take + 1)
            .Select(l => new
            {
                l.TrackId,
                l.LikedAt,
                l.Track.Title,
                l.Track.TrackNumber,
                l.Track.DurationMs,
                ArtistId = l.Track.Artist.Id,
                ArtistName = l.Track.Artist.Name,
                AlbumId = l.Track.Album.Id,
                AlbumTitle = l.Track.Album.Title
            })
            .ToListAsync(ct);

        var page = rows.Take(take).Select(r => new LikedPlaylistTrackDto(
            r.TrackId,
            r.Title,
            r.TrackNumber,
            r.DurationMs,
            r.ArtistId,
            r.ArtistName,
            r.AlbumId,
            r.AlbumTitle,
            r.LikedAt)).ToList();

        string? next = null;
        if (rows.Count > take)
        {
            var last = page[^1];
            next = EncodeLikedCursor(last.LikedAt, last.Id);
        }

        var trackCount = await db.LikedTracks.AsNoTracking().CountAsync(l => l.UserId == userId, ct);

        return new PlaylistDetailDto(
            playlist.Id,
            playlist.Title,
            playlist.Kind,
            trackCount,
            playlist.CreatedAt,
            playlist.UpdatedAt,
            page,
            next);
    }

    public async Task<Playlist> EnsureLikedPlaylistAsync(Guid userId, CancellationToken ct)
    {
        var existing = await db.Playlists
            .FirstOrDefaultAsync(p => p.UserId == userId && p.Kind == Playlist.KindLiked, ct);
        if (existing is not null)
        {
            return existing;
        }

        var now = DateTimeOffset.UtcNow;
        var playlist = CreateLikedPlaylist(userId, now);
        db.Playlists.Add(playlist);
        try
        {
            await db.SaveChangesAsync(ct);
            return playlist;
        }
        catch (DbUpdateException)
        {
            db.Entry(playlist).State = EntityState.Detached;
            return await db.Playlists
                .FirstAsync(p => p.UserId == userId && p.Kind == Playlist.KindLiked, ct);
        }
    }

    private async Task EnsureTrackExistsAsync(Guid trackId, CancellationToken ct)
    {
        if (!await db.Tracks.AsNoTracking().AnyAsync(t => t.Id == trackId, ct))
        {
            throw NotFound();
        }
    }

    private static ApiException NotFound() => new(404, "not_found", "Not found.");

    private static (DateTimeOffset LikedAt, Guid TrackId)? DecodeLikedCursor(string? cursor, Dictionary<string, string[]> errors)
    {
        if (string.IsNullOrWhiteSpace(cursor))
        {
            return null;
        }

        try
        {
            var json = Encoding.UTF8.GetString(Convert.FromBase64String(cursor));
            var dto = JsonSerializer.Deserialize<LikedCursorDto>(json, JsonOpts);
            if (dto is null || dto.TrackId == Guid.Empty)
            {
                CatalogValidation.Add(errors, "cursor", CatalogValidation.Required);
                return null;
            }

            return (dto.LikedAt, dto.TrackId);
        }
        catch
        {
            CatalogValidation.Add(errors, "cursor", CatalogValidation.Required);
            return null;
        }
    }

    private static string EncodeLikedCursor(DateTimeOffset likedAt, Guid trackId)
    {
        var json = JsonSerializer.Serialize(new LikedCursorDto(likedAt, trackId), JsonOpts);
        return Convert.ToBase64String(Encoding.UTF8.GetBytes(json));
    }

    private sealed record LikedCursorDto(DateTimeOffset LikedAt, Guid TrackId);
}
