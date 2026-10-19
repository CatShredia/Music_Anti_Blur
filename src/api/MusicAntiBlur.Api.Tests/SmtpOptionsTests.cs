using MusicAntiBlur.Api.Mail;
using Xunit;

namespace MusicAntiBlur.Api.Tests;

public sealed class SmtpOptionsTests
{
    [Theory]
    [InlineData(null, "None")]
    [InlineData("", "None")]
    [InlineData("none", "None")]
    [InlineData("StartTls", "StartTls")]
    [InlineData("starttls", "StartTls")]
    [InlineData("SslOnConnect", "SslOnConnect")]
    public void ParseSecurity_known_values(string? raw, string expected)
    {
        Assert.Equal(expected, SmtpOptions.ParseSecurity(raw).ToString());
    }

    [Fact]
    public void ParseSecurity_rejects_unknown()
    {
        Assert.Throws<InvalidOperationException>(() => SmtpOptions.ParseSecurity("tls"));
    }

    [Fact]
    public void Auth_only_when_user_set_and_from_falls_back_to_user()
    {
        var open = new SmtpOptions();
        Assert.False(open.RequiresAuth);
        Assert.Equal("noreply@localhost", open.EffectiveFrom);

        var personal = new SmtpOptions { User = " owner@yandex.ru ", Password = "app" };
        Assert.True(personal.RequiresAuth);
        Assert.Equal("owner@yandex.ru", personal.EffectiveFrom);

        var relay = new SmtpOptions { User = "relay", From = "noreply@example.com" };
        Assert.True(relay.RequiresAuth);
        Assert.Equal("noreply@example.com", relay.EffectiveFrom);
    }
}
