using System.Security.Cryptography;
using System.Text;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Auth;

public static class TokenHasher
{
    public static string Hash(string value)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    public static string NewNumericCode()
    {
        return RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6");
    }

    public static void EnsureNumericCode(string? code)
    {
        if (code is null || code.Length != 6 || !code.All(char.IsAsciiDigit))
        {
            throw new ApiException(400, "validation_failed", "Code must be 6 digits.",
                new Dictionary<string, string[]> { ["code"] = ["Must be a 6-digit code."] });
        }
    }

    public static string NewOpaqueToken()
    {
        Span<byte> bytes = stackalloc byte[32];
        RandomNumberGenerator.Fill(bytes);
        return Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }
}
