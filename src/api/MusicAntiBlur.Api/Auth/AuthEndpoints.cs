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
            Results.Ok(await svc.LoginAsync(req, DeviceId(http), ClientIp(http), ct)));

        auth.MapPost("/refresh", async (RefreshRequest req, AuthService svc, HttpContext http, CancellationToken ct) =>
            Results.Ok(await svc.RefreshAsync(req.RefreshToken, DeviceId(http), ClientIp(http), ct)));

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

    private static string ClientIp(HttpContext http) =>
        http.Connection.RemoteIpAddress?.ToString() ?? "unknown";
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
                var result = ProblemResults.Problem(context, ex.Status, ex.Code, ex.Title, ex.Errors);
                await result.ExecuteAsync(context);
            }
        });
    }
}
