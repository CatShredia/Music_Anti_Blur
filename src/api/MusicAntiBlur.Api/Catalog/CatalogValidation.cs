using System.Text;
using MusicAntiBlur.Api.Auth;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Catalog;

public static class CatalogValidation
{
    public const int NameMin = 1;
    public const int NameMax = 200;
    public const int QueryMin = 2;
    public const int QueryMax = 100;
    public const int LimitDefault = 20;
    public const int LimitMin = 1;
    public const int LimitMax = 50;
    public const int YearMin = 1000;
    public const int YearMax = 9999;
    public const int CoverKeyMax = 512;
    public const int IsrcMax = 32;
    public const double SearchMinSimilarity = 0.1;

    public const string Required = AuthValidation.Required;
    public const string SearchQuery = "search_query";
    public const string LimitRange = "limit_range";
    public const string YearRange = "year_range";
    public const string TrackNumber = "track_number";
    public const string Duration = "duration";
    public const string NameLength = "name_length";
    public const string TitleLength = "title_length";
    public const string CoverKey = "cover_object_key";
    public const string CoverType = "cover_type";
    public const string FileTooLarge = "file_too_large";
    public const string IsrcFormat = "isrc_format";
    public const string IdentifierTaken = AuthValidation.IdentifierTaken;

    public static Dictionary<string, string[]> NewErrors() => AuthValidation.NewErrors();

    public static void Add(Dictionary<string, string[]> errors, string field, string code) =>
        AuthValidation.Add(errors, field, code);

    public static void ThrowIfAny(Dictionary<string, string[]> errors) =>
        AuthValidation.ThrowIfAny(errors);

    public static int ParseLimit(int? limit, Dictionary<string, string[]> errors)
    {
        var value = limit ?? LimitDefault;
        if (value < LimitMin || value > LimitMax)
        {
            Add(errors, "limit", LimitRange);
        }

        return value;
    }

    public static string ParseQuery(string? q, Dictionary<string, string[]> errors)
    {
        var trimmed = q?.Trim() ?? "";
        if (trimmed.Length == 0)
        {
            Add(errors, "q", Required);
            return trimmed;
        }

        if (trimmed.Length < QueryMin || trimmed.Length > QueryMax)
        {
            Add(errors, "q", SearchQuery);
        }

        return trimmed;
    }

    public static string? AddName(Dictionary<string, string[]> errors, string field, string? value)
    {
        var trimmed = value?.Trim() ?? "";
        if (trimmed.Length == 0)
        {
            Add(errors, field, Required);
            return null;
        }

        if (trimmed.Length < NameMin || trimmed.Length > NameMax)
        {
            Add(errors, field, field == "title" ? TitleLength : NameLength);
            return null;
        }

        return trimmed;
    }

    public static string SortName(string name, string? sortName)
    {
        var trimmed = sortName?.Trim() ?? "";
        return trimmed.Length == 0 ? name.ToLowerInvariant() : trimmed.ToLowerInvariant();
    }

    public static int? AddYear(Dictionary<string, string[]> errors, int? year)
    {
        if (year is null)
        {
            return null;
        }

        if (year < YearMin || year > YearMax)
        {
            Add(errors, "year", YearRange);
            return year;
        }

        return year;
    }

    public static string? AddCoverKey(Dictionary<string, string[]> errors, string? key)
    {
        if (key is null)
        {
            return null;
        }

        var trimmed = key.Trim();
        if (trimmed.Length == 0)
        {
            return null;
        }

        if (trimmed.Length > CoverKeyMax)
        {
            Add(errors, "coverObjectKey", CoverKey);
            return null;
        }

        return trimmed;
    }

    public static int? AddTrackNumber(Dictionary<string, string[]> errors, int? number)
    {
        if (number is null)
        {
            Add(errors, "trackNumber", Required);
            return null;
        }

        if (number < 1)
        {
            Add(errors, "trackNumber", TrackNumber);
            return number;
        }

        return number;
    }

    public static int? AddDuration(Dictionary<string, string[]> errors, int? durationMs)
    {
        if (durationMs is null)
        {
            return null;
        }

        if (durationMs <= 0)
        {
            Add(errors, "durationMs", Duration);
            return durationMs;
        }

        return durationMs;
    }

    public static string? AddIsrc(Dictionary<string, string[]> errors, string? isrc)
    {
        if (isrc is null)
        {
            return null;
        }

        var trimmed = isrc.Trim();
        if (trimmed.Length == 0)
        {
            return null;
        }

        if (trimmed.Length > IsrcMax || !trimmed.All(char.IsLetterOrDigit))
        {
            Add(errors, "isrc", IsrcFormat);
            return null;
        }

        return trimmed.ToUpperInvariant();
    }

    public static Guid AddRequiredId(Dictionary<string, string[]> errors, string field, Guid? id)
    {
        if (id is null || id == Guid.Empty)
        {
            Add(errors, field, Required);
            return Guid.Empty;
        }

        return id.Value;
    }

    public static string EscapeLike(string value)
    {
        var sb = new StringBuilder(value.Length);
        foreach (var ch in value)
        {
            if (ch is '%' or '_' or '\\')
            {
                sb.Append('\\');
            }

            sb.Append(ch);
        }

        return sb.ToString();
    }
}
