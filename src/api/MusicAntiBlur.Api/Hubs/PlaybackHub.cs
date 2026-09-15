using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using MusicAntiBlur.Api.Playback;
using MusicAntiBlur.Api.RateLimiting;
using StackExchange.Redis;

namespace MusicAntiBlur.Api.Hubs;

[Authorize]
public sealed class PlaybackHub(
    RedisRateLimiter limiter,
    IConnectionMultiplexer redis,
    PlaybackPresenceStore presence,
    IPlaybackHubPublisher publisher) : Hub
{
    public override async Task OnConnectedAsync()
    {
        if (!TryUserId(out var userId))
        {
            Context.Abort();
            return;
        }

        try
        {
            await redis.GetDatabase().PingAsync();
        }
        catch
        {
            Context.Abort();
            return;
        }

        var ip = Context.GetHttpContext()?.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        try
        {
            await limiter.HitAsync($"rl:signalr:{ip}:{userId:D}", 20, TimeSpan.FromMinutes(5), Context.ConnectionAborted);
        }
        catch (RateLimitedException)
        {
            Context.Abort();
            return;
        }
        catch (Http.ApiException)
        {
            Context.Abort();
            return;
        }

        Context.Items["userId"] = userId;
        await Groups.AddToGroupAsync(Context.ConnectionId, PlaybackHubGroups.ForUser(userId), Context.ConnectionAborted);
        if (TryDeviceId(out var deviceId))
        {
            Context.Items["deviceId"] = deviceId;
            await TryPresenceAsync(() => presence.UpsertAsync(userId, deviceId, Context.ConnectionId, Context.ConnectionAborted));
            await PublishPresenceAsync(userId, Context.ConnectionAborted);
        }

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        if (Context.Items["userId"] is Guid userId)
        {
            await TryPresenceAsync(() => presence.RemoveByConnectionAsync(userId, Context.ConnectionId, CancellationToken.None));
            await PublishPresenceAsync(userId, CancellationToken.None);
        }

        await base.OnDisconnectedAsync(exception);
    }

    public async Task Heartbeat()
    {
        if (Context.Items["userId"] is Guid userId && Context.Items["deviceId"] is Guid deviceId)
        {
            await TryPresenceAsync(() => presence.UpsertAsync(userId, deviceId, Context.ConnectionId, Context.ConnectionAborted));
        }
    }

    private async Task PublishPresenceAsync(Guid userId, CancellationToken ct)
    {
        try
        {
            var dto = await presence.ListAsync(userId, ct);
            await publisher.DevicePresenceAsync(userId, dto, ct);
        }
        catch
        {
        }
    }

    private static async Task TryPresenceAsync(Func<Task> op)
    {
        try
        {
            await op();
        }
        catch
        {
        }
    }

    private bool TryUserId(out Guid userId)
    {
        var raw = Context.User?.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? Context.User?.FindFirstValue(JwtRegisteredClaimNames.Sub);
        return Guid.TryParse(raw, out userId);
    }

    private bool TryDeviceId(out Guid deviceId)
    {
        var http = Context.GetHttpContext();
        var raw = http?.Request.Query["deviceId"].FirstOrDefault()
            ?? http?.Request.Headers["X-Device-Id"].FirstOrDefault();
        return Guid.TryParse(raw, out deviceId);
    }
}
