using System.Net.Mail;
using System.Text.RegularExpressions;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Auth;

public static class AuthValidation
{
    public const int LoginMin = 3;
    public const int LoginMax = 32;
    public const int PasswordMin = 12;
    public const int PasswordMax = 128;
    public const int EmailMin = 3;
    public const int EmailMax = 254;
    public const int CodeLength = 6;

    public const string Required = "required";
    public const string LoginFormat = "login_format";
    public const string EmailFormat = "email_format";
    public const string PasswordLength = "password_length";
    public const string PasswordCommon = "password_common";
    public const string CodeFormat = "code_format";
    public const string IdentifierType = "identifier_type";
    public const string PreferredQuality = "preferred_quality";
    public const string IdentifierTaken = "identifier_taken";

    public static readonly HashSet<string> Qualities = new(StringComparer.Ordinal)
    {
        "auto", "aac_128", "aac_256", "src"
    };

    private static readonly Regex LoginPattern = new(
        $"^[a-zA-Z0-9_.-]{{{LoginMin},{LoginMax}}}$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private static readonly HashSet<string> CommonPasswords = new(StringComparer.OrdinalIgnoreCase)
    {
        "password", "password123", "password1234", "123456789012", "1234567890123",
        "qwertyuiopas", "letmein12345", "adminpassword", "changeme1234", "iloveyou1234",
        "welcome12345", "monkey123456", "dragon123456", "master123456", "login1234567",
        "abc123456789", "passw0rd1234", "admin1234567", "rootpassword1"
    };

    public static Dictionary<string, string[]> NewErrors() =>
        new(StringComparer.Ordinal);

    public static void Add(Dictionary<string, string[]> errors, string field, string code)
    {
        if (errors.TryGetValue(field, out var existing))
        {
            if (!existing.Contains(code, StringComparer.Ordinal))
            {
                errors[field] = [.. existing, code];
            }

            return;
        }

        errors[field] = [code];
    }

    public static void ThrowIfAny(Dictionary<string, string[]> errors)
    {
        if (errors.Count > 0)
        {
            throw new ApiException(400, "validation_failed", "Validation failed.", errors);
        }
    }

    public static string? AddLogin(Dictionary<string, string[]> errors, string field, string? login)
    {
        var trimmed = login?.Trim() ?? "";
        if (trimmed.Length == 0)
        {
            Add(errors, field, Required);
            return null;
        }

        if (!LoginPattern.IsMatch(trimmed))
        {
            Add(errors, field, LoginFormat);
            return null;
        }

        return trimmed;
    }

    public static string? AddEmail(Dictionary<string, string[]> errors, string field, string? email)
    {
        var trimmed = email?.Trim() ?? "";
        if (trimmed.Length == 0)
        {
            Add(errors, field, Required);
            return null;
        }

        if (!TryNormalizeEmail(trimmed, out var normalized))
        {
            Add(errors, field, EmailFormat);
            return null;
        }

        return normalized;
    }

    public static void AddPassword(Dictionary<string, string[]> errors, string field, string? password)
    {
        if (password is null || password.Length == 0)
        {
            Add(errors, field, Required);
            return;
        }

        var runes = password.EnumerateRunes().Count();
        if (runes < PasswordMin || runes > PasswordMax)
        {
            Add(errors, field, PasswordLength);
        }

        if (CommonPasswords.Contains(password) || CommonPasswords.Contains(password.Trim()))
        {
            Add(errors, field, PasswordCommon);
        }
    }

    public static void AddCode(Dictionary<string, string[]> errors, string field, string? code)
    {
        var trimmed = code?.Trim() ?? "";
        if (trimmed.Length == 0)
        {
            Add(errors, field, Required);
            return;
        }

        if (trimmed.Length != CodeLength || !trimmed.All(char.IsAsciiDigit))
        {
            Add(errors, field, CodeFormat);
        }
    }

    public static string AddIdentifierType(Dictionary<string, string[]> errors, string? type)
    {
        if (type is "email" or "login")
        {
            return type;
        }

        Add(errors, "identifierType", IdentifierType);
        return "";
    }

    public static void AddPreferredQuality(Dictionary<string, string[]> errors, string? quality)
    {
        if (string.IsNullOrWhiteSpace(quality))
        {
            Add(errors, "preferredQuality", Required);
            return;
        }

        if (!Qualities.Contains(quality))
        {
            Add(errors, "preferredQuality", PreferredQuality);
        }
    }

    public static bool TryNormalizeEmail(string email, out string normalized)
    {
        normalized = email.Trim().ToLowerInvariant();
        if (normalized.Length < EmailMin || normalized.Length > EmailMax)
        {
            return false;
        }

        try
        {
            var at = normalized.IndexOf('@');
            if (at < 1 || normalized.IndexOf('.', at + 1) <= at)
            {
                return false;
            }

            var address = new MailAddress(normalized);
            return address.Address == normalized;
        }
        catch
        {
            return false;
        }
    }

    public static string RequireLogin(string? login)
    {
        var errors = NewErrors();
        var value = AddLogin(errors, "login", login);
        ThrowIfAny(errors);
        return value!;
    }

    public static string RequireEmail(string? email)
    {
        var errors = NewErrors();
        var value = AddEmail(errors, "email", email);
        ThrowIfAny(errors);
        return value!;
    }

    public static void EnsurePassword(string? password)
    {
        var errors = NewErrors();
        AddPassword(errors, "password", password);
        ThrowIfAny(errors);
    }

    public static void EnsureCode(string? code)
    {
        var errors = NewErrors();
        AddCode(errors, "code", code);
        ThrowIfAny(errors);
    }
}
