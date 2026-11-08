namespace MusicAntiBlur.Api.Catalog;

public sealed record GenreRefDto(Guid Id, string Name);

public sealed record GenreListItemDto(Guid Id, string Name, int AlbumCount, int TrackCount);

public sealed record GenreDetailDto(
    Guid Id,
    string Name,
    IReadOnlyList<AlbumListItemDto> Albums,
    IReadOnlyList<PopularTrackDto> PopularTracks);

public sealed record GenreRemovedDto(int Tracks, int Albums);

public sealed record UpsertGenreRequest(string? Name);

public sealed record SetGenresRequest(IReadOnlyList<Guid>? GenreIds);

/// <summary>Трек в списке популярного. Числа прослушиваний нет намеренно.</summary>
public sealed record PopularTrackDto(
    Guid Id,
    string Title,
    int TrackNumber,
    int? DurationMs,
    Guid ArtistId,
    string ArtistName,
    Guid AlbumId,
    string AlbumTitle,
    string? CoverUrl,
    DateTimeOffset? CoverUrlExpiresAt);

public sealed record PopularTracksDto(IReadOnlyList<PopularTrackDto> Items);
