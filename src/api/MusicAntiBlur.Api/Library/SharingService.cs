using System.Net;
using System.Text;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;

namespace MusicAntiBlur.Api.Library;

/// <summary>Публичные карточки для ссылок: трек, альбом, публичный плейлист.</summary>
public sealed class SharingService(
    AppDbContext db,
    CatalogService catalog,
    IOptions<SharingOptions> options,
    IHttpContextAccessor http)
{
    public const string TypeTrack = "track";
    public const string TypeAlbum = "album";
    public const string TypePlaylist = "playlist";
    public const string AppScheme = "musicantiblur";

    public sealed record ShareCard(string Type, Guid Id, string Title, string Subtitle, string? ImageUrl);

    /// <summary>Карточка или null: несуществующее, удалённое и приватное неотличимы (404).</summary>
    public async Task<ShareCard?> FindAsync(string type, Guid id, CancellationToken ct)
    {
        switch (type)
        {
            case TypeTrack:
            {
                var t = await db.Tracks.AsNoTracking()
                    .Where(x => x.Id == id)
                    .Select(x => new { x.Title, Artist = x.Artist.Name, Album = x.Album.Title, x.Album.CoverObjectKey })
                    .FirstOrDefaultAsync(ct);
                return t is null
                    ? null
                    : new ShareCard(type, id, t.Title, $"{t.Artist} · {t.Album}", catalog.SignCover(t.CoverObjectKey).Url);
            }
            case TypeAlbum:
            {
                var a = await db.Albums.AsNoTracking()
                    .Where(x => x.Id == id)
                    .Select(x => new { x.Title, x.Year, Artist = x.Artist.Name, x.CoverObjectKey })
                    .FirstOrDefaultAsync(ct);
                return a is null
                    ? null
                    : new ShareCard(type, id, a.Title,
                        a.Year is { } y ? $"{a.Artist} · {y}" : a.Artist,
                        catalog.SignCover(a.CoverObjectKey).Url);
            }
            case TypePlaylist:
            {
                var p = await db.Playlists.AsNoTracking()
                    .Where(x => x.Id == id && x.IsPublic && x.Kind == Playlist.KindUser)
                    .Select(x => new { x.Title, x.Description, Owner = x.User.Login ?? x.User.Email })
                    .FirstOrDefaultAsync(ct);
                if (p is null)
                {
                    return null;
                }

                var keys = await db.PlaylistTracks.AsNoTracking()
                    .Where(x => x.PlaylistId == id && db.Tracks.Any(t => t.Id == x.TrackId))
                    .OrderBy(x => x.Position)
                    .Select(x => x.Track.Album.CoverObjectKey)
                    .Take(1)
                    .ToListAsync(ct);
                var owner = PlaylistService.OwnerDisplayName(p.Owner);
                var subtitle = string.IsNullOrWhiteSpace(p.Description)
                    ? (owner is null ? "Плейлист" : $"Плейлист · {owner}")
                    : p.Description;
                return new ShareCard(type, id, p.Title, subtitle, catalog.SignCover(keys.FirstOrDefault()).Url);
            }
            default:
                return null;
        }
    }

    public string PublicUrl(string type, Guid id)
    {
        var configured = options.Value.PublicBaseUrl.Trim().TrimEnd('/');
        var request = http.HttpContext?.Request;
        var baseUrl = configured.Length > 0
            ? configured
            : request is null ? "" : $"{request.Scheme}://{request.Host}";
        return $"{baseUrl}/s/{type}/{id}";
    }

    public static string AppLink(string type, Guid id) => $"{AppScheme}://app/{type}/{id}";

    /// <summary>HTML с Open Graph; все пользовательские значения экранируются.</summary>
    public static string RenderHtml(ShareCard card, string publicUrl)
    {
        static string E(string? s) => WebUtility.HtmlEncode(s ?? "");
        var app = AppLink(card.Type, card.Id);
        var ogType = card.Type switch
        {
            TypeTrack => "music.song",
            TypeAlbum => "music.album",
            _ => "music.playlist"
        };

        var sb = new StringBuilder();
        sb.Append("<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\">");
        sb.Append("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">");
        sb.Append($"<title>{E(card.Title)} · Music Anti Blur</title>");
        sb.Append("<meta name=\"robots\" content=\"noindex\">");
        sb.Append("<meta property=\"og:site_name\" content=\"Music Anti Blur\">");
        sb.Append($"<meta property=\"og:type\" content=\"{ogType}\">");
        sb.Append($"<meta property=\"og:title\" content=\"{E(card.Title)}\">");
        sb.Append($"<meta property=\"og:description\" content=\"{E(card.Subtitle)}\">");
        sb.Append($"<meta property=\"og:url\" content=\"{E(publicUrl)}\">");
        if (!string.IsNullOrEmpty(card.ImageUrl))
        {
            sb.Append($"<meta property=\"og:image\" content=\"{E(card.ImageUrl)}\">");
            sb.Append("<meta name=\"twitter:card\" content=\"summary_large_image\">");
        }

        sb.Append("<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#040807;color:#e8f5ee;font-family:system-ui,sans-serif}");
        sb.Append("main{max-width:360px;padding:24px;text-align:center}img{width:240px;height:240px;object-fit:cover;border-radius:12px}");
        sb.Append("h1{font-size:22px;margin:16px 0 4px}p{color:#8fb5a2;margin:0 0 24px}");
        sb.Append("a{display:inline-block;padding:12px 28px;border-radius:999px;background:#18d98f;color:#04120c;text-decoration:none;font-weight:600}</style>");
        sb.Append("</head><body><main>");
        if (!string.IsNullOrEmpty(card.ImageUrl))
        {
            sb.Append($"<img src=\"{E(card.ImageUrl)}\" alt=\"\">");
        }

        sb.Append($"<h1>{E(card.Title)}</h1><p>{E(card.Subtitle)}</p>");
        sb.Append($"<a href=\"{E(app)}\">Открыть в приложении</a>");
        sb.Append("</main></body></html>");
        return sb.ToString();
    }
}
