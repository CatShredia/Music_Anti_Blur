namespace MusicAntiBlur.Api.Data.Entities;

/// <summary>Per-user override of the private upload quota. Null fields fall back to Storage options.</summary>
public sealed class UserQuota
{
    public Guid UserId { get; set; }
    public long? MaxBytes { get; set; }
    public int? MaxFiles { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public User? User { get; set; }
}
