namespace MusicAntiBlur.Api.Library;

public sealed class LibraryOptions
{
    public const string Section = "Library";

    public int MaxPlaylists { get; set; } = 100;
    public int MaxTracksPerPlaylist { get; set; } = 1000;
    public int SearchHistoryMax { get; set; } = 50;
}
