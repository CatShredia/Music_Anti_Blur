using System.Net.Mail;
using System.Text.RegularExpressions;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Auth;

public static class PasswordRules
{
    public const int MinLength = 12;
    public const int MaxLength = 128;

    private static readonly HashSet<string> Common = new(StringComparer.OrdinalIgnoreCase)
    {
        "password", "password123", "password1234", "123456789012", "1234567890123",
        "qwertyuiopas", "letmein12345", "adminpassword", "changeme1234", "iloveyou1234",
        "welcome12345", "monkey123456", "dragon123456", "master123456", "login1234567",
        "abc123456789", "passw0rd1234", "admin1234567", "rootpassword1"
    };

    private static readonly Regex LoginPattern = new("^[a-zA-Z0-9_.-]{3,32}$", RegexOptions.Compiled);

    public static void EnsurePassword(string password)
    {
        if (password.Length < MinLength || password.Length > MaxLength)
        {
            throw new ApiException(400, "validation_failed", "Password does not meet requirements.",
                new Dictionary<string, string[]> { ["password"] = ["Password must be 12 to 128 characters."] });
        }

        if (Common.Contains(password) || Common.Contains(password.Trim()))
        {
            throw new ApiException(400, "validation_failed", "Password does not meet requirements.",
                new Dictionary<string, string[]> { ["password"] = ["Password is too common."] });
        }
    }

    public static void EnsureLogin(string login)
    {
        if (!LoginPattern.IsMatch(login))
        {
            throw new ApiException(400, "validation_failed", "Login format is invalid.",
                new Dictionary<string, string[]> { ["identifier"] = ["Login must be 3-32 characters: letters, digits, _ . -"] });
        }
    }

    public static string NormalizeEmail(string email)
    {
        var normalized = email.Trim().ToLowerInvariant();
        try
        {
            _ = new MailAddress(normalized);
        }
        catch
        {
            throw new ApiException(400, "validation_failed", "Email format is invalid.",
                new Dictionary<string, string[]> { ["identifier"] = ["Email is invalid."] });
        }

        return normalized;
    }
}
