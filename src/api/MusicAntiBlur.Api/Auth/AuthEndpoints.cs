using System.Security.Claims;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.RateLimiting;

namespace MusicAntiBlur.Api.Auth;

public static class AuthEndpoints
{
    public static void MapAuthEndpoints(this WebApplication app)
    {
        var v1 = app.MapGroup("/api/v1");
        var auth = v1.MapGroup("/auth");
        var me = v1.MapGroup("/me").RequireAuthorization();

        auth.MapPost("/register", async (RegisterRequest req, AuthService svc, HttpContext http, CancellationToken ct) =>
            Results.Json(await svc.RegisterAsync(req, DeviceId(http), ClientIp(http), ct), statusCode: StatusCodes.Status201Created));

        auth.MapPost("/login", async (LoginRequest req, AuthService svc, HttpContext http, CancellationToken ct) =>
            Results.Ok(await svc.LoginAsync(req, DeviceId(http), Client(http), ct)));

        auth.MapPost("/2fa/email", async (ChallengeRequest req, TwoFactorService svc, HttpContext http, CancellationToken ct) =>
        {
            await svc.SendEmailCodeAsync(req.ChallengeId, ClientIp(http), ct);
            return Results.StatusCode(StatusCodes.Status202Accepted);
        });

        auth.MapPost("/2fa/verify", async (VerifyTwoFactorRequest req, AuthService svc, HttpContext http, CancellationToken ct) =>
            Results.Ok(await svc.VerifyTwoFactorAsync(req, Client(http), ct)));

        auth.MapPost("/refresh", async (RefreshRequest req, AuthService svc, HttpContext http, CancellationToken ct) =>
            Results.Ok(await svc.RefreshAsync(req.RefreshToken, DeviceId(http), Client(http), ct)));

        auth.MapPost("/logout", async (LogoutRequest req, AuthService svc, CancellationToken ct) =>
        {
            if (!string.IsNullOrEmpty(req.RefreshToken))
            {
                await svc.LogoutAsync(req.RefreshToken, ct);
            }

            return Results.NoContent();
        });

        auth.MapPost("/logout-all", async (AuthService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.LogoutAllAsync(UserId(user), ct);
            return Results.NoContent();
        }).RequireAuthorization();

        auth.MapPost("/forgot-password", async (ForgotRequest req, AuthService svc, HttpContext http, CancellationToken ct) =>
        {
            await svc.ForgotPasswordAsync(req.Email, ClientIp(http), ct);
            return Results.Ok();
        });

        auth.MapPost("/reset-password", async (ResetRequest req, AuthService svc, HttpContext http, CancellationToken ct) =>
        {
            await svc.ResetPasswordAsync(req.Code, req.NewPassword, ClientIp(http), ct);
            return Results.NoContent();
        });

        auth.MapPost("/email/verify", async (CodeRequest req, AuthService svc, HttpContext http, CancellationToken ct) =>
        {
            await svc.VerifyEmailAsync(req.Code, ClientIp(http), ct);
            return Results.NoContent();
        });

        auth.MapPost("/email/resend", async (EmailOnlyRequest req, AuthService svc, HttpContext http, CancellationToken ct) =>
        {
            await svc.ResendVerificationAsync(req.Email, ClientIp(http), ct);
            return Results.StatusCode(StatusCodes.Status202Accepted);
        });

        me.MapGet("", async (AuthService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetMeAsync(UserId(user), ct)));

        me.MapGet("/settings", async (AuthService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetSettingsAsync(UserId(user), ct)));

        me.MapPatch("/settings", async (UpdateSettingsRequest req, AuthService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.UpdateSettingsAsync(UserId(user), req.PreferredQuality, ct)));

        me.MapGet("/devices", async (AuthService svc, ClaimsPrincipal user, HttpContext http, CancellationToken ct) =>
            Results.Ok(await svc.ListDevicesAsync(UserId(user), DeviceId(http), ct)));

        me.MapDelete("/devices/{deviceId:guid}", async (Guid deviceId, AuthService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.RevokeDeviceAsync(UserId(user), deviceId, ct);
            return Results.NoContent();
        });

        me.MapPost("/identifiers/email", async (BindEmailRequest req, AuthService svc, ClaimsPrincipal user, HttpContext http, CancellationToken ct) =>
        {
            await svc.BindEmailAsync(UserId(user), req.Email, req.CurrentPassword, ClientIp(http), ct);
            return Results.StatusCode(StatusCodes.Status202Accepted);
        });

        me.MapPost("/identifiers/email/confirm", async (CodeRequest req, AuthService svc, HttpContext http, CancellationToken ct) =>
        {
            await svc.VerifyEmailAsync(req.Code, ClientIp(http), ct);
            return Results.NoContent();
        });

        var twoFa = me.MapGroup("/2fa");
        twoFa.MapGet("", async (TwoFactorService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetStatusAsync(UserId(user), ct)));
        twoFa.MapPost("/totp/setup", async (PasswordRequest req, TwoFactorService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.BeginTotpSetupAsync(UserId(user), req.CurrentPassword, ct)));
        twoFa.MapPost("/totp/confirm", async (CodeOnlyRequest req, TwoFactorService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.ConfirmTotpAsync(UserId(user), req.Code, ct)));
        twoFa.MapPost("/email/enable", async (PasswordRequest req, TwoFactorService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            var codes = await svc.EnableEmailAsync(UserId(user), req.CurrentPassword, ct);
            return codes is null ? Results.NoContent() : Results.Ok(codes);
        });
        twoFa.MapPost("/email/disable", async (PasswordRequest req, TwoFactorService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.DisableEmailAsync(UserId(user), req.CurrentPassword, ct);
            return Results.NoContent();
        });
        twoFa.MapPost("/recovery-codes/regenerate", async (PasswordRequest req, TwoFactorService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.RegenerateRecoveryCodesAsync(UserId(user), req.CurrentPassword, ct)));
        twoFa.MapPost("/disable", async (DisableTwoFactorRequest req, TwoFactorService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.DisableAllAsync(UserId(user), req.CurrentPassword, req.Code, ct);
            return Results.NoContent();
        });

        me.MapGet("/login-events", async (string? cursor, int? limit, LoginEventService svc, ClaimsPrincipal user, HttpContext http, CancellationToken ct) =>
            Results.Ok(await svc.ListAsync(UserId(user), DeviceId(http), cursor, limit, ct)));
        me.MapPost("/login-events/{eventId:guid}/not-me", async (Guid eventId, LoginEventService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.NotMeAsync(UserId(user), eventId, ct);
            return Results.NoContent();
        });

        me.MapPost("/identifiers/login", async (BindLoginRequest req, AuthService svc, ClaimsPrincipal user, CancellationToken ct) =>
        {
            await svc.BindLoginAsync(UserId(user), req.Login, req.CurrentPassword, ct);
            return Results.NoContent();
        });
    }

    private static Guid UserId(ClaimsPrincipal user)
    {
        var raw = user.FindFirstValue(ClaimTypes.NameIdentifier) ?? user.FindFirstValue("sub");
        if (raw is null || !Guid.TryParse(raw, out var id))
        {
            throw new ApiException(401, "invalid_token", "Invalid token.");
        }

        return id;
    }

    private static Guid DeviceId(HttpContext http)
    {
        var header = http.Request.Headers["X-Device-Id"].FirstOrDefault();
        return Guid.TryParse(header, out var id) ? id : Guid.NewGuid();
    }

    /// <summary>
    /// Client address. X-Forwarded-For is honoured only through UseForwardedHeaders,
    /// which trusts the proxies listed in ForwardedHeaders:KnownProxies.
    /// </summary>
    private static string ClientIp(HttpContext http) =>
        http.Connection.RemoteIpAddress?.ToString() ?? "unknown";

    private static ClientInfo Client(HttpContext http) =>
        new(ClientIp(http), http.Request.Headers.UserAgent.FirstOrDefault());
}

public static class ExceptionHandling
{
    public static IApplicationBuilder UseApiExceptionHandler(this IApplicationBuilder app)
    {
        return app.Use(async (context, next) =>
        {
            try
            {
                await next();
            }
            catch (RateLimitedException ex)
            {
                context.Response.Headers.RetryAfter = ex.RetryAfterSeconds.ToString();
                var result = ProblemResults.Problem(context, 429, "rate_limited", "Too many requests.");
                await result.ExecuteAsync(context);
            }
            catch (ApiException ex)
            {
                var result = ProblemResults.Problem(context, ex.Status, ex.Code, ex.Title, ex.Errors, ex.Extras);
                await result.ExecuteAsync(context);
            }
            catch (Microsoft.EntityFrameworkCore.DbUpdateException ex)
            {
                var mapped = DbConstraintMapper.ToApiException(ex);
                var result = ProblemResults.Problem(context, mapped.Status, mapped.Code, mapped.Title, mapped.Errors);
                await result.ExecuteAsync(context);
            }
        });
    }
}
