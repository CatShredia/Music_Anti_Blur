using System.Text.Json;

namespace MusicAntiBlur.Api.Playback;

public sealed record PlaybackQueueItemDto(Guid ItemId, Guid TrackId, string SourcePreference);

public sealed record PlaybackQueueDto(
    int SchemaVersion,
    string Repeat,
    bool Shuffle,
    Guid? CurrentItemId,
    IReadOnlyList<PlaybackQueueItemDto> Items);

public sealed record PlaybackSnapshotDto(
    long Revision,
    Guid? WriterSessionId,
    Guid? DeviceId,
    Guid? TrackId,
    int PositionMs,
    bool IsPlaying,
    string? QualityCode,
    string? Source,
    PlaybackQueueDto Queue,
    DateTimeOffset UpdatedAt);

public sealed record CreatePlaybackSessionRequest(Guid? DeviceId);

public sealed record CreatePlaybackSessionResponse(Guid WriterSessionId, PlaybackSnapshotDto Snapshot);

public sealed record ClaimPlaybackSessionRequest(long? ExpectedRevision);

public sealed record PlaybackProgressState(int? PositionMs, Guid? CurrentItemId);

public sealed record PlaybackCommandState(
    Guid? TrackId,
    int? PositionMs,
    bool? IsPlaying,
    string? QualityCode,
    string? Source,
    PlaybackQueueDto? Queue);

public sealed record PutPlaybackStateRequest(
    long? ExpectedRevision,
    Guid? WriterSessionId,
    string? Kind,
    JsonElement State);
