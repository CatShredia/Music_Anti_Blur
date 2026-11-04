using System.Security.Cryptography;
using System.Text.Json;
using Hangfire;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Jobs;
using MusicAntiBlur.Api.RateLimiting;
using StackExchange.Redis;

namespace MusicAntiBlur.Api.Auth;

/// <summary>
/// Second factor: TOTP (primary), one-time code by email (fallback) and recovery codes.
/// Login challenges live in Redis for <see cref="ChallengeTtl"/>.
/// </summary>
public sealed class TwoFactorService(
    AppDbContext db,
    PasswordHasher<User> hasher,
    IDataProtectionProvider dataProtection,
    IConnectionMultiplexer redis,
    RedisRateLimiter limiter,
    IBackgroundJobClient jobs,
    TimeProvider clock)
{
    public const int RecoveryCodeCount = 10;
    public const int MaxChallengeAttempts = 5;
    public static readonly TimeSpan ChallengeTtl = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan SetupTtl = TimeSpan.FromMinutes(10);
    private const string RecoveryAlphabet = "abcdefghjkmnpqrstuvwxyz23456789";

    private IDataProtector Protector => dataProtection.CreateProtector("MusicAntiBlur.Totp.v1");

    // ---------- management (/me/2fa) ----------

    public async Task<TwoFactorStatusDto> GetStatusAsync(Guid userId, CancellationToken ct)
    {
        var row = await db.UserTwoFactors.AsNoTracking().FirstOrDefaultAsync(x => x.UserId == userId, ct);
        var left = await db.UserRecoveryCodes.CountAsync(x => x.UserId == userId && x.UsedAt == null, ct);
        return new TwoFactorStatusDto(row?.TotpEnabledAt is not null, row?.EmailOtpEnabled == true, left);
    }

    public async Task<TotpSetupDto> BeginTotpSetupAsync(Guid userId, string? currentPassword, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:2fa-manage:{userId:D}", 10, TimeSpan.FromMinutes(15), ct);
        var user = await RequirePasswordAsync(userId, currentPassword, ct);
        var secret = Totp.NewSecret();
        var base32 = Base32.Encode(secret);
        await redis.GetDatabase().StringSetAsync(SetupKey(userId), Protector.Protect(base32), SetupTtl);
        var account = user.Email ?? user.Login ?? user.Id.ToString("D");
        return new TotpSetupDto(base32, Totp.OtpauthUri(base32, account));
    }

    public async Task<RecoveryCodesDto> ConfirmTotpAsync(Guid userId, string? code, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:2fa-manage:{userId:D}", 10, TimeSpan.FromMinutes(15), ct);
        var pending = await redis.GetDatabase().StringGetAsync(SetupKey(userId));
        if (pending.IsNullOrEmpty)
        {
            throw new ApiException(409, "totp_setup_expired", "Start TOTP setup again.");
        }

        var base32 = Protector.Unprotect(pending.ToString());
        var step = Totp.Match(Base32.Decode(base32), code, clock.GetUtcNow());
        if (step is null)
        {
            throw InvalidCode();
        }

        var now = clock.GetUtcNow();
        var row = await GetOrCreateRowAsync(userId, now, ct);
        row.TotpSecretProtected = Protector.Protect(base32);
        row.TotpEnabledAt = now;
        row.UpdatedAt = now;
        var codes = await ReplaceRecoveryCodesAsync(userId, now, ct);
        await db.SaveChangesAsync(ct);
        await redis.GetDatabase().KeyDeleteAsync(SetupKey(userId));
        await redis.GetDatabase().StringSetAsync(LastStepKey(userId), step.Value, TimeSpan.FromMinutes(5));
        return new RecoveryCodesDto(codes);
    }

    public async Task<RecoveryCodesDto?> EnableEmailAsync(Guid userId, string? currentPassword, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:2fa-manage:{userId:D}", 10, TimeSpan.FromMinutes(15), ct);
        var user = await RequirePasswordAsync(userId, currentPassword, ct);
        if (user.Email is null || user.EmailVerifiedAt is null)
        {
            throw new ApiException(409, "email_not_verified", "A verified email is required.");
        }

        var now = clock.GetUtcNow();
        var row = await GetOrCreateRowAsync(userId, now, ct);
        row.EmailOtpEnabled = true;
        row.UpdatedAt = now;
        var hasCodes = await db.UserRecoveryCodes.AnyAsync(x => x.UserId == userId && x.UsedAt == null, ct);
        var codes = hasCodes ? null : await ReplaceRecoveryCodesAsync(userId, now, ct);
        await db.SaveChangesAsync(ct);
        return codes is null ? null : new RecoveryCodesDto(codes);
    }

    public async Task DisableEmailAsync(Guid userId, string? currentPassword, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:2fa-manage:{userId:D}", 10, TimeSpan.FromMinutes(15), ct);
        await RequirePasswordAsync(userId, currentPassword, ct);
        var row = await db.UserTwoFactors.FirstOrDefaultAsync(x => x.UserId == userId, ct);
        if (row is null)
        {
            return;
        }

        row.EmailOtpEnabled = false;
        row.UpdatedAt = clock.GetUtcNow();
        await DropCodesIfNoFactorAsync(row, ct);
        await db.SaveChangesAsync(ct);
    }

    public async Task<RecoveryCodesDto> RegenerateRecoveryCodesAsync(Guid userId, string? currentPassword, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:2fa-manage:{userId:D}", 10, TimeSpan.FromMinutes(15), ct);
        await RequirePasswordAsync(userId, currentPassword, ct);
        var row = await db.UserTwoFactors.AsNoTracking().FirstOrDefaultAsync(x => x.UserId == userId, ct);
        if (!IsEnabled(row))
        {
            throw new ApiException(409, "two_factor_disabled", "Two-factor authentication is off.");
        }

        var codes = await ReplaceRecoveryCodesAsync(userId, clock.GetUtcNow(), ct);
        await db.SaveChangesAsync(ct);
        return new RecoveryCodesDto(codes);
    }

    /// <summary>Turns every factor off. With TOTP on, a current TOTP or recovery code is required too.</summary>
    public async Task DisableAllAsync(Guid userId, string? currentPassword, string? code, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:2fa-manage:{userId:D}", 10, TimeSpan.FromMinutes(15), ct);
        await RequirePasswordAsync(userId, currentPassword, ct);
        var row = await db.UserTwoFactors.FirstOrDefaultAsync(x => x.UserId == userId, ct);
        if (row is null)
        {
            return;
        }

        if (row.TotpEnabledAt is not null &&
            !await TryTotpAsync(row, code) &&
            !await TryRecoveryAsync(userId, code, ct))
        {
            throw InvalidCode();
        }

        db.UserTwoFactors.Remove(row);
        await db.UserRecoveryCodes.Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);
        await db.SaveChangesAsync(ct);
    }

    // ---------- login challenge (/auth/2fa) ----------

    public async Task<TwoFactorRequiredResponse?> CreateChallengeIfRequiredAsync(User user, Guid deviceId, CancellationToken ct)
    {
        var row = await db.UserTwoFactors.AsNoTracking().FirstOrDefaultAsync(x => x.UserId == user.Id, ct);
        if (!IsEnabled(row))
        {
            return null;
        }

        var methods = new List<string>();
        if (row!.TotpEnabledAt is not null)
        {
            methods.Add("totp");
        }

        if (row.EmailOtpEnabled && user.Email is not null && user.EmailVerifiedAt is not null)
        {
            methods.Add("email");
        }

        if (await db.UserRecoveryCodes.AnyAsync(x => x.UserId == user.Id && x.UsedAt == null, ct))
        {
            methods.Add("recovery");
        }

        var id = Guid.NewGuid();
        var state = new ChallengeState(user.Id, deviceId, methods);
        await redis.GetDatabase().StringSetAsync(ChallengeKey(id), JsonSerializer.Serialize(state), ChallengeTtl);
        return new TwoFactorRequiredResponse(true, id, methods, clock.GetUtcNow().Add(ChallengeTtl));
    }

    public async Task SendEmailCodeAsync(Guid challengeId, string ip, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:2fa-email:{challengeId:D}", 3, TimeSpan.FromMinutes(15), ct);
        await limiter.HitAsync($"rl:2fa-email-ip:{ip}", 10, TimeSpan.FromMinutes(15), ct);
        var state = await LoadChallengeAsync(challengeId);
        if (!state.Methods.Contains("email"))
        {
            throw new ApiException(409, "method_unavailable", "Email code is not available for this account.");
        }

        var user = await db.Users.AsNoTracking().FirstAsync(u => u.Id == state.UserId, ct);
        var code = TokenHasher.NewNumericCode();
        var database = redis.GetDatabase();
        var ttl = await database.KeyTimeToLiveAsync(ChallengeKey(challengeId)) ?? ChallengeTtl;
        await database.StringSetAsync(EmailCodeKey(challengeId), TokenHasher.Hash(code), ttl);
        var mailKey = $"mail:2fa:{challengeId:D}";
        await database.StringSetAsync(mailKey, code, ttl);
        var email = user.Email!;
        jobs.Enqueue<EmailJobs>(x => x.SendTwoFactorCode(mailKey, email));
    }

    /// <summary>Checks the code. Burns the challenge after <see cref="MaxChallengeAttempts"/> failures.</summary>
    public async Task<TwoFactorVerified> VerifyAsync(Guid challengeId, string? method, string? code, string ip, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:2fa-verify:{ip}", 20, TimeSpan.FromMinutes(15), ct);
        var state = await LoadChallengeAsync(challengeId);
        method = (method ?? "").Trim().ToLowerInvariant();
        if (!state.Methods.Contains(method))
        {
            throw new ApiException(400, "validation_failed", "Validation failed.",
                new Dictionary<string, string[]> { ["method"] = ["unsupported"] });
        }

        var ok = method switch
        {
            "totp" => await TryTotpAsync(
                await db.UserTwoFactors.FirstAsync(x => x.UserId == state.UserId, ct), code),
            "email" => await TryEmailCodeAsync(challengeId, code),
            "recovery" => await TryRecoveryAsync(state.UserId, code, ct),
            _ => false
        };

        var database = redis.GetDatabase();
        if (!ok)
        {
            var attempts = await database.StringIncrementAsync(AttemptsKey(challengeId));
            await database.KeyExpireAsync(AttemptsKey(challengeId), ChallengeTtl);
            var burnt = attempts >= MaxChallengeAttempts;
            if (burnt)
            {
                await DeleteChallengeAsync(challengeId);
            }

            return new TwoFactorVerified(state.UserId, state.DeviceId, method, Ok: false, Burnt: burnt);
        }

        await DeleteChallengeAsync(challengeId);
        return new TwoFactorVerified(state.UserId, state.DeviceId, method, Ok: true, Burnt: false);
    }

    // ---------- helpers ----------

    public static bool IsEnabled(UserTwoFactor? row) =>
        row is not null && (row.TotpEnabledAt is not null || row.EmailOtpEnabled);

    public static string NewRecoveryCode()
    {
        Span<char> chars = stackalloc char[9];
        for (var i = 0; i < chars.Length; i++)
        {
            chars[i] = i == 4 ? '-' : RecoveryAlphabet[RandomNumberGenerator.GetInt32(RecoveryAlphabet.Length)];
        }

        return new string(chars);
    }

    public static string NormalizeRecoveryCode(string? code) =>
        (code ?? "").Trim().Replace(" ", "").Replace("-", "").ToLowerInvariant();

    private async Task<bool> TryTotpAsync(UserTwoFactor row, string? code)
    {
        if (row.TotpSecretProtected is null)
        {
            return false;
        }

        var secret = Base32.Decode(Protector.Unprotect(row.TotpSecretProtected));
        var step = Totp.Match(secret, code, clock.GetUtcNow());
        if (step is null)
        {
            return false;
        }

        // A code may be used once: reject steps at or before the last accepted one.
        var database = redis.GetDatabase();
        var last = await database.StringGetAsync(LastStepKey(row.UserId));
        if (last.HasValue && (long)last >= step.Value)
        {
            return false;
        }

        await database.StringSetAsync(LastStepKey(row.UserId), step.Value, TimeSpan.FromMinutes(5));
        return true;
    }

    private async Task<bool> TryEmailCodeAsync(Guid challengeId, string? code)
    {
        if (string.IsNullOrWhiteSpace(code))
        {
            return false;
        }

        var stored = await redis.GetDatabase().StringGetAsync(EmailCodeKey(challengeId));
        if (stored.IsNullOrEmpty)
        {
            return false;
        }

        var given = System.Text.Encoding.ASCII.GetBytes(TokenHasher.Hash(code.Trim()));
        var expected = System.Text.Encoding.ASCII.GetBytes(stored.ToString());
        return CryptographicOperations.FixedTimeEquals(given, expected);
    }

    private async Task<bool> TryRecoveryAsync(Guid userId, string? code, CancellationToken ct)
    {
        var normalized = NormalizeRecoveryCode(code);
        if (normalized.Length != 8)
        {
            return false;
        }

        var hash = TokenHasher.Hash(normalized);
        var now = clock.GetUtcNow();
        var used = await db.UserRecoveryCodes
            .Where(x => x.UserId == userId && x.CodeHash == hash && x.UsedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.UsedAt, now), ct);
        return used == 1;
    }

    private async Task<IReadOnlyList<string>> ReplaceRecoveryCodesAsync(Guid userId, DateTimeOffset now, CancellationToken ct)
    {
        await db.UserRecoveryCodes.Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);
        var codes = new List<string>(RecoveryCodeCount);
        var hashes = new HashSet<string>();
        while (codes.Count < RecoveryCodeCount)
        {
            var code = NewRecoveryCode();
            if (hashes.Add(TokenHasher.Hash(NormalizeRecoveryCode(code))))
            {
                codes.Add(code);
            }
        }

        foreach (var hash in hashes)
        {
            db.UserRecoveryCodes.Add(new UserRecoveryCode { Id = Guid.NewGuid(), UserId = userId, CodeHash = hash, CreatedAt = now });
        }

        return codes;
    }

    private async Task DropCodesIfNoFactorAsync(UserTwoFactor row, CancellationToken ct)
    {
        if (!IsEnabled(row))
        {
            db.UserTwoFactors.Remove(row);
            await db.UserRecoveryCodes.Where(x => x.UserId == row.UserId).ExecuteDeleteAsync(ct);
        }
    }

    private async Task<UserTwoFactor> GetOrCreateRowAsync(Guid userId, DateTimeOffset now, CancellationToken ct)
    {
        var row = await db.UserTwoFactors.FirstOrDefaultAsync(x => x.UserId == userId, ct);
        if (row is null)
        {
            row = new UserTwoFactor { UserId = userId, UpdatedAt = now };
            db.UserTwoFactors.Add(row);
        }

        return row;
    }

    private async Task<User> RequirePasswordAsync(Guid userId, string? currentPassword, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(currentPassword))
        {
            throw new ApiException(400, "validation_failed", "Validation failed.",
                new Dictionary<string, string[]> { ["currentPassword"] = [AuthValidation.Required] });
        }

        var user = await db.Users.AsNoTracking().FirstAsync(u => u.Id == userId, ct);
        if (hasher.VerifyHashedPassword(user, user.PasswordHash, currentPassword) == PasswordVerificationResult.Failed)
        {
            throw new ApiException(401, "invalid_credentials", "Invalid credentials.");
        }

        return user;
    }

    private async Task<ChallengeState> LoadChallengeAsync(Guid challengeId)
    {
        var raw = await redis.GetDatabase().StringGetAsync(ChallengeKey(challengeId));
        if (raw.IsNullOrEmpty)
        {
            throw new ApiException(401, "challenge_expired", "Sign in again.");
        }

        return JsonSerializer.Deserialize<ChallengeState>(raw.ToString())!;
    }

    private async Task DeleteChallengeAsync(Guid challengeId)
    {
        var database = redis.GetDatabase();
        await database.KeyDeleteAsync([ChallengeKey(challengeId), AttemptsKey(challengeId), EmailCodeKey(challengeId)]);
    }

    public static ApiException InvalidCode() =>
        new(400, "invalid_token", "Invalid code.", new Dictionary<string, string[]> { ["code"] = ["invalid_token"] });

    private static string SetupKey(Guid userId) => $"2fa:setup:{userId:D}";
    private static string LastStepKey(Guid userId) => $"2fa:totp-last:{userId:D}";
    private static string ChallengeKey(Guid id) => $"2fa:ch:{id:D}";
    private static string AttemptsKey(Guid id) => $"2fa:ch:{id:D}:attempts";
    private static string EmailCodeKey(Guid id) => $"2fa:ch:{id:D}:email";

    private sealed record ChallengeState(Guid UserId, Guid DeviceId, List<string> Methods);
}

/// <summary>Result of a code check. Burnt = the challenge was deleted after too many failures.</summary>
public sealed record TwoFactorVerified(Guid UserId, Guid DeviceId, string Method, bool Ok, bool Burnt);
public sealed record TwoFactorStatusDto(bool Totp, bool Email, int RecoveryCodesLeft);
public sealed record TotpSetupDto(string Secret, string OtpauthUri);
public sealed record RecoveryCodesDto(IReadOnlyList<string> Codes);
public sealed record TwoFactorRequiredResponse(bool TwoFactorRequired, Guid ChallengeId, IReadOnlyList<string> Methods, DateTimeOffset ExpiresAt);
public sealed record PasswordRequest(string? CurrentPassword);
public sealed record CodeOnlyRequest(string? Code);
public sealed record DisableTwoFactorRequest(string? CurrentPassword, string? Code);
public sealed record ChallengeRequest(Guid ChallengeId);
public sealed record VerifyTwoFactorRequest(Guid ChallengeId, string? Method, string? Code);
