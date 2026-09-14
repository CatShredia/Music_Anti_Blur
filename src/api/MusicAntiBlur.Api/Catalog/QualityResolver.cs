namespace MusicAntiBlur.Api.Catalog;

public sealed record ReadyQuality(
    string Code,
    int BitrateKbps,
    Guid GenerationId,
    int DurationMs,
    string BucketKey);

public sealed record QualityResolveResult(
    bool Ok,
    string? ErrorCode,
    ReadyQuality? Chosen,
    string? QualityFallbackFrom);

public static class QualityResolver
{
    public static QualityResolveResult Resolve(IReadOnlyList<ReadyQuality> ready, string preference)
    {
        var map = ready
            .GroupBy(r => r.Code, StringComparer.Ordinal)
            .ToDictionary(g => g.Key, g => g.First(), StringComparer.Ordinal);

        var pref = string.IsNullOrWhiteSpace(preference) ? "auto" : preference.Trim().ToLowerInvariant();
        return pref switch
        {
            "auto" => ResolveAuto(map),
            "aac_256" => ResolvePreferred(map, "aac_256", allowDown: true),
            "aac_128" => ResolvePreferred(map, "aac_128", allowDown: false),
            "src" => ResolvePreferred(map, "src", allowDown: false),
            _ => new QualityResolveResult(false, "quality_unavailable", null, null)
        };
    }

    private static QualityResolveResult ResolveAuto(IReadOnlyDictionary<string, ReadyQuality> map)
    {
        if (map.TryGetValue("aac_256", out var high))
        {
            return new QualityResolveResult(true, null, high, null);
        }

        if (map.TryGetValue("aac_128", out var low))
        {
            return new QualityResolveResult(true, null, low, null);
        }

        return new QualityResolveResult(false, "source_unavailable", null, null);
    }

    private static QualityResolveResult ResolvePreferred(
        IReadOnlyDictionary<string, ReadyQuality> map, string code, bool allowDown)
    {
        if (map.TryGetValue(code, out var exact))
        {
            return new QualityResolveResult(true, null, exact, null);
        }

        if (allowDown && code == "aac_256" && map.TryGetValue("aac_128", out var down))
        {
            return new QualityResolveResult(true, null, down, "aac_256");
        }

        if (map.Count == 0)
        {
            return new QualityResolveResult(false, "source_unavailable", null, null);
        }

        return new QualityResolveResult(false, "quality_unavailable", null, null);
    }
}
