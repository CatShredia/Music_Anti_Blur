namespace MusicAntiBlur.Api.Data.Entities;

public sealed class Album
{
    public Guid Id { get; set; }
    public Guid ArtistId { get; set; }
    public string Title { get; set; } = "";
    public int? Year { get; set; }
    public string? CoverObjectKey { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    /// <summary>Мягкое удаление (каскад из админки); null — альбом активен.</summary>
    public DateTimeOffset? DeletedAt { get; set; }

    public Artist Artist { get; set; } = null!;
    public ICollection<Track> Tracks { get; set; } = new List<Track>();
}
