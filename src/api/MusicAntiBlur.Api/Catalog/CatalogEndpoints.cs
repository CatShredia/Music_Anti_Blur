namespace MusicAntiBlur.Api.Catalog;

public static class CatalogEndpoints
{
    public static void MapCatalogEndpoints(this WebApplication app)
    {
        var v1 = app.MapGroup("/api/v1").RequireAuthorization();
        var admin = v1.MapGroup("/admin").RequireAuthorization(policy => policy.RequireRole("admin"));

        v1.MapGet("/artists", async (string? cursor, int? limit, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.ListArtistsAsync(cursor, limit, ct)));

        v1.MapGet("/artists/{id:guid}", async (Guid id, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.GetArtistAsync(id, ct)));

        v1.MapGet("/albums", async (Guid? artistId, string? cursor, int? limit, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.ListAlbumsAsync(artistId, cursor, limit, ct)));

        v1.MapGet("/albums/{id:guid}", async (Guid id, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.GetAlbumAsync(id, ct)));

        v1.MapGet("/tracks/{id:guid}", async (Guid id, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.GetTrackAsync(id, ct)));

        v1.MapGet("/search", async (string? q, string? cursor, int? limit, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.SearchAsync(q, cursor, limit, ct)));

        admin.MapPost("/artists", async (UpsertArtistRequest req, CatalogService svc, CancellationToken ct) =>
            Results.Json(await svc.CreateArtistAsync(req, ct), statusCode: StatusCodes.Status201Created));

        admin.MapPut("/artists/{id:guid}", async (Guid id, UpsertArtistRequest req, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.UpdateArtistAsync(id, req, ct)));

        admin.MapPost("/albums", async (UpsertAlbumRequest req, CatalogService svc, CancellationToken ct) =>
            Results.Json(await svc.CreateAlbumAsync(req, ct), statusCode: StatusCodes.Status201Created));

        admin.MapPut("/albums/{id:guid}", async (Guid id, UpsertAlbumRequest req, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.UpdateAlbumAsync(id, req, ct)));

        admin.MapPost("/tracks", async (UpsertTrackRequest req, CatalogService svc, CancellationToken ct) =>
            Results.Json(await svc.CreateTrackAsync(req, ct), statusCode: StatusCodes.Status201Created));

        admin.MapPut("/tracks/{id:guid}", async (Guid id, UpsertTrackRequest req, CatalogService svc, CancellationToken ct) =>
            Results.Ok(await svc.UpdateTrackAsync(id, req, ct)));
    }
}
