namespace MusicAntiBlur.Api.Data.Entities;

public sealed class UserSettings
{
    public Guid UserId { get; set; }
    public string PreferredQuality { get; set; } = "auto";
    public DateTimeOffset UpdatedAt { get; set; }
    public User? User { get; set; }
}
