using System.Security.Claims;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Catalog;

public static class CatalogEndpoints
{
    public static void MapCatalogEndpoints(this WebApplication app)
    {
        var v1 = app.MapGroup("/api/v1").RequireAuthorization();
        var admin = v1.MapGroup("/admin").RequireAuthorization(policy => policy.RequireRole("admin"));

        v1.MapGet("/artists", async (string? cursor, int? limit, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.ListArtistsAsync(cursor, limit, ct)));

        v1.MapGet("/artists/{id:guid}", async (Guid id, CatalogService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetArtistPageAsync(id, UserId(user), ct)));

        v1.MapGet("/artists/{id:guid}/popular", async (
            Guid id, int? limit, CatalogService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetArtistPopularAsync(id, UserId(user), limit, ct)));

        v1.MapGet("/genres", async (GenreService svc, CancellationToken ct) =>
            Results.Ok(await svc.ListAsync(ct)));

        v1.MapGet("/genres/{id:guid}", async (Guid id, GenreService svc, CancellationToken ct) =>
            Results.Ok(await svc.GetAsync(id, ct)));

        v1.MapGet("/albums", async (Guid? artistId, string? cursor, int? limit, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.ListAlbumsAsync(artistId, cursor, limit, ct)));

        v1.MapGet("/albums/{id:guid}", async (Guid id, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.GetAlbumAsync(id, ct)));

        v1.MapGet("/tracks/{id:guid}", async (Guid id, CatalogService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetTrackAsync(id, UserId(user), ct)));

        v1.MapGet("/search", async (string? q, string? cursor, int? limit, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.SearchAsync(q, cursor, limit, ct)));

        admin.MapGet("/search", async (string? q, string? cursor, int? limit, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.AdminSearchAsync(q, cursor, limit, ct)));

        admin.MapGet("/genres", async (GenreService svc, CancellationToken ct) =>
            Results.Ok(await svc.ListAsync(ct)));

        admin.MapPost("/genres", async (UpsertGenreRequest req, GenreService svc, CancellationToken ct) =>
            Results.Json(await svc.CreateAsync(req, ct), statusCode: StatusCodes.Status201Created));

        admin.MapPut("/genres/{id:guid}", async (Guid id, UpsertGenreRequest req, GenreService svc, CancellationToken ct) =>
            Results.Ok(await svc.RenameAsync(id, req, ct)));

        admin.MapDelete("/genres/{id:guid}", async (Guid id, GenreService svc, CancellationToken ct) =>
            Results.Ok(await svc.DeleteAsync(id, ct)));

        admin.MapPut("/albums/{id:guid}/genres", async (Guid id, SetGenresRequest req, GenreService svc, CancellationToken ct) =>
            Results.Ok(await svc.SetAlbumGenresAsync(id, req, ct)));

        admin.MapPut("/tracks/{id:guid}/genres", async (Guid id, SetGenresRequest req, GenreService svc, CancellationToken ct) =>
            Results.Ok(await svc.SetTrackGenresAsync(id, req, ct)));

        admin.MapPost("/artists", async (UpsertArtistRequest req, CatalogService svc, CancellationToken ct) =>
            Results.Json(await svc.CreateArtistAsync(req, ct), statusCode: StatusCodes.Status201Created));

        admin.MapPut("/artists/{id:guid}", async (Guid id, UpsertArtistRequest req, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.UpdateArtistAsync(id, req, ct)));

        admin.MapPost("/albums", async (UpsertAlbumRequest req, CatalogService svc, CancellationToken ct) =>
            Results.Json(await svc.CreateAlbumAsync(req, ct), statusCode: StatusCodes.Status201Created));

        admin.MapPut("/albums/{id:guid}", async (Guid id, UpsertAlbumRequest req, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.UpdateAlbumAsync(id, req, ct)));

        admin.MapPut("/albums/{id:guid}/cover", async (Guid id, HttpRequest request, CatalogService svc, CancellationToken ct) =>
        {
            var limit = request.HttpContext.Features.Get<IHttpMaxRequestBodySizeFeature>();
            if (limit is { IsReadOnly: false })
            {
                limit.MaxRequestBodySize = CoverImageValidation.MaxRequestBytes;
            }

            var form = await request.ReadFormAsync(ct);
            return Results.Ok(await svc.UploadCoverAsync(id, form.Files.GetFile("file"), ct));
        }).WithMetadata(new RequestSizeLimitAttribute(CoverImageValidation.MaxRequestBytes))
            .DisableAntiforgery();

        admin.MapPost("/tracks", async (UpsertTrackRequest req, CatalogService svc, CancellationToken ct) =>
            Results.Json(await svc.CreateTrackAsync(req, ct), statusCode: StatusCodes.Status201Created));

        admin.MapPut("/tracks/{id:guid}", async (Guid id, UpsertTrackRequest req, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.UpdateTrackAsync(id, req, ct)));

        admin.MapGet("/albums/{id:guid}/tracks", async (Guid id, AdminCatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.ListAlbumTracksAsync(id, ct)));

        admin.MapGet("/tracks/deleted", async (AdminCatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.ListDeletedTracksAsync(ct)));

        admin.MapDelete("/tracks/{id:guid}", async (Guid id, AdminCatalogService svc, CancellationToken ct) =>
        {
            await svc.DeleteTrackAsync(id, ct);
            return Results.NoContent();
        });

        admin.MapPost("/tracks/{id:guid}/restore", async (Guid id, AdminCatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.RestoreTrackAsync(id, ct)));

        admin.MapGet("/albums/deleted", async (AdminCatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.ListDeletedAlbumsAsync(ct)));

        admin.MapPost("/albums/{id:guid}/restore", async (Guid id, AdminCatalogService svc, CancellationToken ct) =>
        {
            await svc.RestoreAlbumAsync(id, ct);
            return Results.NoContent();
        });

        admin.MapDelete("/albums/{id:guid}", async (Guid id, bool? cascade, AdminCatalogService svc, CancellationToken ct) =>
        {
            await svc.DeleteAlbumAsync(id, cascade == true, ct);
            return Results.NoContent();
        });

        admin.MapDelete("/artists/{id:guid}", async (Guid id, bool? cascade, AdminCatalogService svc, CancellationToken ct) =>
        {
            await svc.DeleteArtistAsync(id, cascade == true, ct);
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
