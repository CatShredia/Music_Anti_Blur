using System.Security.Cryptography;
using System.Text;

namespace MusicAntiBlur.Api.Auth;

/// <summary>RFC 6238 TOTP: HMAC-SHA1, 6 digits, 30-second step.</summary>
public static class Totp
{
    public const int Digits = 6;
    public const int StepSeconds = 30;
    public const string Issuer = "Music Anti Blur";

    public static byte[] NewSecret() => RandomNumberGenerator.GetBytes(20);

    public static long StepAt(DateTimeOffset at) => at.ToUnixTimeSeconds() / StepSeconds;

    public static string Compute(byte[] secret, long step)
    {
        Span<byte> counter = stackalloc byte[8];
        for (var i = 7; i >= 0; i--)
        {
            counter[i] = (byte)(step & 0xff);
            step >>= 8;
        }

        Span<byte> hash = stackalloc byte[20];
        HMACSHA1.HashData(secret, counter, hash);
        var offset = hash[^1] & 0x0f;
        var binary = ((hash[offset] & 0x7f) << 24)
                     | (hash[offset + 1] << 16)
                     | (hash[offset + 2] << 8)
                     | hash[offset + 3];
        return (binary % 1_000_000).ToString("D6");
    }

    /// <summary>
    /// Returns the matched step within ±<paramref name="window"/> steps, or null.
    /// The caller rejects steps that are not greater than the last accepted one (replay).
    /// </summary>
    public static long? Match(byte[] secret, string? code, DateTimeOffset now, int window = 1)
    {
        if (code is null)
        {
            return null;
        }

        code = code.Trim().Replace(" ", "");
        if (code.Length != Digits || !code.All(char.IsAsciiDigit))
        {
            return null;
        }

        var current = StepAt(now);
        var given = Encoding.ASCII.GetBytes(code);
        for (var delta = -window; delta <= window; delta++)
        {
            var step = current + delta;
            var expected = Encoding.ASCII.GetBytes(Compute(secret, step));
            if (CryptographicOperations.FixedTimeEquals(given, expected))
            {
                return step;
            }
        }

        return null;
    }

    public static string OtpauthUri(string base32Secret, string account) =>
        $"otpauth://totp/{Uri.EscapeDataString(Issuer)}:{Uri.EscapeDataString(account)}" +
        $"?secret={base32Secret}&issuer={Uri.EscapeDataString(Issuer)}&algorithm=SHA1&digits={Digits}&period={StepSeconds}";
}

public static class Base32
{
    private const string Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

    public static string Encode(ReadOnlySpan<byte> data)
    {
        var sb = new StringBuilder((data.Length * 8 + 4) / 5);
        int buffer = 0, bits = 0;
        foreach (var b in data)
        {
            buffer = (buffer << 8) | b;
            bits += 8;
            while (bits >= 5)
            {
                sb.Append(Alphabet[(buffer >> (bits - 5)) & 31]);
                bits -= 5;
            }
        }

        if (bits > 0)
        {
            sb.Append(Alphabet[(buffer << (5 - bits)) & 31]);
        }

        return sb.ToString();
    }

    public static byte[] Decode(string text)
    {
        var clean = text.Trim().TrimEnd('=').Replace(" ", "").ToUpperInvariant();
        var output = new List<byte>(clean.Length * 5 / 8);
        int buffer = 0, bits = 0;
        foreach (var c in clean)
        {
            var value = Alphabet.IndexOf(c);
            if (value < 0)
            {
                throw new FormatException("Invalid base32 character.");
            }

            buffer = (buffer << 5) | value;
            bits += 5;
            if (bits >= 8)
            {
                output.Add((byte)((buffer >> (bits - 8)) & 0xff));
                bits -= 8;
            }
        }

        return output.ToArray();
    }
}
