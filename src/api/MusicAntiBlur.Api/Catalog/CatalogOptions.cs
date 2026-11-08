namespace MusicAntiBlur.Api.Catalog;

public sealed class CatalogOptions
{
    public const string Section = "Catalog";

    public int DeletedRetentionDays { get; set; } = 180;

    /// <summary>Множитель `rank` жанра в поиске: жанры идут после артистов, альбомов и треков.</summary>
    public double GenreRankFactor { get; set; } = 0.8;
}
