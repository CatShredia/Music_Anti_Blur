using System.Net;

namespace MusicAntiBlur.Api.Mail;

public static class MailLayout
{
    public static (string Text, string Html) Code(string title, string lead, string code)
    {
        var text = $"{title}\n\n{code}\n\n{lead}\n";
        var html = Frame(title, $"""
            <p style="margin:0 0 20px;color:#6CE4B4;font-size:15px;line-height:1.5;">{Encode(lead)}</p>
            <div style="font-size:32px;letter-spacing:0.28em;font-weight:700;color:#F4FBF7;background:#0B1310;border:1px solid #1A2E28;border-radius:12px;padding:16px;text-align:center;">{Encode(code)}</div>
            """);
        return (text, html);
    }

    public static (string Text, string Html) Notice(string title, string lead)
    {
        var text = $"{title}\n\n{lead}\n";
        var html = Frame(title, $"""
            <p style="margin:0;color:#F4FBF7;font-size:16px;line-height:1.5;">{Encode(lead)}</p>
            """);
        return (text, html);
    }

    private static string Frame(string title, string body) => $$"""
        <!DOCTYPE html>
        <html>
        <body style="margin:0;background:#050A08;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#050A08;padding:32px 16px;">
            <tr><td align="center">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#13211C;border:1px solid #1A2E28;border-radius:18px;">
                <tr><td style="padding:28px 24px;font-family:Segoe UI,Roboto,Arial,sans-serif;">
                  <div style="font-size:12px;letter-spacing:0.14em;color:#0CB880;font-weight:700;">MUSIC ANTI BLUR</div>
                  <h1 style="margin:16px 0 12px;font-size:22px;line-height:1.3;font-weight:700;color:#F4FBF7;">{{Encode(title)}}</h1>
                  {{body}}
                </td></tr>
              </table>
            </td></tr>
          </table>
        </body>
        </html>
        """;

    private static string Encode(string value) => WebUtility.HtmlEncode(value);
}
