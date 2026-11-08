using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Library;

/// <summary>История поиска пользователя на сервере: до <see cref="LibraryOptions.SearchHistoryMax"/> записей.</summary>
public sealed class SearchHistoryService(AppDbContext db, IOptions<LibraryOptions> options)
{
    public const int ListDefault = 20;

    public async Task<IReadOnlyList<SearchHistoryItemDto>> ListAsync(Guid userId, int? limit, CancellationToken ct)
    {
        var max = options.Value.SearchHistoryMax;
        var take = limit is null ? ListDefault : limit.Value;
        if (take < 1 || take > max)
        {
            var errors = CatalogValidation.NewErrors();
            CatalogValidation.Add(errors, "limit", CatalogValidation.LimitRange);
            CatalogValidation.ThrowIfAny(errors);
        }

        return await db.SearchHistory.AsNoTracking()
            .Where(x => x.UserId == userId)
            .OrderByDescending(x => x.SearchedAt)
            .ThenBy(x => x.Id)
            .Take(take)
            .Select(x => new SearchHistoryItemDto(x.Id, x.Query, x.SearchedAt))
            .ToListAsync(ct);
    }

    /// <summary>Добавляет запрос или поднимает существующий наверх; лишнее сверх лимита удаляет (старые первыми).</summary>
    public async Task<SearchHistoryItemDto> AddAsync(Guid userId, string? rawQuery, CancellationToken ct)
    {
        var errors = CatalogValidation.NewErrors();
        var query = CatalogValidation.ParseQuery(rawQuery, errors);
        CatalogValidation.ThrowIfAny(errors);

        var normalized = Normalize(query);
        var now = DateTimeOffset.UtcNow;

        var entry = await db.SearchHistory.FirstOrDefaultAsync(x => x.UserId == userId && x.Normalized == normalized, ct);
        if (entry is null)
        {
            entry = new SearchHistoryEntry
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                Query = query,
                Normalized = normalized,
                SearchedAt = now
            };
            db.SearchHistory.Add(entry);
        }
        else
        {
            entry.Query = query;
            entry.SearchedAt = now;
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            // Параллельный запрос того же текста уже записан: поднимаем его.
            db.Entry(entry).State = EntityState.Detached;
            entry = await db.SearchHistory.FirstAsync(x => x.UserId == userId && x.Normalized == normalized, ct);
            entry.Query = query;
            entry.SearchedAt = now;
            await db.SaveChangesAsync(ct);
        }

        await TrimAsync(userId, ct);
        return new SearchHistoryItemDto(entry.Id, entry.Query, entry.SearchedAt);
    }

    public async Task RemoveAsync(Guid userId, Guid id, CancellationToken ct)
    {
        var entry = await db.SearchHistory.FirstOrDefaultAsync(x => x.Id == id && x.UserId == userId, ct)
            ?? throw new ApiException(404, "not_found", "Not found.");
        db.SearchHistory.Remove(entry);
        await db.SaveChangesAsync(ct);
    }

    public async Task ClearAsync(Guid userId, CancellationToken ct) =>
        await db.SearchHistory.Where(x => x.UserId == userId).ExecuteDeleteAsync(ct);

    /// <summary>Ключ повтора: без регистра и лишних пробелов.</summary>
    public static string Normalize(string query) =>
        string.Join(' ', query.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)).ToLowerInvariant();

    private async Task TrimAsync(Guid userId, CancellationToken ct)
    {
        var max = options.Value.SearchHistoryMax;
        var stale = await db.SearchHistory.AsNoTracking()
            .Where(x => x.UserId == userId)
            .OrderByDescending(x => x.SearchedAt)
            .ThenBy(x => x.Id)
            .Skip(max)
            .Select(x => x.Id)
            .ToListAsync(ct);
        if (stale.Count > 0)
        {
            await db.SearchHistory.Where(x => stale.Contains(x.Id)).ExecuteDeleteAsync(ct);
        }
    }
}
