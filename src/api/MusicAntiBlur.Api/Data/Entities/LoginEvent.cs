namespace MusicAntiBlur.Api.Data.Entities;

public sealed class LoginEvent
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public Guid? DeviceId { get; set; }
    public DateTimeOffset At { get; set; }
    public string Ip { get; set; } = "";
    public string? UserAgent { get; set; }

    /// <summary>success | bad_password | 2fa_required | 2fa_failed | refresh_reuse</summary>
    public string Result { get; set; } = "";

    /// <summary>password | totp | email | recovery | refresh</summary>
    public string Method { get; set; } = "";

    public DateTimeOffset? NotMeAt { get; set; }

    public User? User { get; set; }
}
