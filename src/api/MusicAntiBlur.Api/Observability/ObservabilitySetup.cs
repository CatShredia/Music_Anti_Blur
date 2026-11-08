using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using MusicAntiBlur.Api.Http;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using Serilog;
using Serilog.Formatting.Compact;
using Serilog.Sinks.Grafana.Loki;

namespace MusicAntiBlur.Api.Observability;

public static class ObservabilitySetup
{
    public const string AppLabel = "musicantiblur-api";

    public static void AddObservability(this WebApplicationBuilder builder)
    {
        var env = builder.Environment;
        var lokiUrl = builder.Configuration["Loki:Url"];

        builder.Services.AddSerilog((_, lc) =>
        {
            lc.ReadFrom.Configuration(builder.Configuration)
                .Enrich.FromLogContext()
                .Enrich.WithProperty("app", AppLabel)
                .Enrich.WithProperty("env", env.EnvironmentName);

            if (env.IsDevelopment())
            {
                lc.WriteTo.Console(outputTemplate:
                    "[{Timestamp:HH:mm:ss} {Level:u3}] {SourceContext}{NewLine}  {Message:lj} {RequestId}{NewLine}{Exception}");
            }
            else
            {
                lc.WriteTo.Console(new RenderedCompactJsonFormatter());
            }

            if (!string.IsNullOrWhiteSpace(lokiUrl))
            {
                lc.WriteTo.GrafanaLoki(
                    lokiUrl,
                    labels: [new LokiLabel { Key = "app", Value = AppLabel }, new LokiLabel { Key = "env", Value = env.EnvironmentName }],
                    propertiesAsLabels: ["level"]);
            }
        });

        // Touch AppMetrics so its observable gauges exist before the first scrape.
        System.Runtime.CompilerServices.RuntimeHelpers.RunClassConstructor(typeof(AppMetrics).TypeHandle);

        builder.Services.AddOpenTelemetry()
            .ConfigureResource(r => r.AddService(AppLabel))
            .WithMetrics(m => m
                .AddAspNetCoreInstrumentation()
                .AddHttpClientInstrumentation()
                .AddRuntimeInstrumentation()
                .AddMeter(AppMetrics.MeterName)
                .AddPrometheusExporter());
    }

    public static void UseRequestLogging(this WebApplication app)
    {
        app.UseSerilogRequestLogging(options =>
        {
            options.MessageTemplate = "HTTP {RequestMethod} {RequestPath} responded {StatusCode} in {Elapsed:0.0} ms";
            options.GetLevel = (ctx, _, ex) =>
                ex is not null || ctx.Response.StatusCode >= 500 ? Serilog.Events.LogEventLevel.Error
                : ctx.Request.Path.StartsWithSegments("/metrics") || ctx.Request.Path.StartsWithSegments("/health")
                    ? Serilog.Events.LogEventLevel.Verbose
                    : Serilog.Events.LogEventLevel.Information;
            options.EnrichDiagnosticContext = (diag, ctx) =>
            {
                if (ctx.Items[RequestIdMiddleware.ItemKey] is string requestId)
                {
                    diag.Set("RequestId", requestId);
                }

                var userId = ctx.User.FindFirstValue(ClaimTypes.NameIdentifier);
                if (userId is not null)
                {
                    diag.Set("UserId", userId);
                }

                if (ctx.GetEndpoint() is RouteEndpoint route)
                {
                    diag.Set("Route", route.RoutePattern.RawText);
                }

                if (ctx.Request.QueryString.HasValue)
                {
                    diag.Set("Query", LogRedaction.QueryString(ctx.Request.QueryString.Value));
                }
            };
        });
    }

    /// <summary>Adds UserId to every log line written while an authenticated request runs.</summary>
    public static void UseUserLogContext(this WebApplication app)
    {
        app.Use(async (ctx, next) =>
        {
            var userId = ctx.User.FindFirstValue(ClaimTypes.NameIdentifier);
            if (userId is null)
            {
                await next(ctx);
                return;
            }

            using (Serilog.Context.LogContext.PushProperty("UserId", userId))
            {
                await next(ctx);
            }
        });
    }

    /// <summary>
    /// Prometheus scrape endpoint. With Metrics:ScrapeToken set, a matching bearer token is required.
    /// Without a token it is open only in Development; elsewhere it answers 404.
    /// </summary>
    public static void MapMetrics(this WebApplication app)
    {
        var token = app.Configuration["Metrics:ScrapeToken"];
        var open = string.IsNullOrEmpty(token) && app.Environment.IsDevelopment();
        app.Use(async (ctx, next) =>
        {
            if (!ctx.Request.Path.StartsWithSegments("/metrics") || open)
            {
                await next(ctx);
                return;
            }

            if (string.IsNullOrEmpty(token))
            {
                ctx.Response.StatusCode = StatusCodes.Status404NotFound;
                return;
            }

            if (!IsTokenValid(ctx.Request.Headers.Authorization.ToString(), token))
            {
                ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
                return;
            }

            await next(ctx);
        });
        app.MapPrometheusScrapingEndpoint("/metrics");
    }

    public static bool IsTokenValid(string authorizationHeader, string token)
    {
        const string prefix = "Bearer ";
        if (!authorizationHeader.StartsWith(prefix, StringComparison.Ordinal))
        {
            return false;
        }

        var given = Encoding.UTF8.GetBytes(authorizationHeader[prefix.Length..]);
        var expected = Encoding.UTF8.GetBytes(token);
        return CryptographicOperations.FixedTimeEquals(given, expected);
    }
}
