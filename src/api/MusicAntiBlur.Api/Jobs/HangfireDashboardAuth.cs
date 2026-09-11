using System.Text;
using Hangfire.Dashboard;

namespace MusicAntiBlur.Api.Jobs;

public sealed class HangfireDashboardAuth(IConfiguration config) : IDashboardAuthorizationFilter
{
    public bool Authorize(DashboardContext context)
    {
        var http = context.GetHttpContext();
        var header = http.Request.Headers.Authorization.ToString();
        if (!header.StartsWith("Basic ", StringComparison.OrdinalIgnoreCase))
        {
            Challenge(http);
            return false;
        }

        string decoded;
        try
        {
            decoded = Encoding.UTF8.GetString(Convert.FromBase64String(header["Basic ".Length..].Trim()));
        }
        catch
        {
            Challenge(http);
            return false;
        }

        var parts = decoded.Split(':', 2);
        var user = config["Hangfire:DashboardUser"];
        var password = config["Hangfire:DashboardPassword"];
        var ok = parts.Length == 2 && parts[0] == user && parts[1] == password;
        if (!ok)
        {
            Challenge(http);
        }

        return ok;
    }

    private static void Challenge(HttpContext http)
    {
        http.Response.Headers.WWWAuthenticate = "Basic realm=\"Hangfire\"";
        http.Response.StatusCode = StatusCodes.Status401Unauthorized;
    }
}
