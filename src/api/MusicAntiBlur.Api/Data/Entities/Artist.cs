namespace MusicAntiBlur.Api.Data.Entities;

public sealed class Artist
{
    public Guid Id { get; set; }
    public string Name { get; set; } = "";
    public string SortName { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; }

    public ICollection<Album> Albums { get; set; } = new List<Album>();
    public ICollection<Track> Tracks { get; set; } = new List<Track>();
}
