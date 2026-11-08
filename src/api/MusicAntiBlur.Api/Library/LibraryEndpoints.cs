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
            Guid playlistId, string? cursor, int? limit, PlaylistService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetAsync(UserId(user), playlistId, cursor, limit, ct)));

        // Чужой публичный плейлист (по ссылке).
        v1.MapGet("/playlists/{playlistId:guid}", async (
            Guid playlistId, string? cursor, int? limit, PlaylistService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetAsync(UserId(user), playlistId, cursor, limit, ct)));

        v1.MapPost("/me/playlists", async (
            CreatePlaylistRequest req, PlaylistService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var created = await svc.CreateAsync(UserId(user), req, ct);
            return Results.Created($"/api/v1/me/playlists/{created.Id}", created);
        });

        v1.MapPut("/me/playlists/{playlistId:guid}", async (
            Guid playlistId, UpdatePlaylistRequest req, PlaylistService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.UpdateAsync(UserId(user), playlistId, req, ct)));

        v1.MapDelete("/me/playlists/{playlistId:guid}", async (
            Guid playlistId, PlaylistService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.DeleteAsync(UserId(user), playlistId, ct);
            return Results.NoContent();
        });

        v1.MapPost("/me/playlists/{playlistId:guid}/tracks", async (
            Guid playlistId, AddPlaylistTracksRequest req, PlaylistService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.AddTracksAsync(UserId(user), playlistId, req, ct)));

        v1.MapDelete("/me/playlists/{playlistId:guid}/tracks/{trackId:guid}", async (
            Guid playlistId, Guid trackId, PlaylistService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.RemoveTrackAsync(UserId(user), playlistId, trackId, ct);
            return Results.NoContent();
        });

        v1.MapPut("/me/playlists/{playlistId:guid}/tracks/order", async (
            Guid playlistId, ReorderPlaylistRequest req, PlaylistService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.ReorderAsync(UserId(user), playlistId, req, ct);
            return Results.NoContent();
        });

        v1.MapGet("/me/library", async (
            string? type, string? cursor, int? limit, SavedLibraryService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.ListAsync(UserId(user), type, cursor, limit, ct)));

        v1.MapPut("/me/library/playlists/{playlistId:guid}", async (
            Guid playlistId, SavedLibraryService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.SavePlaylistAsync(UserId(user), playlistId, ct);
            return Results.Ok(new InLibraryDto(true));
        });

        v1.MapDelete("/me/library/playlists/{playlistId:guid}", async (
            Guid playlistId, SavedLibraryService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.RemovePlaylistAsync(UserId(user), playlistId, ct);
            return Results.NoContent();
        });

        v1.MapGet("/me/library/albums/{albumId:guid}", async (
            Guid albumId, SavedLibraryService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.AlbumStatusAsync(UserId(user), albumId, ct)));

        v1.MapPut("/me/library/albums/{albumId:guid}", async (
            Guid albumId, SavedLibraryService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.SaveAlbumAsync(UserId(user), albumId, ct);
            return Results.Ok(new InLibraryDto(true));
        });

        v1.MapDelete("/me/library/albums/{albumId:guid}", async (
            Guid albumId, SavedLibraryService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.RemoveAlbumAsync(UserId(user), albumId, ct);
            return Results.NoContent();
        });
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
