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
    RedisRateLimiter limiter)
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };

    public async Task<PlaybackSnapshotDto> GetAsync(Guid userId, CancellationToken ct)
    {
        var row = await EnsureRowAsync(userId, ct);
        var known = await KnownTracksAsync(row, ct);
        var snapshot = PlaybackQueue.PruneSnapshot(ToSnapshot(row), known);
        if (NeedsWrite(row, snapshot))
        {
            WriteRow(row, snapshot, row.WriterSessionId, row.DeviceId);
            await db.SaveChangesAsync(ct);
        }

        return ToSnapshot(row);
    }

    public async Task<CreatePlaybackSessionResponse> CreateSessionAsync(Guid userId, Guid? deviceId, CancellationToken ct)
    {
        await limiter.HitAsync($"rl:playback-session:{userId:D}", 20, TimeSpan.FromMinutes(1), ct);
        var device = deviceId is Guid id && id != Guid.Empty ? id : Guid.NewGuid();
        var sessionId = Guid.NewGuid();
        await sessions.CreateAsync(sessionId, userId, device, ct);
        var snapshot = await GetAsync(userId, ct);
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
            throw Conflict("not_writer", "Not the playback writer.", row);
        }

        if (row.Revision != expectedRevision)
        {
            throw Conflict("revision_conflict", "Playback revision conflict.", row);
        }

        row.WriterSessionId = sessionId;
        row.DeviceId = live.DeviceId;
        row.Revision += 1;
        row.UpdatedAt = DateTimeOffset.UtcNow;
        await db.SaveChangesAsync(ct);
        return ToSnapshot(row);
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
            throw Conflict("not_writer", "Not the playback writer.", row);
        }

        if (row.Revision != req.ExpectedRevision)
        {
            throw Conflict("revision_conflict", "Playback revision conflict.", row);
        }

        var current = ToSnapshot(row);
        var known = await KnownTracksAsync(row, ct);
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

        next = PlaybackQueue.PruneSnapshot(next, known);
        WriteRow(row, next, req.WriterSessionId, live.DeviceId);
        row.Revision += 1;
        await db.SaveChangesAsync(ct);
        return ToSnapshot(row);
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

        row = new PlaybackState
        {
            UserId = userId,
            Queue = PlaybackQueue.EmptyJson,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        db.PlaybackStates.Add(row);
        await db.SaveChangesAsync(ct);
        return row;
    }

    private async Task<HashSet<Guid>> KnownTracksAsync(PlaybackState row, CancellationToken ct)
    {
        var ids = PlaybackQueue.Parse(row.Queue).Items.Select(i => i.TrackId).ToHashSet();
        if (row.TrackId is Guid trackId)
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
