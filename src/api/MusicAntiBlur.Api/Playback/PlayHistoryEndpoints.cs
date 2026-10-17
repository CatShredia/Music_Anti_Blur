using System.Security.Claims;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Playback;

public static class PlayHistoryEndpoints
{
    public static void MapPlayHistoryEndpoints(this WebApplication app)
    {
        var me = app.MapGroup("/api/v1/me").RequireAuthorization();

        me.MapPost("/plays", async (RecordPlayRequest req, PlayHistoryService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.RecordAsync(UserId(user), req, ct);
            return Results.NoContent();
        });

        me.MapGet("/history", async (string? cursor, int? limit, PlayHistoryService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.ListAsync(UserId(user), cursor, limit, ct)));
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
