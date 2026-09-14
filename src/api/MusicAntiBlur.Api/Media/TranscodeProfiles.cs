namespace MusicAntiBlur.Api.Media;

public sealed record TranscodeProfile(string Code, int BitrateKbps, string ContentType, string FileName);

public static class TranscodeProfiles
{
    public static readonly TranscodeProfile Aac128 = new("aac_128", 128, "audio/mp4", "aac_128.m4a");
    public static readonly TranscodeProfile Aac256 = new("aac_256", 256, "audio/mp4", "aac_256.m4a");

    public static IReadOnlyList<TranscodeProfile> CatalogEncode { get; } = [Aac128, Aac256];

    public static string[] FfprobeArgs(string inputPath) =>
    [
        "-v", "error",
        "-print_format", "json",
        "-show_format",
        "-show_streams",
        inputPath
    ];

    public static string[] EncodeArgs(string inputPath, string outputPath, TranscodeProfile profile) =>
    [
        "-y",
        "-i", inputPath,
        "-map", "0:a:0",
        "-vn",
        "-c:a", "aac",
        "-b:a", $"{profile.BitrateKbps}k",
        "-ac", "2",
        "-ar", "44100",
        "-movflags", "+faststart",
        outputPath
    ];
}
