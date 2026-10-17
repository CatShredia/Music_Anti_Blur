namespace MusicAntiBlur.Api.Library;

public sealed record LikeStatusDto(bool Liked);

public sealed record PlaylistListItemDto(
    Guid Id,
    string Title,
    string Kind,
    int TrackCount,
    DateTimeOffset UpdatedAt);

public sealed record LikedPlaylistTrackDto(
    Guid Id,
    string Title,
    int TrackNumber,
    int? DurationMs,
    Guid ArtistId,
    string ArtistName,
    Guid AlbumId,
    string AlbumTitle,
    DateTimeOffset LikedAt);

public sealed record PlaylistDetailDto(
    Guid Id,
    string Title,
    string Kind,
    int TrackCount,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    IReadOnlyList<LikedPlaylistTrackDto> Tracks,
    string? NextCursor);
