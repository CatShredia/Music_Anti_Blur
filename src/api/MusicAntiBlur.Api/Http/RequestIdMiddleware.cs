namespace MusicAntiBlur.Api.Http;

public sealed class RequestIdMiddleware(RequestDelegate next)
{
    public const string ItemKey = "requestId";
    public const string HeaderName = "X-Request-Id";

    public async Task InvokeAsync(HttpContext context)
    {
        var id = context.Request.Headers[HeaderName].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(id) || !Guid.TryParse(id, out var parsed))
        {
            parsed = Guid.NewGuid();
        }

        var value = parsed.ToString("D");
        context.Items[ItemKey] = value;
        context.Response.OnStarting(() =>
        {
            context.Response.Headers[HeaderName] = value;
            return Task.CompletedTask;
        });
        await next(context);
    }
}
