using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using MusicAntiBlur.Api.RateLimiting;

namespace MusicAntiBlur.Api.Hubs;

[Authorize]
public sealed class PlaybackHub(RedisRateLimiter limiter) : Hub
{
    public override async Task OnConnectedAsync()
    {
        var userId = Context.User?.FindFirstValue(ClaimTypes.NameIdentifier) ?? "anon";
        var ip = Context.GetHttpContext()?.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        try
        {
            await limiter.HitAsync($"rl:signalr:{ip}:{userId}", 20, TimeSpan.FromMinutes(5), Context.ConnectionAborted);
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

        await base.OnConnectedAsync();
    }
}
