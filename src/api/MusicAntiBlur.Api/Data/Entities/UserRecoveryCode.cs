namespace MusicAntiBlur.Api.Data.Entities;

public sealed class UserRecoveryCode
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string CodeHash { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? UsedAt { get; set; }

    public User? User { get; set; }
}
