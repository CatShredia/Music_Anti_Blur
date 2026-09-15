using System.Security.Claims;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Overrides;
using MusicAntiBlur.Api.Uploads;

namespace MusicAntiBlur.Api.Catalog;

public static class OverrideEndpoints
{
    public static void MapOverrideEndpoints(this WebApplication app)
    {
        var v1 = app.MapGroup("/api/v1").RequireAuthorization();

        v1.MapGet("/tracks/{trackId:guid}/override", async (
            Guid trackId, OverrideService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetAsync(UserId(user), trackId, ct)));

        v1.MapPut("/tracks/{trackId:guid}/override", async (
            Guid trackId, PutOverrideRequest req, OverrideService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.PutAsync(UserId(user), trackId, req, ct)));

        v1.MapDelete("/tracks/{trackId:guid}/private-copy", async (
            Guid trackId, OverrideService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.DeletePrivateCopyAsync(UserId(user), trackId, ct);
            return Results.StatusCode(StatusCodes.Status202Accepted);
        });

        v1.MapDelete("/tracks/{trackId:guid}/override", async (
            Guid trackId, OverrideService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.DeleteOverrideAsync(UserId(user), trackId, ct);
            return Results.StatusCode(StatusCodes.Status202Accepted);
        });

        v1.MapPost("/tracks/{trackId:guid}/private-uploads", async (
            Guid trackId,
            InitiateUploadRequest req,
            PrivateUploadService svc,
            ClaimsPrincipal user,
            HttpContext http,
            CancellationToken ct) =>
            Results.Json(
                await svc.InitiateAsync(UserId(user), trackId, req, http.Request.Headers["Idempotency-Key"], ct),
                statusCode: StatusCodes.Status201Created));

        v1.MapPost("/tracks/{trackId:guid}/private-uploads/{generationId:guid}/parts", async (
            Guid trackId,
            Guid generationId,
            UploadPartsRequest req,
            PrivateUploadService svc,
            ClaimsPrincipal user,
            CancellationToken ct) =>
            Results.Ok(await svc.PartsAsync(UserId(user), trackId, generationId, req, ct)));

        v1.MapPost("/tracks/{trackId:guid}/private-uploads/{generationId:guid}/complete", async (
            Guid trackId,
            Guid generationId,
            CompleteUploadRequest req,
            PrivateUploadService svc,
            ClaimsPrincipal user,
            HttpContext http,
            CancellationToken ct) =>
            Results.Json(
                await svc.CompleteAsync(UserId(user), trackId, generationId, req, http.Request.Headers["Idempotency-Key"], ct),
                statusCode: StatusCodes.Status202Accepted));

        v1.MapGet("/tracks/{trackId:guid}/private-uploads/{generationId:guid}", async (
            Guid trackId, Guid generationId, PrivateUploadService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetAsync(UserId(user), trackId, generationId, ct)));

        v1.MapDelete("/tracks/{trackId:guid}/private-uploads/{generationId:guid}", async (
            Guid trackId, Guid generationId, PrivateUploadService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.AbortAsync(UserId(user), trackId, generationId, ct);
            return Results.StatusCode(StatusCodes.Status202Accepted);
        });

        v1.MapPost("/tracks/{trackId:guid}/private-uploads/{generationId:guid}/transcode", async (
            Guid trackId, Guid generationId, PrivateUploadService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Json(
                await svc.RetryTranscodeAsync(UserId(user), trackId, generationId, ct),
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
