using Hangfire;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Jobs;
using MusicAntiBlur.Api.Overrides;
using MusicAntiBlur.Api.RateLimiting;
using MusicAntiBlur.Api.Storage;

namespace MusicAntiBlur.Api.Uploads;

public sealed class PrivateUploadService(
    AppDbContext db,
    ObjectStorageClient storage,
    IBackgroundJobClient jobs,
    RedisRateLimiter limiter,
    IdempotencyStore idempotency,
    OverrideService overrides,
    IOptions<StorageOptions> storageOptions,
    IHostEnvironment env,
    ILogger<PrivateUploadService> logger)
{
    public const long MaxSourceBytes = 104_857_600;

    public async Task<InitiateUploadResponse> InitiateAsync(
        Guid userId, Guid trackId, InitiateUploadRequest req, string? idempotencyKey, CancellationToken ct)
    {
        await HitImportAsync(userId, ct);
        storage.EnsureConfigured();
        var key = UploadValidation.RequireIdempotencyKey(idempotencyKey);
        if (req.SizeBytes is long tooBig && tooBig > MaxSourceBytes)
        {
            throw new ApiException(400, "validation_failed", "Validation failed.",
                new Dictionary<string, string[]> { ["sizeBytes"] = ["too_large"] });
        }

        var (size, _, checksum, _) = UploadValidation.ValidateInitiate(req, MaxSourceBytes);
        var hash = IdempotencyStore.HashRequest($"{userId:D}:{trackId:D}:{size}:{checksum}");
        var route = $"POST /api/v1/tracks/{trackId:D}/private-uploads";
        return await idempotency.ExecuteAsync(userId, route, key, hash, StatusCodes.Status201Created, async () =>
        {
            await LockUserAsync(userId, ct);
            await overrides.EnsureRowAsync(userId, trackId, ct);

            var used = await db.UserPrivateUploads
                .Where(u => u.UserId == userId && u.Status != "cancelled" && u.Status != "deleting")
                .SumAsync(u => u.SizeBytes ?? 0, ct);
            var quota = storageOptions.Value.PrivateQuotaBytes <= 0
                ? 2L * 1024 * 1024 * 1024
                : storageOptions.Value.PrivateQuotaBytes;
            if (used + size > quota)
            {
                throw new ApiException(400, "validation_failed", "Validation failed.",
                    new Dictionary<string, string[]> { ["sizeBytes"] = ["too_large"] });
            }

            var generationId = Guid.NewGuid();
            var objectKey = ObjectKeys.PrivateSource(userId, trackId, generationId);
            if (objectKey.StartsWith("tracks/", StringComparison.Ordinal))
            {
                throw new InvalidOperationException("Private object key must not use catalog prefix.");
            }

            var uploadId = await storage.InitiateMultipartAsync(objectKey, ct);
            var now = DateTimeOffset.UtcNow;
            db.UserPrivateUploads.Add(new UserPrivateUpload
            {
                GenerationId = generationId,
                UserId = userId,
                TrackId = trackId,
                Status = "initiated",
                IsActive = false,
                MultipartUploadId = uploadId,
                SourceBucketKey = objectKey,
                ExpectedChecksumSha256 = checksum,
                SizeBytes = size,
                CreatedAt = now,
                UpdatedAt = now
            });
            await db.SaveChangesAsync(ct);
            var (partSize, partCount) = UploadValidation.SplitParts(size);
            logger.LogInformation("Private upload initiated track {TrackId} generation {GenerationId}.", trackId, generationId);
            return new InitiateUploadResponse(generationId, partSize, partCount, now.AddHours(24));
        }, ct);
    }

    public async Task<UploadPartsResponse> PartsAsync(
        Guid userId, Guid trackId, Guid generationId, UploadPartsRequest req, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:part-url:{userId:D}", 120, TimeSpan.FromMinutes(1), ct);
        storage.EnsureConfigured();
        var upload = await RequireUpload(userId, trackId, generationId, ct);
        if (upload.MultipartUploadId is null || upload.Status is "ready" or "cancelled" or "deleting" or "failed")
        {
            throw new ApiException(409, "invalid_state", "Upload cannot accept parts.");
        }

        var numbers = req.PartNumbers ?? [];
        if (numbers.Length == 0)
        {
            throw new ApiException(400, "validation_failed", "Validation failed.",
                new Dictionary<string, string[]> { ["partNumbers"] = ["required"] });
        }

        var (_, partCount) = UploadValidation.SplitParts(upload.SizeBytes ?? 0);
        if (numbers.Any(n => n < 1 || n > partCount))
        {
            throw new ApiException(400, "validation_failed", "Validation failed.",
                new Dictionary<string, string[]> { ["partNumbers"] = ["required"] });
        }

        if (upload.Status == "initiated")
        {
            upload.Status = "uploading";
            upload.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
        }

        var ttl = TimeSpan.FromMinutes(15);
        var expires = DateTimeOffset.UtcNow.Add(ttl);
        var parts = numbers.Distinct().OrderBy(n => n)
            .Select(n => new UploadPartUrlDto(n, storage.PresignUploadPart(upload.SourceBucketKey, upload.MultipartUploadId, n, ttl), expires))
            .ToList();
        return new UploadPartsResponse(parts);
    }

    public async Task<UploadAcceptedResponse> CompleteAsync(
        Guid userId, Guid trackId, Guid generationId, CompleteUploadRequest req, string? idempotencyKey, CancellationToken ct)
    {
        await HitImportAsync(userId, ct);
        storage.EnsureConfigured();
        var key = UploadValidation.RequireIdempotencyKey(idempotencyKey);
        var parts = req.Parts ?? [];
        var hash = IdempotencyStore.HashRequest($"{userId:D}:{trackId:D}:{generationId:D}:" +
            string.Join(',', parts.OrderBy(p => p.PartNumber).Select(p => $"{p.PartNumber}:{p.ETag}")));
        var route = $"POST /api/v1/tracks/{trackId:D}/private-uploads/{generationId:D}/complete";
        return await idempotency.ExecuteAsync(userId, route, key, hash, StatusCodes.Status202Accepted, async () =>
        {
            var upload = await RequireUpload(userId, trackId, generationId, ct);
            if (upload.Status is "uploaded" or "validating" or "processing" or "ready")
            {
                return new UploadAcceptedResponse(upload.GenerationId, upload.Status);
            }

            if (upload.MultipartUploadId is null || upload.Status is "cancelled" or "deleting" or "failed")
            {
                throw new ApiException(409, "invalid_state", "Upload cannot be completed.");
            }

            if (parts.Count == 0 || parts.Any(p => p.PartNumber < 1 || string.IsNullOrWhiteSpace(p.ETag)))
            {
                throw new ApiException(400, "validation_failed", "Validation failed.",
                    new Dictionary<string, string[]> { ["parts"] = ["required"] });
            }

            try
            {
                await storage.CompleteMultipartAsync(
                    upload.SourceBucketKey,
                    upload.MultipartUploadId,
                    parts.Select(p => (p.PartNumber, p.ETag!)).ToList(),
                    ct);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "S3 complete failed for private generation {GenerationId}.", generationId);
                throw new ApiException(409, "invalid_state", "Multipart complete failed.");
            }

            var head = await storage.HeadObjectAsync(upload.SourceBucketKey, ct);
            if (head is null || (upload.SizeBytes is long expected && head.ContentLength != expected))
            {
                ObjectDeletionQueue.Enqueue(db, upload.SourceBucketKey, userId);
                upload.Status = "failed";
                upload.MultipartUploadId = null;
                upload.UpdatedAt = DateTimeOffset.UtcNow;
                await db.SaveChangesAsync(ct);
                throw new ApiException(422, "checksum_mismatch", "Uploaded object size does not match.");
            }

            upload.Status = "uploaded";
            upload.MultipartUploadId = null;
            upload.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync(ct);
            jobs.Enqueue<TranscodePrivateJob>(j => j.Run(userId, trackId, generationId));
            logger.LogInformation("Private upload completed track {TrackId} generation {GenerationId}.", trackId, generationId);
            return new UploadAcceptedResponse(generationId, "uploaded");
        }, ct);
    }

    public async Task<UploadStatusResponse> GetAsync(Guid userId, Guid trackId, Guid generationId, CancellationToken ct)
    {
        var upload = await RequireUpload(userId, trackId, generationId, ct);
        var failed = await db.UserPrivateRenditions.AsNoTracking()
            .Where(r => r.GenerationId == generationId && r.Status == "failed" && r.ErrorMessage != null)
            .Select(r => r.ErrorMessage)
            .FirstOrDefaultAsync(ct);
        var error = upload.Status == "failed" ? failed ?? "failed" : null;
        return new UploadStatusResponse(upload.GenerationId, upload.Status, upload.IsActive, upload.SizeBytes, upload.DurationMs, error);
    }

    public async Task AbortAsync(Guid userId, Guid trackId, Guid generationId, CancellationToken ct)
    {
        var upload = await RequireUpload(userId, trackId, generationId, ct);
        if (upload.IsActive || upload.Status == "ready")
        {
            throw new ApiException(409, "invalid_state", "Active generation cannot be aborted.");
        }

        if (upload.MultipartUploadId is not null)
        {
            await storage.AbortMultipartAsync(upload.SourceBucketKey, upload.MultipartUploadId, ct);
        }

        ObjectDeletionQueue.Enqueue(db, upload.SourceBucketKey, userId);
        foreach (var rendition in await db.UserPrivateRenditions.Where(r => r.GenerationId == generationId && r.BucketKey != null).ToListAsync(ct))
        {
            ObjectDeletionQueue.Enqueue(db, rendition.BucketKey!, userId);
        }

        upload.Status = "cancelled";
        upload.MultipartUploadId = null;
        upload.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
    }

    public async Task<UploadAcceptedResponse> RetryTranscodeAsync(Guid userId, Guid trackId, Guid generationId, CancellationToken ct)
    {
        var upload = await RequireUpload(userId, trackId, generationId, ct);
        if (upload.Status is "validating" or "processing" or "ready")
        {
            return new UploadAcceptedResponse(upload.GenerationId, upload.Status);
        }

        if (upload.Status is "cancelled" or "deleting" or "initiated" or "uploading")
        {
            throw new ApiException(409, "invalid_state", "Generation is not ready to transcode.");
        }

        upload.Status = "uploaded";
        upload.LeaseExpiresAt = null;
        upload.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
        jobs.Enqueue<TranscodePrivateJob>(j => j.Run(userId, trackId, upload.GenerationId));
        return new UploadAcceptedResponse(upload.GenerationId, "uploaded");
    }

    private async Task<UserPrivateUpload> RequireUpload(Guid userId, Guid trackId, Guid generationId, CancellationToken ct)
    {
        var upload = await db.UserPrivateUploads
            .FirstOrDefaultAsync(u => u.UserId == userId && u.TrackId == trackId && u.GenerationId == generationId, ct);
        if (upload is null)
        {
            throw new ApiException(404, "not_found", "Not found.");
        }

        return upload;
    }

    private Task HitImportAsync(Guid userId, CancellationToken ct)
    {
        if (env.IsDevelopment())
        {
            return Task.CompletedTask;
        }

        return limiter.HitAsync($"rl:private-import:{userId:D}", 10, TimeSpan.FromHours(1), ct);
    }

    private async Task LockUserAsync(Guid userId, CancellationToken ct)
    {
        var bytes = userId.ToByteArray();
        var k1 = BitConverter.ToInt32(bytes, 0);
        var k2 = BitConverter.ToInt32(bytes, 4);
        await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock({k1}, {k2})", ct);
    }
}
