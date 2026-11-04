using System.Security.Claims;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Uploads;

public static class QuotaEndpoints
{
    public static void MapQuotaEndpoints(this WebApplication app)
    {
        var v1 = app.MapGroup("/api/v1").RequireAuthorization();
        var admin = v1.MapGroup("/admin").RequireAuthorization(policy => policy.RequireRole("admin"));

        v1.MapGet("/me/quota", async (QuotaService svc, ClaimsPrincipal user, CancellationToken ct) =>
            Results.Ok(await svc.GetUsageAsync(UserId(user), ct)));

        admin.MapGet("/users/{userId:guid}/quota", async (Guid userId, QuotaService svc, CancellationToken ct) =>
            Results.Ok(await svc.GetUsageAsync(userId, ct)));

        admin.MapPut("/users/{userId:guid}/quota", async (Guid userId, SetQuotaRequest req, QuotaService svc, CancellationToken ct) =>
            Results.Ok(await svc.SetOverrideAsync(userId, req, ct)));
    }

    private static Guid UserId(ClaimsPrincipal user)
    {
        var raw = user.FindFirstValue(ClaimTypes.NameIdentifier) ?? user.FindFirstValue("sub");
        return raw is not null && Guid.TryParse(raw, out var id)
            ? id
            : throw new ApiException(401, "invalid_token", "Invalid token.");
    }
}
