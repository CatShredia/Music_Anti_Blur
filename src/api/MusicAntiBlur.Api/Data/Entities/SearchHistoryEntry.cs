namespace MusicAntiBlur.Api.Data.Entities;

/// <summary>Запрос в истории поиска пользователя; <c>Normalized</c> — ключ без регистра для поднятия повторов.</summary>
public sealed class SearchHistoryEntry
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Query { get; set; } = "";
    public string Normalized { get; set; } = "";
    public DateTimeOffset SearchedAt { get; set; }

    public User User { get; set; } = null!;
}
