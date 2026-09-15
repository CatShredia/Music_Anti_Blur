using Microsoft.AspNetCore.SignalR;
using MusicAntiBlur.Api.Hubs;

namespace MusicAntiBlur.Api.Playback;

public interface IPlaybackHubPublisher
{
    Task PlaybackSnapshotAsync(Guid userId, PlaybackSnapshotDto snapshot, CancellationToken ct);
}

public sealed class PlaybackHubPublisher(IHubContext<PlaybackHub> hub) : IPlaybackHubPublisher
{
    public Task PlaybackSnapshotAsync(Guid userId, PlaybackSnapshotDto snapshot, CancellationToken ct) =>
        hub.Clients.Group(PlaybackHubGroups.ForUser(userId))
            .SendAsync(PlaybackHubEvents.PlaybackSnapshot, snapshot, cancellationToken: ct);
}
