using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Uploads;

public sealed class IdempotencyStore(AppDbContext db)
{
    private static readonly System.Text.Json.JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase
    };

    public static string HashRequest(string canonical)
    {
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(canonical))).ToLowerInvariant();
    }

    public async Task<T> ExecuteAsync<T>(
        Guid userId,
        string route,
        Guid key,
        string requestHash,
        int successStatus,
        Func<Task<T>> action,
        CancellationToken ct)
    {
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        await db.Database.ExecuteSqlInterpolatedAsync(
            $"SELECT pg_advisory_xact_lock(hashtext({$"{userId:D}:{route}"}), hashtext({key.ToString("D")}))", ct);

        var existing = await db.IdempotencyRecords.FirstOrDefaultAsync(
            r => r.UserId == userId && r.Route == route && r.IdempotencyKey == key, ct);
        if (existing is not null)
        {
            if (!string.Equals(existing.RequestHash, requestHash, StringComparison.Ordinal))
            {
                throw new ApiException(409, "idempotency_conflict", "Idempotency key was reused with a different body.");
            }

            if (existing.ExpiresAt < DateTimeOffset.UtcNow)
            {
                db.IdempotencyRecords.Remove(existing);
                await db.SaveChangesAsync(ct);
            }
            else
            {
                var replay = existing.ResponseBody is null
                    ? default
                    : System.Text.Json.JsonSerializer.Deserialize<T>(existing.ResponseBody, Json);
                if (replay is null)
                {
                    throw new ApiException(409, "idempotency_conflict", "Stored idempotent response is unreadable.");
                }

                await tx.CommitAsync(ct);
                return replay;
            }
        }

        var result = await action();
        db.IdempotencyRecords.Add(new IdempotencyRecord
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Route = route,
            IdempotencyKey = key,
            RequestHash = requestHash,
            ResponseStatus = successStatus,
            ResponseBody = System.Text.Json.JsonSerializer.Serialize(result, Json),
            CreatedAt = DateTimeOffset.UtcNow,
            ExpiresAt = DateTimeOffset.UtcNow.AddHours(24)
        });
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        return result;
    }
}
