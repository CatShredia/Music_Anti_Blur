namespace MusicAntiBlur.Api.Catalog;

public sealed record ArtistRefDto(Guid Id, string Name);

public sealed record AlbumRefDto(Guid Id, string Title);

public sealed record ArtistListItemDto(
    Guid Id,
    string Name,
    string? CoverUrl,
    DateTimeOffset? CoverUrlExpiresAt);

public sealed record ArtistAlbumItemDto(
    Guid Id,
    string Title,
    int? Year,
    string? CoverObjectKey,
    string? CoverUrl,
    DateTimeOffset? CoverUrlExpiresAt);

public sealed record ArtistDetailDto(
    Guid Id,
    string Name,
    string? CoverUrl,
    DateTimeOffset? CoverUrlExpiresAt,
    IReadOnlyList<ArtistAlbumItemDto> Albums,
    IReadOnlyList<PopularTrackDto>? Popular = null,
    IReadOnlyList<GenreRefDto>? Genres = null);

public sealed record AlbumListItemDto(
    Guid Id,
    string Title,
    int? Year,
    string? CoverObjectKey,
    string? CoverUrl,
    DateTimeOffset? CoverUrlExpiresAt,
    ArtistRefDto Artist);

public sealed record TrackListItemDto(Guid Id, string Title, int TrackNumber, int? DurationMs, string? Isrc);

public sealed record AlbumDetailDto(
    Guid Id,
    string Title,
    int? Year,
    string? CoverObjectKey,
    string? CoverUrl,
    DateTimeOffset? CoverUrlExpiresAt,
    ArtistRefDto Artist,
    IReadOnlyList<TrackListItemDto> Tracks,
    IReadOnlyList<GenreRefDto>? Genres = null);

public sealed record TrackDetailDto(
    Guid Id,
    string Title,
    int TrackNumber,
    int? DurationMs,
    string? Isrc,
    ArtistRefDto Artist,
    AlbumRefDto Album,
    IReadOnlyList<QualityDto> AvailableQualities,
    bool Liked,
    string? CoverObjectKey,
    string? CoverUrl,
    DateTimeOffset? CoverUrlExpiresAt,
    IReadOnlyList<GenreRefDto>? Genres = null);

public sealed record QualityDto(string Code, int BitrateKbps);

/// <summary><c>Deleted</c> бывает истинным только в админском поиске (мягко удалённый трек).</summary>
public sealed record SearchItemDto(string Type, Guid Id, string Title, string? Subtitle, double Rank, bool Deleted = false);

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

public sealed record AdminTrackRowDto(
    Guid Id,
    string Title,
    int TrackNumber,
    int? DurationMs,
    string? Isrc,
    string Status,
    int ReadyRenditions,
    int TotalRenditions);

public sealed record DeletedTrackDto(
    Guid Id,
    string Title,
    int TrackNumber,
    ArtistRefDto Artist,
    AlbumRefDto Album,
    DateTimeOffset DeletedAt,
    DateTimeOffset PurgeAt);
