using System.Text;
using MusicAntiBlur.Api.Auth;
using MusicAntiBlur.Api.Uploads;
using Xunit;

namespace MusicAntiBlur.Api.Tests;

public sealed class TotpTests
{
    // RFC 6238 Appendix B, SHA1 secret; the last 6 of the 8-digit reference values.
    private static readonly byte[] RfcSecret = Encoding.ASCII.GetBytes("12345678901234567890");

    [Theory]
    [InlineData(59L, "287082")]
    [InlineData(1111111109L, "081804")]
    [InlineData(1111111111L, "050471")]
    [InlineData(1234567890L, "005924")]
    [InlineData(2000000000L, "279037")]
    public void Matches_rfc6238_vectors(long unixSeconds, string expected) =>
        Assert.Equal(expected, Totp.Compute(RfcSecret, unixSeconds / Totp.StepSeconds));

    [Fact]
    public void Accepts_previous_and_next_step_only()
    {
        var now = DateTimeOffset.FromUnixTimeSeconds(1_700_000_000);
        var step = Totp.StepAt(now);
        Assert.Equal(step - 1, Totp.Match(RfcSecret, Totp.Compute(RfcSecret, step - 1), now));
        Assert.Equal(step + 1, Totp.Match(RfcSecret, Totp.Compute(RfcSecret, step + 1), now));
        Assert.Null(Totp.Match(RfcSecret, Totp.Compute(RfcSecret, step - 2), now));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("12345")]
    [InlineData("abcdef")]
    [InlineData("1234567")]
    public void Rejects_malformed_codes(string? code) =>
        Assert.Null(Totp.Match(RfcSecret, code, DateTimeOffset.UtcNow));

    [Fact]
    public void Base32_matches_known_value_and_round_trips()
    {
        Assert.Equal("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", Base32.Encode(RfcSecret));
        var secret = Totp.NewSecret();
        Assert.Equal(secret, Base32.Decode(Base32.Encode(secret)));
        Assert.Equal(RfcSecret, Base32.Decode("gezd gnbv gy3t qojq gezd gnbv gy3t qojq"));
    }

    [Fact]
    public void Otpauth_uri_carries_secret_and_issuer()
    {
        var uri = Totp.OtpauthUri("ABC", "user@example.com");
        Assert.StartsWith("otpauth://totp/Music%20Anti%20Blur:user%40example.com?secret=ABC", uri);
        Assert.Contains("issuer=Music%20Anti%20Blur", uri);
    }
}

public sealed class RecoveryCodeTests
{
    [Fact]
    public void Code_has_two_groups_of_four()
    {
        var code = TwoFactorService.NewRecoveryCode();
        Assert.Matches("^[a-z2-9]{4}-[a-z2-9]{4}$", code);
    }

    [Theory]
    [InlineData("ABCD-EFGH", "abcdefgh")]
    [InlineData(" abcd efgh ", "abcdefgh")]
    [InlineData(null, "")]
    public void Normalization_ignores_case_dashes_and_spaces(string? raw, string expected) =>
        Assert.Equal(expected, TwoFactorService.NormalizeRecoveryCode(raw));
}

public sealed class QuotaTests
{
    [Theory]
    [InlineData(0L, 0, 100L, true)]
    [InlineData(900L, 0, 100L, true)]
    [InlineData(901L, 0, 100L, false)]
    [InlineData(0L, 4, 1L, true)]
    [InlineData(0L, 5, 1L, false)]
    public void Fits_checks_bytes_and_files(long usedBytes, int usedFiles, long size, bool expected) =>
        Assert.Equal(expected, QuotaService.Fits(new QuotaDto(usedBytes, 1000, usedFiles, 5), size));
}

public sealed class LoginEventTests
{
    [Fact]
    public void Cursor_round_trips()
    {
        var at = new DateTimeOffset(2026, 11, 3, 12, 0, 0, TimeSpan.Zero);
        var id = Guid.NewGuid();
        var decoded = LoginEventService.DecodeCursor(LoginEventService.EncodeCursor(at, id));
        Assert.Equal((at, id), decoded);
        Assert.Null(LoginEventService.DecodeCursor("not-a-cursor"));
    }

    [Theory]
    [InlineData("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/156.0 Safari/537.36", "Windows · Chrome")]
    [InlineData("Dart/3.9 (dart:io)", "приложение")]
    [InlineData("Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/156.0 Mobile Safari/537.36", "Android · Chrome")]
    [InlineData(null, "неизвестное устройство")]
    public void User_agent_is_described(string? ua, string expected) =>
        Assert.Equal(expected, LoginNotice.DescribeUserAgent(ua));
}
