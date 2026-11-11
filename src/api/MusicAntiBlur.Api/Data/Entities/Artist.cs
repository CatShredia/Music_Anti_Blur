namespace MusicAntiBlur.Api.Data.Entities;

public sealed class Artist
{
    public Guid Id { get; set; }
    public string Name { get; set; } = "";
    public string SortName { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; }
    /// <summary>Мягкое удаление (каскад из админки); null — исполнитель активен.</summary>
    public DateTimeOffset? DeletedAt { get; set; }

    public ICollection<Album> Albums { get; set; } = new List<Album>();
    public ICollection<Track> Tracks { get; set; } = new List<Track>();
}
