using Microsoft.EntityFrameworkCore;
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
        await SendTrackedAsync("verification", toEmail, "Подтверждение почты", text, html);
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
        await SendTrackedAsync("password_reset", toEmail, "Смена пароля", text, html);
        await redis.GetDatabase().KeyDeleteAsync(redisKey);
    }

    public Task SendLoginNotice(string toEmail, DateTimeOffset signedInAt)
    {
        var when = signedInAt.ToUniversalTime().ToString("yyyy-MM-dd HH:mm");
        var (text, html) = MailLayout.Notice(
            "Вход в аккаунт",
            $"Вход выполнен {when} UTC. Если это были не вы, смените пароль.");
        return SendTrackedAsync("login_notice", toEmail, "Вход в аккаунт", text, html);
    }

    public Task SendLoginNoticeDetailed(string toEmail, DateTimeOffset signedInAt, string ip, string device, string method)
    {
        var when = signedInAt.ToUniversalTime().ToString("yyyy-MM-dd HH:mm");
        var (text, html) = MailLayout.Notice(
            "Вход в аккаунт",
            $"Вход выполнен {when} UTC. Устройство: {device}. IP: {ip}. Способ: {Auth.LoginNotice.DescribeMethod(method)}. " +
            "Если это были не вы, откройте в приложении «Настройки → Журнал входов» и нажмите «Это не я», затем смените пароль.");
        return SendTrackedAsync("login_notice", toEmail, "Вход в аккаунт", text, html);
    }

    public async Task SendTwoFactorCode(string redisKey, string toEmail)
    {
        var code = await redis.GetDatabase().StringGetAsync(redisKey);
        if (code.IsNullOrEmpty)
        {
            return;
        }

        var (text, html) = MailLayout.Code(
            "Код для входа",
            "Введите код в приложении. Он действует 5 минут. Если вы не входили, смените пароль.",
            code.ToString());
        await SendTrackedAsync("two_factor", toEmail, "Код для входа", text, html);
        await redis.GetDatabase().KeyDeleteAsync(redisKey);
    }

    public Task SendSuspiciousLogin(string toEmail, DateTimeOffset at, string ip)
    {
        var when = at.ToUniversalTime().ToString("yyyy-MM-dd HH:mm");
        var (text, html) = MailLayout.Notice(
            "Подозрительный вход",
            $"Вы отметили вход {when} UTC с IP {ip} как чужой. Сессии этого устройства завершены. " +
            "Рекомендуем сменить пароль и включить двухфакторную защиту.");
        return SendTrackedAsync("suspicious_login", toEmail, "Подозрительный вход", text, html);
    }

    private async Task SendTrackedAsync(string type, string toEmail, string subject, string text, string html)
    {
        try
        {
            await smtp.SendAsync(toEmail, subject, text, html, CancellationToken.None);
            Observability.AppMetrics.EmailSent(type, "sent");
        }
        catch
        {
            Observability.AppMetrics.EmailSent(type, "failed");
            throw;
        }
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

    public Task CleanupLoginEvents()
    {
        var cutoff = DateTimeOffset.UtcNow.AddDays(-Auth.LoginEventService.RetentionDays);
        return db.LoginEvents.Where(e => e.At < cutoff).ExecuteDeleteAsync();
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
        RecurringJob.AddOrUpdate<MaintenanceJobs>("cleanup-login-events", x => x.CleanupLoginEvents(), "30 3 * * *");
        RecurringJob.AddOrUpdate<StorageCleanupJobs>("purge-deleted-tracks", x => x.PurgeDeletedTracks(), "45 3 * * *");
    }
}
