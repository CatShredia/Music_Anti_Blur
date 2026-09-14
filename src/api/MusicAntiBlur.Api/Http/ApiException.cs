using System.Text.Json.Serialization;

namespace MusicAntiBlur.Api.Http;

public sealed class ApiException : Exception
{
    public int Status { get; }
    public string Code { get; }
    public string Title { get; }
    public Dictionary<string, string[]>? Errors { get; }

    public ApiException(int status, string code, string title, Dictionary<string, string[]>? errors = null)
        : base(title)
    {
        Status = status;
        Code = code;
        Title = title;
        Errors = errors;
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
}

public static class ProblemResults
{
    public static IResult Problem(HttpContext http, int status, string code, string title, Dictionary<string, string[]>? errors = null)
    {
        var requestId = http.Items[RequestIdMiddleware.ItemKey] as string ?? http.TraceIdentifier;
        var body = new AppProblem
        {
            Type = $"https://music-anti-blur/errors/{code.Replace('_', '-')}",
            Title = title,
            Status = status,
            Code = code,
            RequestId = requestId,
            Errors = errors
        };
        return Microsoft.AspNetCore.Http.Results.Json(body, statusCode: status, contentType: "application/problem+json");
    }
}
