using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;

namespace MusicAntiBlur.Api.Catalog;

/// <summary>Автоматические жанры из тегов файла. Ручную расстановку не перезаписывает.</summary>
public sealed class GenreTagService(AppDbContext db)
{
    /// <summary>
    /// Создаёт недостающие жанры справочника. Трек получает их, если у него жанров нет,
    /// альбом — если жанров нет у него.
    /// </summary>
    public async Task ApplyAsync(Guid trackId, IReadOnlyList<string> names, CancellationToken ct)
    {
        if (names.Count == 0)
        {
            return;
        }

        var track = await db.Tracks.AsNoTracking()
            .Where(t => t.Id == trackId)
            .Select(t => new { t.Id, t.AlbumId })
            .FirstOrDefaultAsync(ct);
        if (track is null)
        {
            return;
        }

        var genres = await EnsureGenresAsync(names, ct);

        if (!await db.TrackGenres.AnyAsync(x => x.TrackId == trackId, ct))
        {
            db.TrackGenres.AddRange(genres.Select(g => new TrackGenre { TrackId = trackId, GenreId = g.Id }));
        }

        if (!await db.AlbumGenres.AnyAsync(x => x.AlbumId == track.AlbumId, ct))
        {
            db.AlbumGenres.AddRange(genres.Select(g => new AlbumGenre { AlbumId = track.AlbumId, GenreId = g.Id }));
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch
        {
            // Не оставляем в контексте несохранённые связи: общий контекст задачи продолжит транскод.
            foreach (var entry in db.ChangeTracker.Entries()
                         .Where(e => e.State == EntityState.Added && (e.Entity is TrackGenre or AlbumGenre or Genre))
                         .ToList())
            {
                entry.State = EntityState.Detached;
            }

            throw;
        }
    }

    private async Task<List<Genre>> EnsureGenresAsync(IReadOnlyList<string> names, CancellationToken ct)
    {
        var wanted = names
            .Select(GenreNames.Clean)
            .Where(n => n is not null)
            .Select(n => n!)
            .GroupBy(GenreNames.Slug)
            .Select(g => g.First())
            .Take(GenreNames.MaxPerEntity)
            .ToList();
        var slugs = wanted.Select(GenreNames.Slug).ToList();

        var existing = await db.Genres.Where(g => slugs.Contains(g.Slug)).ToListAsync(ct);
        var missing = wanted.Where(n => existing.All(g => g.Slug != GenreNames.Slug(n))).ToList();
        if (missing.Count > 0)
        {
            var created = missing.Select(n => new Genre
            {
                Id = Guid.NewGuid(),
                Name = n,
                Slug = GenreNames.Slug(n),
                CreatedAt = DateTimeOffset.UtcNow
            }).ToList();
            db.Genres.AddRange(created);
            try
            {
                await db.SaveChangesAsync(ct);
                existing.AddRange(created);
            }
            catch (DbUpdateException)
            {
                // Параллельный транскод успел создать тот же жанр: перечитываем справочник.
                foreach (var g in created)
                {
                    db.Entry(g).State = EntityState.Detached;
                }

                existing = await db.Genres.Where(g => slugs.Contains(g.Slug)).ToListAsync(ct);
            }
        }

        return existing;
    }
}
