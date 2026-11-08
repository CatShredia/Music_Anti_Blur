namespace MusicAntiBlur.Api.Data.Entities;

/// <summary>Чужой публичный плейлист, добавленный в библиотеку пользователя (ссылка, не копия).</summary>
public sealed class SavedPlaylist
{
    public Guid UserId { get; set; }
    public Guid PlaylistId { get; set; }
    public DateTimeOffset AddedAt { get; set; }

    public User User { get; set; } = null!;
    public Playlist Playlist { get; set; } = null!;
}
