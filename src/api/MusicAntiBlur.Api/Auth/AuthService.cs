using System.Security.Claims;
using Hangfire;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Jobs;
using MusicAntiBlur.Api.RateLimiting;
using StackExchange.Redis;

namespace MusicAntiBlur.Api.Auth;

public sealed class AuthService(
    AppDbContext db,
    PasswordHasher<User> hasher,
    JwtTokenService jwt,
    RedisRateLimiter limiter,
    IBackgroundJobClient jobs,
    IConnectionMultiplexer redis,
    ILogger<AuthService> logger)
{
    private static readonly User DummyUser = new() { Id = Guid.Empty };
    private static readonly string DummyHash = new PasswordHasher<User>().HashPassword(DummyUser, "dummy-password-not-used");

    public async Task<SessionResponse> RegisterAsync(RegisterRequest req, Guid deviceId, string ip, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:register:{ip}", 30, TimeSpan.FromHours(1), ct);
        PasswordRules.EnsurePassword(req.Password);
        if (string.IsNullOrWhiteSpace(req.Login) || string.IsNullOrWhiteSpace(req.Email))
        {
            throw new ApiException(400, "validation_failed", "Login and email are required.",
                new Dictionary<string, string[]>
                {
                    ["login"] = ["Login is required."],
                    ["email"] = ["Email is required."]
                });
        }

        PasswordRules.EnsureLogin(req.Login);
        var email = PasswordRules.NormalizeEmail(req.Email);
        if (await LoginTakenAsync(req.Login, ct) || await EmailTakenAsync(email, ct))
        {
            throw new ApiException(409, "identifier_taken", "Identifier is already taken.");
        }

        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var now = DateTimeOffset.UtcNow;
        var user = new User
        {
            Id = Guid.NewGuid(),
            Login = req.Login,
            Email = email,
            Role = "user",
            CreatedAt = now,
            UpdatedAt = now,
            Settings = new UserSettings { PreferredQuality = "auto", UpdatedAt = now },
            PasswordHash = ""
        };
        user.PasswordHash = hasher.HashPassword(user, req.Password);
        db.Users.Add(user);
        await db.SaveChangesAsync(ct);
        await CreateVerificationAsync(user.Id, email, "register", TimeSpan.FromHours(24), ct);
        var session = await IssueSessionAsync(user, deviceId, now, ct);
        await tx.CommitAsync(ct);
        return session;
    }

    public async Task<SessionResponse> LoginAsync(LoginRequest req, Guid deviceId, string ip, CancellationToken ct)
    {
        var type = ParseType(req.IdentifierType);
        var identKey = type == "email"
            ? PasswordRules.NormalizeEmail(req.Identifier)
            : req.Identifier;
        await limiter.HitAsync($"rl:login:{ip}:{TokenHasher.Hash(identKey.ToLowerInvariant())}", 10, TimeSpan.FromMinutes(5), ct);

        User? user;
        if (type == "email")
        {
            user = await db.Users.FirstOrDefaultAsync(u => u.Email == identKey, ct);
        }
        else
        {
            PasswordRules.EnsureLogin(req.Identifier);
            var lowered = req.Identifier.ToLowerInvariant();
            user = await db.Users.FirstOrDefaultAsync(u => u.Login != null && u.Login.ToLower() == lowered, ct);
        }

        var hash = user?.PasswordHash ?? DummyHash;
        var verify = hasher.VerifyHashedPassword(user ?? DummyUser, hash, req.Password);
        if (user is null || verify == PasswordVerificationResult.Failed)
        {
            throw new ApiException(401, "invalid_credentials", "Invalid credentials.");
        }

        if (type == "email" && user.EmailVerifiedAt is null)
        {
            throw new ApiException(403, "email_not_verified", "Email is not verified.");
        }

        return await IssueSessionAsync(user, deviceId, DateTimeOffset.UtcNow, ct);
    }

    public async Task<SessionResponse> RefreshAsync(string refreshToken, Guid deviceId, string ip, CancellationToken ct)
    {
        var hash = TokenHasher.Hash(refreshToken);
        var row = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (row is null)
        {
            throw new ApiException(401, "invalid_token", "Invalid token.");
        }

        await limiter.HitAsync($"rl:refresh:{ip}:{row.FamilyId:D}", 30, TimeSpan.FromMinutes(5), ct);

        var now = DateTimeOffset.UtcNow;
        if (row.RevokedAt is not null)
        {
            if (row.RevokeReason == "rotated")
            {
                await RevokeFamilyAsync(row.FamilyId, now, "reuse", ct);
                await db.SaveChangesAsync(ct);
            }

            throw new ApiException(401, "invalid_token", "Invalid token.");
        }

        if (row.ExpiresAt <= now)
        {
            throw new ApiException(401, "invalid_token", "Invalid token.");
        }

        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var affected = await db.RefreshTokens
            .Where(t => t.Id == row.Id && t.RevokedAt == null && t.ExpiresAt > now)
            .ExecuteUpdateAsync(s => s
                .SetProperty(t => t.RevokedAt, now)
                .SetProperty(t => t.RevokeReason, "rotated"), ct);
        if (affected != 1)
        {
            await tx.RollbackAsync(ct);
            throw new ApiException(401, "invalid_token", "Invalid token.");
        }

        var user = await db.Users.FirstAsync(u => u.Id == row.UserId, ct);
        var session = await IssueSessionAsync(user, deviceId == Guid.Empty ? row.DeviceId : deviceId, now, ct, row.FamilyId, row.Id);
        await tx.CommitAsync(ct);
        return session;
    }

    public async Task LogoutAsync(string refreshToken, CancellationToken ct)
    {
        var hash = TokenHasher.Hash(refreshToken);
        var row = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (row is null)
        {
            return;
        }

        await RevokeFamilyAsync(row.FamilyId, DateTimeOffset.UtcNow, "logout", ct);
        await db.SaveChangesAsync(ct);
    }

    public async Task LogoutAllAsync(Guid userId, CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        await db.RefreshTokens
            .Where(t => t.UserId == userId && t.RevokedAt == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(t => t.RevokedAt, now)
                .SetProperty(t => t.RevokeReason, "logout_all"), ct);
    }

    public async Task ForgotPasswordAsync(string emailRaw, string ip, CancellationToken ct)
    {
        string email;
        try
        {
            email = PasswordRules.NormalizeEmail(emailRaw);
        }
        catch (ApiException)
        {
            await limiter.HitAsync($"rl:forgot:{ip}:invalid", 3, TimeSpan.FromHours(1), ct);
            return;
        }

        await limiter.HitAsync($"rl:forgot:{ip}:{TokenHasher.Hash(email)}", 3, TimeSpan.FromHours(1), ct);
        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == email && u.EmailVerifiedAt != null, ct);
        if (user is null)
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        await db.PasswordResetTokens
            .Where(t => t.UserId == user.Id && t.UsedAt == null && t.InvalidatedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.InvalidatedAt, now), ct);

        var raw = await NewUniqueCodeAsync(ct);
        var entity = new PasswordResetToken
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            TokenHash = TokenHasher.Hash(raw),
            CreatedAt = now,
            ExpiresAt = now.AddMinutes(30)
        };
        db.PasswordResetTokens.Add(entity);
        await db.SaveChangesAsync(ct);
        try
        {
            await StoreAndEnqueueResetAsync(entity.Id, raw, email, ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Password reset email was not enqueued.");
        }
    }

    public async Task ResetPasswordAsync(string code, string newPassword, string ip, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:reset:{ip}", 10, TimeSpan.FromMinutes(15), ct);
        TokenHasher.EnsureNumericCode(code);
        PasswordRules.EnsurePassword(newPassword);
        var hash = TokenHasher.Hash(code);
        var now = DateTimeOffset.UtcNow;

        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var affected = await db.PasswordResetTokens
            .Where(t => t.TokenHash == hash && t.UsedAt == null && t.InvalidatedAt == null && t.ExpiresAt > now)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.UsedAt, now), ct);
        if (affected != 1)
        {
            throw new ApiException(400, "invalid_token", "Invalid code.");
        }

        var row = await db.PasswordResetTokens.FirstAsync(t => t.TokenHash == hash, ct);
        var user = await db.Users.FirstAsync(u => u.Id == row.UserId, ct);
        user.PasswordHash = hasher.HashPassword(user, newPassword);
        user.UpdatedAt = now;
        await db.PasswordResetTokens
            .Where(t => t.UserId == user.Id && t.Id != row.Id && t.UsedAt == null && t.InvalidatedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.InvalidatedAt, now), ct);
        await db.RefreshTokens
            .Where(t => t.UserId == user.Id && t.RevokedAt == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(t => t.RevokedAt, now)
                .SetProperty(t => t.RevokeReason, "reset"), ct);
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
    }

    public async Task VerifyEmailAsync(string code, string ip, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:verify:{ip}", 10, TimeSpan.FromMinutes(15), ct);
        TokenHasher.EnsureNumericCode(code);
        await ConsumeVerificationAsync(code, ct);
    }

    public async Task ResendVerificationAsync(string emailRaw, string ip, CancellationToken ct)
    {
        string email;
        try
        {
            email = PasswordRules.NormalizeEmail(emailRaw);
        }
        catch (ApiException)
        {
            await limiter.HitAsync($"rl:resend:{ip}:invalid", 3, TimeSpan.FromHours(1), ct);
            return;
        }

        await limiter.HitAsync($"rl:resend:{ip}:{TokenHasher.Hash(email)}", 3, TimeSpan.FromHours(1), ct);
        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == email && u.EmailVerifiedAt == null, ct);
        if (user is null)
        {
            var pending = await db.EmailVerificationTokens
                .Where(t => t.PendingEmail == email && t.Purpose == "bind" && t.UsedAt == null && t.InvalidatedAt == null && t.ExpiresAt > DateTimeOffset.UtcNow)
                .OrderByDescending(t => t.CreatedAt)
                .FirstOrDefaultAsync(ct);
            if (pending is null)
            {
                return;
            }

            user = await db.Users.FirstAsync(u => u.Id == pending.UserId, ct);
            await TryEnqueueVerificationAsync(user.Id, email, "bind", ct);
            return;
        }

        await TryEnqueueVerificationAsync(user.Id, email, "register", ct);
    }

    private async Task TryEnqueueVerificationAsync(Guid userId, string email, string purpose, CancellationToken ct)
    {
        try
        {
            await CreateVerificationAsync(userId, email, purpose, TimeSpan.FromHours(24), ct);
            await db.SaveChangesAsync(ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Verification email was not enqueued.");
        }
    }

    public async Task BindEmailAsync(Guid userId, string emailRaw, string currentPassword, string ip, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:bind:{userId:D}", 5, TimeSpan.FromHours(1), ct);
        var email = PasswordRules.NormalizeEmail(emailRaw);
        var user = await db.Users.FirstAsync(u => u.Id == userId, ct);
        EnsurePasswordMatches(user, currentPassword);
        if (await EmailTakenAsync(email, ct) && !string.Equals(user.Email, email, StringComparison.Ordinal))
        {
            throw new ApiException(409, "identifier_taken", "Identifier is already taken.");
        }

        await CreateVerificationAsync(user.Id, email, "bind", TimeSpan.FromHours(24), ct);
        await db.SaveChangesAsync(ct);
    }

    public async Task BindLoginAsync(Guid userId, string login, string currentPassword, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:bind:{userId:D}", 5, TimeSpan.FromHours(1), ct);
        PasswordRules.EnsureLogin(login);
        var user = await db.Users.FirstAsync(u => u.Id == userId, ct);
        EnsurePasswordMatches(user, currentPassword);
        if (await LoginTakenAsync(login, ct) && !string.Equals(user.Login, login, StringComparison.OrdinalIgnoreCase))
        {
            throw new ApiException(409, "identifier_taken", "Identifier is already taken.");
        }

        user.Login = login;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
    }

    public async Task<UserDto> GetMeAsync(Guid userId, CancellationToken ct)
    {
        var user = await db.Users.AsNoTracking().FirstAsync(u => u.Id == userId, ct);
        return ToDto(user);
    }

    public async Task<SettingsDto> GetSettingsAsync(Guid userId, CancellationToken ct)
    {
        var settings = await db.UserSettings.AsNoTracking().FirstAsync(s => s.UserId == userId, ct);
        return new SettingsDto(settings.PreferredQuality);
    }

    public async Task<SettingsDto> UpdateSettingsAsync(Guid userId, string preferredQuality, CancellationToken ct)
    {
        var allowed = new[] { "auto", "aac_128", "aac_256", "src" };
        if (!allowed.Contains(preferredQuality))
        {
            throw new ApiException(400, "validation_failed", "preferredQuality is invalid.",
                new Dictionary<string, string[]> { ["preferredQuality"] = ["Must be auto, aac_128, aac_256, or src."] });
        }

        var settings = await db.UserSettings.FirstAsync(s => s.UserId == userId, ct);
        settings.PreferredQuality = preferredQuality;
        settings.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
        return new SettingsDto(settings.PreferredQuality);
    }

    private void EnsurePasswordMatches(User user, string currentPassword)
    {
        var result = hasher.VerifyHashedPassword(user, user.PasswordHash, currentPassword);
        if (result == PasswordVerificationResult.Failed)
        {
            throw new ApiException(401, "invalid_credentials", "Invalid credentials.");
        }
    }

    private async Task ConsumeVerificationAsync(string code, CancellationToken ct)
    {
        var hash = TokenHasher.Hash(code);
        var now = DateTimeOffset.UtcNow;
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        var affected = await db.EmailVerificationTokens
            .Where(t => t.TokenHash == hash && t.UsedAt == null && t.InvalidatedAt == null && t.ExpiresAt > now)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.UsedAt, now), ct);
        if (affected != 1)
        {
            throw new ApiException(400, "invalid_token", "Invalid code.");
        }

        var row = await db.EmailVerificationTokens.FirstAsync(t => t.TokenHash == hash, ct);
        var user = await db.Users.FirstAsync(u => u.Id == row.UserId, ct);
        if (row.Purpose == "bind")
        {
            if (await db.Users.AnyAsync(u => u.Id != user.Id && u.Email == row.PendingEmail, ct))
            {
                throw new ApiException(409, "identifier_taken", "Identifier is already taken.");
            }

            user.Email = row.PendingEmail;
        }

        user.EmailVerifiedAt = now;
        user.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
    }

    private async Task CreateVerificationAsync(Guid userId, string email, string purpose, TimeSpan ttl, CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        await db.EmailVerificationTokens
            .Where(t => t.UserId == userId && t.Purpose == purpose && t.UsedAt == null && t.InvalidatedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.InvalidatedAt, now), ct);

        var raw = await NewUniqueCodeAsync(ct);
        var entity = new EmailVerificationToken
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            PendingEmail = email,
            Purpose = purpose,
            TokenHash = TokenHasher.Hash(raw),
            CreatedAt = now,
            ExpiresAt = now.Add(ttl)
        };
        db.EmailVerificationTokens.Add(entity);
        await db.SaveChangesAsync(ct);
        var key = $"mail:verify:{entity.Id:D}";
        try
        {
            await redis.GetDatabase().StringSetAsync(key, raw, ttl);
        }
        catch (Exception)
        {
            throw new ApiException(503, "dependency_unavailable", "Mail code store is unavailable.");
        }

        jobs.Enqueue<EmailJobs>(x => x.SendVerification(key, email));
        logger.LogInformation("Enqueued verification email job for user {UserId}.", userId);
    }

    private async Task StoreAndEnqueueResetAsync(Guid tokenId, string raw, string email, CancellationToken ct)
    {
        var key = $"mail:reset:{tokenId:D}";
        try
        {
            await redis.GetDatabase().StringSetAsync(key, raw, TimeSpan.FromMinutes(30));
        }
        catch (Exception)
        {
            throw new ApiException(503, "dependency_unavailable", "Mail code store is unavailable.");
        }

        jobs.Enqueue<EmailJobs>(x => x.SendPasswordReset(key, email));
        logger.LogInformation("Enqueued password reset email job.");
        await Task.CompletedTask;
    }

    private async Task<SessionResponse> IssueSessionAsync(
        User user,
        Guid deviceId,
        DateTimeOffset now,
        CancellationToken ct,
        Guid? familyId = null,
        Guid? parentId = null)
    {
        var (access, accessExp) = jwt.IssueAccess(user);
        var raw = TokenHasher.NewOpaqueToken();
        var refresh = new RefreshToken
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            TokenHash = TokenHasher.Hash(raw),
            DeviceId = deviceId == Guid.Empty ? Guid.NewGuid() : deviceId,
            FamilyId = familyId ?? Guid.NewGuid(),
            ParentTokenId = parentId,
            CreatedAt = now,
            ExpiresAt = now.AddDays(JwtTokenService.RefreshTtlDays)
        };
        db.RefreshTokens.Add(refresh);
        await db.SaveChangesAsync(ct);
        return new SessionResponse(access, accessExp, raw, refresh.ExpiresAt, ToDto(user));
    }

    private async Task RevokeFamilyAsync(Guid familyId, DateTimeOffset now, string reason, CancellationToken ct)
    {
        await db.RefreshTokens
            .Where(t => t.FamilyId == familyId && t.RevokedAt == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(t => t.RevokedAt, now)
                .SetProperty(t => t.RevokeReason, reason), ct);
    }

    private Task<bool> EmailTakenAsync(string email, CancellationToken ct) =>
        db.Users.AnyAsync(u => u.Email == email, ct);

    private Task<bool> LoginTakenAsync(string login, CancellationToken ct)
    {
        var lowered = login.ToLowerInvariant();
        return db.Users.AnyAsync(u => u.Login != null && u.Login.ToLower() == lowered, ct);
    }

    private async Task<string> NewUniqueCodeAsync(CancellationToken ct)
    {
        for (var i = 0; i < 32; i++)
        {
            var code = TokenHasher.NewNumericCode();
            var hash = TokenHasher.Hash(code);
            var taken = await db.EmailVerificationTokens.AnyAsync(t => t.TokenHash == hash, ct)
                || await db.PasswordResetTokens.AnyAsync(t => t.TokenHash == hash, ct);
            if (!taken)
            {
                return code;
            }
        }

        throw new ApiException(503, "dependency_unavailable", "Could not allocate a confirmation code.");
    }

    private static string ParseType(string? type)
    {
        if (type is "email" or "login")
        {
            return type;
        }

        throw new ApiException(400, "validation_failed", "identifierType must be email or login.",
            new Dictionary<string, string[]> { ["identifierType"] = ["Must be email or login."] });
    }

    private static UserDto ToDto(User user) =>
        new(user.Id, user.Login, user.Email, user.Role, user.EmailVerifiedAt);
}

public sealed record RegisterRequest(string Login, string Email, string Password);
public sealed record LoginRequest(string IdentifierType, string Identifier, string Password);
public sealed record CodeRequest(string Code);
public sealed record RefreshRequest(string RefreshToken);
public sealed record LogoutRequest(string? RefreshToken);
public sealed record ForgotRequest(string Email);
public sealed record ResetRequest(string Code, string NewPassword);
public sealed record EmailOnlyRequest(string Email);
public sealed record BindEmailRequest(string Email, string CurrentPassword);
public sealed record BindLoginRequest(string Login, string CurrentPassword);
public sealed record UpdateSettingsRequest(string PreferredQuality);
public sealed record UserDto(Guid Id, string? Login, string? Email, string Role, DateTimeOffset? EmailVerifiedAt);
public sealed record SessionResponse(
    string AccessToken,
    DateTimeOffset AccessExpiresAt,
    string RefreshToken,
    DateTimeOffset RefreshExpiresAt,
    UserDto User);
public sealed record SettingsDto(string PreferredQuality);
