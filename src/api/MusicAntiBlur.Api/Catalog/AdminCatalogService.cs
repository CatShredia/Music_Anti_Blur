using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Uploads;

namespace MusicAntiBlur.Api.Catalog;

public sealed class AdminCatalogService(AppDbContext db, CatalogService catalog, IOptions<CatalogOptions> options)
{
    private static readonly string[] InProgress = ["initiated", "uploading", "uploaded", "validating", "processing"];

    public async Task<IReadOnlyList<AdminTrackRowDto>> ListAlbumTracksAsync(Guid albumId, CancellationToken ct)
    {
        if (!await db.Albums.AsNoTracking().AnyAsync(a => a.Id == albumId, ct))
        {
            throw NotFound();
        }

        var tracks = await db.Tracks.AsNoTracking()
            .Where(t => t.AlbumId == albumId)
            .OrderBy(t => t.TrackNumber)
            .ThenBy(t => t.Id)
            .Select(t => new { t.Id, t.Title, t.TrackNumber, t.DurationMs, t.Isrc })
            .ToListAsync(ct);
        var ids = tracks.Select(t => t.Id).ToList();

        var uploads = await db.CatalogUploads.AsNoTracking()
            .Where(u => ids.Contains(u.TrackId) && u.Status != "cancelled" && u.Status != "deleting")
            .Select(u => new { u.TrackId, u.GenerationId, u.Status, u.CreatedAt })
            .ToListAsync(ct);
        var latest = uploads
            .GroupBy(u => u.TrackId)
            .ToDictionary(g => g.Key, g => g.OrderByDescending(u => u.CreatedAt).First());
        var generations = latest.Values.Select(u => u.GenerationId).ToList();
        var renditions = await db.TrackRenditions.AsNoTracking()
            .Where(r => generations.Contains(r.GenerationId))
            .Select(r => new { r.GenerationId, r.Status })
            .ToListAsync(ct);
        var byGeneration = renditions.GroupBy(r => r.GenerationId)
            .ToDictionary(g => g.Key, g => g.Select(r => r.Status).ToList());

        return tracks.Select(t =>
        {
            if (!latest.TryGetValue(t.Id, out var upload))
            {
                return new AdminTrackRowDto(t.Id, t.Title, t.TrackNumber, t.DurationMs, t.Isrc, "none", 0, 0);
            }

            var statuses = byGeneration.GetValueOrDefault(upload.GenerationId) ?? [];
            return new AdminTrackRowDto(
                t.Id, t.Title, t.TrackNumber, t.DurationMs, t.Isrc,
                Summarize(upload.Status, statuses),
                statuses.Count(s => s == "ready"),
                statuses.Count);
        }).ToList();
    }

    /// <summary>none | processing | ready | failed — по последней не отменённой загрузке.</summary>
    public static string Summarize(string uploadStatus, IReadOnlyCollection<string> renditionStatuses)
    {
        if (uploadStatus == "failed" || renditionStatuses.Contains("failed"))
        {
            return "failed";
        }

        if (InProgress.Contains(uploadStatus) || renditionStatuses.Any(s => s is "pending" or "processing"))
        {
            return "processing";
        }

        return uploadStatus == "ready" ? "ready" : "processing";
    }

    public async Task DeleteTrackAsync(Guid id, CancellationToken ct)
    {
        var track = await db.Tracks.FirstOrDefaultAsync(t => t.Id == id, ct) ?? throw NotFound();
        var now = DateTimeOffset.UtcNow;
        track.DeletedAt = now;
        track.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
    }

    public async Task<TrackDetailDto> RestoreTrackAsync(Guid id, CancellationToken ct)
    {
        var track = await db.Tracks.IgnoreQueryFilters()
            .FirstOrDefaultAsync(t => t.Id == id && t.DeletedAt != null, ct) ?? throw NotFound();

        var errors = CatalogValidation.NewErrors();
        if (await db.Tracks.AnyAsync(t => t.AlbumId == track.AlbumId && t.TrackNumber == track.TrackNumber, ct))
        {
            CatalogValidation.Add(errors, "trackNumber", "taken");
        }

        if (track.Isrc is not null && await db.Tracks.AnyAsync(t => t.Isrc == track.Isrc, ct))
        {
            CatalogValidation.Add(errors, "isrc", "taken");
        }

        if (errors.Count > 0)
        {
            throw new ApiException(409, "restore_conflict", "Track number or ISRC is already used.", errors);
        }

        track.DeletedAt = null;
        track.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
        return await catalog.GetTrackAsync(id, Guid.Empty, ct);
    }

    public async Task<IReadOnlyList<DeletedTrackDto>> ListDeletedTracksAsync(CancellationToken ct)
    {
        var retention = TimeSpan.FromDays(Math.Max(1, options.Value.DeletedRetentionDays));
        var rows = await db.Tracks.IgnoreQueryFilters().AsNoTracking()
            .Where(t => t.DeletedAt != null)
            .OrderByDescending(t => t.DeletedAt)
            .Take(200)
            .Select(t => new
            {
                t.Id,
                t.Title,
                t.TrackNumber,
                ArtistId = t.Artist.Id,
                ArtistName = t.Artist.Name,
                AlbumId = t.Album.Id,
                AlbumTitle = t.Album.Title,
                DeletedAt = t.DeletedAt!.Value
            })
            .ToListAsync(ct);
        return rows.Select(r => new DeletedTrackDto(
            r.Id, r.Title, r.TrackNumber,
            new ArtistRefDto(r.ArtistId, r.ArtistName),
            new AlbumRefDto(r.AlbumId, r.AlbumTitle),
            r.DeletedAt, r.DeletedAt + retention)).ToList();
    }

    public async Task DeleteAlbumAsync(Guid id, CancellationToken ct)
    {
        var album = await db.Albums.FirstOrDefaultAsync(a => a.Id == id, ct) ?? throw NotFound();
        if (await db.Tracks.IgnoreQueryFilters().AnyAsync(t => t.AlbumId == id, ct))
        {
            throw HasDependents("Album still has tracks (including deleted ones kept for restore).");
        }

        if (!string.IsNullOrWhiteSpace(album.CoverObjectKey))
        {
            ObjectDeletionQueue.Enqueue(db, album.CoverObjectKey, null);
        }

        db.Albums.Remove(album);
        await db.SaveChangesAsync(ct);
    }

    public async Task DeleteArtistAsync(Guid id, CancellationToken ct)
    {
        var artist = await db.Artists.FirstOrDefaultAsync(a => a.Id == id, ct) ?? throw NotFound();
        if (await db.Albums.AnyAsync(a => a.ArtistId == id, ct) ||
            await db.Tracks.IgnoreQueryFilters().AnyAsync(t => t.ArtistId == id, ct))
        {
            throw HasDependents("Artist still has albums or tracks.");
        }

        db.Artists.Remove(artist);
        await db.SaveChangesAsync(ct);
    }

    private static ApiException HasDependents(string message) => new(409, "has_dependents", message);

    private static ApiException NotFound() => new(404, "not_found", "Not found.");
}
