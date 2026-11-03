using System.Diagnostics.Metrics;
using Hangfire;

namespace MusicAntiBlur.Api.Observability;

public static class AppMetrics
{
    public const string MeterName = "MusicAntiBlur";

    private static readonly Meter Meter = new(MeterName);

    private static readonly Counter<long> TranscodeJobs =
        Meter.CreateCounter<long>("mab_transcode_jobs", description: "Finished transcode jobs by kind and result.");

    private static readonly Histogram<double> TranscodeDuration =
        Meter.CreateHistogram<double>("mab_transcode_duration", unit: "s", description: "Transcode job duration.");

    private static readonly Counter<long> Uploads =
        Meter.CreateCounter<long>("mab_uploads", description: "Completed source uploads by kind and result.");

    private static readonly Counter<long> Emails =
        Meter.CreateCounter<long>("mab_emails", description: "Sent emails by type and result.");

    private static readonly UpDownCounter<long> SignalrConnections =
        Meter.CreateUpDownCounter<long>("mab_signalr_connections", description: "Open playback hub connections.");

    private static readonly Counter<long> PlaybackUrls =
        Meter.CreateCounter<long>("mab_playback_url_issued", description: "Issued playback URLs by source.");

    private static readonly Counter<long> RateLimited =
        Meter.CreateCounter<long>("mab_rate_limited", description: "Requests rejected by the rate limiter.");

    static AppMetrics()
    {
        Meter.CreateObservableGauge("mab_hangfire_jobs", ObserveHangfire, description: "Hangfire jobs by state.");
    }

    public static void TranscodeFinished(string kind, string result, TimeSpan duration)
    {
        var tags = new KeyValuePair<string, object?>[] { new("kind", kind), new("result", result) };
        TranscodeJobs.Add(1, tags);
        TranscodeDuration.Record(duration.TotalSeconds, tags);
    }

    public static void UploadCompleted(string kind, string result) =>
        Uploads.Add(1, new KeyValuePair<string, object?>("kind", kind), new KeyValuePair<string, object?>("result", result));

    public static void EmailSent(string type, string result) =>
        Emails.Add(1, new KeyValuePair<string, object?>("type", type), new KeyValuePair<string, object?>("result", result));

    public static void SignalrConnected() => SignalrConnections.Add(1);

    public static void SignalrDisconnected() => SignalrConnections.Add(-1);

    public static void PlaybackUrlIssued(string source) =>
        PlaybackUrls.Add(1, new KeyValuePair<string, object?>("source", source));

    public static void RateLimitHit(string scope) =>
        RateLimited.Add(1, new KeyValuePair<string, object?>("scope", scope));

    private static IEnumerable<Measurement<long>> ObserveHangfire()
    {
        Hangfire.Storage.Monitoring.StatisticsDto stats;
        try
        {
            stats = JobStorage.Current.GetMonitoringApi().GetStatistics();
        }
        catch
        {
            return [];
        }

        return
        [
            new Measurement<long>(stats.Failed, new KeyValuePair<string, object?>("state", "failed")),
            new Measurement<long>(stats.Enqueued, new KeyValuePair<string, object?>("state", "enqueued")),
            new Measurement<long>(stats.Processing, new KeyValuePair<string, object?>("state", "processing")),
            new Measurement<long>(stats.Scheduled, new KeyValuePair<string, object?>("state", "scheduled")),
        ];
    }
}
