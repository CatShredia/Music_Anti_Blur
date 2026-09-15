using MusicAntiBlur.Api.Playback;

namespace MusicAntiBlur.Api.Data.Entities;

public sealed class PlaybackState
{
    public Guid UserId { get; set; }
    public Guid? TrackId { get; set; }
    public int PositionMs { get; set; }
    public bool IsPlaying { get; set; }
    public string? QualityCode { get; set; }
    public string? Source { get; set; }
    public Guid? DeviceId { get; set; }
    public Guid? WriterSessionId { get; set; }
    public long Revision { get; set; }
    public string Queue { get; set; } = PlaybackQueue.EmptyJson;
    public DateTimeOffset UpdatedAt { get; set; }

    public User User { get; set; } = null!;
    public Track? Track { get; set; }
}
