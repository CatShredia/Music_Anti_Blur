using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Hangfire;
using Hangfire.PostgreSql;
using MailKit.Net.Smtp;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
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
using MusicAntiBlur.Api.Playback;
using StackExchange.Redis;

DotEnv.LoadFromAncestors(Directory.GetCurrentDirectory());
DotEnv.LoadFromAncestors(AppContext.BaseDirectory);

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = 256 * 1024);

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
builder.Services.AddSingleton<SmtpEmailSender>();
builder.Services.Configure<StorageOptions>(builder.Configuration.GetSection(StorageOptions.Section));
builder.Services.Configure<CdnOptions>(builder.Configuration.GetSection(CdnOptions.Section));
builder.Services.Configure<MediaOptions>(builder.Configuration.GetSection(MediaOptions.Section));
builder.Services.AddSingleton<ObjectStorageClient>();
builder.Services.AddSingleton<PlaybackUrlSigner>();
builder.Services.AddSingleton<MediaProcessRunner>();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<CatalogService>();
builder.Services.AddScoped<AdminUploadService>();
builder.Services.AddScoped<IdempotencyStore>();
builder.Services.AddScoped<PlaybackUrlService>();
builder.Services.AddSingleton<PlaybackSessionStore>();
builder.Services.AddScoped<PlaybackStateService>();

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

builder.Services.AddSignalR()
    .AddStackExchangeRedis(redisCs);

builder.Services.AddHangfire(config => config
    .SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
    .UseSimpleAssemblyNameTypeSerializer()
    .UseRecommendedSerializerSettings()
    .UsePostgreSqlStorage(options => options.UseNpgsqlConnection(hangfireCs),
        new PostgreSqlStorageOptions { SchemaName = "hangfire" }));
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

app.UseMiddleware<RequestIdMiddleware>();
app.UseApiExceptionHandler();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(options => options.EnablePersistAuthorization());
}

app.UseAuthentication();
app.UseAuthorization();

app.UseHangfireDashboard("/hangfire", new DashboardOptions
{
    Authorization = [new HangfireDashboardAuth(app.Configuration)]
});

app.MapAuthEndpoints();
app.MapCatalogEndpoints();
app.MapCatalogMediaEndpoints();
app.MapPlaybackEndpoints();
app.MapHub<PlaybackHub>("/hubs/playback");

app.MapGet("/health", async (AppDbContext db, CancellationToken ct) =>
{
    var ok = await db.Database.CanConnectAsync(ct);
    return ok
        ? Results.Ok(new { status = "ok" })
        : Results.Json(new { status = "fail" }, statusCode: 503);
});

app.MapGet("/health/deps", async (IConnectionMultiplexer mux, IConfiguration config, ObjectStorageClient storage, CancellationToken ct) =>
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
        await client.ConnectAsync(config["Smtp:Host"] ?? "localhost", int.Parse(config["Smtp:Port"] ?? "1025"),
            MailKit.Security.SecureSocketOptions.None, ct);
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
