namespace MusicAntiBlur.Api.Data.Entities;

public sealed class UserTwoFactor
{
    public Guid UserId { get; set; }

    /// <summary>TOTP secret protected with ASP.NET Data Protection. Null until TOTP is confirmed.</summary>
    public string? TotpSecretProtected { get; set; }
    public DateTimeOffset? TotpEnabledAt { get; set; }
    public bool EmailOtpEnabled { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public User? User { get; set; }
}
