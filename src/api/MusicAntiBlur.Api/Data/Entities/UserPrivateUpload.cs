namespace MusicAntiBlur.Api.Data.Entities;

public sealed class UserPrivateUpload
{
    public Guid GenerationId { get; set; }
    public Guid UserId { get; set; }
    public Guid TrackId { get; set; }
    public string Status { get; set; } = "initiated";
    public bool IsActive { get; set; }
    public string? MultipartUploadId { get; set; }
    public string SourceBucketKey { get; set; } = "";
    public string ExpectedChecksumSha256 { get; set; } = "";
    public string? ComputedChecksumSha256 { get; set; }
    public long? SizeBytes { get; set; }
    public int? DurationMs { get; set; }
    public DateTimeOffset? LeaseExpiresAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public UserTrackOverride Override { get; set; } = null!;
    public ICollection<UserPrivateRendition> Renditions { get; set; } = new List<UserPrivateRendition>();
}
