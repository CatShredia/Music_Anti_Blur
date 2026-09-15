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
    IPlaybackHubPublisher publisher,
    ILogger<PlaybackHub> logger) : Hub
{
    public override async Task OnConnectedAsync()
    {
        if (!TryUserId(out var userId))
        {
            logger.LogWarning("[sync] hub-connect-abort why=no-user conn={Conn}", Context.ConnectionId);
            Context.Abort();
            return;
        }

        try
        {
            await redis.GetDatabase().PingAsync();
        }
        catch
        {
            logger.LogWarning("[sync] hub-connect-abort why=redis-ping user={UserId} conn={Conn}", userId, Context.ConnectionId);
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
            logger.LogWarning("[sync] hub-connect-abort why=rate-limit user={UserId} ip={Ip} conn={Conn}", userId, ip, Context.ConnectionId);
            Context.Abort();
            return;
        }
        catch (Http.ApiException)
        {
            logger.LogWarning("[sync] hub-connect-abort why=limiter user={UserId} ip={Ip} conn={Conn}", userId, ip, Context.ConnectionId);
            Context.Abort();
            return;
        }

        Context.Items["userId"] = userId;
        var group = PlaybackHubGroups.ForUser(userId);
        await Groups.AddToGroupAsync(Context.ConnectionId, group, Context.ConnectionAborted);
        var hasDevice = TryDeviceId(out var deviceId);
        if (hasDevice)
        {
            Context.Items["deviceId"] = deviceId;
            await TryPresenceAsync(() => presence.UpsertAsync(userId, deviceId, Context.ConnectionId, Context.ConnectionAborted));
            await PublishPresenceAsync(userId, Context.ConnectionAborted);
        }

        logger.LogInformation(
            "[sync] hub-connect user={UserId} device={Device} group={Group} conn={Conn}",
            userId,
            hasDevice ? deviceId.ToString() : "-",
            group,
            Context.ConnectionId);

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        if (Context.Items["userId"] is Guid userId)
        {
            logger.LogInformation(
                "[sync] hub-disconnect user={UserId} device={Device} conn={Conn} error={Error}",
                userId,
                Context.Items["deviceId"],
                Context.ConnectionId,
                exception?.Message ?? "-");
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
