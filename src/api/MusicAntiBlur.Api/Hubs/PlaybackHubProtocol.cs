namespace MusicAntiBlur.Api.Hubs;

public static class PlaybackHubGroups
{
    public static string ForUser(Guid userId) => $"user:{userId:D}";
}

public static class PlaybackHubEvents
{
    public const string PlaybackSnapshot = "PlaybackSnapshot";
    public const string DevicePresence = "DevicePresence";
    public const string RenditionReady = "RenditionReady";
}
