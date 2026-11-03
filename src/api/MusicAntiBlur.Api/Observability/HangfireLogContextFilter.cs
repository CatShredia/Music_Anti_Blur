using Hangfire.Client;
using Hangfire.Common;
using Hangfire.Server;
using MusicAntiBlur.Api.Http;
using Serilog.Context;

namespace MusicAntiBlur.Api.Observability;

/// <summary>
/// Carries the RequestId of the HTTP request that enqueued a job into the job's logs,
/// and adds JobId and JobName to every log line written while the job runs.
/// </summary>
public sealed class HangfireLogContextFilter(IHttpContextAccessor http) : JobFilterAttribute, IClientFilter, IServerFilter
{
    public const string RequestIdParameter = "RequestId";
    private const string ScopeKey = "mab:logscope";

    public void OnCreating(CreatingContext context)
    {
        if (http.HttpContext?.Items[RequestIdMiddleware.ItemKey] is string requestId)
        {
            context.SetJobParameter(RequestIdParameter, requestId);
        }
    }

    public void OnCreated(CreatedContext context)
    {
    }

    public void OnPerforming(PerformingContext context)
    {
        var requestId = context.GetJobParameter<string>(RequestIdParameter);
        var job = context.BackgroundJob.Job;
        var scopes = new List<IDisposable>
        {
            LogContext.PushProperty("JobId", context.BackgroundJob.Id),
            LogContext.PushProperty("JobName", $"{job.Type.Name}.{job.Method.Name}"),
        };
        if (!string.IsNullOrEmpty(requestId))
        {
            scopes.Add(LogContext.PushProperty("RequestId", requestId));
        }

        context.Items[ScopeKey] = scopes;
    }

    public void OnPerformed(PerformedContext context)
    {
        if (context.Items.TryGetValue(ScopeKey, out var value) && value is List<IDisposable> scopes)
        {
            for (var i = scopes.Count - 1; i >= 0; i--)
            {
                scopes[i].Dispose();
            }
        }
    }
}
