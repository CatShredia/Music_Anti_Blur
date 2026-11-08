using System.Text.RegularExpressions;

namespace MusicAntiBlur.Api.Observability;

public static partial class LogRedaction
{
    /// <summary>Masks query parameters that may carry secrets (access_token for SignalR and so on).</summary>
    public static string QueryString(string? query) =>
        string.IsNullOrEmpty(query) ? "" : SecretParam().Replace(query, "$1=[redacted]");

    [GeneratedRegex(@"(access_token|token|code|password|signature|X-Amz-Signature|X-Amz-Credential)=[^&]*",
        RegexOptions.IgnoreCase)]
    private static partial Regex SecretParam();
}
