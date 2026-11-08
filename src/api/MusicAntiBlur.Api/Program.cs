using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Hangfire;
using Hangfire.PostgreSql;
using MailKit.Net.Smtp;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi;
using MusicAntiBlur.Api.Auth;
using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Hubs;
using MusicAntiBlur.Api.Jobs;
using MusicAntiBlur.Api.Mail;
using MusicAntiBlur.Api.Config;
using MusicAntiBlur.Api.RateLimiting;
using MusicAntiBlur.Api.Storage;
using MusicAntiBlur.Api.Media;
using MusicAntiBlur.Api.Uploads;
using MusicAntiBlur.Api.Library;
using MusicAntiBlur.Api.Overrides;
using MusicAntiBlur.Api.Playback;
using MusicAntiBlur.Api.Observability;
using StackExchange.Redis;

DotEnv.LoadFromAncestors(Directory.GetCurrentDirectory());
DotEnv.LoadFromAncestors(AppContext.BaseDirectory);

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = 256 * 1024);
builder.AddObservability();

var jwtKey = builder.Configuration["Jwt:Key"]
    ?? throw new InvalidOperationException("Jwt:Key is required.");
if (Encoding.UTF8.GetByteCount(jwtKey) < 32)
{
    throw new InvalidOperationException("Jwt:Key must be at least 32 bytes.");
}

var postgres = builder.Configuration.GetConnectionString("Postgres")
    ?? throw new InvalidOperationException("ConnectionStrings:Postgres is required.");
var redisCs = builder.Configuration.GetConnectionString("Redis")
    ?? throw new InvalidOperationException("ConnectionStrings:Redis is required.");
var hangfireCs = builder.Configuration.GetConnectionString("Hangfire") ?? postgres;

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(postgres).UseSnakeCaseNamingConvention());

builder.Services.AddSingleton<IConnectionMultiplexer>(_ =>
{
    var options = ConfigurationOptions.Parse(redisCs);
    options.AbortOnConnectFail = false;
    return ConnectionMultiplexer.Connect(options);
});
builder.Services.AddSingleton<RedisRateLimiter>();
builder.Services.AddSingleton<PasswordHasher<User>>();
builder.Services.AddSingleton<JwtTokenService>();
builder.Services.Configure<SmtpOptions>(builder.Configuration.GetSection(SmtpOptions.Section));
builder.Services.AddSingleton<SmtpEmailSender>();
builder.Services.Configure<StorageOptions>(builder.Configuration.GetSection(StorageOptions.Section));
builder.Services.Configure<CdnOptions>(builder.Configuration.GetSection(CdnOptions.Section));
builder.Services.Configure<MediaOptions>(builder.Configuration.GetSection(MediaOptions.Section));
builder.Services.AddSingleton<ObjectStorageClient>();
builder.Services.AddSingleton<PlaybackUrlSigner>();
builder.Services.AddSingleton<MediaProcessRunner>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddHttpContextAccessor();
builder.Services.Configure<CatalogOptions>(builder.Configuration.GetSection(CatalogOptions.Section));
builder.Services.AddScoped<CatalogService>();
builder.Services.AddScoped<AdminCatalogService>();
builder.Services.AddScoped<LibraryService>();
builder.Services.AddScoped<AdminUploadService>();
builder.Services.AddScoped<IdempotencyStore>();
builder.Services.AddScoped<PlaybackUrlService>();
builder.Services.AddScoped<OverrideService>();
builder.Services.AddScoped<PrivateUploadService>();
builder.Services.AddSingleton<PlaybackSessionStore>();
builder.Services.AddSingleton<PlaybackPresenceStore>();
builder.Services.AddSingleton<IPlaybackHubPublisher, PlaybackHubPublisher>();
builder.Services.AddScoped<PlaybackStateService>();
builder.Services.AddScoped<PlayHistoryService>();
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddScoped<TwoFactorService>();
builder.Services.AddScoped<LoginEventService>();
builder.Services.AddScoped<QuotaService>();
// TOTP secrets are protected with these keys; they live in Postgres and must be backed up with it.
builder.Services.AddDataProtection()
    .SetApplicationName("MusicAntiBlur")
    .PersistKeysToDbContext<AppDbContext>();
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    options.KnownIPNetworks.Clear();
    options.KnownProxies.Clear();
    foreach (var raw in (builder.Configuration["ForwardedHeaders:KnownProxies"] ?? "")
                 .Split([',', ';', ' '], StringSplitOptions.RemoveEmptyEntries))
    {
        if (System.Net.IPAddress.TryParse(raw, out var ip))
        {
            options.KnownProxies.Add(ip);
        }
    }
});

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.MapInboundClaims = true;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateIssuerSigningKey = true,
            ValidateLifetime = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidAudience = builder.Configuration["Jwt:Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey)),
            ClockSkew = TimeSpan.FromSeconds(30),
            NameClaimType = System.Security.Claims.ClaimTypes.NameIdentifier,
            RoleClaimType = System.Security.Claims.ClaimTypes.Role
        };
        options.Events = new JwtBearerEvents
        {
            OnMessageReceived = context =>
            {
                var accessToken = context.Request.Query["access_token"];
                var path = context.HttpContext.Request.Path;
                if (!string.IsNullOrEmpty(accessToken) && path.StartsWithSegments("/hubs"))
                {
                    context.Token = accessToken;
                }

                return Task.CompletedTask;
            },
            OnTokenValidated = async context =>
            {
                var raw = context.Principal?.FindFirstValue(ClaimTypes.NameIdentifier)
                    ?? context.Principal?.FindFirstValue(JwtRegisteredClaimNames.Sub);
                if (raw is null || !Guid.TryParse(raw, out var userId))
                {
                    context.Fail("invalid_token");
                    return;
                }

                var db = context.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
                if (!await db.Users.AsNoTracking().AnyAsync(u => u.Id == userId))
                {
                    context.Fail("invalid_token");
                }
            },
            OnChallenge = async context =>
            {
                context.HandleResponse();
                if (context.Response.HasStarted)
                {
                    return;
                }

                var result = ProblemResults.Problem(context.HttpContext, 401, "invalid_token", "Authentication required.");
                await result.ExecuteAsync(context.HttpContext);
            },
            OnForbidden = async context =>
            {
                if (context.Response.HasStarted)
                {
                    return;
                }

                var result = ProblemResults.Problem(context.HttpContext, 403, "admin_required", "Forbidden.");
                await result.ExecuteAsync(context.HttpContext);
            }
        };
    });
builder.Services.AddAuthorization();

var corsOrigins = (builder.Configuration["Cors:AllowedOrigins"] ?? "")
    .Split([',', ';', ' '], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
if (builder.Environment.IsDevelopment() || corsOrigins.Length > 0)
{
    builder.Services.AddCors(options =>
    {
        options.AddDefaultPolicy(policy =>
            policy.SetIsOriginAllowed(origin =>
                    corsOrigins.Contains(origin.TrimEnd('/'), StringComparer.OrdinalIgnoreCase) ||
                    (builder.Environment.IsDevelopment() &&
                     Uri.TryCreate(origin, UriKind.Absolute, out var uri) && uri.IsLoopback))
                .AllowAnyHeader()
                .AllowAnyMethod()
                .AllowCredentials());
    });
}

builder.Services.AddSignalR()
    .AddJsonProtocol(options =>
    {
        options.PayloadSerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        options.PayloadSerializerOptions.PropertyNameCaseInsensitive = true;
    })
    .AddStackExchangeRedis(redisCs);

builder.Services.AddSingleton<HangfireLogContextFilter>();
builder.Services.AddHangfire((sp, config) => config
    .SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
    .UseSimpleAssemblyNameTypeSerializer()
    .UseRecommendedSerializerSettings()
    .UsePostgreSqlStorage(options => options.UseNpgsqlConnection(hangfireCs),
        new PostgreSqlStorageOptions { SchemaName = "hangfire" })
    .UseFilter(sp.GetRequiredService<HangfireLogContextFilter>()));
builder.Services.AddHangfireServer(options => options.WorkerCount = 2);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.AddSecurityDefinition("bearer", new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        Description = "Paste accessToken from POST /api/v1/auth/login. Do not include the Bearer prefix."
    });
    options.AddSecurityRequirement(document => new OpenApiSecurityRequirement
    {
        [new OpenApiSecuritySchemeReference("bearer", document)] = []
    });
});

var app = builder.Build();

// Without configured proxies the list is empty and X-Forwarded-For is ignored (no IP spoofing).
if (!string.IsNullOrWhiteSpace(app.Configuration["ForwardedHeaders:KnownProxies"]))
{
    app.UseForwardedHeaders();
}

app.UseMiddleware<RequestIdMiddleware>();
app.UseRequestLogging();
app.UseApiExceptionHandler();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(options => options.EnablePersistAuthorization());
}

if (app.Environment.IsDevelopment() || corsOrigins.Length > 0)
{
    app.UseCors();
}

app.UseAuthentication();
app.UseUserLogContext();
app.UseAuthorization();

app.UseHangfireDashboard("/hangfire", new DashboardOptions
{
    Authorization = [new HangfireDashboardAuth(app.Configuration)]
});

app.MapAuthEndpoints();
app.MapCatalogEndpoints();
app.MapPlayHistoryEndpoints();
app.MapCatalogMediaEndpoints();
app.MapLibraryEndpoints();
app.MapOverrideEndpoints();
app.MapQuotaEndpoints();
app.MapPlaybackEndpoints();
app.MapHub<PlaybackHub>("/hubs/playback");
app.MapMetrics();

app.MapGet("/health", async (AppDbContext db, CancellationToken ct) =>
{
    var ok = await db.Database.CanConnectAsync(ct);
    return ok
        ? Results.Ok(new { status = "ok" })
        : Results.Json(new { status = "fail" }, statusCode: 503);
});

app.MapGet("/health/deps", async (IConnectionMultiplexer mux, IOptions<SmtpOptions> smtpOptions, ObjectStorageClient storage, CancellationToken ct) =>
{
    var redis = false;
    var smtp = false;
    var s3 = false;
    try
    {
        redis = (await mux.GetDatabase().PingAsync()).TotalMilliseconds >= 0;
    }
    catch
    {
        redis = false;
    }

    try
    {
        using var client = new SmtpClient();
        await SmtpConnection.ConnectAsync(client, smtpOptions.Value, ct);
        await client.DisconnectAsync(true, ct);
        smtp = true;
    }
    catch
    {
        smtp = false;
    }

    var hangfire = true;
    try
    {
        _ = JobStorage.Current.GetMonitoringApi().GetStatistics();
    }
    catch
    {
        hangfire = false;
    }

    s3 = await storage.HeadBucketAsync(ct);

    var payload = new { redis, smtp, hangfire, s3 };
    var all = redis && smtp && hangfire && s3;
    return all ? Results.Ok(payload) : Results.Json(payload, statusCode: 503);
});

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    await db.Database.MigrateAsync();
}

if (!app.Environment.IsDevelopment())
{
    var storage = app.Services.GetRequiredService<Microsoft.Extensions.Options.IOptions<StorageOptions>>().Value;
    if (!storage.IsConfigured)
    {
        throw new InvalidOperationException("Storage is required in Production.");
    }

    if (storage.UseCdn)
    {
        var cdn = app.Services.GetRequiredService<Microsoft.Extensions.Options.IOptions<CdnOptions>>().Value;
        if (!cdn.IsConfigured)
        {
            throw new InvalidOperationException("Cdn is required when Storage:UseCdn is true.");
        }
    }
}

await AdminSeeder.SeedAsync(app);
await CatalogSeeder.SeedAsync(app);
RecurringJobSetup.Register();

app.Run();
