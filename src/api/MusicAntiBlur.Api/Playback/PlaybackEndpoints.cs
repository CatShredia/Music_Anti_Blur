using System.Security.Claims;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Playback;

public static class PlaybackEndpoints
{
    public static void MapPlaybackEndpoints(this WebApplication app)
    {
        var v1 = app.MapGroup("/api/v1").RequireAuthorization();

        v1.MapGet("/playback-state", async (PlaybackStateService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetAsync(UserId(user), ct)));

        v1.MapPost("/playback-sessions", async (
            CreatePlaybackSessionRequest? req,
            PlaybackStateService svc,
            ClaimsPrincipal user,
            CancellationToken ct) =>
            Results.Json(
                await svc.CreateSessionAsync(UserId(user), req?.DeviceId, ct),
                statusCode: StatusCodes.Status201Created));

        v1.MapPost("/playback-sessions/{sessionId:guid}/claim", async (
            Guid sessionId,
            ClaimPlaybackSessionRequest? req,
            PlaybackStateService svc,
            ClaimsPrincipal user,
            CancellationToken ct) =>
            Results.Ok(await svc.ClaimAsync(UserId(user), sessionId, req?.ExpectedRevision, ct)));

        v1.MapPut("/playback-state", async (
            PutPlaybackStateRequest req,
            PlaybackStateService svc,
            ClaimsPrincipal user,
            CancellationToken ct) =>
            Results.Ok(await svc.PutAsync(UserId(user), req, ct)));
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
