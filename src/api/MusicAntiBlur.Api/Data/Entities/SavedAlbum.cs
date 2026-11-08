namespace MusicAntiBlur.Api.Data.Entities;

/// <summary>Альбом, добавленный в библиотеку пользователя.</summary>
public sealed class SavedAlbum
{
    public Guid UserId { get; set; }
    public Guid AlbumId { get; set; }
    public DateTimeOffset AddedAt { get; set; }

    public User User { get; set; } = null!;
    public Album Album { get; set; } = null!;
}
