namespace MusicAntiBlur.Api.Library;

public sealed class SharingOptions
{
    public const string Section = "Sharing";

    /// <summary>Внешний адрес API для https-ссылок. Пусто — берётся из запроса.</summary>
    public string PublicBaseUrl { get; set; } = "";
}
