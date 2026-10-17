namespace MusicAntiBlur.Api.Data.Entities;

public sealed class LikedTrack
{
    public Guid UserId { get; set; }
    public Guid TrackId { get; set; }
    public DateTimeOffset LikedAt { get; set; }

    public User User { get; set; } = null!;
    public Track Track { get; set; } = null!;
}
