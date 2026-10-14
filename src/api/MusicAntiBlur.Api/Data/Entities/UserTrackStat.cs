namespace MusicAntiBlur.Api.Data.Entities;

public sealed class UserTrackStat
{
    public Guid UserId { get; set; }
    public Guid TrackId { get; set; }
    public int PlayCount { get; set; }
    public DateTimeOffset LastPlayedAt { get; set; }

    public User User { get; set; } = null!;
    public Track Track { get; set; } = null!;
}
