namespace MusicAntiBlur.Api.Data.Entities;

public sealed class IdempotencyRecord
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Route { get; set; } = "";
    public Guid IdempotencyKey { get; set; }
    public string RequestHash { get; set; } = "";
    public int ResponseStatus { get; set; }
    public string? ResponseBody { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }

    public User User { get; set; } = null!;
}
