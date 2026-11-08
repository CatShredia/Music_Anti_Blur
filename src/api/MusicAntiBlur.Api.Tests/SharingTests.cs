using MusicAntiBlur.Api.Library;
using Xunit;

namespace MusicAntiBlur.Api.Tests;

public class SharingTests
{
    [Fact]
    public void App_link_uses_custom_scheme()
    {
        var id = Guid.NewGuid();

        Assert.Equal($"musicantiblur://app/playlist/{id}", SharingService.AppLink("playlist", id));
    }

    [Fact]
    public void Html_escapes_user_values()
    {
        var card = new SharingService.ShareCard(
            "playlist", Guid.NewGuid(), "<script>alert(1)</script>", "a\"b & c", "https://x/y?a=1&b=2");

        var html = SharingService.RenderHtml(card, "https://api/s/playlist/1");

        Assert.DoesNotContain("<script>", html);
        Assert.Contains("&lt;script&gt;", html);
        Assert.Contains("a&quot;b &amp; c", html);
        Assert.Contains("a=1&amp;b=2", html);
    }

    [Fact]
    public void Html_has_open_graph_and_open_in_app_link()
    {
        var id = Guid.NewGuid();
        var card = new SharingService.ShareCard("album", id, "Meteora", "Linkin Park · 2003", "https://cdn/cover.jpg");

        var html = SharingService.RenderHtml(card, "https://api/s/album/" + id);

        Assert.Contains("property=\"og:title\" content=\"Meteora\"", html);
        Assert.Contains("property=\"og:type\" content=\"music.album\"", html);
        Assert.Contains("property=\"og:image\" content=\"https://cdn/cover.jpg\"", html);
        Assert.Contains($"href=\"musicantiblur://app/album/{id}\"", html);
    }

    [Fact]
    public void Html_without_cover_has_no_image_tags()
    {
        var card = new SharingService.ShareCard("track", Guid.NewGuid(), "T", "S", null);

        var html = SharingService.RenderHtml(card, "https://api/s/track/1");

        Assert.DoesNotContain("og:image", html);
        Assert.DoesNotContain("<img", html);
    }
}
