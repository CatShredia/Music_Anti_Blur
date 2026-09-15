using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.RateLimiting;
using MusicAntiBlur.Api.Storage;
using StackExchange.Redis;

namespace MusicAntiBlur.Api.Catalog;

public sealed record PlaybackUrlRequest(string? SourcePreference, string? QualityPreference, bool LocalAvailable);

public sealed record PlaybackUrlResponse(
    string ResolvedSource,
    string Delivery,
    string? ResolvedQuality,
    string? Url,
    DateTimeOffset? ExpiresAt,
    Guid? GenerationId,
    int? DurationMs,
    string? QualityFallbackFrom,
    string? FallbackReason);

public sealed class PlaybackUrlService(
    AppDbContext db,
    RedisRateLimiter limiter,
    IConnectionMultiplexer redis,
    PlaybackUrlSigner signer,
    IOptions<CdnOptions> cdnOptions)
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public async Task<PlaybackUrlResponse> IssueAsync(
        Guid userId, Guid trackId, PlaybackUrlRequest req, string? clientHost, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:playback-url:{userId:D}", 60, TimeSpan.FromMinutes(1), ct);

        if (!await db.Tracks.AsNoTracking().AnyAsync(t => t.Id == trackId, ct))
        {
            throw new ApiException(404, "not_found", "Not found.");
        }

        var sourcePref = (req.SourcePreference ?? "auto").Trim().ToLowerInvariant();
        if (sourcePref is not ("auto" or "catalog" or "local" or "private"))
        {
            throw new ApiException(400, "validation_failed", "Validation failed.",
                new Dictionary<string, string[]> { ["sourcePreference"] = ["required"] });
        }

        var qualityPref = (req.QualityPreference ?? "auto").Trim().ToLowerInvariant();
        if (qualityPref is not ("auto" or "aac_128" or "aac_256" or "src"))
        {
            throw new ApiException(400, "validation_failed", "Validation failed.",
                new Dictionary<string, string[]> { ["qualityPreference"] = ["preferred_quality"] });
        }

        var catalogReady = await LoadCatalogReadyAsync(trackId, ct);
        var privateReady = await LoadPrivateReadyAsync(userId, trackId, ct);
        var source = SourceResolver.Resolve(sourcePref, req.LocalAvailable, privateReady.Count > 0, catalogReady.Count > 0);
        if (!source.Ok || source.Chosen is null)
        {
            throw new ApiException(422, "source_unavailable", "No playable source.", extras: new Dictionary<string, object>
            {
                ["localAvailable"] = req.LocalAvailable,
                ["privateReady"] = privateReady.Count > 0,
                ["catalogReady"] = catalogReady.Count > 0
            });
        }

        if (source.Chosen == "local")
        {
            var localDuration = await db.UserTrackOverrides.AsNoTracking()
                .Where(o => o.UserId == userId && o.TrackId == trackId)
                .Select(o => o.DurationMs)
                .FirstOrDefaultAsync(ct);
            return new PlaybackUrlResponse(
                "local",
                "local",
                null,
                null,
                null,
                null,
                localDuration,
                null,
                source.FallbackReason);
        }

        var pool = source.Chosen == "private" ? privateReady : catalogReady;
        var resolved = QualityResolver.Resolve(pool, qualityPref);
        if (!resolved.Ok || resolved.Chosen is null)
        {
            if (resolved.ErrorCode == "quality_unavailable")
            {
                throw new ApiException(422, "quality_unavailable", "Requested quality is not available.");
            }

            throw new ApiException(422, "source_unavailable", "No playable source.", extras: new Dictionary<string, object>
            {
                ["localAvailable"] = req.LocalAvailable,
                ["privateReady"] = privateReady.Count > 0,
                ["catalogReady"] = catalogReady.Count > 0
            });
        }

        var chosen = resolved.Chosen;
        var cacheTtl = Math.Clamp(cdnOptions.Value.CacheTtlSeconds, 1, 480);
        var cacheKey = source.Chosen == "private"
            ? $"playback:private:{userId:D}:{trackId:D}:{chosen.GenerationId:D}:{chosen.Code}:{signer.CachePartition(clientHost)}"
            : $"playback:{trackId:D}:{chosen.GenerationId:D}:{chosen.Code}:{signer.CachePartition(clientHost)}";

        try
        {
            var cached = await redis.GetDatabase().StringGetAsync(cacheKey);
            if (cached.HasValue)
            {
                var replay = JsonSerializer.Deserialize<PlaybackUrlResponse>((string)cached!, Json);
                if (replay is not null && replay.ExpiresAt is DateTimeOffset exp && exp > DateTimeOffset.UtcNow.AddSeconds(30))
                {
                    return replay with { FallbackReason = source.FallbackReason, QualityFallbackFrom = resolved.QualityFallbackFrom };
                }
            }
        }
        catch (Exception ex) when (ex is not ApiException)
        {
            throw new ApiException(503, "dependency_unavailable", "Rate limiter is unavailable.");
        }

        var signed = signer.Sign(chosen.BucketKey, clientHost);
        var response = new PlaybackUrlResponse(
            source.Chosen,
            "cdn",
            chosen.Code,
            signed.Url,
            signed.ExpiresAt,
            chosen.GenerationId,
            chosen.DurationMs,
            resolved.QualityFallbackFrom,
            source.FallbackReason);

        try
        {
            await redis.GetDatabase().StringSetAsync(cacheKey, JsonSerializer.Serialize(response, Json), TimeSpan.FromSeconds(cacheTtl));
        }
        catch (Exception ex) when (ex is not ApiException)
        {
            throw new ApiException(503, "dependency_unavailable", "Rate limiter is unavailable.");
        }

        return response;
    }

    private Task<List<ReadyQuality>> LoadCatalogReadyAsync(Guid trackId, CancellationToken ct) =>
        db.TrackRenditions.AsNoTracking()
            .Where(r => r.TrackId == trackId && r.Status == "ready" && r.Upload.IsActive && r.BucketKey != null && r.DurationMs != null && r.BitrateKbps != null)
            .Select(r => new ReadyQuality(r.ProfileCode, r.BitrateKbps!.Value, r.GenerationId, r.DurationMs!.Value, r.BucketKey!))
            .ToListAsync(ct);

    private Task<List<ReadyQuality>> LoadPrivateReadyAsync(Guid userId, Guid trackId, CancellationToken ct) =>
        db.UserPrivateRenditions.AsNoTracking()
            .Where(r => r.UserId == userId && r.TrackId == trackId && r.Status == "ready" && r.Upload.IsActive &&
                        r.Upload.Status == "ready" && r.BucketKey != null && r.DurationMs != null && r.BitrateKbps != null)
            .Select(r => new ReadyQuality(r.ProfileCode, r.BitrateKbps!.Value, r.GenerationId, r.DurationMs!.Value, r.BucketKey!))
            .ToListAsync(ct);
}
