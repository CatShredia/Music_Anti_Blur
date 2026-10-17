using System.Security.Claims;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Library;

public static class LibraryEndpoints
{
    public static void MapLibraryEndpoints(this WebApplication app)
    {
        var v1 = app.MapGroup("/api/v1").RequireAuthorization();

        v1.MapGet("/tracks/{trackId:guid}/like", async (
            Guid trackId, LibraryService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetLikeAsync(UserId(user), trackId, ct)));

        v1.MapPut("/tracks/{trackId:guid}/like", async (
            Guid trackId, LibraryService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.LikeAsync(UserId(user), trackId, ct)));

        v1.MapDelete("/tracks/{trackId:guid}/like", async (
            Guid trackId, LibraryService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.UnlikeAsync(UserId(user), trackId, ct);
            return Results.NoContent();
        });

        v1.MapGet("/me/playlists", async (LibraryService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.ListPlaylistsAsync(UserId(user), ct)));

        v1.MapGet("/me/playlists/liked", async (
            string? cursor, int? limit, LibraryService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetLikedPlaylistAsync(UserId(user), cursor, limit, ct)));

        v1.MapGet("/me/playlists/{playlistId:guid}", async (
            Guid playlistId, string? cursor, int? limit, LibraryService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetPlaylistAsync(UserId(user), playlistId, cursor, limit, ct)));
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
