using MusicAntiBlur.Api.Hubs;
using MusicAntiBlur.Api.Playback;
using Xunit;

namespace MusicAntiBlur.Api.Tests;

public sealed class PlaybackHubProtocolTests
{
    [Fact]
    public void Group_name_is_user_prefix_and_canonical_guid()
    {
        var id = Guid.Parse("AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA");
        Assert.Equal("user:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", PlaybackHubGroups.ForUser(id));
    }

    [Fact]
    public void Snapshot_event_name_matches_contract()
    {
        Assert.Equal("PlaybackSnapshot", PlaybackHubEvents.PlaybackSnapshot);
        Assert.Equal("DevicePresence", PlaybackHubEvents.DevicePresence);
        Assert.Equal("RenditionReady", PlaybackHubEvents.RenditionReady);
    }

    [Fact]
    public void Presence_redis_key_is_user_scoped()
    {
        var id = Guid.Parse("AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA");
        Assert.Equal("playback-presence:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", PlaybackPresenceStore.Key(id));
    }
}
