using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;

namespace MusicAntiBlur.Api.Catalog;

public static class CatalogSeeder
{
    public const string Marker = "[SEED DATA]";

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
        var now = DateTimeOffset.UtcNow;

        EnsureArtist(db, NeonHarborId, "Neon Harbor", now);
        EnsureArtist(db, VelvetStaticId, "Velvet Static", now);
        EnsureArtist(db, CopperFieldId, "Copper Field", now);

        EnsureAlbum(db, NightSignalsId, NeonHarborId, "Night Signals", 2021, now);
        EnsureAlbum(db, HarborLiveId, NeonHarborId, "Harbor Live", 2024, now);
        EnsureAlbum(db, SoftVoltageId, VelvetStaticId, "Soft Voltage", 2022, now);
        EnsureAlbum(db, FieldNotesId, CopperFieldId, "Field Notes", 2020, now);

        EnsureTrack(db, NeonPulseId, NightSignalsId, NeonHarborId, "Neon Pulse", 1, 214_000, now);
        EnsureTrack(db, Guid.Parse("d1111111-1111-4111-8111-111111111112"), NightSignalsId, NeonHarborId, "Glass Rain", 2, 198_000, now);
        EnsureTrack(db, Guid.Parse("d1111111-1111-4111-8111-111111111113"), NightSignalsId, NeonHarborId, "Afterglow Drive", 3, 241_000, now);
        EnsureTrack(db, Guid.Parse("d1111111-1111-4111-8111-111111111114"), HarborLiveId, NeonHarborId, "Harbor Lights", 1, 186_000, now);
        EnsureTrack(db, Guid.Parse("d1111111-1111-4111-8111-111111111115"), HarborLiveId, NeonHarborId, "Static Bloom", 2, 203_000, now);
        EnsureTrack(db, Guid.Parse("d2222222-2222-4222-8222-222222222221"), SoftVoltageId, VelvetStaticId, "Voltage Drift", 1, 227_000, now);
        EnsureTrack(db, Guid.Parse("d2222222-2222-4222-8222-222222222222"), SoftVoltageId, VelvetStaticId, "Quiet Circuit", 2, 175_000, now);
        EnsureTrack(db, Guid.Parse("d3333333-3333-4333-8333-333333333331"), FieldNotesId, CopperFieldId, "Copper Morning", 1, 192_000, now);
        EnsureTrack(db, Guid.Parse("d3333333-3333-4333-8333-333333333332"), FieldNotesId, CopperFieldId, "Field Sketch", 2, 168_000, now);
        EnsureTrack(db, Guid.Parse("d3333333-3333-4333-8333-333333333333"), FieldNotesId, CopperFieldId, "Last Acre", 3, 251_000, now);

        await db.SaveChangesAsync();
    }

    public static string Mark(string value) => $"{Marker} {value}";

    private static void EnsureArtist(AppDbContext db, Guid id, string name, DateTimeOffset now)
    {
        var marked = Mark(name);
        var existing = db.Artists.Find(id);
        if (existing is null)
        {
            db.Artists.Add(new Artist
            {
                Id = id,
                Name = marked,
                SortName = name.ToLowerInvariant(),
                CreatedAt = now
            });
            return;
        }

        if (existing.Name != marked)
        {
            existing.Name = marked;
        }
        existing.SortName = name.ToLowerInvariant();
    }

    private static void EnsureAlbum(
        AppDbContext db, Guid id, Guid artistId, string title, int year, DateTimeOffset now)
    {
        var marked = Mark(title);
        var existing = db.Albums.Find(id);
        if (existing is null)
        {
            db.Albums.Add(new Album
            {
                Id = id,
                ArtistId = artistId,
                Title = marked,
                Year = year,
                CreatedAt = now
            });
            return;
        }

        if (existing.Title != marked)
        {
            existing.Title = marked;
        }
        existing.Year = year;
    }

    private static void EnsureTrack(
        AppDbContext db,
        Guid id,
        Guid albumId,
        Guid artistId,
        string title,
        int number,
        int durationMs,
        DateTimeOffset now)
    {
        var marked = Mark(title);
        var existing = db.Tracks.Find(id);
        if (existing is null)
        {
            db.Tracks.Add(new Track
            {
                Id = id,
                AlbumId = albumId,
                ArtistId = artistId,
                Title = marked,
                TrackNumber = number,
                DurationMs = durationMs,
                CreatedAt = now,
                UpdatedAt = now
            });
            return;
        }

        if (existing.Title != marked)
        {
            existing.Title = marked;
            existing.UpdatedAt = now;
        }
        existing.TrackNumber = number;
        existing.DurationMs = durationMs;
    }
}
