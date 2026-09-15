namespace MusicAntiBlur.Api.Data.Entities;

public sealed class UserPrivateRendition
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public Guid TrackId { get; set; }
    public Guid GenerationId { get; set; }
    public string ProfileCode { get; set; } = "";
    public string Status { get; set; } = "pending";
    public string? BucketKey { get; set; }
    public string? ContentType { get; set; }
    public int? BitrateKbps { get; set; }
    public long? SizeBytes { get; set; }
    public int? DurationMs { get; set; }
    public string? ErrorMessage { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public UserPrivateUpload Upload { get; set; } = null!;
}
