namespace MusicAntiBlur.Api.Data.Entities;

public sealed class ObjectDeletion
{
    public Guid Id { get; set; }
    public Guid? OwnerUserId { get; set; }
    public string BucketKey { get; set; } = "";
    public string Status { get; set; } = "pending";
    public int AttemptCount { get; set; }
    public DateTimeOffset NextAttemptAt { get; set; }
    public DateTimeOffset? LeaseExpiresAt { get; set; }
    public string? LastError { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset? CompletedAt { get; set; }

    public User? Owner { get; set; }
}
