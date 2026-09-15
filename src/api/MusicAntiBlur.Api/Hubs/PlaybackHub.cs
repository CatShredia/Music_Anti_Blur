using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using MusicAntiBlur.Api.RateLimiting;
using StackExchange.Redis;

namespace MusicAntiBlur.Api.Hubs;

[Authorize]
public sealed class PlaybackHub(RedisRateLimiter limiter, IConnectionMultiplexer redis) : Hub
{
    public override async Task OnConnectedAsync()
    {
        var raw = Context.User?.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? Context.User?.FindFirstValue(JwtRegisteredClaimNames.Sub);
        if (raw is null || !Guid.TryParse(raw, out var userId))
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

        await Groups.AddToGroupAsync(Context.ConnectionId, PlaybackHubGroups.ForUser(userId), Context.ConnectionAborted);
        await base.OnConnectedAsync();
    }
}
