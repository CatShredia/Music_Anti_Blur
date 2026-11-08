namespace MusicAntiBlur.Api.Library;

public sealed record LikeStatusDto(bool Liked);

public sealed record PlaylistListItemDto(
    Guid Id,
    string Title,
    string Kind,
    int TrackCount,
    DateTimeOffset UpdatedAt,
    bool IsPublic = false);

/// <summary>Трек плейлиста. <c>LikedAt</c> дублирует <c>AddedAt</c> для старых клиентов.</summary>
public sealed record PlaylistTrackDto(
    Guid Id,
    string Title,
    int TrackNumber,
    int? DurationMs,
    Guid ArtistId,
    string ArtistName,
    Guid AlbumId,
    string AlbumTitle,
    DateTimeOffset AddedAt)
{
    public DateTimeOffset LikedAt => AddedAt;
}

public sealed record PlaylistDetailDto(
    Guid Id,
    string Title,
    string Kind,
    int TrackCount,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    IReadOnlyList<PlaylistTrackDto> Tracks,
    string? NextCursor,
    string? Description = null,
    bool IsPublic = false,
    bool IsOwner = true,
    string? OwnerName = null,
    bool InLibrary = false,
    IReadOnlyList<string>? CoverUrls = null);

public sealed record CreatePlaylistRequest(string? Title, string? Description, bool? IsPublic);

public sealed record UpdatePlaylistRequest(string? Title, string? Description, bool? IsPublic);

public sealed record AddPlaylistTracksRequest(IReadOnlyList<Guid>? TrackIds, int? Position);

public sealed record ReorderPlaylistRequest(IReadOnlyList<Guid>? TrackIds);

public sealed record AddedTracksDto(int Added, int TrackCount);

public sealed record InLibraryDto(bool InLibrary);

/// <summary>Плитка библиотеки: плейлист (свой, liked или сохранённый чужой) либо альбом.</summary>
public sealed record LibraryItemDto(
    string Type,
    Guid Id,
    string Title,
    string? Subtitle,
    string Kind,
    bool IsOwn,
    string? OwnerName,
    int TrackCount,
    IReadOnlyList<string> CoverUrls,
    DateTimeOffset SortAt);

public sealed record LibraryPageDto(IReadOnlyList<LibraryItemDto> Items, string? NextCursor);

public sealed record SearchHistoryItemDto(Guid Id, string Query, DateTimeOffset SearchedAt);

public sealed record AddSearchHistoryRequest(string? Query);
