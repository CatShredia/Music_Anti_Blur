namespace MusicAntiBlur.Api.Data.Entities;

/// <summary>Жанр справочника. <c>Slug</c> — нормализованное имя (без регистра и лишних пробелов), уникален.</summary>
public sealed class Genre
{
    public Guid Id { get; set; }
    public string Name { get; set; } = "";
    public string Slug { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; }
}
