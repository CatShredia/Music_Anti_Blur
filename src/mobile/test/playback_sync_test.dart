import 'package:flutter_test/flutter_test.dart';
import 'package:music_anti_blur/player/playback_sync.dart';

void main() {
  test('older revision from another device is ignored', () {
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

  test('same revision from another device is a writer handoff', () {
    expect(
      shouldIgnoreRemoteSnapshot(
        localRevision: 4,
        incomingRevision: 4,
        localDeviceId: 'a',
        incomingDeviceId: 'b',
      ),
      isFalse,
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

  test('hub payload accepts PascalCase keys and a JSON string', () {
    final snapshot = snapshotFromHubArgs([
      {
        'Revision': 8,
        'DeviceId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'TrackId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'PositionMs': 900,
        'IsPlaying': true,
        'Source': 'catalog',
        'UpdatedAt': '2026-09-15T12:00:00Z',
        'Queue': {
          'SchemaVersion': 1,
          'Repeat': 'off',
          'Shuffle': false,
          'CurrentItemId': 'item-1',
          'Items': [
            {
              'ItemId': 'item-1',
              'TrackId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              'SourcePreference': 'auto',
            },
          ],
        },
      },
    ]);
    expect(snapshot?.trackId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    expect(snapshot?.isPlaying, isTrue);
    expect(snapshot?.queue.current?.itemId, 'item-1');

    final fromString = snapshotFromHubArgs([
      '{"revision":2,"trackId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","positionMs":0,"isPlaying":false,"queue":{"schemaVersion":1,"repeat":"off","shuffle":false,"currentItemId":null,"items":[]}}',
    ]);
    expect(fromString?.revision, 2);
    expect(fromString?.trackId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  });

  test('DevicePresence and RenditionReady parse hub payloads', () {
    final presence = presenceFromHubArgs([
      {
        'devices': [
          {'deviceId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'lastSeen': '2026-09-15T12:00:00Z'},
          {'deviceId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'},
        ],
      },
    ]);
    expect(presence?.devices, hasLength(2));
    expect(presence!.devices.first.deviceId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');

    final ready = renditionReadyFromHubArgs([
      {
        'trackId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'generationId': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'scope': 'private',
      },
    ]);
    expect(ready?.scope, 'private');
    expect(ready?.trackId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  });
}
