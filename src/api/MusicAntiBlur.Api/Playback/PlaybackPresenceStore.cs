using System.Text.Json;
using StackExchange.Redis;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Playback;

public sealed class PlaybackPresenceStore(IConnectionMultiplexer redis)
{
    public static readonly TimeSpan StaleAfter = TimeSpan.FromSeconds(90);
    private static readonly TimeSpan KeyTtl = TimeSpan.FromMinutes(2);
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };

    public static string Key(Guid userId) => $"playback-presence:{userId:D}";

    public async Task UpsertAsync(Guid userId, Guid deviceId, string connectionId, CancellationToken ct)
    {
        try
        {
            var db = redis.GetDatabase();
            var payload = JsonSerializer.Serialize(new PresenceEntry(connectionId, DateTimeOffset.UtcNow), Json);
            await db.HashSetAsync(Key(userId), deviceId.ToString("D"), payload);
            await db.KeyExpireAsync(Key(userId), KeyTtl);
        }
        catch
        {
            throw Unavailable();
        }
    }

    public async Task RemoveByConnectionAsync(Guid userId, string connectionId, CancellationToken ct)
    {
        try
        {
            var db = redis.GetDatabase();
            var entries = await db.HashGetAllAsync(Key(userId));
            foreach (var hash in entries)
            {
                var parsed = Parse(hash.Value);
                if (parsed is not null &&
                    string.Equals(parsed.ConnectionId, connectionId, StringComparison.Ordinal))
                {
                    await db.HashDeleteAsync(Key(userId), hash.Name);
                }
            }
        }
        catch
        {
            throw Unavailable();
        }
    }

    public async Task<DevicePresenceDto> ListAsync(Guid userId, CancellationToken ct)
    {
        try
        {
            var db = redis.GetDatabase();
            var entries = await db.HashGetAllAsync(Key(userId));
            var cutoff = DateTimeOffset.UtcNow - StaleAfter;
            var devices = new List<DevicePresenceItemDto>();
            foreach (var hash in entries)
            {
                var parsed = Parse(hash.Value);
                if (parsed is null || !Guid.TryParse((string?)hash.Name, out var deviceId))
                {
                    continue;
                }

                if (parsed.LastSeen < cutoff)
                {
                    await db.HashDeleteAsync(Key(userId), hash.Name);
                    continue;
                }

                devices.Add(new DevicePresenceItemDto(deviceId, parsed.LastSeen));
            }

            devices.Sort((a, b) => a.DeviceId.CompareTo(b.DeviceId));
            return new DevicePresenceDto(devices);
        }
        catch
        {
            throw Unavailable();
        }
    }

    private static PresenceEntry? Parse(RedisValue value)
    {
        if (value.IsNullOrEmpty)
        {
            return null;
        }

        try
        {
            return JsonSerializer.Deserialize<PresenceEntry>((string)value!, Json);
        }
        catch
        {
            return null;
        }
    }

    private static ApiException Unavailable() =>
        new(503, "dependency_unavailable", "A required dependency is unavailable.");

    private sealed record PresenceEntry(string ConnectionId, DateTimeOffset LastSeen);
}
