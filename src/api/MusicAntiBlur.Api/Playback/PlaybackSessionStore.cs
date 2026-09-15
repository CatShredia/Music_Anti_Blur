using StackExchange.Redis;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Playback;

public sealed class PlaybackSessionStore(IConnectionMultiplexer redis)
{
    private static readonly TimeSpan Ttl = TimeSpan.FromHours(24);

    public async Task CreateAsync(Guid sessionId, Guid userId, Guid deviceId, CancellationToken ct)
    {
        try
        {
            var ok = await redis.GetDatabase().StringSetAsync(
                Key(sessionId),
                $"{userId:D}|{deviceId:D}",
                Ttl);
            if (!ok)
            {
                throw Unavailable();
            }
        }
        catch (ApiException)
        {
            throw;
        }
        catch
        {
            throw Unavailable();
        }
    }

    public async Task<(Guid UserId, Guid DeviceId)?> GetAsync(Guid sessionId, CancellationToken ct)
    {
        try
        {
            var value = await redis.GetDatabase().StringGetAsync(Key(sessionId));
            if (value.IsNullOrEmpty)
            {
                return null;
            }

            var parts = ((string)value!).Split('|');
            if (parts.Length != 2 || !Guid.TryParse(parts[0], out var userId) || !Guid.TryParse(parts[1], out var deviceId))
            {
                return null;
            }

            return (userId, deviceId);
        }
        catch
        {
            throw Unavailable();
        }
    }

    private static string Key(Guid sessionId) => $"playback-session:{sessionId:D}";

    private static ApiException Unavailable() =>
        new(503, "dependency_unavailable", "A required dependency is unavailable.");
}
