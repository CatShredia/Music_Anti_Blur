using Hangfire;
using MusicAntiBlur.Api.Mail;
using StackExchange.Redis;

namespace MusicAntiBlur.Api.Jobs;

public sealed class EmailJobs(SmtpEmailSender smtp, IConnectionMultiplexer redis)
{
    public async Task SendVerification(string redisKey, string toEmail)
    {
        var code = await redis.GetDatabase().StringGetAsync(redisKey);
        if (code.IsNullOrEmpty)
        {
            return;
        }

        var body = $"Your confirmation code is:\n\n{code}\n\nEnter this code in the app. It expires in 24 hours.\n";
        await smtp.SendAsync(toEmail, "Confirm your email", body, CancellationToken.None);
        await redis.GetDatabase().KeyDeleteAsync(redisKey);
    }

    public async Task SendPasswordReset(string redisKey, string toEmail)
    {
        var code = await redis.GetDatabase().StringGetAsync(redisKey);
        if (code.IsNullOrEmpty)
        {
            return;
        }

        var body = $"Your password reset code is:\n\n{code}\n\nEnter this code in the app. It expires in 30 minutes.\n";
        await smtp.SendAsync(toEmail, "Reset your password", body, CancellationToken.None);
        await redis.GetDatabase().KeyDeleteAsync(redisKey);
    }
}

public sealed class MaintenanceJobs(Data.AppDbContext db)
{
    public Task Ping() => Task.CompletedTask;

    public async Task CleanupUnverifiedEmailAccounts()
    {
        var cutoff = DateTimeOffset.UtcNow.AddHours(-24);
        var stale = db.Users.Where(u =>
            u.Login == null &&
            u.Email != null &&
            u.EmailVerifiedAt == null &&
            u.CreatedAt < cutoff);
        db.Users.RemoveRange(stale);
        await db.SaveChangesAsync();
    }

    public async Task CleanupExpiredAuthTokens()
    {
        var now = DateTimeOffset.UtcNow;
        var verifyCutoff = now.AddDays(-7);
        var refreshCutoff = now.AddDays(-30);

        db.EmailVerificationTokens.RemoveRange(
            db.EmailVerificationTokens.Where(t =>
                (t.UsedAt != null && t.UsedAt < verifyCutoff) ||
                (t.InvalidatedAt != null && t.InvalidatedAt < verifyCutoff) ||
                t.ExpiresAt < verifyCutoff));
        db.PasswordResetTokens.RemoveRange(
            db.PasswordResetTokens.Where(t =>
                (t.UsedAt != null && t.UsedAt < verifyCutoff) ||
                (t.InvalidatedAt != null && t.InvalidatedAt < verifyCutoff) ||
                t.ExpiresAt < verifyCutoff));
        db.RefreshTokens.RemoveRange(
            db.RefreshTokens.Where(t =>
                (t.RevokedAt != null && t.RevokedAt < refreshCutoff) ||
                t.ExpiresAt < refreshCutoff));
        await db.SaveChangesAsync();
    }
}

public static class RecurringJobSetup
{
    public static void Register()
    {
        RecurringJob.AddOrUpdate<MaintenanceJobs>("ping", x => x.Ping(), "*/5 * * * *");
        RecurringJob.AddOrUpdate<MaintenanceJobs>("cleanup-unverified", x => x.CleanupUnverifiedEmailAccounts(), "0 * * * *");
        RecurringJob.AddOrUpdate<MaintenanceJobs>("cleanup-auth-tokens", x => x.CleanupExpiredAuthTokens(), "15 * * * *");
    }
}
