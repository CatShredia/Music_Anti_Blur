namespace MusicAntiBlur.Api.Data.Entities;

public sealed class RefreshToken
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string TokenHash { get; set; } = "";
    public Guid DeviceId { get; set; }
    public Guid FamilyId { get; set; }
    public Guid? ParentTokenId { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
    public string? RevokeReason { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    public User? User { get; set; }
    public RefreshToken? Parent { get; set; }
}
