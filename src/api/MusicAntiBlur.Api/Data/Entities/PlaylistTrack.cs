namespace MusicAntiBlur.Api.Data.Entities;

public sealed class PlaylistTrack
{
    public Guid PlaylistId { get; set; }
    public Guid TrackId { get; set; }
    public int Position { get; set; }
    public DateTimeOffset AddedAt { get; set; }

    public Playlist Playlist { get; set; } = null!;
    public Track Track { get; set; } = null!;
}
