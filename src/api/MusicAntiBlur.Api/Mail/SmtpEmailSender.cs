using MailKit.Net.Smtp;
using MimeKit;

namespace MusicAntiBlur.Api.Mail;

public sealed class SmtpEmailSender(IConfiguration config, ILogger<SmtpEmailSender> logger)
{
    public async Task SendAsync(string to, string subject, string body, CancellationToken ct)
    {
        var message = new MimeMessage();
        message.From.Add(MailboxAddress.Parse(config["Smtp:From"] ?? "noreply@localhost"));
        message.To.Add(MailboxAddress.Parse(to));
        message.Subject = subject;
        message.Body = new TextPart("plain") { Text = body };

        using var client = new SmtpClient();
        var host = config["Smtp:Host"] ?? "localhost";
        var port = int.Parse(config["Smtp:Port"] ?? "1025");
        await client.ConnectAsync(host, port, MailKit.Security.SecureSocketOptions.None, ct);
        await client.SendAsync(message, ct);
        await client.DisconnectAsync(true, ct);
        logger.LogInformation("Queued email {Subject} to recipient (redacted).", subject);
    }
}
