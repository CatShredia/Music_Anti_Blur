using System.Text.Json;

namespace MusicAntiBlur.Api.Media;

public sealed record ProbeResult(
    string FormatName,
    int DurationMs,
    int AudioStreamCount,
    string? AudioCodec,
    int? BitrateKbps,
    bool HasVideo);

public static class FfprobeParser
{
    /// <summary>Жанры из тега <c>genre</c> формата (имя тега без учёта регистра); пусто при любой ошибке разбора.</summary>
    public static IReadOnlyList<string> ExtractGenreTags(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("format", out var format) &&
                format.TryGetProperty("tags", out var tags) &&
                tags.ValueKind == JsonValueKind.Object)
            {
                foreach (var tag in tags.EnumerateObject())
                {
                    if (string.Equals(tag.Name, "genre", StringComparison.OrdinalIgnoreCase) &&
                        tag.Value.ValueKind == JsonValueKind.String)
                    {
                        return Catalog.GenreNames.ParseTag(tag.Value.GetString());
                    }
                }
            }
        }
        catch (JsonException)
        {
        }

        return [];
    }

    private static readonly HashSet<string> AllowedFormats =
    [
        "mp3", "mp4", "m4a", "mov", "aac", "flac", "ogg", "opus", "wav", "wave"
    ];

    public static ProbeResult Parse(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        var formatName = root.TryGetProperty("format", out var format)
            ? format.GetProperty("format_name").GetString() ?? ""
            : "";
        var durationMs = 0;
        if (format.ValueKind == JsonValueKind.Object &&
            format.TryGetProperty("duration", out var durationEl) &&
            double.TryParse(durationEl.GetString(), System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out var seconds) &&
            seconds > 0)
        {
            durationMs = Math.Max(1, (int)Math.Round(seconds * 1000));
        }

        var audioCount = 0;
        string? codec = null;
        int? bitrate = null;
        var hasVideo = false;
        if (root.TryGetProperty("streams", out var streams) && streams.ValueKind == JsonValueKind.Array)
        {
            foreach (var stream in streams.EnumerateArray())
            {
                var type = stream.TryGetProperty("codec_type", out var ct) ? ct.GetString() : null;
                if (type == "audio")
                {
                    audioCount++;
                    if (codec is null)
                    {
                        codec = stream.TryGetProperty("codec_name", out var cn) ? cn.GetString() : null;
                    }

                    if (bitrate is null && stream.TryGetProperty("bit_rate", out var br) &&
                        int.TryParse(br.GetString(), out var bps) && bps > 0)
                    {
                        bitrate = Math.Max(1, bps / 1000);
                    }
                }
                else if (type == "video")
                {
                    hasVideo = true;
                }
            }
        }

        return new ProbeResult(formatName, durationMs, audioCount, codec, bitrate, hasVideo);
    }

    public static bool IsAllowedContainer(ProbeResult probe)
    {
        var names = probe.FormatName.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        return names.Any(n => AllowedFormats.Contains(n.ToLowerInvariant()));
    }

    public static bool IsStreamableSource(ProbeResult probe)
    {
        var names = probe.FormatName.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Select(n => n.ToLowerInvariant())
            .ToHashSet();
        if (names.Contains("mp3"))
        {
            return true;
        }

        return names.Overlaps(["mp4", "m4a", "mov", "aac"]);
    }
}
