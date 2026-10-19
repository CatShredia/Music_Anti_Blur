using MailKit.Net.Smtp;
using MailKit.Security;

namespace MusicAntiBlur.Api.Mail;

public sealed class SmtpOptions
{
    public const string Section = "Smtp";

    public string Host { get; set; } = "localhost";
    public int Port { get; set; } = 1025;
    public string From { get; set; } = "";
    public string FromName { get; set; } = "";
    public string User { get; set; } = "";
    public string Password { get; set; } = "";
    public string Security { get; set; } = "None";

    public string EffectiveFrom =>
        !string.IsNullOrWhiteSpace(From) ? From.Trim()
        : RequiresAuth ? User.Trim()
        : "noreply@localhost";

    public bool RequiresAuth => !string.IsNullOrWhiteSpace(User);

    public static SecureSocketOptions ParseSecurity(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Equals("None", StringComparison.OrdinalIgnoreCase))
        {
            return SecureSocketOptions.None;
        }

        if (value.Equals("StartTls", StringComparison.OrdinalIgnoreCase))
        {
            return SecureSocketOptions.StartTls;
        }

        if (value.Equals("SslOnConnect", StringComparison.OrdinalIgnoreCase))
        {
            return SecureSocketOptions.SslOnConnect;
        }

        throw new InvalidOperationException("Smtp:Security must be None, StartTls, or SslOnConnect.");
    }
}

public static class SmtpConnection
{
    public static async Task ConnectAsync(SmtpClient client, SmtpOptions options, CancellationToken ct)
    {
        var host = string.IsNullOrWhiteSpace(options.Host) ? "localhost" : options.Host.Trim();
        var port = options.Port > 0 ? options.Port : 1025;
        await client.ConnectAsync(host, port, SmtpOptions.ParseSecurity(options.Security), ct);
        if (options.RequiresAuth)
        {
            await client.AuthenticateAsync(options.User.Trim(), options.Password ?? "", ct);
        }
    }
}
