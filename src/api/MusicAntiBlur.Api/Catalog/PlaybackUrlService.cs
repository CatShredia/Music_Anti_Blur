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
    string ResolvedQuality,
    string Url,
    DateTimeOffset ExpiresAt,
    Guid GenerationId,
    int DurationMs,
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

    public async Task<PlaybackUrlResponse> IssueAsync(Guid userId, Guid trackId, PlaybackUrlRequest req, CancellationToken ct)
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

        string? fallbackReason = null;
        if (sourcePref == "local")
        {
            fallbackReason = "local_unavailable";
        }
        else if (sourcePref == "private")
        {
            fallbackReason = "private_not_ready";
        }

        var ready = await db.TrackRenditions.AsNoTracking()
            .Where(r => r.TrackId == trackId && r.Status == "ready" && r.Upload.IsActive && r.BucketKey != null && r.DurationMs != null && r.BitrateKbps != null)
            .Select(r => new ReadyQuality(r.ProfileCode, r.BitrateKbps!.Value, r.GenerationId, r.DurationMs!.Value, r.BucketKey!))
            .ToListAsync(ct);

        var resolved = QualityResolver.Resolve(ready, qualityPref);
        if (!resolved.Ok || resolved.Chosen is null)
        {
            if (resolved.ErrorCode == "quality_unavailable")
            {
                throw new ApiException(422, "quality_unavailable", "Requested quality is not available.");
            }

            throw new ApiException(422, "source_unavailable", "No playable catalog rendition.", extras: new Dictionary<string, object>
            {
                ["localAvailable"] = req.LocalAvailable,
                ["privateReady"] = false,
                ["catalogReady"] = false
            });
        }

        var chosen = resolved.Chosen;
        var cacheTtl = Math.Clamp(cdnOptions.Value.CacheTtlSeconds, 1, 480);
        var cacheKey = $"playback:catalog:{trackId:D}:{chosen.GenerationId:D}:{chosen.Code}";
        try
        {
            var cached = await redis.GetDatabase().StringGetAsync(cacheKey);
            if (cached.HasValue)
            {
                var replay = JsonSerializer.Deserialize<PlaybackUrlResponse>((string)cached!, Json);
                if (replay is not null && replay.ExpiresAt > DateTimeOffset.UtcNow.AddSeconds(30))
                {
                    return replay with { FallbackReason = fallbackReason, QualityFallbackFrom = resolved.QualityFallbackFrom };
                }
            }
        }
        catch (Exception ex) when (ex is not ApiException)
        {
            throw new ApiException(503, "dependency_unavailable", "Rate limiter is unavailable.");
        }

        var signed = signer.Sign(chosen.BucketKey);
        var response = new PlaybackUrlResponse(
            "catalog",
            "cdn",
            chosen.Code,
            signed.Url,
            signed.ExpiresAt,
            chosen.GenerationId,
            chosen.DurationMs,
            resolved.QualityFallbackFrom,
            fallbackReason);

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
}
