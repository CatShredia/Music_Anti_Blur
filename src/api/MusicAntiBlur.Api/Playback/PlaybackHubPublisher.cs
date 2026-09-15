using Microsoft.AspNetCore.SignalR;
using MusicAntiBlur.Api.Hubs;

namespace MusicAntiBlur.Api.Playback;

public interface IPlaybackHubPublisher
{
    Task PlaybackSnapshotAsync(Guid userId, PlaybackSnapshotDto snapshot, CancellationToken ct);
    Task DevicePresenceAsync(Guid userId, DevicePresenceDto presence, CancellationToken ct);
    Task RenditionReadyAsync(Guid userId, RenditionReadyDto ready, CancellationToken ct);
}

public sealed class PlaybackHubPublisher(IHubContext<PlaybackHub> hub) : IPlaybackHubPublisher
{
    public Task PlaybackSnapshotAsync(Guid userId, PlaybackSnapshotDto snapshot, CancellationToken ct) =>
        SendAsync(userId, PlaybackHubEvents.PlaybackSnapshot, snapshot, ct);

    public Task DevicePresenceAsync(Guid userId, DevicePresenceDto presence, CancellationToken ct) =>
        SendAsync(userId, PlaybackHubEvents.DevicePresence, presence, ct);

    public Task RenditionReadyAsync(Guid userId, RenditionReadyDto ready, CancellationToken ct) =>
        SendAsync(userId, PlaybackHubEvents.RenditionReady, ready, ct);

    private Task SendAsync(Guid userId, string eventName, object payload, CancellationToken ct) =>
        hub.Clients.Group(PlaybackHubGroups.ForUser(userId))
            .SendAsync(eventName, payload, cancellationToken: ct);
}
