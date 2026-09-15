using MusicAntiBlur.Api.Hubs;
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
    }
}
