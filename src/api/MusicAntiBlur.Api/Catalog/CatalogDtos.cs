namespace MusicAntiBlur.Api.Catalog;

public sealed record ArtistRefDto(Guid Id, string Name);

public sealed record AlbumRefDto(Guid Id, string Title);

public sealed record ArtistListItemDto(Guid Id, string Name);

public sealed record ArtistAlbumItemDto(Guid Id, string Title, int? Year);

public sealed record ArtistDetailDto(Guid Id, string Name, IReadOnlyList<ArtistAlbumItemDto> Albums);

public sealed record AlbumListItemDto(
    Guid Id,
    string Title,
    int? Year,
    string? CoverObjectKey,
    ArtistRefDto Artist);

public sealed record TrackListItemDto(Guid Id, string Title, int TrackNumber, int? DurationMs, string? Isrc);

public sealed record AlbumDetailDto(
    Guid Id,
    string Title,
    int? Year,
    string? CoverObjectKey,
    ArtistRefDto Artist,
    IReadOnlyList<TrackListItemDto> Tracks);

public sealed record TrackDetailDto(
    Guid Id,
    string Title,
    int TrackNumber,
    int? DurationMs,
    string? Isrc,
    ArtistRefDto Artist,
    AlbumRefDto Album,
    IReadOnlyList<string> AvailableQualities);

public sealed record SearchItemDto(string Type, Guid Id, string Title, string? Subtitle, double Rank);

public sealed record PageDto<T>(IReadOnlyList<T> Items, string? NextCursor);

public sealed record UpsertArtistRequest(string? Name, string? SortName);

public sealed record UpsertAlbumRequest(Guid? ArtistId, string? Title, int? Year, string? CoverObjectKey);

public sealed record UpsertTrackRequest(
    Guid? AlbumId,
    Guid? ArtistId,
    string? Title,
    int? TrackNumber,
    int? DurationMs,
    string? Isrc);
