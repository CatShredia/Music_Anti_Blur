namespace MusicAntiBlur.Api.Catalog;

/// <summary>Нормализация имён жанров и разбор тега <c>genre</c> из файла.</summary>
public static class GenreNames
{
    public const int NameMax = 60;
    public const int MaxPerEntity = 10;

    private static readonly char[] TagSeparators = [';', '/', ',', '\0'];

    /// <summary>Убирает крайние и повторные пробелы; <c>null</c>, если имя пустое или длиннее 60 символов.</summary>
    public static string? Clean(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return null;
        }

        var name = string.Join(' ', raw.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        return name.Length is >= 1 and <= NameMax ? name : null;
    }

    /// <summary>Ключ уникальности: имя без регистра и лишних пробелов.</summary>
    public static string Slug(string cleanName) => cleanName.ToLowerInvariant();

    /// <summary>
    /// Разбирает значение тега (`Rock; Alternative`, `Rock/Pop`): уникальные по ключу имена,
    /// пустые и слишком длинные отбрасываются, не больше <see cref="MaxPerEntity"/>.
    /// </summary>
    public static IReadOnlyList<string> ParseTag(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw))
        {
            return [];
        }

        var seen = new HashSet<string>();
        var result = new List<string>();
        foreach (var part in raw.Split(TagSeparators))
        {
            var name = Clean(part);
            if (name is not null && seen.Add(Slug(name)))
            {
                result.Add(name);
                if (result.Count == MaxPerEntity)
                {
                    break;
                }
            }
        }

        return result;
    }
}
