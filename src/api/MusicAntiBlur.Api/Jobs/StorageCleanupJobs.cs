using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Storage;

namespace MusicAntiBlur.Api.Jobs;

public sealed class StorageCleanupJobs(AppDbContext db, ObjectStorageClient storage, ILogger<StorageCleanupJobs> logger)
{
    public async Task Sweep()
    {
        var ct = CancellationToken.None;
        var now = DateTimeOffset.UtcNow;
        await ReclaimStaleAsync(now, ct);
        await AbortOldMultipartAsync(now, ct);
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

            if (!db.ObjectDeletions.Local.Any(o => o.BucketKey == upload.SourceBucketKey && o.Status != "done") &&
                !db.ObjectDeletions.Any(o => o.BucketKey == upload.SourceBucketKey && o.Status != "done"))
            {
                db.ObjectDeletions.Add(new ObjectDeletion
                {
                    Id = Guid.NewGuid(),
                    BucketKey = upload.SourceBucketKey,
                    Status = "pending",
                    NextAttemptAt = now,
                    CreatedAt = now
                });
            }
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
