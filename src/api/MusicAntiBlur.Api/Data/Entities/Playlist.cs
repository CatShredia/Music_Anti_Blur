namespace MusicAntiBlur.Api.Data.Entities;

public sealed class Playlist
{
    public const string KindLiked = "liked";
    public const string KindUser = "user";
    public const string LikedTitle = "Мне нравится";

    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Title { get; set; } = "";
    public string Kind { get; set; } = KindUser;
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }

    public User User { get; set; } = null!;
    public ICollection<PlaylistTrack> Tracks { get; set; } = new List<PlaylistTrack>();
}
