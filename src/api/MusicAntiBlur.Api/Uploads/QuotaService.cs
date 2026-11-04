using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Storage;

namespace MusicAntiBlur.Api.Uploads;

/// <summary>
/// Private upload quota. Counted: the active generation of each track plus uploads still in flight.
/// A replaced or failed generation does not count, so replacing a file never charges twice.
/// </summary>
public sealed class QuotaService(AppDbContext db, IOptions<StorageOptions> storageOptions)
{
    public const long DefaultMaxBytes = 2L * 1024 * 1024 * 1024;
    public const int DefaultMaxFiles = 500;

    private static readonly string[] InFlight = ["initiated", "uploaded", "validating", "processing"];

    public async Task<QuotaDto> GetUsageAsync(Guid userId, CancellationToken ct)
    {
        var counted = db.UserPrivateUploads.AsNoTracking()
            .Where(u => u.UserId == userId && (u.IsActive || InFlight.Contains(u.Status)));
        var usedBytes = await counted.SumAsync(u => u.SizeBytes ?? 0, ct);
        var usedFiles = await counted.CountAsync(ct);
        var (maxBytes, maxFiles) = await GetLimitsAsync(userId, ct);
        return new QuotaDto(usedBytes, maxBytes, usedFiles, maxFiles);
    }

    /// <summary>Throws 413 quota_exceeded when one more file of <paramref name="sizeBytes"/> does not fit.</summary>
    public async Task EnsureFitsAsync(Guid userId, long sizeBytes, CancellationToken ct)
    {
        var usage = await GetUsageAsync(userId, ct);
        if (!Fits(usage, sizeBytes))
        {
            Observability.AppMetrics.QuotaRejected();
            throw new ApiException(413, "quota_exceeded", "Private storage quota exceeded.",
                extras: new Dictionary<string, object> { ["quota"] = usage });
        }
    }

    public static bool Fits(QuotaDto usage, long sizeBytes) =>
        usage.UsedFiles + 1 <= usage.MaxFiles && usage.UsedBytes + sizeBytes <= usage.MaxBytes;

    public async Task<QuotaDto> SetOverrideAsync(Guid userId, SetQuotaRequest req, CancellationToken ct)
    {
        var errors = new Dictionary<string, string[]>();
        if (req.MaxBytes is < 0)
        {
            errors["maxBytes"] = ["out_of_range"];
        }

        if (req.MaxFiles is < 0)
        {
            errors["maxFiles"] = ["out_of_range"];
        }

        if (errors.Count > 0)
        {
            throw new ApiException(400, "validation_failed", "Validation failed.", errors);
        }

        if (!await db.Users.AnyAsync(u => u.Id == userId, ct))
        {
            throw new ApiException(404, "not_found", "Not found.");
        }

        var row = await db.UserQuotas.FirstOrDefaultAsync(q => q.UserId == userId, ct);
        if (req.MaxBytes is null && req.MaxFiles is null)
        {
            if (row is not null)
            {
                db.UserQuotas.Remove(row);
            }
        }
        else
        {
            if (row is null)
            {
                row = new UserQuota { UserId = userId };
                db.UserQuotas.Add(row);
            }

            row.MaxBytes = req.MaxBytes;
            row.MaxFiles = req.MaxFiles;
            row.UpdatedAt = DateTimeOffset.UtcNow;
        }

        await db.SaveChangesAsync(ct);
        return await GetUsageAsync(userId, ct);
    }

    private async Task<(long MaxBytes, int MaxFiles)> GetLimitsAsync(Guid userId, CancellationToken ct)
    {
        var options = storageOptions.Value;
        var defaultBytes = options.PrivateQuotaBytes > 0 ? options.PrivateQuotaBytes : DefaultMaxBytes;
        var defaultFiles = options.PrivateQuotaFiles > 0 ? options.PrivateQuotaFiles : DefaultMaxFiles;
        var row = await db.UserQuotas.AsNoTracking().FirstOrDefaultAsync(q => q.UserId == userId, ct);
        return (row?.MaxBytes ?? defaultBytes, row?.MaxFiles ?? defaultFiles);
    }
}

public sealed record QuotaDto(long UsedBytes, long MaxBytes, int UsedFiles, int MaxFiles);
public sealed record SetQuotaRequest(long? MaxBytes, int? MaxFiles);
