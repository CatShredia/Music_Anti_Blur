import 'package:flutter_test/flutter_test.dart';
import 'package:music_anti_blur/player/playback_sync.dart';

void main() {
  test('stale revision is ignored', () {
    expect(
      shouldIgnoreRemoteSnapshot(
        localRevision: 4,
        incomingRevision: 4,
        localDeviceId: 'a',
        incomingDeviceId: 'b',
      ),
      isTrue,
    );
    expect(
      shouldIgnoreRemoteSnapshot(
        localRevision: 5,
        incomingRevision: 4,
        localDeviceId: 'a',
        incomingDeviceId: 'b',
      ),
      isTrue,
    );
  });

  test('own device echo is ignored even with a newer revision', () {
    expect(
      shouldIgnoreRemoteSnapshot(
        localRevision: 1,
        incomingRevision: 2,
        localDeviceId: 'device-a',
        incomingDeviceId: 'device-a',
      ),
      isTrue,
    );
  });

  test('other device with a newer revision is applied', () {
    expect(
      shouldIgnoreRemoteSnapshot(
        localRevision: 1,
        incomingRevision: 2,
        localDeviceId: 'device-a',
        incomingDeviceId: 'device-b',
      ),
      isFalse,
    );
  });

  test('playhead interpolates while remote is playing', () {
    final updatedAt = DateTime.utc(2026, 9, 15, 12);
    final now = updatedAt.add(const Duration(seconds: 2));
    expect(
      interpolatePositionMs(
        positionMs: 1000,
        isPlaying: true,
        updatedAt: updatedAt,
        now: now,
        durationMs: 10000,
      ),
      3000,
    );
    expect(
      interpolatePositionMs(
        positionMs: 1000,
        isPlaying: false,
        updatedAt: updatedAt,
        now: now,
        durationMs: 10000,
      ),
      1000,
    );
  });

  test('hub payload with non-string map keys still parses', () {
    final snapshot = snapshotFromHubArgs([
      {
        'revision': 3,
        'deviceId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'trackId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'positionMs': 1500,
        'isPlaying': true,
        'source': 'local',
        'updatedAt': '2026-09-15T12:00:00Z',
        'queue': {
          'schemaVersion': 1,
          'repeat': 'off',
          'shuffle': false,
          'currentItemId': 'item-1',
          'items': [
            {
              'itemId': 'item-1',
              'trackId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'sourcePreference': 'auto',
            },
          ],
        },
      },
    ]);
    expect(snapshot, isNotNull);
    expect(snapshot!.revision, 3);
    expect(snapshot.source, 'local');
    expect(snapshot.queue.current?.trackId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    expect(snapshot.updatedAt, DateTime.utc(2026, 9, 15, 12));
  });
}
