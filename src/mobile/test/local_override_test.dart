import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_anti_blur/overrides/local_binding_store.dart';
import 'package:music_anti_blur/player/player_queue.dart';

void main() {
  test('durationDiffersTooMuch is a 5 percent warning not a blocker', () {
    expect(durationDiffersTooMuch(1000, 1000), isFalse);
    expect(durationDiffersTooMuch(1060, 1000), isTrue);
    expect(durationDiffersTooMuch(null, 1000), isFalse);
  });

  test('LocalBindingStore roundtrip stays on device', () async {
    final dir = await Directory.systemTemp.createTemp('mab-bind');
    addTearDown(() => dir.delete(recursive: true));
    final store = LocalBindingStore(directory: dir);
    final copied = File('${dir.path}/song.mp3')..writeAsStringSync('bytes');
    final saved = await store.put(
      LocalTrackBinding(
        trackId: 't1',
        copiedPath: copied.path,
        displayName: 'song.mp3',
        durationMs: 1200,
        sizeBytes: 5,
      ),
    );
    expect(saved.fileExists, isTrue);
    expect(await store.isAvailable('t1'), isTrue);
    expect((await store.get('t1'))?.displayName, 'song.mp3');
    await store.remove('t1');
    expect(await store.isAvailable('t1'), isFalse);
  });

  test('queue defaults to auto so Local can win', () {
    final queue = PlayerQueue.single('t1', itemId: 'i1');
    expect(queue.current?.sourcePreference, 'auto');
    final switched = queue.withItemSource('i1', 'catalog');
    expect(switched.current?.sourcePreference, 'catalog');
  });
}
