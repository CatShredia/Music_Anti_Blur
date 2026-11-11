using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Observability;
using MusicAntiBlur.Api.Storage;
using MusicAntiBlur.Api.Uploads;

namespace MusicAntiBlur.Api.Jobs;

public sealed class StorageCleanupJobs(
    AppDbContext db,
    ObjectStorageClient storage,
    IOptions<CatalogOptions> catalogOptions,
    ILogger<StorageCleanupJobs> logger)
{
    /// <summary>Физически удаляет треки из корзины старше срока хранения; файлы уходят в очередь удаления S3.</summary>
    public async Task PurgeDeletedTracks()
    {
        var ct = CancellationToken.None;
        var cutoff = DateTimeOffset.UtcNow.AddDays(-Math.Max(1, catalogOptions.Value.DeletedRetentionDays));
        var tracks = await db.Tracks.IgnoreQueryFilters()
            .Where(t => t.DeletedAt != null && t.DeletedAt < cutoff)
            .Include(t => t.Uploads).ThenInclude(u => u.Renditions)
            .OrderBy(t => t.DeletedAt)
            .Take(100)
            .ToListAsync(ct);

        foreach (var track in tracks)
        {
            foreach (var upload in track.Uploads)
            {
                ObjectDeletionQueue.Enqueue(db, upload.SourceBucketKey, null);
                foreach (var rendition in upload.Renditions.Where(r => r.BucketKey != null))
                {
                    ObjectDeletionQueue.Enqueue(db, rendition.BucketKey!, null);
                }
            }

            db.Tracks.Remove(track);
            await db.SaveChangesAsync(ct);
        }

        if (tracks.Count > 0)
        {
            AppMetrics.TracksPurgedAdd(tracks.Count);
            logger.LogInformation("Purged {Count} deleted tracks older than retention.", tracks.Count);
        }

        // Скрытые альбомы и исполнители стираются, когда в них не осталось треков.
        var albums = await db.Albums.IgnoreQueryFilters()
            .Where(a => a.DeletedAt != null && a.DeletedAt < cutoff &&
                        !db.Tracks.IgnoreQueryFilters().Any(t => t.AlbumId == a.Id))
            .Take(100).ToListAsync(ct);
        foreach (var album in albums)
        {
            if (!string.IsNullOrWhiteSpace(album.CoverObjectKey))
            {
                ObjectDeletionQueue.Enqueue(db, album.CoverObjectKey, null);
            }

            db.Albums.Remove(album);
        }

        await db.SaveChangesAsync(ct);

        var artists = await db.Artists.IgnoreQueryFilters()
            .Where(a => a.DeletedAt != null && a.DeletedAt < cutoff &&
                        !db.Albums.IgnoreQueryFilters().Any(al => al.ArtistId == a.Id) &&
                        !db.Tracks.IgnoreQueryFilters().Any(t => t.ArtistId == a.Id))
            .Take(100).ToListAsync(ct);
        db.Artists.RemoveRange(artists);
        await db.SaveChangesAsync(ct);
    }

    public async Task Sweep()
    {
        var ct = CancellationToken.None;
        var now = DateTimeOffset.UtcNow;
        await ReclaimStaleAsync(now, ct);
        await ReclaimStalePrivateAsync(now, ct);
        await AbortOldMultipartAsync(now, ct);
        await AbortOldPrivateMultipartAsync(now, ct);
        await DrainOutboxAsync(now, ct);
        await db.IdempotencyRecords.Where(r => r.ExpiresAt < now).ExecuteDeleteAsync(ct);
        await db.ObjectDeletions.Where(o => o.Status == "done" && o.CompletedAt != null && o.CompletedAt < now.AddDays(-30))
            .ExecuteDeleteAsync(ct);
    }

    private async Task ReclaimStaleAsync(DateTimeOffset now, CancellationToken ct)
    {
        var stale = await db.CatalogUploads
            .Where(u => (u.Status == "validating" || u.Status == "processing") &&
                        u.LeaseExpiresAt != null && u.LeaseExpiresAt < now)
            .ToListAsync(ct);
        foreach (var upload in stale)
        {
            upload.Status = "failed";
            upload.LeaseExpiresAt = null;
            upload.UpdatedAt = now;
            logger.LogWarning("Stale transcode lease generation {GenerationId}.", upload.GenerationId);
        }

        if (stale.Count > 0)
        {
            await db.SaveChangesAsync(ct);
        }
    }

    private async Task ReclaimStalePrivateAsync(DateTimeOffset now, CancellationToken ct)
    {
        var stale = await db.UserPrivateUploads
            .Where(u => (u.Status == "validating" || u.Status == "processing") &&
                        u.LeaseExpiresAt != null && u.LeaseExpiresAt < now)
            .ToListAsync(ct);
        foreach (var upload in stale)
        {
            upload.Status = "failed";
            upload.LeaseExpiresAt = null;
            upload.UpdatedAt = now;
            logger.LogWarning("Stale private transcode lease generation {GenerationId}.", upload.GenerationId);
        }

        if (stale.Count > 0)
        {
            await db.SaveChangesAsync(ct);
        }
    }

    private async Task AbortOldMultipartAsync(DateTimeOffset now, CancellationToken ct)
    {
        var cutoff = now.AddHours(-24);
        var stale = await db.CatalogUploads
            .Where(u => (u.Status == "initiated" || u.Status == "uploading") && u.CreatedAt < cutoff)
            .ToListAsync(ct);
        foreach (var upload in stale)
        {
            if (upload.MultipartUploadId is not null)
            {
                try
                {
                    await storage.AbortMultipartAsync(upload.SourceBucketKey, upload.MultipartUploadId, ct);
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "Abort multipart failed generation {GenerationId}.", upload.GenerationId);
                }
            }

            ObjectDeletionQueue.Enqueue(db, upload.SourceBucketKey, null);
            upload.Status = "cancelled";
            upload.MultipartUploadId = null;
            upload.UpdatedAt = now;
        }

        if (stale.Count > 0)
        {
            await db.SaveChangesAsync(ct);
        }
    }

    private async Task AbortOldPrivateMultipartAsync(DateTimeOffset now, CancellationToken ct)
    {
        var cutoff = now.AddHours(-24);
        var stale = await db.UserPrivateUploads
            .Where(u => (u.Status == "initiated" || u.Status == "uploading") && u.CreatedAt < cutoff)
            .ToListAsync(ct);
        foreach (var upload in stale)
        {
            if (upload.MultipartUploadId is not null)
            {
                try
                {
                    await storage.AbortMultipartAsync(upload.SourceBucketKey, upload.MultipartUploadId, ct);
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "Abort private multipart failed generation {GenerationId}.", upload.GenerationId);
                }
            }

            ObjectDeletionQueue.Enqueue(db, upload.SourceBucketKey, upload.UserId);
            upload.Status = "cancelled";
            upload.MultipartUploadId = null;
            upload.UpdatedAt = now;
        }

        if (stale.Count > 0)
        {
            await db.SaveChangesAsync(ct);
        }
    }

    private async Task DrainOutboxAsync(DateTimeOffset now, CancellationToken ct)
    {
        if (!storage.IsConfigured)
        {
            return;
        }

        var due = await db.ObjectDeletions
            .Where(o => o.Status != "done" && o.Status != "failed" && o.NextAttemptAt <= now &&
                        (o.LeaseExpiresAt == null || o.LeaseExpiresAt < now))
            .OrderBy(o => o.NextAttemptAt)
            .Take(50)
            .ToListAsync(ct);

        foreach (var row in due)
        {
            row.Status = "processing";
            row.LeaseExpiresAt = now.AddMinutes(5);
            row.AttemptCount++;
            await db.SaveChangesAsync(ct);
            try
            {
                await storage.DeleteObjectAsync(row.BucketKey, ct);
                row.Status = "done";
                row.CompletedAt = DateTimeOffset.UtcNow;
                row.LeaseExpiresAt = null;
                row.LastError = null;
            }
            catch (Exception ex)
            {
                row.Status = row.AttemptCount >= 10 ? "failed" : "pending";
                row.LastError = "storage_error";
                row.NextAttemptAt = DateTimeOffset.UtcNow.AddMinutes(Math.Min(60, Math.Pow(2, row.AttemptCount)));
                row.LeaseExpiresAt = null;
                logger.LogWarning(ex, "Outbox delete failed for key hash {KeyLength}.", row.BucketKey.Length);
            }

            await db.SaveChangesAsync(ct);
        }
    }
}
