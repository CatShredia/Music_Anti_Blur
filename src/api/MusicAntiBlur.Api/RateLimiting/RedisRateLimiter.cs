using StackExchange.Redis;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.RateLimiting;

public sealed class RedisRateLimiter(IConnectionMultiplexer redis)
{
    public async Task HitAsync(string key, int limit, TimeSpan window, CancellationToken ct)
    {
        try
        {
            var db = redis.GetDatabase();
            var count = await db.StringIncrementAsync(key);
            if (count == 1)
            {
                await db.KeyExpireAsync(key, window);
            }

            if (count > limit)
            {
                var ttl = await db.KeyTimeToLiveAsync(key) ?? window;
                throw new RateLimitedException(Math.Max(1, (int)ttl.TotalSeconds));
            }
        }
        catch (RateLimitedException)
        {
            throw;
        }
        catch (Exception)
        {
            throw new ApiException(503, "dependency_unavailable", "Rate limiter is unavailable.");
        }
    }
}

public sealed class RateLimitedException(int retryAfterSeconds) : Exception
{
    public int RetryAfterSeconds { get; } = retryAfterSeconds;
}
