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

        var (text, html) = MailLayout.Code(
            "Подтверждение почты",
            "Введите код в приложении. Он действует 24 часа.",
            code.ToString());
        await smtp.SendAsync(toEmail, "Подтверждение почты", text, html, CancellationToken.None);
        await redis.GetDatabase().KeyDeleteAsync(redisKey);
    }

    public async Task SendPasswordReset(string redisKey, string toEmail)
    {
        var code = await redis.GetDatabase().StringGetAsync(redisKey);
        if (code.IsNullOrEmpty)
        {
            return;
        }

        var (text, html) = MailLayout.Code(
            "Смена пароля",
            "Введите код в приложении. Он действует 30 минут.",
            code.ToString());
        await smtp.SendAsync(toEmail, "Смена пароля", text, html, CancellationToken.None);
        await redis.GetDatabase().KeyDeleteAsync(redisKey);
    }

    public Task SendLoginNotice(string toEmail, DateTimeOffset signedInAt)
    {
        var when = signedInAt.ToUniversalTime().ToString("yyyy-MM-dd HH:mm");
        var (text, html) = MailLayout.Notice(
            "Вход в аккаунт",
            $"Вход выполнен {when} UTC. Если это были не вы, смените пароль.");
        return smtp.SendAsync(toEmail, "Вход в аккаунт", text, html, CancellationToken.None);
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
        RecurringJob.AddOrUpdate<StorageCleanupJobs>("storage-sweep", x => x.Sweep(), "*/5 * * * *");
    }
}
