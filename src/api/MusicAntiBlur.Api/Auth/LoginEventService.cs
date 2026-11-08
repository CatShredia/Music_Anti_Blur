using System.Text;
using System.Text.Json;
using Hangfire;
using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Jobs;
using MusicAntiBlur.Api.RateLimiting;

namespace MusicAntiBlur.Api.Auth;

public sealed record ClientInfo(string Ip, string? UserAgent);

public sealed class LoginEventService(
    AppDbContext db,
    AuthService auth,
    RedisRateLimiter limiter,
    IBackgroundJobClient jobs,
    TimeProvider clock,
    ILogger<LoginEventService> logger)
{
    public const int RetentionDays = 90;
    private const int MaxUserAgent = 512;

    public static void Add(AppDbContext db, Guid userId, Guid? deviceId, ClientInfo client, string result, string method, DateTimeOffset at)
    {
        var ua = client.UserAgent;
        if (ua is { Length: > MaxUserAgent })
        {
            ua = ua[..MaxUserAgent];
        }

        db.LoginEvents.Add(new LoginEvent
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            DeviceId = deviceId,
            At = at,
            Ip = client.Ip.Length > 64 ? client.Ip[..64] : client.Ip,
            UserAgent = ua,
            Result = result,
            Method = method
        });
    }

    public async Task<PageDto<LoginEventDto>> ListAsync(Guid userId, Guid currentDeviceId, string? cursor, int? limit, CancellationToken ct)
    {
        var errors = CatalogValidation.NewErrors();
        var take = CatalogValidation.ParseLimit(limit, errors);
        (DateTimeOffset At, Guid Id)? after = null;
        if (!string.IsNullOrWhiteSpace(cursor))
        {
            after = DecodeCursor(cursor);
            if (after is null)
            {
                CatalogValidation.Add(errors, "cursor", CatalogValidation.Required);
            }
        }

        CatalogValidation.ThrowIfAny(errors);

        var query = db.LoginEvents.AsNoTracking().Where(e => e.UserId == userId);
        if (after is { } a)
        {
            query = query.Where(e => e.At < a.At || (e.At == a.At && e.Id.CompareTo(a.Id) < 0));
        }

        var rows = await query
            .OrderByDescending(e => e.At)
            .ThenByDescending(e => e.Id)
            .Take(take + 1)
            .ToListAsync(ct);

        var items = rows.Take(take)
            .Select(e => new LoginEventDto(e.Id, e.At, e.Ip, e.UserAgent, e.Result, e.Method, e.DeviceId,
                e.DeviceId == currentDeviceId, e.NotMeAt))
            .ToList();
        var next = rows.Count > take ? EncodeCursor(items[^1].At, items[^1].Id) : null;
        return new PageDto<LoginEventDto>(items, next);
    }

    /// <summary>
    /// "This was not me": revokes the sessions of the event's device and emails a password-change hint.
    /// Idempotent: an already revoked device is not an error.
    /// </summary>
    public async Task NotMeAsync(Guid userId, Guid eventId, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:not-me:{userId:D}", 10, TimeSpan.FromHours(1), ct);
        var row = await db.LoginEvents.FirstOrDefaultAsync(e => e.Id == eventId && e.UserId == userId, ct)
                  ?? throw new ApiException(404, "not_found", "Not found.");

        if (row.DeviceId is Guid deviceId)
        {
            try
            {
                await auth.RevokeDeviceAsync(userId, deviceId, ct);
            }
            catch (ApiException ex) when (ex.Status == 404)
            {
                // Sessions of this device are already gone.
            }
        }

        if (row.NotMeAt is null)
        {
            row.NotMeAt = clock.GetUtcNow();
            await db.SaveChangesAsync(ct);

            var user = await db.Users.AsNoTracking().FirstAsync(u => u.Id == userId, ct);
            if (user.Email is not null && user.EmailVerifiedAt is not null)
            {
                var email = user.Email;
                jobs.Enqueue<EmailJobs>(x => x.SendSuspiciousLogin(email, row.At, row.Ip));
            }

            logger.LogWarning("Login event {EventId} reported as not-me by user {UserId}.", eventId, userId);
        }
    }

    public static string EncodeCursor(DateTimeOffset at, Guid id)
    {
        var json = JsonSerializer.Serialize(new { at, id });
        return Convert.ToBase64String(Encoding.UTF8.GetBytes(json)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }

    public static (DateTimeOffset At, Guid Id)? DecodeCursor(string cursor)
    {
        try
        {
            var padded = cursor.Replace('-', '+').Replace('_', '/');
            padded = padded.PadRight(padded.Length + (4 - padded.Length % 4) % 4, '=');
            using var doc = JsonDocument.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(padded)));
            return (doc.RootElement.GetProperty("at").GetDateTimeOffset(), doc.RootElement.GetProperty("id").GetGuid());
        }
        catch
        {
            return null;
        }
    }
}

public sealed record LoginEventDto(
    Guid Id,
    DateTimeOffset At,
    string Ip,
    string? UserAgent,
    string Result,
    string Method,
    Guid? DeviceId,
    bool CurrentDevice,
    DateTimeOffset? NotMeAt);
