using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;

namespace MusicAntiBlur.Api.Catalog;

public static class CatalogSeeder
{
    public static readonly Guid NeonHarborId = Guid.Parse("11111111-1111-4111-8111-111111111111");
    public static readonly Guid VelvetStaticId = Guid.Parse("22222222-2222-4222-8222-222222222222");
    public static readonly Guid CopperFieldId = Guid.Parse("33333333-3333-4333-8333-333333333333");

    public static readonly Guid NightSignalsId = Guid.Parse("aaaa1111-1111-4111-8111-111111111111");
    public static readonly Guid HarborLiveId = Guid.Parse("aaaa2222-2222-4222-8222-222222222222");
    public static readonly Guid SoftVoltageId = Guid.Parse("bbbb1111-1111-4111-8111-111111111111");
    public static readonly Guid FieldNotesId = Guid.Parse("cccc1111-1111-4111-8111-111111111111");

    public static readonly Guid NeonPulseId = Guid.Parse("d1111111-1111-4111-8111-111111111111");

    public static async Task SeedAsync(WebApplication app)
    {
        if (!app.Environment.IsDevelopment())
        {
            return;
        }

        using var scope = app.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        if (await db.Artists.AnyAsync())
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        var neon = Artist(NeonHarborId, "Neon Harbor", now);
        var velvet = Artist(VelvetStaticId, "Velvet Static", now);
        var copper = Artist(CopperFieldId, "Copper Field", now);

        var night = Album(NightSignalsId, neon.Id, "Night Signals", 2021, now);
        var live = Album(HarborLiveId, neon.Id, "Harbor Live", 2024, now);
        var voltage = Album(SoftVoltageId, velvet.Id, "Soft Voltage", 2022, now);
        var notes = Album(FieldNotesId, copper.Id, "Field Notes", 2020, now);

        db.Artists.AddRange(neon, velvet, copper);
        db.Albums.AddRange(night, live, voltage, notes);
        db.Tracks.AddRange(
            Track(NeonPulseId, night.Id, neon.Id, "Neon Pulse", 1, 214_000, now),
            Track(Guid.Parse("d1111111-1111-4111-8111-111111111112"), night.Id, neon.Id, "Glass Rain", 2, 198_000, now),
            Track(Guid.Parse("d1111111-1111-4111-8111-111111111113"), night.Id, neon.Id, "Afterglow Drive", 3, 241_000, now),
            Track(Guid.Parse("d1111111-1111-4111-8111-111111111114"), live.Id, neon.Id, "Harbor Lights", 1, 186_000, now),
            Track(Guid.Parse("d1111111-1111-4111-8111-111111111115"), live.Id, neon.Id, "Static Bloom", 2, 203_000, now),
            Track(Guid.Parse("d2222222-2222-4222-8222-222222222221"), voltage.Id, velvet.Id, "Voltage Drift", 1, 227_000, now),
            Track(Guid.Parse("d2222222-2222-4222-8222-222222222222"), voltage.Id, velvet.Id, "Quiet Circuit", 2, 175_000, now),
            Track(Guid.Parse("d3333333-3333-4333-8333-333333333331"), notes.Id, copper.Id, "Copper Morning", 1, 192_000, now),
            Track(Guid.Parse("d3333333-3333-4333-8333-333333333332"), notes.Id, copper.Id, "Field Sketch", 2, 168_000, now),
            Track(Guid.Parse("d3333333-3333-4333-8333-333333333333"), notes.Id, copper.Id, "Last Acre", 3, 251_000, now));

        await db.SaveChangesAsync();
    }

    private static Artist Artist(Guid id, string name, DateTimeOffset now) => new()
    {
        Id = id,
        Name = name,
        SortName = name.ToLowerInvariant(),
        CreatedAt = now
    };

    private static Album Album(Guid id, Guid artistId, string title, int year, DateTimeOffset now) => new()
    {
        Id = id,
        ArtistId = artistId,
        Title = title,
        Year = year,
        CreatedAt = now
    };

    private static Track Track(
        Guid id, Guid albumId, Guid artistId, string title, int number, int durationMs, DateTimeOffset now) => new()
    {
        Id = id,
        AlbumId = albumId,
        ArtistId = artistId,
        Title = title,
        TrackNumber = number,
        DurationMs = durationMs,
        CreatedAt = now,
        UpdatedAt = now
    };
}
