using Hangfire;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Media;
using MusicAntiBlur.Api.Storage;
using MusicAntiBlur.Api.Uploads;

namespace MusicAntiBlur.Api.Jobs;

public sealed class TranscodePrivateJob(
    AppDbContext db,
    ObjectStorageClient storage,
    MediaProcessRunner runner,
    IOptions<MediaOptions> mediaOptions,
    ILogger<TranscodePrivateJob> logger)
{
    [AutomaticRetry(Attempts = 5)]
    [DisableConcurrentExecution(1200)]
    public async Task Run(Guid userId, Guid trackId, Guid generationId)
    {
        var ct = CancellationToken.None;
        var upload = await db.UserPrivateUploads.FirstOrDefaultAsync(
            u => u.UserId == userId && u.TrackId == trackId && u.GenerationId == generationId, ct);
        if (upload is null || upload.Status is "ready" or "cancelled" or "deleting")
        {
            return;
        }

        if (upload.Status is not ("uploaded" or "validating" or "processing" or "failed"))
        {
            return;
        }

        upload.Status = "validating";
        upload.LeaseExpiresAt = DateTimeOffset.UtcNow.AddMinutes(20);
        upload.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        var workDir = Path.Combine(Path.GetTempPath(), "mab-private-transcode", generationId.ToString("D"));
        Directory.CreateDirectory(workDir);
        try
        {
            await ExecuteAsync(upload, workDir, ct);
        }
        catch (FfmpegNotFoundException)
        {
            await FailAsync(upload, "ffmpeg not found", ct);
        }
        catch (NonRetryableMediaException ex)
        {
            await FailAsync(upload, ex.Message, ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Private transcode retryable failure track {TrackId} generation {GenerationId}.", trackId, generationId);
            throw;
        }
        finally
        {
            TryDeleteDir(workDir);
        }
    }

    private async Task ExecuteAsync(UserPrivateUpload upload, string workDir, CancellationToken ct)
    {
        var sourcePath = Path.Combine(workDir, "source");
        var hash = await storage.DownloadAndHashAsync(upload.SourceBucketKey, sourcePath, ct);
        if (!string.Equals(hash, upload.ExpectedChecksumSha256, StringComparison.OrdinalIgnoreCase))
        {
            ObjectDeletionQueue.Enqueue(db, upload.SourceBucketKey, upload.UserId);
            await FailAsync(upload, "checksum_mismatch", ct);
            return;
        }

        upload.ComputedChecksumSha256 = hash;
        upload.Status = "processing";
        upload.LeaseExpiresAt = DateTimeOffset.UtcNow.AddMinutes(20);
        upload.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);

        var media = mediaOptions.Value;
        ProcessResult probeRun;
        try
        {
            probeRun = await runner.RunAsync(media.FfprobePath, TranscodeProfiles.FfprobeArgs(sourcePath), TimeSpan.FromSeconds(30), ct);
        }
        catch (FfmpegNotFoundException)
        {
            throw new FfmpegNotFoundException(media.FfprobePath);
        }

        if (probeRun.ExitCode != 0)
        {
            throw new NonRetryableMediaException("unsupported_audio");
        }

        ProbeResult probe;
        try
        {
            probe = FfprobeParser.Parse(probeRun.Stdout);
        }
        catch
        {
            throw new NonRetryableMediaException("unsupported_audio");
        }

        if (!FfprobeParser.IsAllowedContainer(probe) || probe.AudioStreamCount != 1 || probe.DurationMs <= 0)
        {
            throw new NonRetryableMediaException("unsupported_audio");
        }

        if (probe.DurationMs > 3_600_000)
        {
            throw new NonRetryableMediaException("duration_too_long");
        }

        upload.DurationMs = probe.DurationMs;
        await db.SaveChangesAsync(ct);

        foreach (var profile in TranscodeProfiles.CatalogEncode)
        {
            await EncodeProfileAsync(upload, sourcePath, workDir, probe.DurationMs, profile, media, ct);
        }

        if (FfprobeParser.IsStreamableSource(probe) && await storage.RangeOkAsync(upload.SourceBucketKey, ct))
        {
            await UpsertRenditionAsync(upload, "src", "ready", upload.SourceBucketKey, ContentTypeFor(probe),
                probe.BitrateKbps ?? 128, upload.SizeBytes ?? 1, probe.DurationMs, null, ct);
        }

        await PublishAsync(upload, probe.DurationMs, ct);
        logger.LogInformation("Private transcode published track {TrackId} generation {GenerationId}.",
            upload.TrackId, upload.GenerationId);
    }

    private async Task EncodeProfileAsync(
        UserPrivateUpload upload,
        string sourcePath,
        string workDir,
        int durationMs,
        TranscodeProfile profile,
        MediaOptions media,
        CancellationToken ct)
    {
        var output = Path.Combine(workDir, profile.FileName);
        await UpsertRenditionAsync(upload, profile.Code, "processing", null, null, profile.BitrateKbps, null, null, null, ct);
        var result = await runner.RunAsync(
            media.FfmpegPath,
            TranscodeProfiles.EncodeArgs(sourcePath, output, profile),
            TimeSpan.FromMinutes(15),
            ct);
        if (result.ExitCode != 0 || !File.Exists(output))
        {
            logger.LogWarning("FFmpeg failed private profile {Profile} generation {GenerationId} exit {Exit}.",
                profile.Code, upload.GenerationId, result.ExitCode);
            throw new NonRetryableMediaException("unsupported_audio");
        }

        var key = ObjectKeys.PrivateAac(upload.UserId, upload.TrackId, upload.GenerationId, profile.Code);
        await storage.PutFileAsync(key, output, profile.ContentType, ct);
        var head = await storage.HeadObjectAsync(key, ct);
        if (head is null || head.ContentLength <= 0)
        {
            throw new InvalidOperationException("S3 HEAD after encode returned empty object.");
        }

        await UpsertRenditionAsync(upload, profile.Code, "ready", key, profile.ContentType, profile.BitrateKbps,
            head.ContentLength, durationMs, null, ct);
    }

    private async Task PublishAsync(UserPrivateUpload upload, int durationMs, CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        var previous = await db.UserPrivateUploads
            .Where(u => u.UserId == upload.UserId && u.TrackId == upload.TrackId && u.IsActive && u.GenerationId != upload.GenerationId)
            .ToListAsync(ct);
        foreach (var old in previous)
        {
            old.IsActive = false;
            old.UpdatedAt = now;
        }

        if (previous.Count > 0)
        {
            await db.SaveChangesAsync(ct);
        }

        upload.Status = "ready";
        upload.IsActive = true;
        upload.DurationMs = durationMs;
        upload.LeaseExpiresAt = null;
        upload.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
    }

    private async Task UpsertRenditionAsync(
        UserPrivateUpload upload,
        string profile,
        string status,
        string? bucketKey,
        string? contentType,
        int? bitrate,
        long? size,
        int? durationMs,
        string? error,
        CancellationToken ct)
    {
        var row = await db.UserPrivateRenditions.FirstOrDefaultAsync(
            r => r.GenerationId == upload.GenerationId && r.ProfileCode == profile, ct);
        var now = DateTimeOffset.UtcNow;
        if (row is null)
        {
            row = new UserPrivateRendition
            {
                Id = Guid.NewGuid(),
                UserId = upload.UserId,
                TrackId = upload.TrackId,
                GenerationId = upload.GenerationId,
                ProfileCode = profile,
                CreatedAt = now
            };
            db.UserPrivateRenditions.Add(row);
        }

        row.Status = status;
        row.BucketKey = bucketKey;
        row.ContentType = contentType;
        row.BitrateKbps = bitrate;
        row.SizeBytes = size;
        row.DurationMs = durationMs;
        row.ErrorMessage = error;
        row.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
    }

    private async Task FailAsync(UserPrivateUpload upload, string message, CancellationToken ct)
    {
        upload.Status = "failed";
        upload.IsActive = false;
        upload.LeaseExpiresAt = null;
        upload.UpdatedAt = DateTimeOffset.UtcNow;
        var rows = await db.UserPrivateRenditions.Where(r => r.GenerationId == upload.GenerationId).ToListAsync(ct);
        foreach (var row in rows.Where(r => r.Status != "ready"))
        {
            row.Status = "failed";
            row.ErrorMessage = Sanitize(message);
            row.UpdatedAt = DateTimeOffset.UtcNow;
        }

        if (rows.Count == 0)
        {
            db.UserPrivateRenditions.Add(new UserPrivateRendition
            {
                Id = Guid.NewGuid(),
                UserId = upload.UserId,
                TrackId = upload.TrackId,
                GenerationId = upload.GenerationId,
                ProfileCode = "aac_128",
                Status = "failed",
                ErrorMessage = Sanitize(message),
                CreatedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow
            });
        }

        await db.SaveChangesAsync(ct);
        logger.LogWarning("Private transcode failed track {TrackId} generation {GenerationId}: {Message}",
            upload.TrackId, upload.GenerationId, Sanitize(message));
    }

    private static string Sanitize(string message)
    {
        var text = message;
        if (text.Contains("http", StringComparison.OrdinalIgnoreCase) || text.Contains("X-Amz", StringComparison.OrdinalIgnoreCase))
        {
            text = "storage_error";
        }

        return text.Length > 200 ? text[..200] : text;
    }

    private static string ContentTypeFor(ProbeResult probe)
    {
        var names = probe.FormatName.ToLowerInvariant();
        if (names.Contains("mp3"))
        {
            return "audio/mpeg";
        }

        if (names.Contains("mp4") || names.Contains("m4a"))
        {
            return "audio/mp4";
        }

        return "application/octet-stream";
    }

    private static void TryDeleteDir(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, true);
            }
        }
        catch
        {
        }
    }
}
