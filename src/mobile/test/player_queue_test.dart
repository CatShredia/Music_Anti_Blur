import 'package:flutter_test/flutter_test.dart';
import 'package:music_anti_blur/player/player_queue.dart';

void main() {
  const a = QueueItem(itemId: 'i1', trackId: 't1');
  const b = QueueItem(itemId: 'i2', trackId: 't2');
  const c = QueueItem(itemId: 'i3', trackId: 't3');

  test('album queue starts at selected track', () {
    final queue = PlayerQueue.album(
      ['t1', 't2', 't3'],
      startTrackId: 't2',
      newId: () {
        var n = 0;
        return () => 'id-${n++}';
      }(),
    );
    expect(queue.current?.trackId, 't2');
    expect(queue.items.map((e) => e.trackId).toList(), ['t1', 't2', 't3']);
  });

  test('single queue has one item', () {
    final queue = PlayerQueue.single('t9', itemId: 'x');
    expect(queue.items, hasLength(1));
    expect(queue.current?.trackId, 't9');
  });

  test('skipNext wraps on repeat all and stops on off', () {
    final off = PlayerQueue(repeat: 'off', currentItemId: 'i3', items: const [a, b, c]);
    expect(off.skipNext().currentItemId, 'i3');
    final all = off.copyWith(repeat: 'all');
    expect(all.skipNext().currentItemId, 'i1');
  });

  test('afterCompleted replays one and stops at end', () {
    final one = PlayerQueue(repeat: 'one', currentItemId: 'i2', items: const [a, b, c]);
    expect(one.afterCompleted()?.currentItemId, 'i2');
    final end = PlayerQueue(repeat: 'off', currentItemId: 'i3', items: const [a, b, c]);
    expect(end.afterCompleted(), isNull);
    final mid = PlayerQueue(repeat: 'off', currentItemId: 'i1', items: const [a, b, c]);
    expect(mid.afterCompleted()?.currentItemId, 'i2');
  });

  test('shuffle keeps current first and stores actual order', () {
    final queue = PlayerQueue(currentItemId: 'i2', items: const [a, b, c]);
    final shuffled = queue.withShuffle(
      true,
      shuffleItems: (items) => items.reversed.toList(),
    );
    expect(shuffled.shuffle, isTrue);
    expect(shuffled.items.first.itemId, 'i2');
    expect(shuffled.items.map((e) => e.itemId).toList(), ['i2', 'i3', 'i1']);
    final restored = shuffled.withOrder(const [a, b, c], shuffle: false);
    expect(restored.shuffle, isFalse);
    expect(restored.currentItemId, 'i2');
    expect(restored.items.map((e) => e.itemId).toList(), ['i1', 'i2', 'i3']);
  });

  test('withShuffle rotates rest when mix keeps the same order', () {
    final queue = PlayerQueue(currentItemId: 'i1', items: const [a, b, c]);
    final shuffled = queue.withShuffle(true, shuffleItems: (items) => items);
    expect(shuffled.items.map((e) => e.itemId).toList(), ['i1', 'i3', 'i2']);
  });

  test('replacingWithAlbum keeps current itemId and fills the rest', () {
    final queue = PlayerQueue.single('t2', itemId: 'keep');
    final expanded = queue.replacingWithAlbum(
      ['t1', 't2', 't3'],
      newId: () {
        var n = 0;
        return () => 'n-${n++}';
      }(),
    );
    expect(expanded.currentItemId, 'keep');
    expect(expanded.current?.trackId, 't2');
    expect(expanded.items.map((e) => e.trackId).toList(), ['t1', 't2', 't3']);
    expect(expanded.hasNext, isTrue);
    expect(expanded.hasPrevious, isTrue);
  });

  test('json keeps currentItemId null', () {
    final json = PlayerQueue.empty.toJson();
    expect(json['currentItemId'], isNull);
    expect(json['schemaVersion'], 1);
    expect(json['items'], isEmpty);
  });
}
