using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;

namespace MusicAntiBlur.Api.Auth;

public static class AdminSeeder
{
    public static async Task SeedAsync(WebApplication app)
    {
        if (!app.Environment.IsDevelopment())
        {
            return;
        }

        using var scope = app.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var config = scope.ServiceProvider.GetRequiredService<IConfiguration>();
        var hasher = scope.ServiceProvider.GetRequiredService<PasswordHasher<User>>();

        var type = config["Seed:AdminIdentifierType"] ?? "login";
        var identifier = config["Seed:AdminIdentifier"] ?? "admin";
        var password = config["Seed:AdminPassword"] ?? "AdminPassword123";
        var now = DateTimeOffset.UtcNow;

        var exists = type == "email"
            ? await db.Users.AnyAsync(u => u.Email == identifier.Trim().ToLowerInvariant())
            : await db.Users.AnyAsync(u => u.Login != null && u.Login.ToLower() == identifier.ToLower());
        if (exists)
        {
            return;
        }

        var user = new User
        {
            Id = Guid.NewGuid(),
            Role = "admin",
            CreatedAt = now,
            UpdatedAt = now,
            Settings = new UserSettings { PreferredQuality = "auto", UpdatedAt = now }
        };
        if (type == "email")
        {
            user.Email = identifier.Trim().ToLowerInvariant();
            user.EmailVerifiedAt = now;
        }
        else
        {
            user.Login = identifier;
        }

        user.PasswordHash = hasher.HashPassword(user, password);
        db.Users.Add(user);
        await db.SaveChangesAsync();
    }
}
