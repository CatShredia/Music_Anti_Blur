namespace MusicAntiBlur.Api.Data.Entities;

public sealed class Track
{
    public Guid Id { get; set; }
    public Guid AlbumId { get; set; }
    public Guid ArtistId { get; set; }
    public string Title { get; set; } = "";
    public int TrackNumber { get; set; }
    public int? DurationMs { get; set; }
    public string? Isrc { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public Album Album { get; set; } = null!;
    public Artist Artist { get; set; } = null!;
}
