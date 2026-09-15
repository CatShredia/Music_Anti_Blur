using System.Text;
using System.Text.Json;
using MusicAntiBlur.Api.Http;

namespace MusicAntiBlur.Api.Playback;

public static class PlaybackQueue
{
    public const string EmptyJson =
        """{"schemaVersion":1,"repeat":"off","shuffle":false,"currentItemId":null,"items":[]}""";

    public static readonly PlaybackQueueDto Empty = new(1, "off", false, null, []);

    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public static PlaybackQueueDto Parse(string json)
    {
        try
        {
            var dto = JsonSerializer.Deserialize<PlaybackQueueDto>(json, Json);
            if (dto is null)
            {
                throw InvalidQueue();
            }

            return Normalize(dto);
        }
        catch (ApiException)
        {
            throw;
        }
        catch
        {
            throw InvalidQueue();
        }
    }

    public static string Serialize(PlaybackQueueDto queue) =>
        JsonSerializer.Serialize(Normalize(queue), Json);

    public static PlaybackQueueDto Require(PlaybackQueueDto? queue)
    {
        if (queue is null)
        {
            throw InvalidQueue();
        }

        return Normalize(queue);
    }

    public static PlaybackQueueDto Normalize(PlaybackQueueDto queue)
    {
        if (queue.SchemaVersion != 1)
        {
            throw InvalidQueue("schemaVersion");
        }

        var repeat = (queue.Repeat ?? "").Trim().ToLowerInvariant();
        if (repeat is not ("off" or "one" or "all"))
        {
            throw InvalidQueue("repeat");
        }

        var items = queue.Items ?? [];
        if (items.Count > 500)
        {
            throw InvalidQueue("items");
        }

        var normalized = new List<PlaybackQueueItemDto>(items.Count);
        var seen = new HashSet<Guid>();
        foreach (var item in items)
        {
            if (item.ItemId == Guid.Empty || item.TrackId == Guid.Empty)
            {
                throw InvalidQueue("items");
            }

            if (!seen.Add(item.ItemId))
            {
                throw InvalidQueue("items");
            }

            var source = string.IsNullOrWhiteSpace(item.SourcePreference)
                ? "auto"
                : item.SourcePreference.Trim().ToLowerInvariant();
            if (source is not ("auto" or "catalog" or "local" or "private"))
            {
                throw InvalidQueue("sourcePreference");
            }

            normalized.Add(new PlaybackQueueItemDto(item.ItemId, item.TrackId, source));
        }

        Guid? current = queue.CurrentItemId;
        if (normalized.Count == 0)
        {
            current = null;
        }
        else if (current is null || normalized.All(i => i.ItemId != current))
        {
            throw InvalidQueue("currentItemId");
        }

        var result = new PlaybackQueueDto(1, repeat, queue.Shuffle, current, normalized);
        var json = JsonSerializer.Serialize(result, Json);
        if (Encoding.UTF8.GetByteCount(json) > 262144)
        {
            throw InvalidQueue("items");
        }

        return result;
    }

    public static PlaybackQueueDto Prune(PlaybackQueueDto queue, IReadOnlySet<Guid> knownTracks)
    {
        var kept = queue.Items.Where(i => knownTracks.Contains(i.TrackId)).ToList();
        if (kept.Count == 0)
        {
            return Empty;
        }

        var current = queue.CurrentItemId is Guid id && kept.Any(i => i.ItemId == id)
            ? queue.CurrentItemId
            : kept[0].ItemId;
        return new PlaybackQueueDto(1, queue.Repeat, queue.Shuffle, current, kept);
    }

    public static PlaybackSnapshotDto ApplyEmpty(PlaybackSnapshotDto snapshot) =>
        snapshot with
        {
            TrackId = null,
            PositionMs = 0,
            IsPlaying = false,
            QualityCode = null,
            Source = null,
            Queue = Empty
        };

    public static PlaybackSnapshotDto EnforceInvariant(PlaybackSnapshotDto snapshot)
    {
        var queue = Normalize(snapshot.Queue);
        if (queue.Items.Count == 0)
        {
            if (snapshot.TrackId is not null || snapshot.IsPlaying || snapshot.PositionMs != 0 ||
                snapshot.Source is not null || snapshot.QualityCode is not null)
            {
                throw InvalidQueue("trackId");
            }

            return snapshot with { Queue = queue, TrackId = null, PositionMs = 0, IsPlaying = false, Source = null, QualityCode = null };
        }

        var current = queue.Items.First(i => i.ItemId == queue.CurrentItemId);
        if (snapshot.TrackId != current.TrackId)
        {
            throw InvalidQueue("trackId");
        }

        if (snapshot.PositionMs < 0)
        {
            throw InvalidQueue("positionMs");
        }

        var source = snapshot.Source?.Trim().ToLowerInvariant();
        if (source is not (null or "catalog" or "local" or "private"))
        {
            throw InvalidQueue("source");
        }

        var quality = snapshot.QualityCode?.Trim().ToLowerInvariant();
        if (quality is not (null or "auto" or "aac_128" or "aac_256" or "src"))
        {
            throw InvalidQueue("qualityCode");
        }

        return snapshot with { Queue = queue, Source = source, QualityCode = quality };
    }

    public static PlaybackSnapshotDto ApplyCommand(PlaybackSnapshotDto current, PlaybackCommandState state)
    {
        var next = current with
        {
            TrackId = state.TrackId,
            PositionMs = state.PositionMs ?? 0,
            IsPlaying = state.IsPlaying ?? false,
            QualityCode = state.QualityCode,
            Source = state.Source,
            Queue = Require(state.Queue)
        };
        return EnforceInvariant(next);
    }

    public static PlaybackSnapshotDto ApplyProgress(PlaybackSnapshotDto current, PlaybackProgressState state)
    {
        if (state.PositionMs is < 0)
        {
            throw InvalidQueue("positionMs");
        }

        var queue = Normalize(current.Queue);
        var currentItemId = state.CurrentItemId ?? queue.CurrentItemId;
        if (queue.Items.Count == 0)
        {
            return ApplyEmpty(current);
        }

        if (currentItemId is null || queue.Items.All(i => i.ItemId != currentItemId))
        {
            throw InvalidQueue("currentItemId");
        }

        var item = queue.Items.First(i => i.ItemId == currentItemId);
        return current with
        {
            PositionMs = state.PositionMs ?? current.PositionMs,
            TrackId = item.TrackId,
            Queue = queue with { CurrentItemId = currentItemId }
        };
    }

    public static PlaybackSnapshotDto PruneSnapshot(PlaybackSnapshotDto snapshot, IReadOnlySet<Guid> knownTracks)
    {
        var queue = Prune(snapshot.Queue, knownTracks);
        if (queue.Items.Count == 0)
        {
            return ApplyEmpty(snapshot);
        }

        var item = queue.Items.First(i => i.ItemId == queue.CurrentItemId);
        var trackGone = snapshot.TrackId is Guid trackId && !knownTracks.Contains(trackId);
        return snapshot with
        {
            Queue = queue,
            TrackId = item.TrackId,
            PositionMs = trackGone ? 0 : snapshot.PositionMs,
            IsPlaying = trackGone ? false : snapshot.IsPlaying
        };
    }

    private static ApiException InvalidQueue(string field = "queue") =>
        new(400, "validation_failed", "Validation failed.",
            new Dictionary<string, string[]> { [field] = ["required"] });
}
