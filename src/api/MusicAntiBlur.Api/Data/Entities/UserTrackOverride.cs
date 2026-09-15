namespace MusicAntiBlur.Api.Data.Entities;

public sealed class UserTrackOverride
{
    public Guid UserId { get; set; }
    public Guid TrackId { get; set; }
    public string SourcePreference { get; set; } = "auto";
    public string? DisplayName { get; set; }
    public int? DurationMs { get; set; }
    public long? SizeBytes { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public User User { get; set; } = null!;
    public Track Track { get; set; } = null!;
    public ICollection<UserPrivateUpload> Uploads { get; set; } = new List<UserPrivateUpload>();
}
