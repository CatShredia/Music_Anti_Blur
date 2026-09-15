using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;
using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.RateLimiting;

namespace MusicAntiBlur.Api.Playback;

public sealed class PlaybackStateService(
    AppDbContext db,
    PlaybackSessionStore sessions,
    RedisRateLimiter limiter,
    IPlaybackHubPublisher hub,
    ILogger<PlaybackStateService> logger)
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };

    public async Task<PlaybackSnapshotDto> GetAsync(Guid userId, CancellationToken ct)
    {
        var row = await EnsureRowAsync(userId, ct);
        var snapshot = ToSnapshot(row);
        var known = await KnownTracksAsync(snapshot, ct);
        snapshot = PlaybackQueue.PruneSnapshot(snapshot, known);
        if (NeedsWrite(row, snapshot))
        {
            WriteRow(row, snapshot, row.WriterSessionId, row.DeviceId);
            await db.SaveChangesAsync(ct);
        }

        var result = ToSnapshot(row);
        logger.LogInformation(
            "[sync] get user={UserId} rev={Revision} device={DeviceId} track={TrackId} playing={Playing} posMs={Pos} items={Items}",
            userId, result.Revision, result.DeviceId, result.TrackId, result.IsPlaying, result.PositionMs, result.Queue.Items.Count);
        return result;
    }

    public async Task<CreatePlaybackSessionResponse> CreateSessionAsync(Guid userId, Guid? deviceId, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:playback-session:{userId:D}", 20, TimeSpan.FromMinutes(1), ct);
        var device = deviceId is Guid id && id != Guid.Empty ? id : Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        await sessions.CreateAsync(sessionId, userId, device, ct);
        var snapshot = await GetAsync(userId, ct);
        logger.LogInformation(
            "[sync] session-create user={UserId} device={DeviceId} session={SessionId} rev={Revision}",
            userId, device, sessionId, snapshot.Revision);
        return new CreatePlaybackSessionResponse(sessionId, snapshot);
    }

    public async Task<PlaybackSnapshotDto> ClaimAsync(Guid userId, Guid sessionId, long? expectedRevision, CancellationToken ct)
    {
        await HitStateLimitAsync(userId, ct);
        if (expectedRevision is null)
        {
            throw new ApiException(400, "validation_failed", "Validation failed.",
                new Dictionary<string, string[]> { ["expectedRevision"] = ["required"] });
        }

        var row = await EnsureRowAsync(userId, ct);
        var session = await sessions.GetAsync(sessionId, ct);
        if (session is not { } live || live.UserId != userId)
        {
            logger.LogWarning("[sync] conflict code=not_writer op=claim user={UserId} session={SessionId} rev={Revision}",
                userId, sessionId, row.Revision);
            throw Conflict("not_writer", "Not the playback writer.", row);
        }

        if (row.Revision != expectedRevision)
        {
            logger.LogWarning(
                "[sync] conflict code=revision_conflict op=claim user={UserId} expected={Expected} actual={Actual}",
                userId, expectedRevision, row.Revision);
            throw Conflict("revision_conflict", "Playback revision conflict.", row);
        }

        row.WriterSessionId = sessionId;
        row.DeviceId = live.DeviceId;
        row.Revision += 1;
        row.UpdatedAt = DateTimeOffset.UtcNow;
        logger.LogInformation(
            "[sync] claim user={UserId} device={DeviceId} session={SessionId} rev={Revision}",
            userId, live.DeviceId, sessionId, row.Revision);
        return await CommitAndBroadcastAsync(userId, row, ct);
    }

    public async Task<PlaybackSnapshotDto> PutAsync(Guid userId, PutPlaybackStateRequest req, CancellationToken ct)
    {
        await HitStateLimitAsync(userId, ct);
        if (req.ExpectedRevision is null || req.WriterSessionId is null || string.IsNullOrWhiteSpace(req.Kind))
        {
            throw new ApiException(400, "validation_failed", "Validation failed.",
                new Dictionary<string, string[]> { ["expectedRevision"] = ["required"] });
        }

        var kind = req.Kind.Trim().ToLowerInvariant();
        if (kind is not ("command" or "progress"))
        {
            throw new ApiException(400, "validation_failed", "Validation failed.",
                new Dictionary<string, string[]> { ["kind"] = ["required"] });
        }

        var row = await EnsureRowAsync(userId, ct);
        var session = await sessions.GetAsync(req.WriterSessionId.Value, ct);
        if (session is not { } live || live.UserId != userId || row.WriterSessionId != req.WriterSessionId)
        {
            logger.LogWarning(
                "[sync] conflict code=not_writer op=put user={UserId} kind={Kind} session={Session} writer={Writer} rev={Revision}",
                userId, kind, req.WriterSessionId, row.WriterSessionId, row.Revision);
            throw Conflict("not_writer", "Not the playback writer.", row);
        }

        if (row.Revision != req.ExpectedRevision)
        {
            logger.LogWarning(
                "[sync] conflict code=revision_conflict op=put user={UserId} kind={Kind} expected={Expected} actual={Actual}",
                userId, kind, req.ExpectedRevision, row.Revision);
            throw Conflict("revision_conflict", "Playback revision conflict.", row);
        }

        var current = ToSnapshot(row);
        PlaybackSnapshotDto next;
        if (kind == "progress")
        {
            var progress = req.State.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null
                ? throw new ApiException(400, "validation_failed", "Validation failed.",
                    new Dictionary<string, string[]> { ["state"] = ["required"] })
                : JsonSerializer.Deserialize<PlaybackProgressState>(req.State.GetRawText(), Json)
                  ?? throw new ApiException(400, "validation_failed", "Validation failed.",
                      new Dictionary<string, string[]> { ["state"] = ["required"] });
            next = PlaybackQueue.ApplyProgress(current, progress);
        }
        else
        {
            var command = req.State.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null
                ? throw new ApiException(400, "validation_failed", "Validation failed.",
                    new Dictionary<string, string[]> { ["state"] = ["required"] })
                : JsonSerializer.Deserialize<PlaybackCommandState>(req.State.GetRawText(), Json)
                  ?? throw new ApiException(400, "validation_failed", "Validation failed.",
                      new Dictionary<string, string[]> { ["state"] = ["required"] });
            next = PlaybackQueue.ApplyCommand(current, command);
        }

        // Lookup IDs from the incoming snapshot. Using the previous row skipped every
        // first play: known was empty, PruneSnapshot wiped the new queue, and pause
        // then persisted that empty state to every device.
        var known = await KnownTracksAsync(next, ct);
        next = PlaybackQueue.PruneSnapshot(next, known);
        WriteRow(row, next, req.WriterSessionId, live.DeviceId);
        row.Revision += 1;
        logger.LogInformation(
            "[sync] put user={UserId} kind={Kind} device={DeviceId} rev={Revision} track={TrackId} playing={Playing} posMs={Pos} items={Items}",
            userId, kind, live.DeviceId, row.Revision, next.TrackId, next.IsPlaying, next.PositionMs, next.Queue.Items.Count);
        return await CommitAndBroadcastAsync(userId, row, ct);
    }

    private async Task<PlaybackSnapshotDto> CommitAndBroadcastAsync(
        Guid userId,
        PlaybackState row,
        CancellationToken ct)
    {
        await db.SaveChangesAsync(ct);
        var snapshot = ToSnapshot(row);
        try
        {
            await hub.PlaybackSnapshotAsync(userId, snapshot, ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "[sync] broadcast-fail user={UserId} rev={Revision} track={TrackId}",
                userId, snapshot.Revision, snapshot.TrackId);
        }

        return snapshot;
    }

    private async Task HitStateLimitAsync(Guid userId, CancellationToken ct)
    {
        var bucket = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        await limiter.HitAsync($"rl:playback-state-burst:{userId:D}", 10, TimeSpan.FromSeconds(5), ct);
        await limiter.HitAsync($"rl:playback-state:{userId:D}:{bucket}", 2, TimeSpan.FromSeconds(1), ct);
    }

    private async Task<PlaybackState> EnsureRowAsync(Guid userId, CancellationToken ct)
    {
        var row = await db.PlaybackStates.FirstOrDefaultAsync(s => s.UserId == userId, ct);
        if (row is not null)
        {
            return row;
        }

        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId, ct)
            ?? throw new ApiException(401, "invalid_token", "Invalid token.");

        row = new PlaybackState
        {
            UserId = user.Id,
            User = user,
            Queue = PlaybackQueue.EmptyJson,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        db.PlaybackStates.Add(row);
        await db.SaveChangesAsync(ct);
        return row;
    }

    private async Task<HashSet<Guid>> KnownTracksAsync(PlaybackSnapshotDto snapshot, CancellationToken ct)
    {
        var ids = snapshot.Queue.Items.Select(i => i.TrackId).ToHashSet();
        if (snapshot.TrackId is Guid trackId)
        {
            ids.Add(trackId);
        }

        if (ids.Count == 0)
        {
            return [];
        }

        var existing = await db.Tracks.AsNoTracking()
            .Where(t => ids.Contains(t.Id))
            .Select(t => t.Id)
            .ToListAsync(ct);
        return existing.ToHashSet();
    }

    private static bool NeedsWrite(PlaybackState row, PlaybackSnapshotDto pruned) =>
        row.TrackId != pruned.TrackId ||
        row.PositionMs != pruned.PositionMs ||
        row.IsPlaying != pruned.IsPlaying ||
        row.QualityCode != pruned.QualityCode ||
        row.Source != pruned.Source ||
        !string.Equals(row.Queue, PlaybackQueue.Serialize(pruned.Queue), StringComparison.Ordinal);

    private static void WriteRow(PlaybackState row, PlaybackSnapshotDto snapshot, Guid? writerSessionId, Guid? deviceId)
    {
        row.TrackId = snapshot.TrackId;
        row.PositionMs = snapshot.PositionMs;
        row.IsPlaying = snapshot.IsPlaying;
        row.QualityCode = snapshot.QualityCode;
        row.Source = snapshot.Source;
        row.WriterSessionId = writerSessionId;
        row.DeviceId = deviceId;
        row.Queue = PlaybackQueue.Serialize(snapshot.Queue);
        row.UpdatedAt = DateTimeOffset.UtcNow;
    }

    private static PlaybackSnapshotDto ToSnapshot(PlaybackState row) =>
        new(
            row.Revision,
            row.WriterSessionId,
            row.DeviceId,
            row.TrackId,
            row.PositionMs,
            row.IsPlaying,
            row.QualityCode,
            row.Source,
            PlaybackQueue.Parse(row.Queue),
            row.UpdatedAt);

    private static ApiException Conflict(string code, string title, PlaybackState row) =>
        new(409, code, title, extras: new Dictionary<string, object> { ["snapshot"] = ToSnapshot(row) });
}
