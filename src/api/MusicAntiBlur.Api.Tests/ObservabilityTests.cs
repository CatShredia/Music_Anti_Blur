using System.Diagnostics.Metrics;
using MusicAntiBlur.Api.Observability;
using MusicAntiBlur.Api.RateLimiting;
using Xunit;

namespace MusicAntiBlur.Api.Tests;

public sealed class ObservabilityTests
{
    [Fact]
    public void Query_secrets_are_redacted()
    {
        var q = "?id=1&access_token=eyJabc&X-Amz-Signature=deadbeef&X-Amz-Credential=AKIA%2F1&keep=yes";
        var redacted = LogRedaction.QueryString(q);
        Assert.DoesNotContain("eyJabc", redacted);
        Assert.DoesNotContain("deadbeef", redacted);
        Assert.DoesNotContain("AKIA", redacted);
        Assert.Contains("id=1", redacted);
        Assert.Contains("keep=yes", redacted);
    }

    [Fact]
    public void Empty_query_stays_empty() => Assert.Equal("", LogRedaction.QueryString(null));

    [Theory]
    [InlineData("Bearer secret-token", true)]
    [InlineData("Bearer other", false)]
    [InlineData("secret-token", false)]
    [InlineData("", false)]
    public void Scrape_token_check(string header, bool expected) =>
        Assert.Equal(expected, ObservabilitySetup.IsTokenValid(header, "secret-token"));

    [Theory]
    [InlineData("rl:login:1.2.3.4:abc", "login")]
    [InlineData("rl:signalr:ip:user", "signalr")]
    [InlineData("weird", "other")]
    public void Rate_limit_scope_from_key(string key, string scope) =>
        Assert.Equal(scope, RedisRateLimiter.Scope(key));

    [Fact]
    public void Transcode_counter_records_kind_and_result()
    {
        var seen = new List<(long Value, Dictionary<string, object?> Tags)>();
        using var listener = new MeterListener();
        listener.InstrumentPublished = (instrument, l) =>
        {
            if (instrument.Meter.Name == AppMetrics.MeterName && instrument.Name == "mab_transcode_jobs")
            {
                l.EnableMeasurementEvents(instrument);
            }
        };
        listener.SetMeasurementEventCallback<long>((_, value, tags, _) =>
            seen.Add((value, tags.ToArray().ToDictionary(t => t.Key, t => t.Value))));
        listener.Start();

        AppMetrics.TranscodeFinished("catalog", "failed", TimeSpan.FromSeconds(3));

        Assert.Contains(seen, m => m.Value == 1 && (string?)m.Tags["kind"] == "catalog" && (string?)m.Tags["result"] == "failed");
    }
}
