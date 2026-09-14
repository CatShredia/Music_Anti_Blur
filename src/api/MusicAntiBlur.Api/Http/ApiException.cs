using System.Text.Json.Serialization;

namespace MusicAntiBlur.Api.Http;

public sealed class ApiException : Exception
{
    public int Status { get; }
    public string Code { get; }
    public string Title { get; }
    public Dictionary<string, string[]>? Errors { get; }
    public Dictionary<string, object>? Extras { get; }

    public ApiException(
        int status,
        string code,
        string title,
        Dictionary<string, string[]>? errors = null,
        Dictionary<string, object>? extras = null)
        : base(title)
    {
        Status = status;
        Code = code;
        Title = title;
        Errors = errors;
        Extras = extras;
    }
}

public sealed class AppProblem
{
    public string Type { get; init; } = "";
    public string Title { get; init; } = "";
    public int Status { get; init; }
    public string Code { get; init; } = "";
    public string RequestId { get; init; } = "";
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public Dictionary<string, string[]>? Errors { get; init; }
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public bool? LocalAvailable { get; init; }
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public bool? PrivateReady { get; init; }
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public bool? CatalogReady { get; init; }
}

public static class ProblemResults
{
    public static IResult Problem(HttpContext http, int status, string code, string title, Dictionary<string, string[]>? errors = null, Dictionary<string, object>? extras = null)
    {
        var requestId = http.Items[RequestIdMiddleware.ItemKey] as string ?? http.TraceIdentifier;
        var body = new AppProblem
        {
            Type = $"https://music-anti-blur/errors/{code.Replace('_', '-')}",
            Title = title,
            Status = status,
            Code = code,
            RequestId = requestId,
            Errors = errors,
            LocalAvailable = ExtraBool(extras, "localAvailable"),
            PrivateReady = ExtraBool(extras, "privateReady"),
            CatalogReady = ExtraBool(extras, "catalogReady")
        };
        return Microsoft.AspNetCore.Http.Results.Json(body, statusCode: status, contentType: "application/problem+json");
    }

    private static bool? ExtraBool(Dictionary<string, object>? extras, string key)
    {
        if (extras is null || !extras.TryGetValue(key, out var value))
        {
            return null;
        }

        return value is bool b ? b : null;
    }
}
