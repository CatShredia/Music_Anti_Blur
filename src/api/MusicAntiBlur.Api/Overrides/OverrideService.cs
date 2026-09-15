using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Auth;
using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Uploads;

namespace MusicAntiBlur.Api.Overrides;

public sealed record PutOverrideRequest(string? SourcePreference, string? DisplayName, int? DurationMs, long? SizeBytes);

public sealed record TrackOverrideResponse(
    string SourcePreference,
    string? DisplayName,
    int? DurationMs,
    long? SizeBytes,
    bool PrivateReady,
    string? PrivateStatus,
    Guid? PrivateGenerationId,
    IReadOnlyList<QualityDto> AvailableQualities);

public sealed class OverrideService(AppDbContext db)
{
    public async Task<TrackOverrideResponse> GetAsync(Guid userId, Guid trackId, CancellationToken ct)
    {
        await EnsureTrackAsync(trackId, ct);
        var row = await db.UserTrackOverrides.AsNoTracking()
            .FirstOrDefaultAsync(o => o.UserId == userId && o.TrackId == trackId, ct)
            ?? throw new ApiException(404, "not_found", "Not found.");
        return await ToResponseAsync(row, ct);
    }

    public async Task<TrackOverrideResponse> PutAsync(Guid userId, Guid trackId, PutOverrideRequest req, CancellationToken ct)
    {
        await EnsureTrackAsync(trackId, ct);
        var errors = AuthValidation.NewErrors();
        var source = (req.SourcePreference ?? "").Trim().ToLowerInvariant();
        if (source is not ("auto" or "catalog" or "local" or "private"))
        {
            AuthValidation.Add(errors, "sourcePreference", AuthValidation.Required);
        }

        if (req.DurationMs is <= 0)
        {
            AuthValidation.Add(errors, "durationMs", AuthValidation.Required);
        }

        if (req.SizeBytes is <= 0)
        {
            AuthValidation.Add(errors, "sizeBytes", AuthValidation.Required);
        }

        AuthValidation.ThrowIfAny(errors);

        var display = string.IsNullOrWhiteSpace(req.DisplayName) ? null : req.DisplayName.Trim();
        if (display is { Length: > 255 })
        {
            display = display[..255];
        }

        var now = DateTimeOffset.UtcNow;
        var row = await db.UserTrackOverrides.FirstOrDefaultAsync(o => o.UserId == userId && o.TrackId == trackId, ct);
        if (row is null)
        {
            row = new UserTrackOverride
            {
                UserId = userId,
                TrackId = trackId,
                SourcePreference = source,
                DisplayName = display,
                DurationMs = req.DurationMs,
                SizeBytes = req.SizeBytes,
                UpdatedAt = now
            };
            db.UserTrackOverrides.Add(row);
        }
        else
        {
            row.SourcePreference = source;
            if (req.DisplayName != null)
            {
                row.DisplayName = display;
            }

            if (req.DurationMs != null)
            {
                row.DurationMs = req.DurationMs;
            }

            if (req.SizeBytes != null)
            {
                row.SizeBytes = req.SizeBytes;
            }

            row.UpdatedAt = now;
        }

        await db.SaveChangesAsync(ct);
        return await ToResponseAsync(row, ct);
    }

    public async Task DeletePrivateCopyAsync(Guid userId, Guid trackId, CancellationToken ct)
    {
        await EnsureTrackAsync(trackId, ct);
        var row = await db.UserTrackOverrides.FirstOrDefaultAsync(o => o.UserId == userId && o.TrackId == trackId, ct)
            ?? throw new ApiException(404, "not_found", "Not found.");

        var uploads = await db.UserPrivateUploads
            .Include(u => u.Renditions)
            .Where(u => u.UserId == userId && u.TrackId == trackId)
            .ToListAsync(ct);
        foreach (var upload in uploads)
        {
            EnqueueUploadObjects(upload, userId);
            upload.IsActive = false;
            upload.Status = "deleting";
            upload.MultipartUploadId = null;
            upload.UpdatedAt = DateTimeOffset.UtcNow;
        }

        row.SourcePreference = "catalog";
        row.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
    }

    public async Task DeleteOverrideAsync(Guid userId, Guid trackId, CancellationToken ct)
    {
        await EnsureTrackAsync(trackId, ct);
        var row = await db.UserTrackOverrides.FirstOrDefaultAsync(o => o.UserId == userId && o.TrackId == trackId, ct)
            ?? throw new ApiException(404, "not_found", "Not found.");

        var uploads = await db.UserPrivateUploads
            .Include(u => u.Renditions)
            .Where(u => u.UserId == userId && u.TrackId == trackId)
            .ToListAsync(ct);
        foreach (var upload in uploads)
        {
            EnqueueUploadObjects(upload, userId);
        }

        db.UserTrackOverrides.Remove(row);
        await db.SaveChangesAsync(ct);
    }

    public async Task<UserTrackOverride> EnsureRowAsync(Guid userId, Guid trackId, CancellationToken ct)
    {
        await EnsureTrackAsync(trackId, ct);
        var row = await db.UserTrackOverrides.FirstOrDefaultAsync(o => o.UserId == userId && o.TrackId == trackId, ct);
        if (row is not null)
        {
            return row;
        }

        row = new UserTrackOverride
        {
            UserId = userId,
            TrackId = trackId,
            SourcePreference = "auto",
            UpdatedAt = DateTimeOffset.UtcNow
        };
        db.UserTrackOverrides.Add(row);
        await db.SaveChangesAsync(ct);
        return row;
    }

    private async Task EnsureTrackAsync(Guid trackId, CancellationToken ct)
    {
        if (!await db.Tracks.AsNoTracking().AnyAsync(t => t.Id == trackId, ct))
        {
            throw new ApiException(404, "not_found", "Not found.");
        }
    }

    private async Task<TrackOverrideResponse> ToResponseAsync(UserTrackOverride row, CancellationToken ct)
    {
        var active = await db.UserPrivateUploads.AsNoTracking()
            .Where(u => u.UserId == row.UserId && u.TrackId == row.TrackId && u.IsActive && u.Status == "ready")
            .OrderByDescending(u => u.UpdatedAt)
            .FirstOrDefaultAsync(ct);
        var latest = active ?? await db.UserPrivateUploads.AsNoTracking()
            .Where(u => u.UserId == row.UserId && u.TrackId == row.TrackId)
            .OrderByDescending(u => u.CreatedAt)
            .FirstOrDefaultAsync(ct);

        var qualities = Array.Empty<QualityDto>();
        var privateReady = false;
        if (active is not null)
        {
            qualities = await db.UserPrivateRenditions.AsNoTracking()
                .Where(r => r.GenerationId == active.GenerationId && r.Status == "ready" && r.BitrateKbps != null)
                .Select(r => new QualityDto(r.ProfileCode, r.BitrateKbps!.Value))
                .ToArrayAsync(ct);
            privateReady = qualities.Length > 0;
        }

        return new TrackOverrideResponse(
            row.SourcePreference,
            row.DisplayName,
            row.DurationMs,
            row.SizeBytes,
            privateReady,
            latest?.Status,
            latest?.GenerationId,
            qualities);
    }

    private void EnqueueUploadObjects(UserPrivateUpload upload, Guid ownerUserId)
    {
        ObjectDeletionQueue.Enqueue(db, upload.SourceBucketKey, ownerUserId);
        foreach (var rendition in upload.Renditions.Where(r => r.BucketKey != null))
        {
            ObjectDeletionQueue.Enqueue(db, rendition.BucketKey!, ownerUserId);
        }
    }
}
