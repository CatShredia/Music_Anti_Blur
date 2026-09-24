namespace MusicAntiBlur.Api.Data.Entities;

public sealed class UserPlayHistory
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public Guid TrackId { get; set; }
    public DateTimeOffset PlayedAt { get; set; }

    public User User { get; set; } = null!;
    public Track Track { get; set; } = null!;
}
