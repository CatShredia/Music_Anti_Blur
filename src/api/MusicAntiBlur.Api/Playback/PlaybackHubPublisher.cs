using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging;
using MusicAntiBlur.Api.Hubs;

namespace MusicAntiBlur.Api.Playback;

public interface IPlaybackHubPublisher
{
    Task PlaybackSnapshotAsync(Guid userId, PlaybackSnapshotDto snapshot, CancellationToken ct);
    Task DevicePresenceAsync(Guid userId, DevicePresenceDto presence, CancellationToken ct);
    Task RenditionReadyAsync(Guid userId, RenditionReadyDto ready, CancellationToken ct);
}

public sealed class PlaybackHubPublisher(IHubContext<PlaybackHub> hub, ILogger<PlaybackHubPublisher> logger)
    : IPlaybackHubPublisher
{
    public Task PlaybackSnapshotAsync(Guid userId, PlaybackSnapshotDto snapshot, CancellationToken ct) =>
        SendAsync(userId, PlaybackHubEvents.PlaybackSnapshot, snapshot, ct);

    public Task DevicePresenceAsync(Guid userId, DevicePresenceDto presence, CancellationToken ct) =>
        SendAsync(userId, PlaybackHubEvents.DevicePresence, presence, ct);

    public Task RenditionReadyAsync(Guid userId, RenditionReadyDto ready, CancellationToken ct) =>
        SendAsync(userId, PlaybackHubEvents.RenditionReady, ready, ct);

    private async Task SendAsync(Guid userId, string eventName, object payload, CancellationToken ct)
    {
        var group = PlaybackHubGroups.ForUser(userId);
        logger.LogInformation(
            "[sync] broadcast event={Event} group={Group} user={UserId} {Detail}",
            eventName,
            group,
            userId,
            payload is PlaybackSnapshotDto snap
                ? $"rev={snap.Revision} device={snap.DeviceId} track={snap.TrackId} playing={snap.IsPlaying} posMs={snap.PositionMs}"
                : payload is DevicePresenceDto presence
                    ? $"devices={presence.Devices.Count}"
                    : payload.GetType().Name);
        await hub.Clients.Group(group).SendAsync(eventName, payload, cancellationToken: ct);
    }
}
