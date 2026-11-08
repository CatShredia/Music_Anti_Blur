namespace MusicAntiBlur.Api.Auth;

public static class LoginNotice
{
    /// <summary>Short human label for a User-Agent: "Android", "Windows · Chrome", "Dart" and so on.</summary>
    public static string DescribeUserAgent(string? userAgent)
    {
        if (string.IsNullOrWhiteSpace(userAgent))
        {
            return "неизвестное устройство";
        }

        var ua = userAgent;
        string? os = null;
        if (ua.Contains("Android", StringComparison.OrdinalIgnoreCase)) os = "Android";
        else if (ua.Contains("iPhone", StringComparison.OrdinalIgnoreCase) || ua.Contains("iPad", StringComparison.OrdinalIgnoreCase)) os = "iOS";
        else if (ua.Contains("Windows", StringComparison.OrdinalIgnoreCase)) os = "Windows";
        else if (ua.Contains("Mac OS", StringComparison.OrdinalIgnoreCase)) os = "macOS";
        else if (ua.Contains("Linux", StringComparison.OrdinalIgnoreCase)) os = "Linux";

        string? app = null;
        if (ua.Contains("Edg/", StringComparison.Ordinal)) app = "Edge";
        else if (ua.Contains("Chrome/", StringComparison.Ordinal)) app = "Chrome";
        else if (ua.Contains("Firefox/", StringComparison.Ordinal)) app = "Firefox";
        else if (ua.Contains("Safari/", StringComparison.Ordinal)) app = "Safari";
        else if (ua.StartsWith("Dart/", StringComparison.Ordinal)) app = "приложение";
        else if (ua.StartsWith("MusicAntiBlur", StringComparison.OrdinalIgnoreCase)) app = "приложение";

        return (os, app) switch
        {
            (not null, not null) => $"{os} · {app}",
            (not null, null) => os,
            (null, not null) => app,
            _ => ua.Length > 60 ? ua[..60] : ua
        };
    }

    public static string DescribeMethod(string method) => method switch
    {
        "totp" => "пароль и код из приложения",
        "email" => "пароль и код из письма",
        "recovery" => "пароль и резервный код",
        _ => "пароль"
    };
}
