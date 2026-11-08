using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;

namespace MusicAntiBlur.Api.Catalog;

public sealed record PopularRow(
    Guid TrackId,
    string Title,
    int TrackNumber,
    int? DurationMs,
    Guid ArtistId,
    string ArtistName,
    Guid AlbumId,
    string AlbumTitle,
    string? CoverObjectKey);

/// <summary>
/// Популярные треки по <c>user_track_stats</c>: порядок задают прослушивания всех пользователей,
/// при равенстве выше те, что чаще слушал текущий пользователь. Без прослушиваний список пуст.
/// </summary>
public sealed class PopularityService(AppDbContext db)
{
    public Task<IReadOnlyList<PopularRow>> ForArtistAsync(Guid artistId, Guid userId, int limit, CancellationToken ct) =>
        TopAsync(db.Tracks.AsNoTracking().Where(t => t.ArtistId == artistId), userId, limit, ct);

    /// <summary>Популярность произвольной выборки треков (жанр и т.п.).</summary>
    public Task<IReadOnlyList<PopularRow>> ForTracksAsync(IQueryable<Track> tracks, Guid? userId, int limit, CancellationToken ct) =>
        TopAsync(tracks, userId ?? Guid.Empty, limit, ct);

    private async Task<IReadOnlyList<PopularRow>> TopAsync(IQueryable<Track> tracks, Guid userId, int limit, CancellationToken ct)
    {
        var stats = db.UserTrackStats.AsNoTracking().Where(s => s.PlayCount > 0);

        // Мягко удалённые треки отсекает глобальный фильтр Track в выборке `tracks`.
        var rows = await (
                from t in tracks
                join s in stats on t.Id equals s.TrackId
                group s by new
                {
                    t.Id,
                    t.Title,
                    t.TrackNumber,
                    t.DurationMs,
                    ArtistId = t.Artist.Id,
                    ArtistName = t.Artist.Name,
                    AlbumId = t.Album.Id,
                    AlbumTitle = t.Album.Title,
                    t.Album.CoverObjectKey
                }
                into g
                orderby g.Sum(x => x.PlayCount) descending,
                    g.Sum(x => x.UserId == userId ? x.PlayCount : 0) descending,
                    g.Key.AlbumTitle, g.Key.TrackNumber, g.Key.Id
                select new
                {
                    g.Key.Id,
                    g.Key.Title,
                    g.Key.TrackNumber,
                    g.Key.DurationMs,
                    g.Key.ArtistId,
                    g.Key.ArtistName,
                    g.Key.AlbumId,
                    g.Key.AlbumTitle,
                    g.Key.CoverObjectKey
                })
            .Take(limit)
            .ToListAsync(ct);

        return rows.Select(r => new PopularRow(
            r.Id, r.Title, r.TrackNumber, r.DurationMs, r.ArtistId, r.ArtistName,
            r.AlbumId, r.AlbumTitle, r.CoverObjectKey)).ToList();
    }
}
