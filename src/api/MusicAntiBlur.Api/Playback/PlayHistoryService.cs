using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.RateLimiting;

namespace MusicAntiBlur.Api.Playback;

public sealed record RecordPlayRequest(Guid? TrackId);

public sealed record PlayHistoryItemDto(
    Guid Id,
    Guid TrackId,
    string Title,
    Guid ArtistId,
    string ArtistName,
    Guid AlbumId,
    string AlbumTitle,
    string? CoverUrl,
    DateTimeOffset? CoverUrlExpiresAt,
    DateTimeOffset PlayedAt,
    int PlayCount);

public sealed class PlayHistoryService(
    AppDbContext db,
    RedisRateLimiter limiter,
    CatalogService catalog)
{
    private static readonly TimeSpan DedupeWindow = TimeSpan.FromSeconds(30);

    public async Task RecordAsync(Guid userId, RecordPlayRequest req, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:plays:{userId:D}", 60, TimeSpan.FromMinutes(1), ct);
        var errors = CatalogValidation.NewErrors();
        var trackId = CatalogValidation.AddRequiredId(errors, "trackId", req.TrackId);
        CatalogValidation.ThrowIfAny(errors);
        if (!await db.Tracks.AsNoTracking().AnyAsync(t => t.Id == trackId, ct))
        {
            throw new ApiException(404, "not_found", "Not found.");
        }

        var now = DateTimeOffset.UtcNow;
        var last = await db.UserPlayHistories.AsNoTracking()
            .Where(h => h.UserId == userId)
            .OrderByDescending(h => h.PlayedAt)
            .ThenByDescending(h => h.Id)
            .Select(h => new { h.TrackId, h.PlayedAt })
            .FirstOrDefaultAsync(ct);
        if (last is not null && last.TrackId == trackId && now - last.PlayedAt < DedupeWindow)
        {
            return;
        }

        var stat = await db.UserTrackStats.FirstOrDefaultAsync(s => s.UserId == userId && s.TrackId == trackId, ct);
        if (stat is null)
        {
            db.UserTrackStats.Add(new UserTrackStat
            {
                UserId = userId,
                TrackId = trackId,
                PlayCount = 1,
                LastPlayedAt = now
            });
        }
        else
        {
            stat.PlayCount += 1;
            stat.LastPlayedAt = now;
        }

        db.UserPlayHistories.Add(new UserPlayHistory
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            TrackId = trackId,
            PlayedAt = now
        });
        await db.SaveChangesAsync(ct);
    }

    public async Task<PageDto<PlayHistoryItemDto>> ListAsync(Guid userId, string? cursor, int? limit, CancellationToken ct)
    {
        var errors = CatalogValidation.NewErrors();
        var take = CatalogValidation.ParseLimit(limit, errors);
        DateTimeOffset? afterAt = null;
        Guid? afterId = null;
        if (!string.IsNullOrWhiteSpace(cursor))
        {
            try
            {
                var padded = cursor.Replace('-', '+').Replace('_', '/');
                padded = padded.PadRight(padded.Length + (4 - padded.Length % 4) % 4, '=');
                var json = System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(padded));
                using var doc = System.Text.Json.JsonDocument.Parse(json);
                afterAt = doc.RootElement.GetProperty("at").GetDateTimeOffset();
                afterId = doc.RootElement.GetProperty("id").GetGuid();
            }
            catch
            {
                CatalogValidation.Add(errors, "cursor", CatalogValidation.Required);
            }
        }

        CatalogValidation.ThrowIfAny(errors);

        var query = db.UserPlayHistories.AsNoTracking().Where(h => h.UserId == userId);
        if (afterAt is { } at && afterId is { } id)
        {
            query = query.Where(h =>
                h.PlayedAt < at ||
                (h.PlayedAt == at && h.Id.CompareTo(id) < 0));
        }

        var rows = await query
            .OrderByDescending(h => h.PlayedAt)
            .ThenByDescending(h => h.Id)
            .Take(take + 1)
            .Select(h => new
            {
                h.Id,
                h.TrackId,
                h.PlayedAt,
                h.Track.Title,
                ArtistId = h.Track.Artist.Id,
                ArtistName = h.Track.Artist.Name,
                AlbumId = h.Track.Album.Id,
                AlbumTitle = h.Track.Album.Title,
                CoverObjectKey = h.Track.Album.CoverObjectKey
            })
            .ToListAsync(ct);

        var counts = await db.UserTrackStats.AsNoTracking()
            .Where(s => s.UserId == userId && rows.Select(r => r.TrackId).Contains(s.TrackId))
            .ToDictionaryAsync(s => s.TrackId, s => s.PlayCount, ct);

        var page = rows.Take(take).Select(r =>
        {
            var cover = catalog.SignCover(r.CoverObjectKey);
            return new PlayHistoryItemDto(
                r.Id,
                r.TrackId,
                r.Title,
                r.ArtistId,
                r.ArtistName,
                r.AlbumId,
                r.AlbumTitle,
                cover.Url,
                cover.ExpiresAt,
                r.PlayedAt,
                counts.GetValueOrDefault(r.TrackId));
        }).ToList();

        string? next = null;
        if (rows.Count > take)
        {
            var last = rows[take - 1];
            var payload = System.Text.Json.JsonSerializer.Serialize(new { at = last.PlayedAt, id = last.Id });
            next = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(payload))
                .TrimEnd('=').Replace('+', '-').Replace('/', '_');
        }

        return new PageDto<PlayHistoryItemDto>(page, next);
    }
}
