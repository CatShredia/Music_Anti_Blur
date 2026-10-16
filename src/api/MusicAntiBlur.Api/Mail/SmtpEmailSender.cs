using MailKit.Net.Smtp;
using Microsoft.Extensions.Options;
using MimeKit;

namespace MusicAntiBlur.Api.Mail;

public sealed class SmtpEmailSender(IOptions<SmtpOptions> options, ILogger<SmtpEmailSender> logger)
{
    public async Task SendAsync(string to, string subject, string text, string html, CancellationToken ct)
    {
        var smtp = options.Value;
        var message = new MimeMessage();
        var from = smtp.EffectiveFrom;
        message.From.Add(string.IsNullOrWhiteSpace(smtp.FromName)
            ? MailboxAddress.Parse(from)
            : new MailboxAddress(smtp.FromName.Trim(), from));
        message.To.Add(MailboxAddress.Parse(to));
        message.Subject = subject;
        message.Body = new BodyBuilder { TextBody = text, HtmlBody = html }.ToMessageBody();

        using var client = new SmtpClient();
        await SmtpConnection.ConnectAsync(client, smtp, ct);
        await client.SendAsync(message, ct);
        await client.DisconnectAsync(true, ct);
        logger.LogInformation("Sent email {Subject}.", subject);
    }
}
