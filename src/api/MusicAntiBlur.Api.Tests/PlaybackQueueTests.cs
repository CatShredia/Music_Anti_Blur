using MusicAntiBlur.Api.Http;
using MusicAntiBlur.Api.Playback;
using Xunit;

namespace MusicAntiBlur.Api.Tests;

public sealed class PlaybackQueueTests
{
    private static readonly Guid TrackA = Guid.Parse("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
    private static readonly Guid TrackB = Guid.Parse("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb");
    private static readonly Guid Item1 = Guid.Parse("11111111-1111-4111-8111-111111111111");
    private static readonly Guid Item2 = Guid.Parse("22222222-2222-4222-8222-222222222222");

    [Fact]
    public void Empty_json_roundtrip_keeps_currentItemId_key()
    {
        var queue = PlaybackQueue.Parse(PlaybackQueue.EmptyJson);
        var json = PlaybackQueue.Serialize(queue);
        Assert.Contains("\"currentItemId\":null", json, StringComparison.Ordinal);
        Assert.Empty(queue.Items);
    }

    [Fact]
    public void Rejects_more_than_500_items()
    {
        var items = Enumerable.Range(0, 501)
            .Select(i => new PlaybackQueueItemDto(Guid.NewGuid(), TrackA, "catalog"))
            .ToList();
        var ex = Assert.Throws<ApiException>(() =>
            PlaybackQueue.Normalize(new PlaybackQueueDto(1, "off", false, items[0].ItemId, items)));
        Assert.Equal(400, ex.Status);
    }

    [Fact]
    public void Rejects_unknown_repeat()
    {
        Assert.Throws<ApiException>(() =>
            PlaybackQueue.Normalize(new PlaybackQueueDto(1, "random", false, null, [])));
    }

    [Fact]
    public void Command_empty_queue_clears_player()
    {
        var current = Snapshot(TrackA, Item1);
        var next = PlaybackQueue.ApplyCommand(current, new PlaybackCommandState(
            null, 0, false, null, null, PlaybackQueue.Empty));
        Assert.Null(next.TrackId);
        Assert.False(next.IsPlaying);
        Assert.Equal(0, next.PositionMs);
    }

    [Fact]
    public void Command_requires_trackId_match_current_item()
    {
        var current = Snapshot(TrackA, Item1);
        Assert.Throws<ApiException>(() => PlaybackQueue.ApplyCommand(current, new PlaybackCommandState(
            TrackB, 10, true, "auto", "catalog",
            new PlaybackQueueDto(1, "off", false, Item1, [new PlaybackQueueItemDto(Item1, TrackA, "catalog")]))));
    }

    [Fact]
    public void Rejects_items_without_currentItemId()
    {
        Assert.Throws<ApiException>(() =>
            PlaybackQueue.Normalize(new PlaybackQueueDto(
                1, "off", false, null, [new PlaybackQueueItemDto(Item1, TrackA, "catalog")])));
    }

    [Fact]
    public void Command_keeps_matching_track_and_quality()
    {
        var current = Snapshot(TrackA, Item1);
        var next = PlaybackQueue.ApplyCommand(current, new PlaybackCommandState(
            TrackA, 2400, true, "aac_128", "catalog",
            new PlaybackQueueDto(1, "one", false, Item1, [new PlaybackQueueItemDto(Item1, TrackA, "catalog")])));
        Assert.Equal(TrackA, next.TrackId);
        Assert.Equal(2400, next.PositionMs);
        Assert.Equal("aac_128", next.QualityCode);
        Assert.Equal("one", next.Queue.Repeat);
    }

    [Fact]
    public void Progress_does_not_overwrite_quality_or_queue_items()
    {
        var current = Snapshot(TrackA, Item1) with { QualityCode = "aac_256", IsPlaying = true };
        var next = PlaybackQueue.ApplyProgress(current, new PlaybackProgressState(1500, Item1));
        Assert.Equal(1500, next.PositionMs);
        Assert.Equal("aac_256", next.QualityCode);
        Assert.Equal(Item1, next.Queue.CurrentItemId);
        Assert.Single(next.Queue.Items);
        Assert.True(next.IsPlaying);
    }

    [Fact]
    public void Prune_drops_missing_tracks_and_keeps_remaining()
    {
        var snapshot = Snapshot(TrackA, Item1) with
        {
            Queue = new PlaybackQueueDto(1, "off", false, Item1,
            [
                new PlaybackQueueItemDto(Item1, TrackA, "catalog"),
                new PlaybackQueueItemDto(Item2, TrackB, "catalog")
            ])
        };
        var pruned = PlaybackQueue.PruneSnapshot(snapshot, new HashSet<Guid> { TrackB });
        Assert.Equal(TrackB, pruned.TrackId);
        Assert.Equal(Item2, pruned.Queue.CurrentItemId);
        Assert.False(pruned.IsPlaying);
        Assert.Equal(0, pruned.PositionMs);
    }

    private static PlaybackSnapshotDto Snapshot(Guid trackId, Guid itemId) =>
        new(
            1,
            null,
            null,
            trackId,
            1200,
            true,
            "auto",
            "catalog",
            new PlaybackQueueDto(1, "off", false, itemId, [new PlaybackQueueItemDto(itemId, trackId, "catalog")]),
            DateTimeOffset.UtcNow);
}
