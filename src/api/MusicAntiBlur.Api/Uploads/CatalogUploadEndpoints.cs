using System.Security.Claims;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Uploads;

namespace MusicAntiBlur.Api.Catalog;

public static class CatalogUploadEndpoints
{
    public static void MapCatalogMediaEndpoints(this WebApplication app)
    {
        var v1 = app.MapGroup("/api/v1").RequireAuthorization();
        var admin = v1.MapGroup("/admin").RequireAuthorization(policy => policy.RequireRole("admin"));

        v1.MapPost("/tracks/{id:guid}/playback-url", async (
            Guid id,
            PlaybackUrlRequest? req,
            PlaybackUrlService svc,
            ClaimsPrincipal user,
            HttpContext http,
            CancellationToken ct) =>
            Results.Ok(await svc.IssueAsync(
                UserId(user),
                id,
                req ?? new PlaybackUrlRequest(null, null, false),
                http.Request.Host.Host,
                ct)));

        admin.MapPost("/tracks/{trackId:guid}/uploads", async (
            Guid trackId,
            InitiateUploadRequest req,
            AdminUploadService svc,
            ClaimsPrincipal user,
            HttpContext http,
            CancellationToken ct) =>
            Results.Json(
                await svc.InitiateAsync(UserId(user), trackId, req, http.Request.Headers["Idempotency-Key"], ct),
                statusCode: StatusCodes.Status201Created));

        admin.MapPost("/tracks/{trackId:guid}/uploads/{generationId:guid}/parts", async (
            Guid trackId,
            Guid generationId,
            UploadPartsRequest req,
            AdminUploadService svc,
            ClaimsPrincipal user,
            HttpContext http,
            CancellationToken ct) =>
            Results.Ok(await svc.PartsAsync(UserId(user), trackId, generationId, req, http.Request.Host.Host, ct)));

        admin.MapPost("/tracks/{trackId:guid}/uploads/{generationId:guid}/complete", async (
            Guid trackId,
            Guid generationId,
            CompleteUploadRequest req,
            AdminUploadService svc,
            ClaimsPrincipal user,
            HttpContext http,
            CancellationToken ct) =>
            Results.Json(
                await svc.CompleteAsync(UserId(user), trackId, generationId, req, http.Request.Headers["Idempotency-Key"], ct),
                statusCode: StatusCodes.Status202Accepted));

        admin.MapGet("/tracks/{trackId:guid}/uploads/{generationId:guid}", async (
            Guid trackId, Guid generationId, AdminUploadService svc, CancellationToken ct) =>
            Results.Ok(await svc.GetAsync(trackId, generationId, ct)));

        admin.MapDelete("/tracks/{trackId:guid}/uploads/{generationId:guid}", async (
            Guid trackId, Guid generationId, AdminUploadService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.AbortAsync(UserId(user), trackId, generationId, ct);
            return Results.StatusCode(StatusCodes.Status202Accepted);
        });

        admin.MapGet("/tracks/{trackId:guid}/renditions", async (Guid trackId, AdminUploadService svc, CancellationToken ct) =>
            Results.Ok(await svc.ListRenditionsAsync(trackId, ct)));

        admin.MapPost("/tracks/{trackId:guid}/transcode", async (
            Guid trackId, TranscodeRequest? req, AdminUploadService svc, CancellationToken ct) =>
            Results.Json(
                await svc.RetryTranscodeAsync(trackId, req ?? new TranscodeRequest(null), ct),
                statusCode: StatusCodes.Status202Accepted));
    }

    private static Guid UserId(ClaimsPrincipal user)
    {
        var raw = user.FindFirstValue(ClaimTypes.NameIdentifier) ?? user.FindFirstValue("sub");
        if (raw is null || !Guid.TryParse(raw, out var id))
        {
            throw new ApiException(401, "invalid_token", "Invalid token.");
        }

        return id;
    }
}
