using Microsoft.AspNetCore.Http;

namespace MusicAntiBlur.Api.Library;

public static class SharingEndpoints
{
    public static void MapSharingEndpoints(this WebApplication app)
    {
        // Публичная карточка без авторизации; приватное, удалённое и несуществующее — одинаковый 404.
        app.MapGet("/s/{type}/{id:guid}", async (
            string type, Guid id, SharingService svc, HttpContext ctx, CancellationToken ct) =>
        {
            var card = await svc.FindAsync(type, id, ct);
            if (card is null)
            {
                return Results.NotFound();
            }

            ctx.Response.Headers.CacheControl = "no-store";
            return Results.Content(SharingService.RenderHtml(card, svc.PublicUrl(card.Type, card.Id)), "text/html; charset=utf-8");
        }).AllowAnonymous().ExcludeFromDescription();
    }
}
