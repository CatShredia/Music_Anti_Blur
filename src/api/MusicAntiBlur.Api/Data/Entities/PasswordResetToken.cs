namespace MusicAntiBlur.Api.Data.Entities;

public sealed class PasswordResetToken
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string TokenHash { get; set; } = "";
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? UsedAt { get; set; }
    public DateTimeOffset? InvalidatedAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User? User { get; set; }
}
