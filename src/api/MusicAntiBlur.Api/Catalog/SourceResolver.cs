namespace MusicAntiBlur.Api.Catalog;

public sealed record SourceResolveResult(
    bool Ok,
    string? Chosen,
    string? FallbackReason,
    string? ErrorCode);

public static class SourceResolver
{
    public static SourceResolveResult Resolve(
        string preference,
        bool localAvailable,
        bool privateReady,
        bool catalogReady)
    {
        var pref = string.IsNullOrWhiteSpace(preference) ? "auto" : preference.Trim().ToLowerInvariant();
        return pref switch
        {
            "catalog" => catalogReady
                ? new SourceResolveResult(true, "catalog", null, null)
                : Unavailable(),
            "local" => PreferThenFallback("local", localAvailable, "local_unavailable", localAvailable, privateReady, catalogReady),
            "private" => PreferThenFallback("private", privateReady, "private_not_ready", localAvailable, privateReady, catalogReady),
            "auto" => Auto(localAvailable, privateReady, catalogReady),
            _ => Unavailable()
        };
    }

    private static SourceResolveResult Auto(bool localAvailable, bool privateReady, bool catalogReady)
    {
        if (localAvailable)
        {
            return new SourceResolveResult(true, "local", null, null);
        }

        if (privateReady)
        {
            return new SourceResolveResult(true, "private", null, null);
        }

        if (catalogReady)
        {
            return new SourceResolveResult(true, "catalog", null, null);
        }

        return Unavailable();
    }

    private static SourceResolveResult PreferThenFallback(
        string preferred,
        bool preferredReady,
        string reason,
        bool localAvailable,
        bool privateReady,
        bool catalogReady)
    {
        if (preferredReady)
        {
            return new SourceResolveResult(true, preferred, null, null);
        }

        if (preferred != "local" && localAvailable)
        {
            return new SourceResolveResult(true, "local", reason, null);
        }

        if (preferred != "private" && privateReady)
        {
            return new SourceResolveResult(true, "private", reason, null);
        }

        if (preferred != "catalog" && catalogReady)
        {
            return new SourceResolveResult(true, "catalog", reason, null);
        }

        return Unavailable();
    }

    private static SourceResolveResult Unavailable() =>
        new(false, null, null, "source_unavailable");
}
