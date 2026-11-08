namespace MusicAntiBlur.Api.Catalog;

public sealed class CatalogOptions
{
    public const string Section = "Catalog";

    public int DeletedRetentionDays { get; set; } = 180;
}
